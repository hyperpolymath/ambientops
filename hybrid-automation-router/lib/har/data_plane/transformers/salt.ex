# SPDX-License-Identifier: MPL-2.0
defmodule HAR.DataPlane.Transformers.Salt do
  @moduledoc """
  Transformer for Salt Stack SLS format.

  Converts HAR semantic graph to Salt SLS (YAML) configuration.
  Generates requisites (require, watch, prereq) from dependency graph.
  """

  @behaviour HAR.DataPlane.Transformer

  alias HAR.Semantic.{Graph, Operation}
  require Logger

  @impl true
  def transform(%Graph{} = graph, opts \\ []) do
    with {:ok, sorted_ops} <- Graph.topological_sort(graph),
         {:ok, states} <- operations_to_states(sorted_ops, graph, opts),
         {:ok, sls_content} <- format_sls(states, opts) do
      {:ok, sls_content}
    end
  end

  @impl true
  def validate(%Graph{} = graph) do
    Graph.validate(graph)
  end

  # Internal Functions

  defp operations_to_states(operations, graph, opts) do
    # Build operation ID to state ID mapping
    op_to_state = build_op_state_mapping(operations)

    states =
      operations
      |> Enum.with_index()
      |> Enum.map(fn {op, idx} ->
        requisites = build_requisites(op, graph, op_to_state)
        operation_to_state(op, idx, requisites, opts)
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, states}
  end

  defp build_op_state_mapping(operations) do
    operations
    |> Enum.with_index()
    |> Enum.map(fn {op, idx} ->
      state_id = state_id_for_operation(op, idx, get_prefix_for_type(op.type))
      {op.id, state_id}
    end)
    |> Map.new()
  end

  defp get_prefix_for_type(:package_install), do: "install_package"
  defp get_prefix_for_type(:package_remove), do: "remove_package"
  defp get_prefix_for_type(:package_upgrade), do: "upgrade_package"
  defp get_prefix_for_type(:service_start), do: "start_service"
  defp get_prefix_for_type(:service_stop), do: "stop_service"
  defp get_prefix_for_type(:service_restart), do: "restart_service"
  defp get_prefix_for_type(:service_enable), do: "enable_service"
  defp get_prefix_for_type(:service_disable), do: "disable_service"
  defp get_prefix_for_type(:file_write), do: "manage_file"
  defp get_prefix_for_type(:file_copy), do: "copy_file"
  defp get_prefix_for_type(:file_template), do: "template_file"
  defp get_prefix_for_type(:file_delete), do: "delete_file"
  defp get_prefix_for_type(:directory_create), do: "create_directory"
  defp get_prefix_for_type(:directory_delete), do: "delete_directory"
  defp get_prefix_for_type(:user_create), do: "create_user"
  defp get_prefix_for_type(:user_delete), do: "delete_user"
  defp get_prefix_for_type(:group_create), do: "create_group"
  defp get_prefix_for_type(:group_delete), do: "delete_group"
  defp get_prefix_for_type(:command_run), do: "run_command"
  defp get_prefix_for_type(:shell_run), do: "run_shell"
  defp get_prefix_for_type(:script_execute), do: "execute_script"
  defp get_prefix_for_type(:cron_create), do: "create_cron"
  defp get_prefix_for_type(:cron_delete), do: "delete_cron"
  defp get_prefix_for_type(:git_clone), do: "clone_git"
  defp get_prefix_for_type(:docker_container), do: "manage_container"
  defp get_prefix_for_type(:docker_image), do: "manage_image"
  defp get_prefix_for_type(_), do: "state"

  # Build requisites from dependency graph
  defp build_requisites(op, graph, op_to_state) do
    # Find all dependencies where this operation is the target
    deps = get_dependencies_for_op(op.id, graph)

    # Group by dependency type
    requires = filter_deps_by_type(deps, [:requires, :sequential], op_to_state)
    watches = filter_deps_by_type(deps, [:watches, :watch], op_to_state)
    prereqs = filter_deps_by_type(deps, [:prereq], op_to_state)
    onfails = filter_deps_by_type(deps, [:onfail], op_to_state)

    %{
      require: requires,
      watch: watches,
      prereq: prereqs,
      onfail: onfails
    }
  end

  defp get_dependencies_for_op(op_id, graph) do
    # Find edges where this op is the destination (to)
    Enum.filter(graph.edges, fn dep ->
      dep.to == op_id
    end)
  end

  defp filter_deps_by_type(deps, types, op_to_state) do
    deps
    |> Enum.filter(fn dep -> dep.type in types end)
    |> Enum.map(fn dep ->
      # Map from operation ID to state ID
      Map.get(op_to_state, dep.from)
    end)
    |> Enum.reject(&is_nil/1)
  end

  # Add requisites to state definition
  defp add_requisites(state_def, requisites) do
    state_def
    |> add_requisite_list("require", requisites.require)
    |> add_requisite_list("watch", requisites.watch)
    |> add_requisite_list("prereq", requisites.prereq)
    |> add_requisite_list("onfail", requisites.onfail)
  end

  defp add_requisite_list(state_def, _key, []), do: state_def

  defp add_requisite_list(state_def, key, state_ids) do
    requisites = Enum.map(state_ids, fn id -> %{"state" => id} end)
    state_def ++ [%{key => requisites}]
  end

  # Operation to State transformations

  defp operation_to_state(%Operation{type: :package_install} = op, idx, requisites, _opts) do
    state_id = state_id_for_operation(op, idx, "install_package")
    pkg_name = op.params[:package] || op.params[:name]

    state_def = [%{"name" => pkg_name}]

    state_def =
      if op.params[:version],
        do: state_def ++ [%{"version" => op.params[:version]}],
        else: state_def

    state_def = if op.params[:refresh], do: state_def ++ [%{"refresh" => true}], else: state_def
    state_def = add_requisites(state_def, requisites)

    {state_id, %{"pkg.installed" => state_def}}
  end

  defp operation_to_state(%Operation{type: :package_remove} = op, idx, requisites, _opts) do
    state_id = state_id_for_operation(op, idx, "remove_package")
    pkg_name = op.params[:package] || op.params[:name]

    state_def = [%{"name" => pkg_name}]
    state_def = add_requisites(state_def, requisites)

    {state_id, %{"pkg.removed" => state_def}}
  end

  defp operation_to_state(%Operation{type: :package_upgrade} = op, idx, requisites, _opts) do
    state_id = state_id_for_operation(op, idx, "upgrade_package")
    pkg_name = op.params[:package] || op.params[:name]

    state_def = [%{"name" => pkg_name}]
    state_def = add_requisites(state_def, requisites)

    {state_id, %{"pkg.latest" => state_def}}
  end

  defp operation_to_state(%Operation{type: :service_start} = op, idx, requisites, _opts) do
    state_id = state_id_for_operation(op, idx, "start_service")
    service_name = op.params[:service] || op.params[:name]

    state_def = [%{"name" => service_name}]
    state_def = if op.params[:enabled], do: state_def ++ [%{"enable" => true}], else: state_def
    state_def = add_requisites(state_def, requisites)

    {state_id, %{"service.running" => state_def}}
  end

  defp operation_to_state(%Operation{type: :service_stop} = op, idx, requisites, _opts) do
    state_id = state_id_for_operation(op, idx, "stop_service")
    service_name = op.params[:service] || op.params[:name]

    state_def = [%{"name" => service_name}]
    state_def = add_requisites(state_def, requisites)

    {state_id, %{"service.dead" => state_def}}
  end

  defp operation_to_state(%Operation{type: :service_restart} = op, idx, requisites, _opts) do
    state_id = state_id_for_operation(op, idx, "restart_service")
    service_name = op.params[:service] || op.params[:name]

    # Salt doesn't have service.restart - use module.run with service.restart
    state_def = [
      %{"name" => "service.restart"},
      %{"m_name" => service_name}
    ]

    state_def = add_requisites(state_def, requisites)

    {state_id, %{"module.run" => state_def}}
  end

  defp operation_to_state(%Operation{type: :service_enable} = op, idx, requisites, _opts) do
    state_id = state_id_for_operation(op, idx, "enable_service")
    service_name = op.params[:service] || op.params[:name]

    state_def = [%{"name" => service_name}, %{"enable" => true}]
    state_def = add_requisites(state_def, requisites)

    {state_id, %{"service.enabled" => state_def}}
  end

  defp operation_to_state(%Operation{type: :service_disable} = op, idx, requisites, _opts) do
    state_id = state_id_for_operation(op, idx, "disable_service")
    service_name = op.params[:service] || op.params[:name]

    state_def = [%{"name" => service_name}]
    state_def = add_requisites(state_def, requisites)

    {state_id, %{"service.disabled" => state_def}}
  end

  defp operation_to_state(%Operation{type: :file_write} = op, idx, requisites, _opts) do
    state_id = state_id_for_operation(op, idx, "manage_file")
    path = op.params[:path] || op.params[:destination]

    state_def = [%{"name" => path}]
    state_def = maybe_add(state_def, "contents", op.params[:content])
    state_def = maybe_add(state_def, "source", op.params[:source])
    state_def = maybe_add(state_def, "mode", op.params[:mode])
    state_def = maybe_add(state_def, "user", op.params[:owner] || op.params[:user])
    state_def = maybe_add(state_def, "group", op.params[:group])
    state_def = maybe_add(state_def, "template", op.params[:template])
    state_def = add_requisites(state_def, requisites)

    {state_id, %{"file.managed" => state_def}}
  end

  defp operation_to_state(%Operation{type: :file_copy} = op, idx, requisites, _opts) do
    state_id = state_id_for_operation(op, idx, "copy_file")

    state_def = [
      %{"name" => op.params[:destination]},
      %{"source" => op.params[:source]}
    ]

    state_def = maybe_add(state_def, "mode", op.params[:mode])
    state_def = maybe_add(state_def, "user", op.params[:owner] || op.params[:user])
    state_def = maybe_add(state_def, "group", op.params[:group])
    state_def = add_requisites(state_def, requisites)

    {state_id, %{"file.managed" => state_def}}
  end

  defp operation_to_state(%Operation{type: :file_template} = op, idx, requisites, _opts) do
    state_id = state_id_for_operation(op, idx, "template_file")

    state_def = [
      %{"name" => op.params[:destination]},
      %{"source" => op.params[:source]},
      %{"template" => op.params[:template] || "jinja"}
    ]

    state_def = maybe_add(state_def, "mode", op.params[:mode])
    state_def = maybe_add(state_def, "user", op.params[:owner] || op.params[:user])
    state_def = maybe_add(state_def, "group", op.params[:group])
    state_def = add_requisites(state_def, requisites)

    {state_id, %{"file.managed" => state_def}}
  end

  defp operation_to_state(%Operation{type: :file_delete} = op, idx, requisites, _opts) do
    state_id = state_id_for_operation(op, idx, "delete_file")
    path = op.params[:path]

    state_def = [%{"name" => path}]
    state_def = add_requisites(state_def, requisites)

    {state_id, %{"file.absent" => state_def}}
  end

  defp operation_to_state(%Operation{type: :directory_create} = op, idx, requisites, _opts) do
    state_id = state_id_for_operation(op, idx, "create_directory")

    state_def = [%{"name" => op.params[:path]}]
    state_def = maybe_add(state_def, "mode", op.params[:mode])
    state_def = maybe_add(state_def, "user", op.params[:owner] || op.params[:user])
    state_def = maybe_add(state_def, "group", op.params[:group])
    state_def = maybe_add(state_def, "makedirs", op.params[:makedirs])
    state_def = add_requisites(state_def, requisites)

    {state_id, %{"file.directory" => state_def}}
  end

  defp operation_to_state(%Operation{type: :directory_delete} = op, idx, requisites, _opts) do
    state_id = state_id_for_operation(op, idx, "delete_directory")

    state_def = [%{"name" => op.params[:path]}]
    state_def = add_requisites(state_def, requisites)

    {state_id, %{"file.absent" => state_def}}
  end

  defp operation_to_state(%Operation{type: :user_create} = op, idx, requisites, _opts) do
    state_id = state_id_for_operation(op, idx, "create_user")

    state_def = [%{"name" => op.params[:name]}]
    state_def = maybe_add(state_def, "shell", op.params[:shell])
    state_def = maybe_add(state_def, "home", op.params[:home])
    state_def = maybe_add(state_def, "groups", op.params[:groups])
    state_def = maybe_add(state_def, "uid", op.params[:uid])
    state_def = maybe_add(state_def, "gid", op.params[:gid])
    state_def = add_requisites(state_def, requisites)

    {state_id, %{"user.present" => state_def}}
  end

  defp operation_to_state(%Operation{type: :user_delete} = op, idx, requisites, _opts) do
    state_id = state_id_for_operation(op, idx, "delete_user")

    state_def = [%{"name" => op.params[:name]}]
    state_def = maybe_add(state_def, "purge", op.params[:purge])
    state_def = add_requisites(state_def, requisites)

    {state_id, %{"user.absent" => state_def}}
  end

  defp operation_to_state(%Operation{type: :group_create} = op, idx, requisites, _opts) do
    state_id = state_id_for_operation(op, idx, "create_group")

    state_def = [%{"name" => op.params[:name]}]
    state_def = maybe_add(state_def, "gid", op.params[:gid])
    state_def = add_requisites(state_def, requisites)

    {state_id, %{"group.present" => state_def}}
  end

  defp operation_to_state(%Operation{type: :group_delete} = op, idx, requisites, _opts) do
    state_id = state_id_for_operation(op, idx, "delete_group")

    state_def = [%{"name" => op.params[:name]}]
    state_def = add_requisites(state_def, requisites)

    {state_id, %{"group.absent" => state_def}}
  end

  defp operation_to_state(%Operation{type: :command_run} = op, idx, requisites, _opts) do
    state_id = state_id_for_operation(op, idx, "run_command")
    cmd = op.params[:command] || op.params[:cmd]

    state_def = [%{"name" => cmd}]
    state_def = maybe_add(state_def, "cwd", op.params[:chdir] || op.params[:cwd])
    state_def = maybe_add(state_def, "creates", op.params[:creates])
    state_def = maybe_add(state_def, "unless", op.params[:unless])
    state_def = maybe_add(state_def, "onlyif", op.params[:onlyif])
    state_def = maybe_add(state_def, "runas", op.params[:user])
    state_def = add_requisites(state_def, requisites)

    {state_id, %{"cmd.run" => state_def}}
  end

  defp operation_to_state(%Operation{type: :shell_run} = op, idx, requisites, _opts) do
    state_id = state_id_for_operation(op, idx, "run_shell")
    cmd = op.params[:command] || op.params[:cmd]

    state_def = [%{"name" => cmd}]
    state_def = maybe_add(state_def, "cwd", op.params[:chdir] || op.params[:cwd])
    state_def = maybe_add(state_def, "shell", op.params[:shell] || "/bin/bash")
    state_def = add_requisites(state_def, requisites)

    {state_id, %{"cmd.run" => state_def}}
  end

  defp operation_to_state(%Operation{type: :script_execute} = op, idx, requisites, _opts) do
    state_id = state_id_for_operation(op, idx, "execute_script")
    script = op.params[:script] || op.params[:path]

    state_def = [%{"name" => script}]
    state_def = maybe_add(state_def, "cwd", op.params[:cwd])
    state_def = add_requisites(state_def, requisites)

    {state_id, %{"cmd.script" => state_def}}
  end

  defp operation_to_state(%Operation{type: :cron_create} = op, idx, requisites, _opts) do
    state_id = state_id_for_operation(op, idx, "create_cron")

    state_def = [
      %{"name" => op.params[:name]},
      %{"user" => op.params[:user] || "root"}
    ]

    state_def = maybe_add(state_def, "minute", op.params[:minute])
    state_def = maybe_add(state_def, "hour", op.params[:hour])
    state_def = maybe_add(state_def, "daymonth", op.params[:day])
    state_def = maybe_add(state_def, "month", op.params[:month])
    state_def = maybe_add(state_def, "dayweek", op.params[:weekday])
    state_def = add_requisites(state_def, requisites)

    {state_id, %{"cron.present" => state_def}}
  end

  defp operation_to_state(%Operation{type: :cron_delete} = op, idx, requisites, _opts) do
    state_id = state_id_for_operation(op, idx, "delete_cron")

    state_def = [
      %{"name" => op.params[:name]},
      %{"user" => op.params[:user] || "root"}
    ]

    state_def = add_requisites(state_def, requisites)

    {state_id, %{"cron.absent" => state_def}}
  end

  defp operation_to_state(%Operation{type: :git_clone} = op, idx, requisites, _opts) do
    state_id = state_id_for_operation(op, idx, "clone_git")

    state_def = [
      %{"name" => op.params[:repo] || op.params[:url]},
      %{"target" => op.params[:dest] || op.params[:destination]}
    ]

    state_def = maybe_add(state_def, "rev", op.params[:version] || op.params[:branch])
    state_def = maybe_add(state_def, "depth", op.params[:depth])
    state_def = maybe_add(state_def, "user", op.params[:user])
    state_def = add_requisites(state_def, requisites)

    {state_id, %{"git.latest" => state_def}}
  end

  defp operation_to_state(%Operation{type: :docker_container} = op, idx, requisites, _opts) do
    state_id = state_id_for_operation(op, idx, "manage_container")

    state_def = [
      %{"name" => op.params[:name]},
      %{"image" => op.params[:image]}
    ]

    state_def = maybe_add(state_def, "port_bindings", op.params[:ports])
    state_def = maybe_add(state_def, "binds", op.params[:volumes])
    state_def = maybe_add(state_def, "environment", op.params[:env])
    state_def = add_requisites(state_def, requisites)

    {state_id, %{"docker_container.running" => state_def}}
  end

  defp operation_to_state(%Operation{type: :docker_image} = op, idx, requisites, _opts) do
    state_id = state_id_for_operation(op, idx, "manage_image")

    state_def = [%{"name" => op.params[:name]}]
    state_def = maybe_add(state_def, "tag", op.params[:tag])
    state_def = add_requisites(state_def, requisites)

    {state_id, %{"docker_image.present" => state_def}}
  end

  defp operation_to_state(%Operation{type: :pip_install} = op, idx, requisites, _opts) do
    state_id = state_id_for_operation(op, idx, "install_pip")
    pkg_name = op.params[:package] || op.params[:name]

    state_def = [%{"name" => pkg_name}]
    state_def = maybe_add(state_def, "pip_bin", op.params[:pip_bin])
    state_def = maybe_add(state_def, "requirements", op.params[:requirements])
    state_def = add_requisites(state_def, requisites)

    {state_id, %{"pip.installed" => state_def}}
  end

  defp operation_to_state(%Operation{type: :npm_install} = op, idx, requisites, _opts) do
    state_id = state_id_for_operation(op, idx, "install_npm")
    pkg_name = op.params[:package] || op.params[:name]

    state_def = [%{"name" => pkg_name}]
    state_def = maybe_add(state_def, "dir", op.params[:dir])
    state_def = add_requisites(state_def, requisites)

    {state_id, %{"npm.installed" => state_def}}
  end

  defp operation_to_state(%Operation{type: type} = op, idx, requisites, _opts) do
    # Fallback for unsupported types
    Logger.warning("Unsupported operation type for Salt: #{type}")

    state_id = state_id_for_operation(op, idx, "unsupported")

    state_def = [%{"name" => "echo 'Unsupported operation: #{type}'"}]
    state_def = add_requisites(state_def, requisites)

    {state_id, %{"cmd.run" => state_def}}
  end

  defp state_id_for_operation(op, idx, prefix) do
    case op.metadata[:task_name] || op.metadata[:state_id] do
      nil ->
        "#{prefix}_#{idx}"

      name ->
        safe_name =
          name
          |> to_string()
          |> String.downcase()
          |> String.replace(~r/[^a-z0-9_]/, "_")
          |> String.slice(0..50)

        "#{safe_name}_#{idx}"
    end
  end

  defp maybe_add(list, _key, nil), do: list
  defp maybe_add(list, key, value), do: list ++ [%{key => value}]

  defp format_sls(states, _opts) do
    sls_map = Enum.into(states, %{})
    HAR.Utils.YamlFormatter.to_yaml(sls_map)
  end
end
