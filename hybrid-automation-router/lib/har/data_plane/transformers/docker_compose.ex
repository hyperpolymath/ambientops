# SPDX-License-Identifier: MPL-2.0
defmodule HAR.DataPlane.Transformers.DockerCompose do
  @moduledoc """
  Transformer for Docker Compose format (YAML).

  Converts HAR semantic graph to Docker Compose files.

  ## Features

  - Services with image/build configuration
  - Networks and volumes
  - Port mappings and environment variables
  - Dependencies (depends_on)
  - Configs and secrets
  - Deploy configuration
  - Health checks
  """

  @behaviour HAR.DataPlane.Transformer

  alias HAR.Semantic.Graph
  require Logger

  @impl true
  def transform(%Graph{} = graph, opts \\ []) do
    with {:ok, sorted_ops} <- Graph.topological_sort(graph),
         {:ok, compose} <- operations_to_compose(sorted_ops, graph, opts),
         {:ok, yaml} <- format_compose(compose, opts) do
      {:ok, yaml}
    end
  end

  @impl true
  def validate(%Graph{} = graph) do
    case Graph.topological_sort(graph) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:invalid_graph, reason}}
    end
  end

  defp operations_to_compose(operations, graph, _opts) do
    services = %{}
    networks = %{}
    volumes = %{}
    configs = %{}
    secrets = %{}

    # Build service dependency map from graph edges
    service_deps = build_service_deps(graph)

    {services, networks, volumes, configs, secrets} =
      Enum.reduce(operations, {services, networks, volumes, configs, secrets}, fn op, acc ->
        add_operation_to_compose(op, acc, service_deps)
      end)

    compose = %{"services" => services}
    compose = if networks != %{}, do: Map.put(compose, "networks", networks), else: compose
    compose = if volumes != %{}, do: Map.put(compose, "volumes", volumes), else: compose
    compose = if configs != %{}, do: Map.put(compose, "configs", configs), else: compose
    compose = if secrets != %{}, do: Map.put(compose, "secrets", secrets), else: compose

    {:ok, compose}
  end

  defp build_service_deps(graph) do
    # Map from operation_id to list of dependency service names
    graph.edges
    |> Enum.filter(fn dep -> dep.metadata[:reason] == "depends_on" end)
    |> Enum.group_by(fn dep -> dep.to end, fn dep -> dep.from end)
    |> Map.new(fn {to_id, from_ids} ->
      # Need to resolve from_ids to service names
      service_names =
        Enum.flat_map(from_ids, fn from_id ->
          op = Enum.find(graph.vertices, fn v -> v.id == from_id end)
          if op && op.params[:name], do: [op.params[:name]], else: []
        end)

      {to_id, service_names}
    end)
  end

  defp add_operation_to_compose(op, {services, networks, volumes, configs, secrets}, service_deps) do
    case op.type do
      :container_run ->
        name = op.params[:name] || "unnamed"
        service = build_service(op, service_deps)
        {Map.put(services, name, service), networks, volumes, configs, secrets}

      :container_deployment_create ->
        name = op.params[:name] || "unnamed"
        service = build_service_from_deployment(op, service_deps)
        {Map.put(services, name, service), networks, volumes, configs, secrets}

      :network_create ->
        name = op.params[:name] || "unnamed"
        network = build_network(op)
        {services, Map.put(networks, name, network), volumes, configs, secrets}

      :storage_volume_create ->
        name = op.params[:name] || "unnamed"
        volume = build_volume(op)
        {services, networks, Map.put(volumes, name, volume), configs, secrets}

      :config_create ->
        name = op.params[:name] || "unnamed"
        config = build_config(op)
        {services, networks, volumes, Map.put(configs, name, config), secrets}

      :secret_create ->
        name = op.params[:name] || "unnamed"
        secret = build_secret(op)
        {services, networks, volumes, configs, Map.put(secrets, name, secret)}

      _ ->
        Logger.debug("Skipping unsupported operation type for Docker Compose: #{op.type}")
        {services, networks, volumes, configs, secrets}
    end
  end

  defp build_service(op, service_deps) do
    params = op.params

    service = %{}
    service = add_if_present(service, "image", params[:image])
    service = add_build(service, params[:build])
    service = add_if_present(service, "command", params[:command])
    service = add_if_present(service, "entrypoint", params[:entrypoint])
    service = add_environment(service, params[:environment])
    service = add_if_present(service, "env_file", params[:env_file])
    service = add_ports(service, params[:ports])
    service = add_if_present(service, "expose", params[:expose])
    service = add_volumes(service, params[:volumes])
    service = add_networks(service, params[:networks])
    service = add_depends_on(service, Map.get(service_deps, op.id, []), params[:depends_on])
    service = add_restart(service, params[:restart])
    service = add_if_present(service, "deploy", params[:deploy])
    service = add_if_present(service, "healthcheck", params[:healthcheck])
    service = add_if_present(service, "labels", params[:labels])
    service = add_if_present(service, "working_dir", params[:working_dir])
    service = add_if_present(service, "user", params[:user])
    service = add_if_present(service, "hostname", params[:hostname])
    service = add_if_present(service, "extra_hosts", params[:extra_hosts])
    service = add_if_present(service, "dns", params[:dns])
    service = add_if_present(service, "configs", params[:configs])
    service = add_if_present(service, "secrets", params[:secrets])
    service = add_if_present(service, "cap_add", params[:cap_add])
    service = add_if_present(service, "cap_drop", params[:cap_drop])
    service = add_privileged(service, params[:privileged])
    service = add_if_present(service, "security_opt", params[:security_opt])
    service = add_if_present(service, "tmpfs", params[:tmpfs])
    service = add_if_present(service, "ulimits", params[:ulimits])
    service = add_if_present(service, "logging", params[:logging])
    service = add_if_present(service, "stop_grace_period", params[:stop_grace_period])
    service = add_if_present(service, "stop_signal", params[:stop_signal])

    service
  end

  defp build_service_from_deployment(op, service_deps) do
    params = op.params
    containers = params[:containers] || []
    main_container = List.first(containers) || %{}

    service = %{}
    service = add_if_present(service, "image", main_container[:image] || main_container["image"])
    service = add_environment_from_container(service, main_container)
    service = add_ports_from_container(service, main_container)
    service = add_volumes_from_container(service, main_container)
    service = add_depends_on(service, Map.get(service_deps, op.id, []), nil)

    # Add replicas via deploy
    replicas = params[:replicas]

    if replicas && replicas > 1 do
      deploy = %{"replicas" => replicas}
      Map.put(service, "deploy", deploy)
    else
      service
    end
  end

  defp build_network(op) do
    params = op.params

    if params[:external] do
      %{"external" => true}
    else
      network = %{}
      network = add_if_present(network, "driver", params[:driver])
      network = add_if_present(network, "driver_opts", params[:driver_opts])
      network = add_if_present(network, "ipam", params[:ipam])
      if network == %{}, do: nil, else: network
    end
  end

  defp build_volume(op) do
    params = op.params

    if params[:external] do
      %{"external" => true}
    else
      volume = %{}
      volume = add_if_present(volume, "driver", params[:driver])
      volume = add_if_present(volume, "driver_opts", params[:driver_opts])
      if volume == %{}, do: nil, else: volume
    end
  end

  defp build_config(op) do
    params = op.params

    if params[:external] do
      %{"external" => true}
    else
      %{}
      |> add_if_present("file", params[:file])
    end
  end

  defp build_secret(op) do
    params = op.params

    if params[:external] do
      %{"external" => true}
    else
      %{}
      |> add_if_present("file", params[:file])
    end
  end

  # Service building helpers

  defp add_build(service, nil), do: service

  defp add_build(service, %{context: context} = build) do
    build_config = %{"context" => context}
    build_config = add_if_present(build_config, "dockerfile", build[:dockerfile])
    build_config = add_if_present(build_config, "args", build[:args])
    build_config = add_if_present(build_config, "target", build[:target])
    build_config = add_if_present(build_config, "cache_from", build[:cache_from])

    # Simplify if only context
    build_value =
      if map_size(build_config) == 1 and Map.has_key?(build_config, "context") do
        context
      else
        build_config
      end

    Map.put(service, "build", build_value)
  end

  defp add_build(service, build) when is_binary(build) do
    Map.put(service, "build", build)
  end

  defp add_environment(service, nil), do: service
  defp add_environment(service, env) when map_size(env) == 0, do: service

  defp add_environment(service, env) when is_map(env) do
    # Convert to list format for better readability
    env_list =
      env
      |> Enum.sort_by(fn {k, _} -> k end)
      |> Enum.map(fn
        {k, nil} -> k
        {k, v} -> "#{k}=#{v}"
      end)

    Map.put(service, "environment", env_list)
  end

  defp add_environment(service, env) when is_list(env) do
    Map.put(service, "environment", env)
  end

  defp add_environment_from_container(service, container) do
    env = container[:env] || container["env"]

    case env do
      nil ->
        service

      env when is_list(env) ->
        env_map =
          Enum.reduce(env, %{}, fn
            %{"name" => name, "value" => value}, acc -> Map.put(acc, name, value)
            item, acc when is_map(item) -> Map.merge(acc, item)
            _, acc -> acc
          end)

        add_environment(service, env_map)

      env ->
        add_environment(service, env)
    end
  end

  defp add_ports(service, nil), do: service
  defp add_ports(service, []), do: service

  defp add_ports(service, ports) when is_list(ports) do
    port_strings =
      Enum.map(ports, fn
        %{host_ip: host_ip, published: published, target: target, protocol: protocol} ->
          format_port(host_ip, published, target, protocol)

        %{published: published, target: target, protocol: protocol} ->
          format_port(nil, published, target, protocol)

        %{target: target, published: published} ->
          "#{published}:#{target}"

        %{target: target} ->
          "#{target}"

        %{raw: raw} ->
          raw

        port when is_integer(port) ->
          "#{port}"

        port when is_binary(port) ->
          port

        port when is_map(port) ->
          # Handle string-keyed maps
          published = port["published"] || port[:published]
          target = port["target"] || port[:target]
          if published && target, do: "#{published}:#{target}", else: nil
      end)
      |> Enum.reject(&is_nil/1)

    if port_strings != [], do: Map.put(service, "ports", port_strings), else: service
  end

  defp format_port(nil, published, target, "tcp"), do: "#{published}:#{target}"
  defp format_port(nil, published, target, protocol), do: "#{published}:#{target}/#{protocol}"
  defp format_port(host_ip, published, target, "tcp"), do: "#{host_ip}:#{published}:#{target}"

  defp format_port(host_ip, published, target, protocol),
    do: "#{host_ip}:#{published}:#{target}/#{protocol}"

  defp add_ports_from_container(service, container) do
    ports = container[:ports] || container["ports"]

    case ports do
      nil ->
        service

      ports when is_list(ports) ->
        port_list =
          Enum.map(ports, fn
            %{"containerPort" => port} -> "#{port}:#{port}"
            %{container_port: port} -> "#{port}:#{port}"
            port when is_integer(port) -> "#{port}:#{port}"
            port -> port
          end)

        if port_list != [], do: Map.put(service, "ports", port_list), else: service

      _ ->
        service
    end
  end

  defp add_volumes(service, nil), do: service
  defp add_volumes(service, []), do: service

  defp add_volumes(service, volumes) when is_list(volumes) do
    volume_strings =
      Enum.map(volumes, fn
        %{source: source, target: target, read_only: true} ->
          "#{source}:#{target}:ro"

        %{source: source, target: target} ->
          "#{source}:#{target}"

        %{target: target} ->
          target

        vol when is_binary(vol) ->
          vol

        vol when is_map(vol) ->
          # Handle string-keyed maps
          source = vol["source"] || vol[:source]
          target = vol["target"] || vol[:target]
          if source && target, do: "#{source}:#{target}", else: nil
      end)
      |> Enum.reject(&is_nil/1)

    if volume_strings != [], do: Map.put(service, "volumes", volume_strings), else: service
  end

  defp add_volumes_from_container(service, container) do
    volume_mounts = container[:volume_mounts] || container["volumeMounts"]

    case volume_mounts do
      nil ->
        service

      mounts when is_list(mounts) ->
        volume_list =
          Enum.map(mounts, fn
            %{"name" => name, "mountPath" => path} -> "#{name}:#{path}"
            %{name: name, mount_path: path} -> "#{name}:#{path}"
            mount -> mount
          end)

        if volume_list != [], do: Map.put(service, "volumes", volume_list), else: service

      _ ->
        service
    end
  end

  defp add_networks(service, nil), do: service
  defp add_networks(service, []), do: service

  defp add_networks(service, networks) when is_list(networks) do
    Map.put(service, "networks", networks)
  end

  defp add_depends_on(service, [], nil), do: service

  defp add_depends_on(service, graph_deps, nil) when is_list(graph_deps) and graph_deps != [] do
    Map.put(service, "depends_on", graph_deps)
  end

  defp add_depends_on(service, graph_deps, params_deps) do
    all_deps = (graph_deps || []) ++ normalize_depends_on_params(params_deps || [])
    all_deps = Enum.uniq(all_deps)
    if all_deps != [], do: Map.put(service, "depends_on", all_deps), else: service
  end

  defp normalize_depends_on_params(deps) when is_list(deps) do
    Enum.map(deps, fn
      %{service: name} -> name
      name when is_binary(name) -> name
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_depends_on_params(_), do: []

  defp add_restart(service, nil), do: service
  defp add_restart(service, "no"), do: service

  defp add_restart(service, restart) do
    Map.put(service, "restart", restart)
  end

  defp add_privileged(service, nil), do: service
  defp add_privileged(service, false), do: service

  defp add_privileged(service, true) do
    Map.put(service, "privileged", true)
  end

  defp add_if_present(map, _key, nil), do: map
  defp add_if_present(map, _key, []), do: map
  defp add_if_present(map, _key, m) when is_map(m) and map_size(m) == 0, do: map
  defp add_if_present(map, key, value), do: Map.put(map, key, value)

  # Compose formatting

  defp format_compose(compose, _opts) do
    yaml = """
    # Generated by HAR (Hybrid Automation Router)
    # Docker Compose file
    """

    case HAR.Utils.YamlFormatter.to_yaml(compose) do
      {:ok, yaml_content} -> {:ok, yaml <> yaml_content}
      {:error, reason} -> {:error, reason}
    end
  end
end
