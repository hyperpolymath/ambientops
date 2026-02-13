# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

defmodule DNFinition.Plugins.StrategyMatrix do
  @moduledoc """
  Snapshot and backout strategy selection matrix.

  Determines the optimal recovery strategy based on:
  1. Package manager capabilities (native transactions, rollback)
  2. Available filesystem features (btrfs, ZFS, LVM)
  3. Operation type and risk level
  4. System configuration (immutable, container, etc.)

  ## Strategy Priority Order

  1. **Native PM Recovery** (Guix/Nix generations) - BEST
     - Instant rollback via generation switch
     - Formally verified in SPARK

  2. **rpm-ostree Deployments**
     - Immutable system deployments
     - Requires reboot for rollback

  3. **Btrfs Snapshots**
     - Fast copy-on-write snapshots
     - No reboot for user packages

  4. **ZFS Snapshots**
     - Enterprise-grade with checksumming
     - Similar to btrfs

  5. **LVM Thin Snapshots**
     - Works on traditional filesystems
     - Slower than btrfs/ZFS

  6. **Transaction Log Only**
     - Fallback when no snapshot support
     - Manual recovery may be needed

  ## Usage

      # Get strategy for operation
      strategy = StrategyMatrix.get_strategy(:guix, :medium)

      # Execute pre-operation snapshot
      {:ok, recovery_point} = StrategyMatrix.execute_pre_operation(strategy, "Pre-install")

      # Execute rollback if needed
      :ok = StrategyMatrix.execute_backout(strategy, recovery_point)
  """

  require Logger

  alias DNFinition.SnapshotManager

  @type risk_level :: :none | :low | :medium | :high | :critical

  @type recovery_strategy ::
          :none
          | :native
          | :btrfs_snapshot
          | :zfs_snapshot
          | :lvm_snapshot
          | :snapper
          | :ostree
          | :apfs
          | :vss
          | :transaction_log
          | :manual

  @type backout_capability ::
          :instant
          | :fast
          | :slow
          | :reboot
          | :manual
          | :none

  @type confidence ::
          :proven
          | :high
          | :medium
          | :low
          | :unknown

  @type strategy_recommendation :: %{
          primary: recovery_strategy(),
          primary_confidence: confidence(),
          fallback: recovery_strategy(),
          fallback_confidence: confidence(),
          backout: backout_capability(),
          requires_reboot: boolean(),
          description: String.t(),
          warnings: String.t() | nil,
          estimated_time: non_neg_integer(),
          applicable: boolean(),
          reason: String.t()
        }

  # ═══════════════════════════════════════════════════════════════════════════
  # Strategy Selection
  # ═══════════════════════════════════════════════════════════════════════════

  @doc """
  Get the recommended strategy for a package manager and risk level.
  """
  @spec get_strategy(atom(), risk_level()) :: strategy_recommendation()
  def get_strategy(pm_type, risk \\ :medium) do
    has_native = has_native_recovery?(pm_type)
    snapshot_backend = detect_snapshot_backend()

    lookup_strategy(pm_type, has_native, snapshot_backend, risk)
  end

  @doc """
  Get strategy based on plugin metadata.
  """
  @spec get_strategy_for_plugin(map(), risk_level()) :: strategy_recommendation()
  def get_strategy_for_plugin(plugin_metadata, risk \\ :medium) do
    lookup_strategy(
      plugin_metadata.pm_type,
      plugin_metadata.has_native_recovery,
      plugin_metadata.preferred_snapshot,
      risk
    )
  end

  @doc """
  Check if a strategy is valid for the current system.
  """
  @spec validate_strategy(strategy_recommendation()) :: boolean()
  def validate_strategy(strategy) do
    case strategy.primary do
      :none -> true
      :native -> detect_snapshot_backend() == :native
      :btrfs_snapshot -> btrfs_available?()
      :zfs_snapshot -> zfs_available?()
      :lvm_snapshot -> lvm_available?()
      :snapper -> snapper_available?()
      :ostree -> ostree_available?()
      :apfs -> apfs_available?()
      :vss -> vss_available?()
      :transaction_log -> true
      :manual -> true
    end
  end

  @doc """
  Check if strategy meets the risk requirements.
  """
  @spec strategy_meets_risk?(strategy_recommendation(), risk_level()) :: boolean()
  def strategy_meets_risk?(strategy, risk) do
    case risk do
      :none ->
        true

      :low ->
        strategy.backout != :none

      :medium ->
        strategy.backout in [:instant, :fast, :slow]

      :high ->
        strategy.backout in [:instant, :fast] and
          strategy.primary_confidence in [:proven, :high]

      :critical ->
        strategy.backout == :instant and
          strategy.primary_confidence == :proven
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Strategy Execution
  # ═══════════════════════════════════════════════════════════════════════════

  @doc """
  Execute pre-operation recovery point creation.
  """
  @spec execute_pre_operation(strategy_recommendation(), String.t()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def execute_pre_operation(strategy, description) do
    if not strategy.applicable do
      {:error, :not_applicable}
    else
      case strategy.primary do
        :none ->
          {:ok, 0}

        :manual ->
          Logger.warn("Manual recovery strategy - no automatic snapshot")
          {:ok, 0}

        _ ->
          # Create snapshot via SnapshotManager
          SnapshotManager.create(description, kind: :pre_transaction)
      end
    end
  end

  @doc """
  Execute rollback using the strategy.
  """
  @spec execute_backout(strategy_recommendation(), non_neg_integer()) ::
          :ok | {:ok, :requires_reboot} | {:error, term()}
  def execute_backout(strategy, recovery_point) do
    if recovery_point == 0 do
      {:error, :no_recovery_point}
    else
      case SnapshotManager.rollback(recovery_point) do
        :ok -> :ok
        {:ok, :requires_reboot} -> {:ok, :requires_reboot}
        error -> error
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Strategy Matrix Lookup
  # ═══════════════════════════════════════════════════════════════════════════

  defp lookup_strategy(pm_type, has_native, snapshot_backend, risk) do
    cond do
      # CASE 1: Native PM recovery (Guix, Nix, rpm-ostree) - BEST
      has_native ->
        native_strategy(pm_type, risk)

      # CASE 2: Filesystem snapshot support
      snapshot_backend == :btrfs ->
        btrfs_strategy(risk)

      snapshot_backend == :zfs ->
        zfs_strategy(risk)

      snapshot_backend == :lvm ->
        lvm_strategy(risk)

      snapshot_backend == :apfs ->
        apfs_strategy(risk)

      snapshot_backend == :vss ->
        vss_strategy(risk)

      # CASE 3: Transaction log fallback
      true ->
        transaction_log_strategy(risk)
    end
  end

  defp native_strategy(pm_type, _risk) do
    case pm_type do
      :guix ->
        %{
          primary: :native,
          primary_confidence: :proven,
          fallback: :transaction_log,
          fallback_confidence: :high,
          backout: :instant,
          requires_reboot: false,
          description: "Guix generation-based recovery",
          warnings: nil,
          estimated_time: 1,
          applicable: true,
          reason: "Guix has atomic generations with instant rollback"
        }

      :nix ->
        %{
          primary: :native,
          primary_confidence: :proven,
          fallback: :transaction_log,
          fallback_confidence: :high,
          backout: :instant,
          requires_reboot: false,
          description: "Nix generation-based recovery",
          warnings: nil,
          estimated_time: 1,
          applicable: true,
          reason: "Nix has atomic generations with instant rollback"
        }

      :rpm_ostree ->
        %{
          primary: :ostree,
          primary_confidence: :proven,
          fallback: :manual,
          fallback_confidence: :medium,
          backout: :reboot,
          requires_reboot: true,
          description: "rpm-ostree deployment-based recovery",
          warnings: "Rollback requires system reboot",
          estimated_time: 60,
          applicable: true,
          reason: "rpm-ostree uses immutable deployments"
        }

      _ ->
        %{
          primary: :native,
          primary_confidence: :medium,
          fallback: :transaction_log,
          fallback_confidence: :high,
          backout: :fast,
          requires_reboot: false,
          description: "Native package manager recovery",
          warnings: nil,
          estimated_time: 10,
          applicable: true,
          reason: "Package manager has native transaction support"
        }
    end
  end

  defp btrfs_strategy(risk) do
    %{
      primary: :btrfs_snapshot,
      primary_confidence: :high,
      fallback: :transaction_log,
      fallback_confidence: :high,
      backout: if(risk >= :high, do: :reboot, else: :fast),
      requires_reboot: risk >= :high,
      description: "Btrfs subvolume snapshot",
      warnings: if(risk >= :high, do: "System-level changes may require reboot", else: nil),
      estimated_time: if(risk >= :high, do: 60, else: 10),
      applicable: true,
      reason: "Btrfs provides fast copy-on-write snapshots"
    }
  end

  defp zfs_strategy(risk) do
    %{
      primary: :zfs_snapshot,
      primary_confidence: :high,
      fallback: :transaction_log,
      fallback_confidence: :high,
      backout: if(risk >= :high, do: :reboot, else: :fast),
      requires_reboot: risk >= :high,
      description: "ZFS snapshot",
      warnings: if(risk >= :high, do: "System-level changes may require reboot", else: nil),
      estimated_time: if(risk >= :high, do: 60, else: 5),
      applicable: true,
      reason: "ZFS provides enterprise-grade snapshots with checksumming"
    }
  end

  defp lvm_strategy(_risk) do
    %{
      primary: :lvm_snapshot,
      primary_confidence: :medium,
      fallback: :transaction_log,
      fallback_confidence: :high,
      backout: :slow,
      requires_reboot: true,
      description: "LVM thin snapshot",
      warnings: "LVM snapshots may require more time to restore",
      estimated_time: 120,
      applicable: true,
      reason: "LVM provides snapshots on traditional filesystems"
    }
  end

  defp apfs_strategy(_risk) do
    %{
      primary: :apfs,
      primary_confidence: :medium,
      fallback: :transaction_log,
      fallback_confidence: :high,
      backout: :fast,
      requires_reboot: false,
      description: "APFS snapshot (Time Machine)",
      warnings: nil,
      estimated_time: 30,
      applicable: true,
      reason: "APFS provides native macOS snapshots"
    }
  end

  defp vss_strategy(_risk) do
    %{
      primary: :vss,
      primary_confidence: :medium,
      fallback: :transaction_log,
      fallback_confidence: :medium,
      backout: :slow,
      requires_reboot: true,
      description: "Windows Volume Shadow Copy",
      warnings: "VSS restore may require reboot",
      estimated_time: 180,
      applicable: true,
      reason: "VSS provides Windows system restore points"
    }
  end

  defp transaction_log_strategy(_risk) do
    %{
      primary: :transaction_log,
      primary_confidence: :high,
      fallback: :manual,
      fallback_confidence: :low,
      backout: :manual,
      requires_reboot: false,
      description: "Transaction log only (no filesystem snapshots)",
      warnings: "No automatic rollback; manual recovery may be needed",
      estimated_time: 0,
      applicable: true,
      reason: "No snapshot backend available; using transaction log"
    }
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Backend Detection
  # ═══════════════════════════════════════════════════════════════════════════

  defp has_native_recovery?(pm_type) do
    pm_type in [:guix, :nix, :rpm_ostree]
  end

  defp detect_snapshot_backend do
    cond do
      btrfs_available?() -> :btrfs
      zfs_available?() -> :zfs
      snapper_available?() -> :snapper
      lvm_available?() -> :lvm
      apfs_available?() -> :apfs
      vss_available?() -> :vss
      true -> :none
    end
  end

  defp btrfs_available? do
    System.find_executable("btrfs") != nil and
      File.exists?("/proc/filesystems") and
      File.read!("/proc/filesystems") =~ "btrfs"
  end

  defp zfs_available? do
    System.find_executable("zfs") != nil
  end

  defp lvm_available? do
    System.find_executable("lvm") != nil
  end

  defp snapper_available? do
    System.find_executable("snapper") != nil
  end

  defp ostree_available? do
    System.find_executable("rpm-ostree") != nil
  end

  defp apfs_available? do
    System.find_executable("tmutil") != nil
  end

  defp vss_available? do
    # Windows-only
    false
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Human-Readable Descriptions
  # ═══════════════════════════════════════════════════════════════════════════

  @doc """
  Get human-readable name for a strategy.
  """
  def strategy_name(strategy) do
    case strategy do
      :none -> "None"
      :native -> "Native PM Recovery"
      :btrfs_snapshot -> "Btrfs Snapshot"
      :zfs_snapshot -> "ZFS Snapshot"
      :lvm_snapshot -> "LVM Snapshot"
      :snapper -> "Snapper"
      :ostree -> "rpm-ostree Deployment"
      :apfs -> "APFS Snapshot"
      :vss -> "Volume Shadow Copy"
      :transaction_log -> "Transaction Log"
      :manual -> "Manual Recovery"
    end
  end

  @doc """
  Get human-readable description for backout capability.
  """
  def backout_description(backout) do
    case backout do
      :instant -> "Instant rollback (< 1 second)"
      :fast -> "Fast restore (< 1 minute)"
      :slow -> "Full restore (minutes)"
      :reboot -> "Requires system reboot"
      :manual -> "Manual intervention required"
      :none -> "No rollback available"
    end
  end

  @doc """
  Get human-readable description for confidence level.
  """
  def confidence_description(confidence) do
    case confidence do
      :proven -> "Formally verified/extensively tested"
      :high -> "Well-tested, reliable"
      :medium -> "Generally works, some edge cases"
      :low -> "Experimental"
      :unknown -> "Not tested"
    end
  end

  @doc """
  Get human-readable description for risk level.
  """
  def risk_description(risk) do
    case risk do
      :none -> "Read-only operations"
      :low -> "Install user packages"
      :medium -> "Remove packages, upgrade specific"
      :high -> "System upgrade, kernel changes"
      :critical -> "Bootloader, system files"
    end
  end
end
