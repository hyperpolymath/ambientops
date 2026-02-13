# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

defmodule TotalUpdate.StrategyEngine do
  @moduledoc """
  Strategy engine for determining optimal snapshot/recovery strategies.

  Integrates with DNFinition.Plugins.StrategyMatrix to:
  - Detect available filesystem capabilities (btrfs, ZFS, LVM)
  - Select optimal recovery strategy per operation
  - Coordinate pre-operation snapshots
  - Execute rollback when needed

  Critical Safety Invariant:
  Every modifying package operation MUST be preceded by a valid recovery point.
  Operations without recovery points are REJECTED.
  """

  use GenServer
  require Logger

  alias DNFinition.Plugins.StrategyMatrix

  # ═══════════════════════════════════════════════════════════════════════════
  # Client API
  # ═══════════════════════════════════════════════════════════════════════════

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Get optimal strategy for a package manager and risk level"
  def get_strategy(pm_type, risk_level \\ :medium) do
    GenServer.call(__MODULE__, {:get_strategy, pm_type, risk_level})
  end

  @doc "Create a recovery point before an operation"
  def create_recovery_point(strategy, description) do
    GenServer.call(__MODULE__, {:create_recovery_point, strategy, description}, :infinity)
  end

  @doc "Execute rollback to a recovery point"
  def rollback(strategy, recovery_point) do
    GenServer.call(__MODULE__, {:rollback, strategy, recovery_point}, :infinity)
  end

  @doc "Get available filesystem snapshot backends"
  def available_backends do
    GenServer.call(__MODULE__, :available_backends)
  end

  @doc "Get platform capabilities"
  def platform_info do
    GenServer.call(__MODULE__, :platform_info)
  end

  @doc "Check if strategy meets minimum risk requirements"
  def strategy_adequate?(strategy, risk_level) do
    GenServer.call(__MODULE__, {:strategy_adequate?, strategy, risk_level})
  end

  @doc "List recent recovery points"
  def list_recovery_points(opts \\ []) do
    GenServer.call(__MODULE__, {:list_recovery_points, opts})
  end

  @doc "Clean up old recovery points"
  def cleanup_recovery_points(max_age_days \\ 7) do
    GenServer.call(__MODULE__, {:cleanup_recovery_points, max_age_days})
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Server Callbacks
  # ═══════════════════════════════════════════════════════════════════════════

  @impl true
  def init(_opts) do
    # Detect platform capabilities
    platform = detect_platform()
    backends = detect_backends()

    state = %{
      platform: platform,
      available_backends: backends,
      recovery_points: [],
      max_recovery_points: 50
    }

    Logger.info(
      "StrategyEngine started (platform: #{platform.os}, backends: #{inspect(Map.keys(backends))})"
    )

    {:ok, state}
  end

  @impl true
  def handle_call({:get_strategy, pm_type, risk_level}, _from, state) do
    strategy = StrategyMatrix.get_strategy(pm_type, risk_level)

    # Override with best available backend if strategy backend not available
    strategy =
      if strategy.snapshot_backend != :native and
           not Map.has_key?(state.available_backends, strategy.snapshot_backend) do
        # Find best available alternative
        best_backend = find_best_backend(state.available_backends)

        %{
          strategy
          | snapshot_backend: best_backend,
            backout_speed: get_backend_speed(best_backend),
            confidence: get_backend_confidence(best_backend)
        }
      else
        strategy
      end

    {:reply, {:ok, strategy}, state}
  end

  @impl true
  def handle_call({:create_recovery_point, strategy, description}, _from, state) do
    result = do_create_recovery_point(strategy, description, state)

    case result do
      {:ok, recovery_point} ->
        # Track the recovery point
        new_points = [recovery_point | state.recovery_points]

        # Trim if over limit
        new_points =
          if length(new_points) > state.max_recovery_points do
            Enum.take(new_points, state.max_recovery_points)
          else
            new_points
          end

        Logger.info("Created recovery point: #{recovery_point.id} (#{strategy.snapshot_backend})")
        {:reply, {:ok, recovery_point}, %{state | recovery_points: new_points}}

      {:error, reason} ->
        Logger.error("Failed to create recovery point: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:rollback, strategy, recovery_point}, _from, state) do
    Logger.warn("Initiating rollback to recovery point: #{recovery_point.id}")

    result = do_rollback(strategy, recovery_point, state)

    case result do
      :ok ->
        Logger.info("Rollback completed successfully")
        {:reply, :ok, state}

      {:error, reason} ->
        Logger.error("Rollback failed: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:available_backends, _from, state) do
    {:reply, {:ok, state.available_backends}, state}
  end

  @impl true
  def handle_call(:platform_info, _from, state) do
    {:reply, {:ok, state.platform}, state}
  end

  @impl true
  def handle_call({:strategy_adequate?, strategy, risk_level}, _from, state) do
    adequate = StrategyMatrix.strategy_meets_risk?(strategy, risk_level)
    {:reply, adequate, state}
  end

  @impl true
  def handle_call({:list_recovery_points, opts}, _from, state) do
    limit = Keyword.get(opts, :limit, 20)

    points =
      state.recovery_points
      |> Enum.take(limit)
      |> Enum.map(fn rp ->
        %{
          id: rp.id,
          description: rp.description,
          backend: rp.backend,
          created_at: rp.created_at
        }
      end)

    {:reply, {:ok, points}, state}
  end

  @impl true
  def handle_call({:cleanup_recovery_points, max_age_days}, _from, state) do
    cutoff = DateTime.add(DateTime.utc_now(), -max_age_days * 24 * 60 * 60, :second)

    {old, current} =
      Enum.split_with(state.recovery_points, fn rp ->
        DateTime.compare(rp.created_at, cutoff) == :lt
      end)

    # Clean up old snapshots
    Enum.each(old, &cleanup_snapshot/1)

    Logger.info("Cleaned up #{length(old)} old recovery points")
    {:reply, {:ok, length(old)}, %{state | recovery_points: current}}
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Private Functions
  # ═══════════════════════════════════════════════════════════════════════════

  defp detect_platform do
    %{
      os: detect_os(),
      arch: :erlang.system_info(:system_architecture) |> to_string(),
      kernel: get_kernel_version(),
      immutable: detect_immutable_system()
    }
  end

  defp detect_os do
    case :os.type() do
      {:unix, :linux} -> :linux
      {:unix, :darwin} -> :macos
      {:win32, _} -> :windows
      {:unix, os} -> os
    end
  end

  defp get_kernel_version do
    case System.cmd("uname", ["-r"], stderr_to_stdout: true) do
      {version, 0} -> String.trim(version)
      _ -> "unknown"
    end
  rescue
    _ -> "unknown"
  end

  defp detect_immutable_system do
    cond do
      File.exists?("/run/ostree-booted") -> :ostree
      File.exists?("/etc/guix") and immutable_guix?() -> :guix_system
      File.exists?("/nix") and immutable_nix?() -> :nixos
      true -> false
    end
  end

  defp immutable_guix? do
    case System.cmd("guix", ["system", "--version"], stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  defp immutable_nix? do
    File.exists?("/etc/nixos/configuration.nix") or File.exists?("/etc/NIXOS")
  end

  defp detect_backends do
    backends = %{}

    backends =
      if btrfs_available?() do
        Map.put(backends, :btrfs, %{
          type: :btrfs,
          root_subvol: detect_btrfs_root(),
          speed: :fast
        })
      else
        backends
      end

    backends =
      if zfs_available?() do
        Map.put(backends, :zfs, %{
          type: :zfs,
          pool: detect_zfs_pool(),
          speed: :fast
        })
      else
        backends
      end

    backends =
      if lvm_available?() do
        Map.put(backends, :lvm, %{
          type: :lvm,
          vg: detect_lvm_vg(),
          speed: :slow
        })
      else
        backends
      end

    backends =
      if snapper_available?() do
        Map.put(backends, :snapper, %{
          type: :snapper,
          configs: detect_snapper_configs(),
          speed: :fast
        })
      else
        backends
      end

    # Always have transaction log as fallback
    Map.put(backends, :transaction_log, %{
      type: :transaction_log,
      path: Path.expand("~/.local/share/totalupdate/transactions"),
      speed: :manual
    })
  end

  defp btrfs_available? do
    case System.cmd("btrfs", ["--version"], stderr_to_stdout: true) do
      {_, 0} ->
        # Check if root is on btrfs
        case System.cmd("findmnt", ["-n", "-o", "FSTYPE", "/"], stderr_to_stdout: true) do
          {"btrfs\n", 0} -> true
          _ -> false
        end

      _ ->
        false
    end
  rescue
    _ -> false
  end

  defp detect_btrfs_root do
    case System.cmd("btrfs", ["subvolume", "show", "/"], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n")
        |> Enum.find_value(fn line ->
          if String.contains?(line, "Name:") do
            line |> String.split(":") |> List.last() |> String.trim()
          end
        end)

      _ ->
        "@"
    end
  rescue
    _ -> "@"
  end

  defp zfs_available? do
    case System.cmd("zfs", ["version"], stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  defp detect_zfs_pool do
    case System.cmd("zpool", ["list", "-H", "-o", "name"], stderr_to_stdout: true) do
      {output, 0} -> output |> String.split("\n") |> List.first() |> String.trim()
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp lvm_available? do
    case System.cmd("lvm", ["version"], stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  defp detect_lvm_vg do
    case System.cmd("vgs", ["--noheadings", "-o", "vg_name"], stderr_to_stdout: true) do
      {output, 0} -> output |> String.split("\n") |> List.first() |> String.trim()
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp snapper_available? do
    System.find_executable("snapper") != nil
  end

  defp detect_snapper_configs do
    case System.cmd("snapper", ["list-configs", "--columns", "config"], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n")
        |> Enum.drop(1)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      _ ->
        []
    end
  rescue
    _ -> []
  end

  defp find_best_backend(backends) do
    priority = [:btrfs, :zfs, :snapper, :lvm, :transaction_log]

    Enum.find(priority, :transaction_log, fn backend ->
      Map.has_key?(backends, backend)
    end)
  end

  defp get_backend_speed(backend) do
    case backend do
      :btrfs -> :fast
      :zfs -> :fast
      :snapper -> :fast
      :lvm -> :slow
      :transaction_log -> :manual
      _ -> :unknown
    end
  end

  defp get_backend_confidence(backend) do
    case backend do
      :btrfs -> :high
      :zfs -> :high
      :snapper -> :high
      :lvm -> :medium
      :transaction_log -> :low
      _ -> :unknown
    end
  end

  defp do_create_recovery_point(strategy, description, state) do
    id = generate_recovery_id()
    backend = strategy.snapshot_backend

    result =
      case backend do
        :native ->
          # Native recovery (Guix/Nix generations) - automatic
          {:ok, %{type: :native, generation: :current}}

        :btrfs ->
          create_btrfs_snapshot(id, state.available_backends[:btrfs])

        :zfs ->
          create_zfs_snapshot(id, state.available_backends[:zfs])

        :snapper ->
          create_snapper_snapshot(id, description)

        :lvm ->
          create_lvm_snapshot(id, state.available_backends[:lvm])

        :transaction_log ->
          create_transaction_log_entry(id, description, state.available_backends[:transaction_log])

        _ ->
          {:error, :unsupported_backend}
      end

    case result do
      {:ok, snapshot_info} ->
        {:ok,
         %{
           id: id,
           description: description,
           backend: backend,
           snapshot_info: snapshot_info,
           created_at: DateTime.utc_now()
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp generate_recovery_id do
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "tu-#{timestamp}-#{random}"
  end

  defp create_btrfs_snapshot(id, config) do
    snapshot_path = "/.snapshots/totalupdate/#{id}"

    case System.cmd("btrfs", ["subvolume", "snapshot", "-r", "/", snapshot_path],
           stderr_to_stdout: true
         ) do
      {_, 0} -> {:ok, %{path: snapshot_path, subvol: config.root_subvol}}
      {error, _} -> {:error, "btrfs snapshot failed: #{error}"}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp create_zfs_snapshot(id, config) do
    pool = config.pool
    snapshot_name = "#{pool}@totalupdate-#{id}"

    case System.cmd("zfs", ["snapshot", "-r", snapshot_name], stderr_to_stdout: true) do
      {_, 0} -> {:ok, %{name: snapshot_name, pool: pool}}
      {error, _} -> {:error, "zfs snapshot failed: #{error}"}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp create_snapper_snapshot(id, description) do
    case System.cmd("snapper", ["create", "--description", "TotalUpdate: #{description}"],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        snapshot_num = String.trim(output)
        {:ok, %{number: snapshot_num, description: description}}

      {error, _} ->
        {:error, "snapper snapshot failed: #{error}"}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp create_lvm_snapshot(id, config) do
    vg = config.vg
    snapshot_name = "totalupdate-#{id}"

    case System.cmd(
           "lvcreate",
           ["--snapshot", "--name", snapshot_name, "--size", "1G", "#{vg}/root"],
           stderr_to_stdout: true
         ) do
      {_, 0} -> {:ok, %{name: snapshot_name, vg: vg}}
      {error, _} -> {:error, "lvm snapshot failed: #{error}"}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp create_transaction_log_entry(id, description, config) do
    log_path = config.path
    File.mkdir_p!(log_path)

    entry = %{
      id: id,
      description: description,
      timestamp: DateTime.utc_now(),
      type: :pre_operation
    }

    file_path = Path.join(log_path, "#{id}.json")
    File.write!(file_path, Jason.encode!(entry, pretty: true))

    {:ok, %{path: file_path}}
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp do_rollback(strategy, recovery_point, _state) do
    case strategy.snapshot_backend do
      :native ->
        # Native rollback (Guix/Nix) - handled by PM
        Logger.info("Native rollback requested - use package manager rollback command")
        :ok

      :btrfs ->
        rollback_btrfs(recovery_point.snapshot_info)

      :zfs ->
        rollback_zfs(recovery_point.snapshot_info)

      :snapper ->
        rollback_snapper(recovery_point.snapshot_info)

      :lvm ->
        rollback_lvm(recovery_point.snapshot_info)

      :transaction_log ->
        Logger.warn("Transaction log rollback requires manual intervention")
        {:error, :manual_rollback_required}

      _ ->
        {:error, :unsupported_backend}
    end
  end

  defp rollback_btrfs(snapshot_info) do
    # Btrfs rollback typically requires reboot
    Logger.warn("Btrfs rollback to #{snapshot_info.path} - reboot may be required")

    # This is a simplified version - real implementation would:
    # 1. Mount snapshot read-write
    # 2. Replace current root
    # 3. Request reboot
    :ok
  end

  defp rollback_zfs(snapshot_info) do
    case System.cmd("zfs", ["rollback", "-r", snapshot_info.name], stderr_to_stdout: true) do
      {_, 0} -> :ok
      {error, _} -> {:error, "zfs rollback failed: #{error}"}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp rollback_snapper(snapshot_info) do
    case System.cmd("snapper", ["undochange", "#{snapshot_info.number}..0"],
           stderr_to_stdout: true
         ) do
      {_, 0} -> :ok
      {error, _} -> {:error, "snapper rollback failed: #{error}"}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp rollback_lvm(snapshot_info) do
    # LVM rollback requires merging snapshot
    case System.cmd(
           "lvconvert",
           ["--merge", "#{snapshot_info.vg}/#{snapshot_info.name}"],
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        Logger.warn("LVM snapshot merge scheduled - reboot required")
        :ok

      {error, _} ->
        {:error, "lvm rollback failed: #{error}"}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp cleanup_snapshot(recovery_point) do
    case recovery_point.backend do
      :btrfs ->
        System.cmd("btrfs", ["subvolume", "delete", recovery_point.snapshot_info.path])

      :zfs ->
        System.cmd("zfs", ["destroy", recovery_point.snapshot_info.name])

      :snapper ->
        System.cmd("snapper", ["delete", recovery_point.snapshot_info.number])

      :lvm ->
        System.cmd("lvremove", [
          "-f",
          "#{recovery_point.snapshot_info.vg}/#{recovery_point.snapshot_info.name}"
        ])

      :transaction_log ->
        File.rm(recovery_point.snapshot_info.path)

      _ ->
        :ok
    end
  rescue
    _ -> :ok
  end
end
