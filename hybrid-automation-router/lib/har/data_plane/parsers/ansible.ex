# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>

defmodule HAR.DataPlane.Parsers.Ansible do
  @moduledoc """
  Parser for Ansible playbooks (YAML format).

  Converts Ansible tasks to HAR semantic graph operations.
  Extracts sequential task dependencies, notify/handler dependencies,
  and when/conditional dependencies from playbook structure.
  """

  @behaviour HAR.DataPlane.Parser

  alias HAR.Semantic.{Graph, Operation, Dependency}
  require Logger

  @impl true
  def parse(yaml_content, opts \\ []) when is_binary(yaml_content) do
    with {:ok, playbook} <- parse_yaml(yaml_content),
         {:ok, operations} <- extract_operations(playbook, opts),
         {:ok, dependencies} <- build_dependencies(operations) do
      graph =
        Graph.new(
          vertices: operations,
          edges: dependencies,
          metadata: %{source: :ansible, parsed_at: DateTime.utc_now()}
        )

      {:ok, graph}
    end
  end

  @impl true
  def validate(yaml_content) when is_binary(yaml_content) do
    case parse_yaml(yaml_content) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  # Internal Functions

  defp parse_yaml(yaml_content) do
    case YamlElixir.read_from_string(yaml_content) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, {:yaml_parse_error, reason}}
    end
  rescue
    e -> {:error, {:yaml_parse_error, Exception.message(e)}}
  end

  defp extract_operations(playbook, _opts) when is_list(playbook) do
    operations =
      playbook
      |> Enum.with_index()
      |> Enum.flat_map(fn {play, play_index} ->
        extract_play_operations(play, play_index)
      end)

    {:ok, operations}
  end

  defp extract_operations(playbook, opts) when is_map(playbook) do
    # Single play as map
    extract_operations([playbook], opts)
  end

  defp extract_play_operations(play, play_index) when is_map(play) do
    tasks = Map.get(play, "tasks", [])
    handlers = Map.get(play, "handlers", [])
    hosts = Map.get(play, "hosts", "all")

    task_ops =
      tasks
      |> Enum.with_index()
      |> Enum.map(fn {task, task_index} ->
        task_to_operation(task, hosts, {play_index, task_index})
      end)

    # Handlers are offset by 1000 to avoid ID collisions with tasks
    handler_ops =
      handlers
      |> Enum.with_index()
      |> Enum.map(fn {handler, handler_index} ->
        op = task_to_operation(handler, hosts, {play_index, 1000 + handler_index})
        %{op | metadata: Map.put(op.metadata, :is_handler, true)}
      end)

    task_ops ++ handler_ops
  end

  defp task_to_operation(task, hosts, {play_idx, task_idx}) when is_map(task) do
    {module_name, module_args} = extract_module(task)
    task_name = Map.get(task, "name", "Unnamed task")

    Operation.new(
      normalize_module_type(module_name, module_args),
      normalize_module_params(module_name, module_args),
      id: generate_task_id(play_idx, task_idx),
      target: extract_target(hosts, task),
      metadata: %{
        source: :ansible,
        original_task: task,
        task_name: task_name,
        module: module_name,
        hosts: hosts
      }
    )
  end

  defp extract_module(task) when is_map(task) do
    # Find module (key that's not a meta-attribute)
    meta_keys = ~w(name when register notify changed_when failed_when tags become)

    module_entry =
      task
      |> Map.drop(meta_keys)
      |> Enum.find(fn {_k, v} -> is_map(v) or is_binary(v) or is_list(v) end)

    case module_entry do
      {module_name, module_args} ->
        {module_name, normalize_args(module_args)}

      nil ->
        # Fallback: command module with raw command
        {command, _} = Enum.find(task, fn {k, _v} -> k not in meta_keys end)
        {"command", %{"cmd" => Map.get(task, command)}}
    end
  end

  defp normalize_args(args) when is_map(args), do: args
  defp normalize_args(args) when is_binary(args), do: %{"_raw" => args}
  defp normalize_args(args) when is_list(args), do: %{"_list" => args}
  defp normalize_args(args), do: %{"_value" => args}

  defp normalize_module_type("apt", _args), do: :package_install
  defp normalize_module_type("yum", _args), do: :package_install
  defp normalize_module_type("dnf", _args), do: :package_install
  defp normalize_module_type("package", _args), do: :package_install

  defp normalize_module_type("service", args), do: service_type_from_state(args)
  defp normalize_module_type("systemd", args), do: service_type_from_state(args)

  defp normalize_module_type("copy", _args), do: :file_copy
  defp normalize_module_type("template", _args), do: :file_template
  defp normalize_module_type("file", _args), do: :file_write
  defp normalize_module_type("lineinfile", _args), do: :file_write
  defp normalize_module_type("user", _args), do: :user_create
  defp normalize_module_type("group", _args), do: :group_create
  defp normalize_module_type("command", _args), do: :command_run
  defp normalize_module_type("shell", _args), do: :command_run
  defp normalize_module_type("script", _args), do: :script_execute
  defp normalize_module_type(module, _args), do: String.to_atom("ansible." <> module)

  defp service_type_from_state(args) when is_map(args) do
    case Map.get(args, "state") do
      "started" -> :service_start
      "stopped" -> :service_stop
      "restarted" -> :service_restart
      "reloaded" -> :service_restart
      _ -> :service_control
    end
  end

  defp service_type_from_state(_), do: :service_control

  defp normalize_module_params("apt", args) do
    %{
      package: Map.get(args, "name") || Map.get(args, "pkg"),
      state: parse_package_state(Map.get(args, "state", "present")),
      update_cache: Map.get(args, "update_cache", false)
    }
  end

  defp normalize_module_params("yum", args) do
    %{
      package: Map.get(args, "name"),
      state: parse_package_state(Map.get(args, "state", "present"))
    }
  end

  defp normalize_module_params("package", args) do
    %{
      package: Map.get(args, "name"),
      state: parse_package_state(Map.get(args, "state", "present"))
    }
  end

  defp normalize_module_params("service", args) do
    %{
      service: Map.get(args, "name"),
      state: parse_service_state(Map.get(args, "state")),
      enabled: Map.get(args, "enabled")
    }
  end

  defp normalize_module_params("copy", args) do
    %{
      source: Map.get(args, "src"),
      destination: Map.get(args, "dest"),
      content: Map.get(args, "content"),
      mode: Map.get(args, "mode"),
      owner: Map.get(args, "owner"),
      group: Map.get(args, "group")
    }
  end

  defp normalize_module_params("template", args) do
    %{
      source: Map.get(args, "src"),
      destination: Map.get(args, "dest"),
      mode: Map.get(args, "mode"),
      owner: Map.get(args, "owner"),
      group: Map.get(args, "group")
    }
  end

  defp normalize_module_params("file", args) do
    %{
      path: Map.get(args, "path") || Map.get(args, "dest"),
      state: Map.get(args, "state", "file"),
      mode: Map.get(args, "mode"),
      owner: Map.get(args, "owner"),
      group: Map.get(args, "group")
    }
  end

  defp normalize_module_params("user", args) do
    %{
      name: Map.get(args, "name"),
      state: Map.get(args, "state", "present"),
      shell: Map.get(args, "shell"),
      home: Map.get(args, "home"),
      groups: Map.get(args, "groups", [])
    }
  end

  defp normalize_module_params("command", args) do
    %{
      command: Map.get(args, "cmd") || Map.get(args, "_raw"),
      chdir: Map.get(args, "chdir"),
      creates: Map.get(args, "creates")
    }
  end

  defp normalize_module_params(_module, args), do: args

  defp parse_package_state("present"), do: :install
  defp parse_package_state("installed"), do: :install
  defp parse_package_state("absent"), do: :remove
  defp parse_package_state("removed"), do: :remove
  defp parse_package_state("latest"), do: :upgrade
  defp parse_package_state(state), do: state

  defp parse_service_state("started"), do: :start
  defp parse_service_state("stopped"), do: :stop
  defp parse_service_state("restarted"), do: :restart
  defp parse_service_state("reloaded"), do: :reload
  defp parse_service_state(state), do: state

  defp extract_target(hosts, task) do
    %{
      hosts: hosts,
      when: Map.get(task, "when"),
      environment: detect_environment(hosts)
    }
  end

  defp detect_environment(hosts) when is_binary(hosts) do
    cond do
      String.contains?(hosts, "prod") -> :prod
      String.contains?(hosts, "staging") -> :staging
      String.contains?(hosts, "dev") -> :dev
      true -> :unknown
    end
  end

  defp detect_environment(_), do: :unknown

  defp build_dependencies(operations) do
    # Build sequential dependencies for non-handler tasks only
    # (handlers run after all tasks, triggered by notify)
    sequential_deps =
      operations
      |> Enum.reject(fn op -> op.metadata[:is_handler] end)
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [op1, op2] ->
        Dependency.new(op1.id, op2.id, :sequential, metadata: %{reason: "ansible_task_order"})
      end)

    # Extract notify/handler dependencies
    notify_deps = build_notify_dependencies(operations)

    # Extract when/conditional dependencies (registered variable references)
    conditional_deps = build_conditional_dependencies(operations)

    {:ok, sequential_deps ++ notify_deps ++ conditional_deps}
  end

  # Build dependencies from task notify directives to handler operations.
  # In Ansible, a task can have `notify: handler_name` or `notify: [h1, h2]`
  # which triggers the named handler(s) when the task reports a change.
  defp build_notify_dependencies(operations) do
    handler_lookup =
      operations
      |> Enum.filter(fn op -> op.metadata[:is_handler] end)
      |> Enum.map(fn op -> {op.metadata.task_name, op.id} end)
      |> Map.new()

    operations
    |> Enum.reject(fn op -> op.metadata[:is_handler] end)
    |> Enum.flat_map(fn op ->
      case get_in(op.metadata, [:original_task, "notify"]) do
        nil ->
          []

        handler_name when is_binary(handler_name) ->
          notify_dep_for_handler(op.id, handler_name, handler_lookup)

        handler_names when is_list(handler_names) ->
          Enum.flat_map(handler_names, fn name ->
            notify_dep_for_handler(op.id, name, handler_lookup)
          end)

        _other ->
          []
      end
    end)
  end

  defp notify_dep_for_handler(task_id, handler_name, handler_lookup) do
    case Map.get(handler_lookup, handler_name) do
      nil ->
        Logger.warning(
          "Ansible parser: task #{task_id} notifies unknown handler #{inspect(handler_name)}"
        )

        []

      handler_id ->
        [Dependency.new(task_id, handler_id, :notifies, metadata: %{reason: "ansible_notify"})]
    end
  end

  # Build conditional dependencies based on `when:` clauses that reference
  # registered variables. In Ansible, `register: var_name` saves task output,
  # and `when: var_name.rc == 0` creates an implicit dependency.
  defp build_conditional_dependencies(operations) do
    # Build a lookup of registered variable name -> operation ID
    register_lookup =
      operations
      |> Enum.flat_map(fn op ->
        case get_in(op.metadata, [:original_task, "register"]) do
          nil -> []
          var_name when is_binary(var_name) -> [{var_name, op.id}]
          _other -> []
        end
      end)
      |> Map.new()

    operations
    |> Enum.flat_map(fn op ->
      case get_in(op.metadata, [:original_task, "when"]) do
        nil ->
          []

        condition when is_binary(condition) ->
          find_conditional_deps(op.id, condition, register_lookup)

        conditions when is_list(conditions) ->
          Enum.flat_map(conditions, fn cond_str ->
            if is_binary(cond_str) do
              find_conditional_deps(op.id, cond_str, register_lookup)
            else
              []
            end
          end)

        _other ->
          []
      end
    end)
  end

  # Scan a when-condition string for references to registered variables.
  # Returns a list of :conditional dependencies from the registering task
  # to the task with the when clause.
  defp find_conditional_deps(dependent_id, condition, register_lookup) do
    register_lookup
    |> Enum.flat_map(fn {var_name, registering_id} ->
      # Match the variable name as a standalone token or dotted access
      # (e.g., "result" in "result.rc == 0" or "result is defined")
      if String.contains?(condition, var_name) and registering_id != dependent_id do
        [
          Dependency.new(registering_id, dependent_id, :conditional,
            metadata: %{
              reason: "ansible_when_register",
              variable: var_name,
              condition: condition
            }
          )
        ]
      else
        []
      end
    end)
  end

  defp generate_task_id(play_idx, task_idx) do
    "ansible_p#{play_idx}_t#{task_idx}_#{:erlang.unique_integer([:positive])}"
  end
end
