# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

defmodule DNFinition.AdaWrapper do
  @moduledoc """
  Wraps the Ada TUI binary as a managed Port.

  The Ada binary handles:
  - Platform detection
  - ncurses TUI rendering
  - Package manager backend interactions
  - Snapshot operations

  This GenServer:
  - Manages the Ada process lifecycle
  - Handles communication via stdin/stdout
  - Provides fault tolerance (restart on crash)
  - Coordinates with other Elixir components
  """

  use GenServer
  require Logger

  @ada_binary "dnfinition"
  @timeout 30_000

  # ═══════════════════════════════════════════════════════════════════════════
  # Client API
  # ═══════════════════════════════════════════════════════════════════════════

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Start the Ada TUI in interactive mode.
  """
  def start_tui do
    GenServer.call(__MODULE__, :start_tui, @timeout)
  end

  @doc """
  Execute a command (non-interactive).
  """
  def execute(command, args \\ []) do
    GenServer.call(__MODULE__, {:execute, command, args}, @timeout)
  end

  @doc """
  Get platform information from Ada.
  """
  def get_platform_info do
    GenServer.call(__MODULE__, :get_platform_info, @timeout)
  end

  @doc """
  Request snapshot creation.
  """
  def create_snapshot(description) do
    GenServer.call(__MODULE__, {:create_snapshot, description}, @timeout)
  end

  @doc """
  Request rollback to snapshot.
  """
  def rollback(snapshot_id) do
    GenServer.call(__MODULE__, {:rollback, snapshot_id}, @timeout)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Server Callbacks
  # ═══════════════════════════════════════════════════════════════════════════

  @impl true
  def init(_opts) do
    # Find the Ada binary
    ada_path = find_ada_binary()

    state = %{
      ada_path: ada_path,
      port: nil,
      status: :idle
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:start_tui, _from, state) do
    case start_ada_process(state.ada_path, []) do
      {:ok, port} ->
        {:reply, :ok, %{state | port: port, status: :running}}

      {:error, reason} ->
        Logger.error("Failed to start Ada TUI: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:execute, command, args}, _from, state) do
    full_args = [command | args]

    case run_ada_command(state.ada_path, full_args) do
      {:ok, output} ->
        {:reply, {:ok, output}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_platform_info, _from, state) do
    case run_ada_command(state.ada_path, ["info", "--json"]) do
      {:ok, output} ->
        # Parse JSON output from Ada
        {:reply, {:ok, parse_platform_info(output)}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:create_snapshot, description}, _from, state) do
    # Delegate to SnapshotManager which coordinates with Ada
    case DNFinition.SnapshotManager.create(description) do
      {:ok, snapshot_id} ->
        {:reply, {:ok, snapshot_id}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:rollback, snapshot_id}, _from, state) do
    case DNFinition.SnapshotManager.rollback(snapshot_id) do
      :ok ->
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    # Handle output from Ada process
    Logger.debug("Ada output: #{inspect(data)}")
    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.info("Ada process exited with status: #{status}")

    if status != 0 do
      # Non-zero exit - Ada crashed or errored
      Logger.warning("Ada process exited abnormally")
      # Recovery will be handled by supervisor restart
    end

    {:noreply, %{state | port: nil, status: :stopped}}
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Private Functions
  # ═══════════════════════════════════════════════════════════════════════════

  defp find_ada_binary do
    # Look in standard locations
    paths = [
      Path.join([File.cwd!(), "ada", "dnfinition", "bin", @ada_binary]),
      Path.join([System.get_env("HOME"), ".local", "bin", @ada_binary]),
      Path.join(["/usr", "local", "bin", @ada_binary]),
      Path.join(["/usr", "bin", @ada_binary])
    ]

    Enum.find(paths, &File.exists?/1) ||
      raise "Could not find #{@ada_binary} binary"
  end

  defp start_ada_process(path, args) do
    try do
      port =
        Port.open({:spawn_executable, path}, [
          :binary,
          :exit_status,
          args: args,
          env: [{'TERM', 'xterm-256color'}]
        ])

      {:ok, port}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  defp run_ada_command(path, args) do
    case System.cmd(path, args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {output, code} -> {:error, "Exit code #{code}: #{output}"}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp parse_platform_info(json_output) do
    # TODO: Implement JSON parsing when Ada outputs JSON
    %{
      raw: json_output,
      os: :unknown,
      distribution: :unknown,
      package_manager: :unknown
    }
  end
end
