# SPDX-License-Identifier: MPL-2.0
defmodule HAR.DataPlane.Parsers.DockerCompose do
  @moduledoc """
  Parser for Docker Compose files (YAML).

  Converts Docker Compose service definitions to HAR semantic graph operations.

  ## Supported Elements

  - Services (containers)
  - Networks
  - Volumes
  - Configs
  - Secrets
  - Port mappings
  - Environment variables
  - Dependencies (depends_on)
  - Health checks

  ## Compose Versions

  Supports both Compose v2 and v3+ formats.
  """

  @behaviour HAR.DataPlane.Parser

  alias HAR.Semantic.{Graph, Operation, Dependency}
  require Logger

  @impl true
  def parse(content, opts \\ []) when is_binary(content) do
    with {:ok, parsed} <- parse_yaml(content),
         {:ok, services} <- extract_services(parsed),
         {:ok, networks} <- extract_networks(parsed),
         {:ok, volumes} <- extract_volumes(parsed),
         {:ok, configs} <- extract_configs(parsed),
         {:ok, secrets} <- extract_secrets(parsed),
         {:ok, operations} <-
           build_operations(services, networks, volumes, configs, secrets, opts),
         {:ok, dependencies} <- build_dependencies(services, operations) do
      graph =
        Graph.new(
          vertices: operations,
          edges: dependencies,
          metadata: %{source: :docker_compose, parsed_at: DateTime.utc_now()}
        )

      {:ok, graph}
    end
  end

  @impl true
  def validate(content) when is_binary(content) do
    case parse_yaml(content) do
      {:ok, parsed} when is_map(parsed) ->
        if Map.has_key?(parsed, "services") or Map.has_key?(parsed, "version") do
          :ok
        else
          {:error, {:docker_compose_parse_error, "No services section found"}}
        end

      {:ok, _} ->
        {:error, {:docker_compose_parse_error, "Invalid Docker Compose format"}}

      {:error, reason} ->
        {:error, {:docker_compose_parse_error, reason}}
    end
  end

  # YAML parsing

  defp parse_yaml(content) do
    case YamlElixir.read_from_string(content) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, reason} -> {:error, {:yaml_parse_error, reason}}
    end
  end

  # Element extraction

  defp extract_services(parsed) do
    services = Map.get(parsed, "services", %{})
    {:ok, services}
  end

  defp extract_networks(parsed) do
    networks = Map.get(parsed, "networks", %{})
    {:ok, networks}
  end

  defp extract_volumes(parsed) do
    volumes = Map.get(parsed, "volumes", %{})
    {:ok, volumes}
  end

  defp extract_configs(parsed) do
    configs = Map.get(parsed, "configs", %{})
    {:ok, configs}
  end

  defp extract_secrets(parsed) do
    secrets = Map.get(parsed, "secrets", %{})
    {:ok, secrets}
  end

  # Operation building

  defp build_operations(services, networks, volumes, configs, secrets, opts) do
    # Build operations in dependency order: networks/volumes/configs/secrets first, then services
    network_ops = build_network_operations(networks)
    volume_ops = build_volume_operations(volumes)
    config_ops = build_config_operations(configs)
    secret_ops = build_secret_operations(secrets)
    service_ops = build_service_operations(services, opts)

    operations = network_ops ++ volume_ops ++ config_ops ++ secret_ops ++ service_ops
    {:ok, operations}
  end

  defp build_network_operations(networks) do
    networks
    |> Enum.with_index()
    |> Enum.map(fn {{name, config}, index} ->
      config = config || %{}

      Operation.new(
        :network_create,
        %{
          name: name,
          driver: Map.get(config, "driver", "bridge"),
          external: Map.get(config, "external", false),
          driver_opts: Map.get(config, "driver_opts", %{}),
          ipam: Map.get(config, "ipam")
        },
        id: "compose_network_#{safe_name(name)}_#{index}",
        metadata: %{
          source: :docker_compose,
          compose_type: :network,
          name: name
        }
      )
    end)
  end

  defp build_volume_operations(volumes) do
    volumes
    |> Enum.with_index()
    |> Enum.map(fn {{name, config}, index} ->
      config = config || %{}

      Operation.new(
        :storage_volume_create,
        %{
          name: name,
          driver: Map.get(config, "driver", "local"),
          external: Map.get(config, "external", false),
          driver_opts: Map.get(config, "driver_opts", %{})
        },
        id: "compose_volume_#{safe_name(name)}_#{index}",
        metadata: %{
          source: :docker_compose,
          compose_type: :volume,
          name: name
        }
      )
    end)
  end

  defp build_config_operations(configs) do
    configs
    |> Enum.with_index()
    |> Enum.map(fn {{name, config}, index} ->
      config = config || %{}

      Operation.new(
        :config_create,
        %{
          name: name,
          file: Map.get(config, "file"),
          external: Map.get(config, "external", false)
        },
        id: "compose_config_#{safe_name(name)}_#{index}",
        metadata: %{
          source: :docker_compose,
          compose_type: :config,
          name: name
        }
      )
    end)
  end

  defp build_secret_operations(secrets) do
    secrets
    |> Enum.with_index()
    |> Enum.map(fn {{name, config}, index} ->
      config = config || %{}

      Operation.new(
        :secret_create,
        %{
          name: name,
          file: Map.get(config, "file"),
          external: Map.get(config, "external", false)
        },
        id: "compose_secret_#{safe_name(name)}_#{index}",
        metadata: %{
          source: :docker_compose,
          compose_type: :secret,
          name: name
        }
      )
    end)
  end

  defp build_service_operations(services, _opts) do
    services
    |> Enum.with_index()
    |> Enum.map(fn {{name, config}, index} ->
      service_to_operation(name, config, index)
    end)
  end

  defp service_to_operation(name, config, index) do
    config = config || %{}

    Operation.new(
      :container_run,
      %{
        name: name,
        image: Map.get(config, "image"),
        build: normalize_build(Map.get(config, "build")),
        command: Map.get(config, "command"),
        entrypoint: Map.get(config, "entrypoint"),
        environment: normalize_environment(Map.get(config, "environment")),
        env_file: Map.get(config, "env_file"),
        ports: normalize_ports(Map.get(config, "ports", [])),
        expose: Map.get(config, "expose", []),
        volumes: normalize_volumes(Map.get(config, "volumes", [])),
        networks: Map.get(config, "networks", []),
        depends_on: normalize_depends_on(Map.get(config, "depends_on")),
        restart: Map.get(config, "restart", "no"),
        deploy: Map.get(config, "deploy"),
        healthcheck: Map.get(config, "healthcheck"),
        labels: Map.get(config, "labels", %{}),
        working_dir: Map.get(config, "working_dir"),
        user: Map.get(config, "user"),
        hostname: Map.get(config, "hostname"),
        extra_hosts: Map.get(config, "extra_hosts", []),
        dns: Map.get(config, "dns"),
        configs: Map.get(config, "configs", []),
        secrets: Map.get(config, "secrets", []),
        cap_add: Map.get(config, "cap_add", []),
        cap_drop: Map.get(config, "cap_drop", []),
        privileged: Map.get(config, "privileged", false),
        security_opt: Map.get(config, "security_opt", []),
        tmpfs: Map.get(config, "tmpfs"),
        ulimits: Map.get(config, "ulimits"),
        logging: Map.get(config, "logging"),
        stop_grace_period: Map.get(config, "stop_grace_period"),
        stop_signal: Map.get(config, "stop_signal")
      },
      id: "compose_service_#{safe_name(name)}_#{index}",
      metadata: %{
        source: :docker_compose,
        compose_type: :service,
        name: name,
        has_build: Map.has_key?(config, "build")
      }
    )
  end

  # Normalization helpers

  defp normalize_build(nil), do: nil
  defp normalize_build(build) when is_binary(build), do: %{context: build}

  defp normalize_build(build) when is_map(build) do
    %{
      context: Map.get(build, "context", "."),
      dockerfile: Map.get(build, "dockerfile"),
      args: Map.get(build, "args", %{}),
      target: Map.get(build, "target"),
      cache_from: Map.get(build, "cache_from", [])
    }
  end

  defp normalize_environment(nil), do: %{}

  defp normalize_environment(env) when is_list(env) do
    env
    |> Enum.map(fn
      item when is_binary(item) ->
        case String.split(item, "=", parts: 2) do
          [key, value] -> {key, value}
          [key] -> {key, nil}
        end

      item when is_map(item) ->
        Enum.map(item, fn {k, v} -> {k, v} end)
    end)
    |> List.flatten()
    |> Map.new()
  end

  defp normalize_environment(env) when is_map(env), do: env

  defp normalize_ports(nil), do: []

  defp normalize_ports(ports) when is_list(ports) do
    Enum.map(ports, &normalize_port/1)
  end

  defp normalize_port(port) when is_binary(port) do
    case parse_port_string(port) do
      {:ok, parsed} -> parsed
      :error -> %{raw: port}
    end
  end

  defp normalize_port(port) when is_integer(port) do
    %{target: port, published: port, protocol: "tcp"}
  end

  defp normalize_port(port) when is_map(port), do: port

  defp parse_port_string(port_str) do
    # Handle formats: "8080", "8080:80", "8080:80/udp", "127.0.0.1:8080:80"
    cond do
      String.contains?(port_str, "/") ->
        [port_part, protocol] = String.split(port_str, "/")

        case parse_port_string(port_part) do
          {:ok, parsed} -> {:ok, Map.put(parsed, :protocol, protocol)}
          :error -> :error
        end

      String.contains?(port_str, ":") ->
        parts = String.split(port_str, ":")

        case parts do
          [host_port, container_port] ->
            {:ok,
             %{
               published: parse_int(host_port),
               target: parse_int(container_port),
               protocol: "tcp"
             }}

          [host_ip, host_port, container_port] ->
            {:ok,
             %{
               host_ip: host_ip,
               published: parse_int(host_port),
               target: parse_int(container_port),
               protocol: "tcp"
             }}

          _ ->
            :error
        end

      true ->
        port = parse_int(port_str)
        {:ok, %{target: port, published: port, protocol: "tcp"}}
    end
  end

  defp parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {int, ""} -> int
      _ -> str
    end
  end

  defp parse_int(int) when is_integer(int), do: int

  defp normalize_volumes(nil), do: []

  defp normalize_volumes(volumes) when is_list(volumes) do
    Enum.map(volumes, &normalize_volume_mount/1)
  end

  defp normalize_volume_mount(vol) when is_binary(vol) do
    parts = String.split(vol, ":")

    case parts do
      [source, target] ->
        %{source: source, target: target, type: infer_volume_type(source)}

      [source, target, mode] ->
        %{
          source: source,
          target: target,
          type: infer_volume_type(source),
          read_only: mode == "ro"
        }

      [target] ->
        %{target: target, type: "volume"}
    end
  end

  defp normalize_volume_mount(vol) when is_map(vol), do: vol

  defp infer_volume_type(source) do
    cond do
      String.starts_with?(source, "/") -> "bind"
      String.starts_with?(source, "./") -> "bind"
      String.starts_with?(source, "~/") -> "bind"
      true -> "volume"
    end
  end

  defp normalize_depends_on(nil), do: []
  defp normalize_depends_on(deps) when is_list(deps), do: deps

  defp normalize_depends_on(deps) when is_map(deps) do
    # Handle extended depends_on format with condition
    Enum.map(deps, fn {name, config} ->
      condition = get_in(config, ["condition"])
      %{service: name, condition: condition}
    end)
  end

  # Dependency building

  defp build_dependencies(services, operations) do
    # Build lookup: service_name -> operation_id
    service_lookup =
      operations
      |> Enum.filter(fn op -> op.metadata[:compose_type] == :service end)
      |> Enum.map(fn op -> {op.metadata[:name], op.id} end)
      |> Map.new()

    # Build lookup: volume/network/config/secret name -> operation_id
    resource_lookup =
      operations
      |> Enum.reject(fn op -> op.metadata[:compose_type] == :service end)
      |> Enum.map(fn op -> {"#{op.metadata[:compose_type]}/#{op.metadata[:name]}", op.id} end)
      |> Map.new()

    deps =
      services
      |> Enum.flat_map(fn {name, config} ->
        config = config || %{}
        service_id = Map.get(service_lookup, name)

        if service_id do
          service_deps = extract_service_dependencies(config, service_id, service_lookup)
          resource_deps = extract_resource_dependencies(config, service_id, resource_lookup)
          service_deps ++ resource_deps
        else
          []
        end
      end)

    {:ok, deps}
  end

  defp extract_service_dependencies(config, service_id, service_lookup) do
    depends_on = normalize_depends_on(Map.get(config, "depends_on"))

    depends_on
    |> Enum.flat_map(fn
      dep when is_binary(dep) ->
        case Map.get(service_lookup, dep) do
          nil ->
            []

          dep_id ->
            [Dependency.new(dep_id, service_id, :requires, metadata: %{reason: "depends_on"})]
        end

      %{service: dep} ->
        case Map.get(service_lookup, dep) do
          nil ->
            []

          dep_id ->
            [Dependency.new(dep_id, service_id, :requires, metadata: %{reason: "depends_on"})]
        end

      _ ->
        []
    end)
  end

  defp extract_resource_dependencies(config, service_id, resource_lookup) do
    # Network dependencies
    network_deps =
      (Map.get(config, "networks") || [])
      |> List.wrap()
      |> Enum.flat_map(fn
        network when is_binary(network) ->
          case Map.get(resource_lookup, "network/#{network}") do
            nil ->
              []

            dep_id ->
              [Dependency.new(dep_id, service_id, :requires, metadata: %{reason: "network_ref"})]
          end

        _ ->
          []
      end)

    # Volume dependencies
    volume_deps =
      (Map.get(config, "volumes") || [])
      |> Enum.flat_map(fn
        vol when is_binary(vol) ->
          source = vol |> String.split(":") |> List.first()
          # Only add dependency for named volumes (not bind mounts)
          if not String.starts_with?(source, "/") and not String.starts_with?(source, ".") do
            case Map.get(resource_lookup, "volume/#{source}") do
              nil ->
                []

              dep_id ->
                [Dependency.new(dep_id, service_id, :requires, metadata: %{reason: "volume_ref"})]
            end
          else
            []
          end

        %{"source" => source} when is_binary(source) ->
          case Map.get(resource_lookup, "volume/#{source}") do
            nil ->
              []

            dep_id ->
              [Dependency.new(dep_id, service_id, :requires, metadata: %{reason: "volume_ref"})]
          end

        _ ->
          []
      end)

    # Config dependencies
    config_deps =
      (Map.get(config, "configs") || [])
      |> Enum.flat_map(fn
        cfg when is_binary(cfg) ->
          case Map.get(resource_lookup, "config/#{cfg}") do
            nil ->
              []

            dep_id ->
              [Dependency.new(dep_id, service_id, :requires, metadata: %{reason: "config_ref"})]
          end

        %{"source" => source} ->
          case Map.get(resource_lookup, "config/#{source}") do
            nil ->
              []

            dep_id ->
              [Dependency.new(dep_id, service_id, :requires, metadata: %{reason: "config_ref"})]
          end

        _ ->
          []
      end)

    # Secret dependencies
    secret_deps =
      (Map.get(config, "secrets") || [])
      |> Enum.flat_map(fn
        secret when is_binary(secret) ->
          case Map.get(resource_lookup, "secret/#{secret}") do
            nil ->
              []

            dep_id ->
              [Dependency.new(dep_id, service_id, :requires, metadata: %{reason: "secret_ref"})]
          end

        %{"source" => source} ->
          case Map.get(resource_lookup, "secret/#{source}") do
            nil ->
              []

            dep_id ->
              [Dependency.new(dep_id, service_id, :requires, metadata: %{reason: "secret_ref"})]
          end

        _ ->
          []
      end)

    network_deps ++ volume_deps ++ config_deps ++ secret_deps
  end

  defp safe_name(name) do
    name
    |> to_string()
    |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
    |> String.slice(0, 30)
  end
end
