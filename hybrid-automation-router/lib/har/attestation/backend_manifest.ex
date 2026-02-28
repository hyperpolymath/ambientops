# SPDX-License-Identifier: PMPL-1.0-or-later
#
# HAR.Attestation.BackendManifest — backend authority scope declarations.
#
# Part of the Hybrid Automation Router (HAR) project.
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)

defmodule HAR.Attestation.BackendManifest do
  @moduledoc """
  Declares backend authority scope via a2ml manifests.

  Each backend in the HAR ecosystem publishes a manifest declaring what
  operations it handles, its health contract, and its service level
  expectations. The router uses these declarations for three critical
  purposes:

  ## 1. Conflict Resolution at Registration Time

  When a new backend registers with the router, its authority declarations
  are checked against all existing backends. If two backends claim authority
  over the same operation type with overlapping scope, the conflict is
  detected immediately — before any traffic flows. This prevents the
  dangerous scenario where two backends silently compete for the same
  operations at runtime, potentially applying conflicting changes to the
  same infrastructure resources.

  For example, if both an `apt-backend` and a `dpkg-backend` claim
  authority over `:package_install` with scope `%{os: "debian"}`, the
  conflict is flagged at registration. The operator must resolve it by
  either narrowing one backend's scope or removing the duplicate.

  ## 2. Per-Backend Health Check Configuration

  Instead of the router applying a one-size-fits-all 30-second health
  check interval, each backend declares its own health contract:

  - `check_interval_ms` — How often to probe the backend (default: 30s)
  - `failure_threshold` — How many consecutive failures before marking unhealthy (default: 3)
  - `recovery_strategy` — How to recover after failure (`:fixed`, `:exponential_backoff`, `:linear_backoff`)
  - `half_open_after_ms` — How long to wait before probing a failed backend (default: 60s)

  This allows lightweight backends (e.g., local `apt` commands) to use
  aggressive health checking, while heavyweight backends (e.g., Terraform
  Cloud API) can use longer intervals to avoid rate limiting.

  ## 3. Circuit Breaker Configuration

  The health contract doubles as circuit breaker configuration. When a
  backend exceeds its `failure_threshold`, the router opens the circuit
  (stops routing to it). After `half_open_after_ms`, the router sends
  a single probe request (half-open state). If the probe succeeds, the
  circuit closes (full traffic resumes). If it fails, the circuit remains
  open and the timer resets.

  The `recovery_strategy` controls how the half-open timer scales:
  - `:fixed` — Always wait `half_open_after_ms` (no escalation)
  - `:exponential_backoff` — Double the wait each time (2x, 4x, 8x...)
  - `:linear_backoff` — Add `half_open_after_ms` each time (1x, 2x, 3x...)

  ## Manifest Format Example

      %BackendManifest{
        name: "apt-backend",
        authority: [
          %{operation: :package_install, scope: %{os: "debian"}},
          %{operation: :package_remove, scope: %{os: "debian"}}
        ],
        health_contract: %{
          check_interval_ms: 15_000,
          failure_threshold: 3,
          recovery_strategy: :exponential_backoff,
          half_open_after_ms: 30_000
        },
        registered_at: ~U[2026-02-28 12:00:00Z]
      }

  ## Scope Overlap Rules

  Two authority scopes overlap if ALL shared keys have identical values.
  An empty scope (`%{}`) is treated as a wildcard — it overlaps with
  everything. This means a backend that declares `scope: %{}` for an
  operation claims authority over that operation for ALL contexts.

  Scope keys are compared by value equality, not pattern matching.
  For example, `%{os: "debian"}` overlaps with `%{os: "debian", arch: "x86_64"}`
  because the shared key `os` has the same value in both. But
  `%{os: "debian"}` does NOT overlap with `%{os: "redhat"}`.
  """

  # ---------------------------------------------------------------------------
  # Struct Definition
  # ---------------------------------------------------------------------------

  defstruct [
    :name,
    :authority,
    :health_contract,
    :registered_at
  ]

  # ---------------------------------------------------------------------------
  # Type Specifications
  # ---------------------------------------------------------------------------

  @typedoc """
  A single authority declaration: an operation type and its scope constraints.

  - `operation` — The semantic operation type (e.g., `:package_install`).
    Must match an operation type defined in `HAR.Semantic.Operation`.
  - `scope` — A map of constraints that narrow the authority. An empty map
    means "this backend handles this operation for ALL targets."

  Example: `%{operation: :package_install, scope: %{os: "debian"}}` means
  "this backend handles package installation, but only for Debian systems."
  """
  @type authority_scope :: %{
          operation: atom(),
          scope: map()
        }

  @typedoc """
  Health check contract declaring how the router should monitor this backend.

  - `check_interval_ms` — Milliseconds between health probes (positive integer).
  - `failure_threshold` — Number of consecutive probe failures before the
    backend is marked unhealthy and its circuit is opened.
  - `recovery_strategy` — How the half-open timer escalates after repeated
    failures. One of `:fixed`, `:exponential_backoff`, `:linear_backoff`.
  - `half_open_after_ms` — Base duration (in ms) to wait before sending a
    probe to a failed backend. The actual wait may be longer if the recovery
    strategy applies escalation.
  """
  @type health_contract :: %{
          check_interval_ms: pos_integer(),
          failure_threshold: pos_integer(),
          recovery_strategy: :fixed | :exponential_backoff | :linear_backoff,
          half_open_after_ms: pos_integer()
        }

  @typedoc """
  A backend manifest declaring authority scope and health contract.

  - `name` — Unique backend identifier (string). Must be unique across the
    entire router. Convention: lowercase, hyphen-separated (e.g., "apt-backend").
  - `authority` — List of authority scope declarations. Each entry declares
    one operation+scope combination that this backend handles.
  - `health_contract` — How the router should health-check this backend.
  - `registered_at` — UTC timestamp of when this manifest was registered.
    Set automatically by `new/3`; `nil` for manifests not yet registered.
  """
  @type t :: %__MODULE__{
          name: String.t(),
          authority: list(authority_scope()),
          health_contract: health_contract(),
          registered_at: DateTime.t() | nil
        }

  # Default health contract used when a backend doesn't specify one.
  # Conservative defaults: 30s check interval, 3 failures before unhealthy,
  # fixed recovery (no backoff escalation), 60s half-open wait.
  @default_health_contract %{
    check_interval_ms: 30_000,
    failure_threshold: 3,
    recovery_strategy: :fixed,
    half_open_after_ms: 60_000
  }

  require Logger

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Create a new backend manifest with the given authority declarations.

  This is the primary constructor for backend manifests. It stamps the
  manifest with the current UTC time as the registration timestamp.

  ## Parameters

    - `name` — Backend identifier string. Must be unique across the router.
      Convention: lowercase with hyphens (e.g., "apt-backend", "yum-backend").
    - `authority` — List of `%{operation: atom(), scope: map()}` maps. Each
      entry declares one operation+scope combination this backend handles.
    - `health_contract` — Optional health check configuration. If `nil`,
      defaults are applied: 30s check interval, 3 failure threshold, fixed
      recovery, 60s half-open wait.

  ## Returns

  A `%BackendManifest{}` struct ready for registration with the router.

  ## Examples

      iex> manifest = BackendManifest.new("apt", [
      ...>   %{operation: :package_install, scope: %{os: "debian"}},
      ...>   %{operation: :package_remove, scope: %{os: "debian"}}
      ...> ])
      iex> manifest.name
      "apt"
      iex> length(manifest.authority)
      2
      iex> manifest.health_contract.check_interval_ms
      30_000

      iex> custom_health = %{
      ...>   check_interval_ms: 5_000,
      ...>   failure_threshold: 5,
      ...>   recovery_strategy: :exponential_backoff,
      ...>   half_open_after_ms: 10_000
      ...> }
      iex> manifest = BackendManifest.new("fast-backend", [], custom_health)
      iex> manifest.health_contract.recovery_strategy
      :exponential_backoff
  """
  @spec new(String.t(), list(authority_scope()), health_contract() | nil) :: t()
  def new(name, authority, health_contract \\ nil) do
    %__MODULE__{
      name: name,
      authority: authority,
      health_contract: health_contract || @default_health_contract,
      registered_at: DateTime.utc_now()
    }
  end

  @doc """
  Check if two backend manifests have conflicting authority declarations.

  Two backends conflict if they both claim authority over the same operation
  type with overlapping scope. This check MUST be performed at registration
  time to prevent runtime routing conflicts where two backends silently
  compete for the same operations.

  The check is symmetric: `check_conflicts(a, b)` finds the same conflicts
  as `check_conflicts(b, a)`, just with `backend_a` and `backend_b` swapped
  in the conflict details.

  ## Overlap Rules

  Two scopes overlap if:
  1. Either scope is empty (wildcard — matches everything), OR
  2. All keys that appear in BOTH scopes have identical values.

  Note that scopes with disjoint key sets are considered overlapping,
  because neither scope constrains the other. For example,
  `%{os: "debian"}` and `%{arch: "x86_64"}` overlap because there's
  no shared key to differentiate them — a Debian x86_64 system would
  match both.

  ## Parameters

    - `a` — First backend manifest
    - `b` — Second backend manifest

  ## Returns

    - `{:ok, []}` — No conflicts found; both backends can coexist.
    - `{:conflict, details}` — One or more authority overlaps detected.
      `details` is a list of maps, each containing:
      - `:operation` — The conflicting operation type
      - `:backend_a` / `:backend_b` — Backend names
      - `:scope_a` / `:scope_b` — The overlapping scope declarations

  ## Examples

      iex> apt = BackendManifest.new("apt", [%{operation: :package_install, scope: %{os: "debian"}}])
      iex> yum = BackendManifest.new("yum", [%{operation: :package_install, scope: %{os: "redhat"}}])
      iex> BackendManifest.check_conflicts(apt, yum)
      {:ok, []}

      iex> apt2 = BackendManifest.new("apt2", [%{operation: :package_install, scope: %{os: "debian"}}])
      iex> BackendManifest.check_conflicts(apt, apt2)
      {:conflict, [%{operation: :package_install, ...}]}
  """
  @spec check_conflicts(t(), t()) :: {:ok, []} | {:conflict, list(map())}
  def check_conflicts(%__MODULE__{} = a, %__MODULE__{} = b) do
    # Cross-product comparison: check every pair of authority declarations
    # from the two manifests. This is O(|a.authority| * |b.authority|),
    # which is acceptable because authority lists are typically small
    # (most backends declare authority over 2-10 operations).
    conflicts =
      for auth_a <- a.authority,
          auth_b <- b.authority,
          auth_a.operation == auth_b.operation,
          scopes_overlap?(auth_a.scope, auth_b.scope) do
        %{
          operation: auth_a.operation,
          backend_a: a.name,
          scope_a: auth_a.scope,
          backend_b: b.name,
          scope_b: auth_b.scope
        }
      end

    case conflicts do
      [] ->
        {:ok, []}

      conflicts ->
        Logger.warning("Backend authority conflict detected",
          backends: [a.name, b.name],
          conflicts: length(conflicts)
        )

        {:conflict, conflicts}
    end
  end

  # ---------------------------------------------------------------------------
  # Private Functions
  # ---------------------------------------------------------------------------

  # Check if two scope maps overlap.
  #
  # Overlap semantics:
  # 1. Empty scope = wildcard. An empty scope overlaps with everything,
  #    because it places no constraints — the backend accepts ALL targets
  #    for that operation.
  # 2. Non-empty scopes overlap if every key that appears in BOTH scopes
  #    has the same value. Keys that appear in only one scope don't prevent
  #    overlap — they represent orthogonal dimensions that don't differentiate.
  #
  # Examples:
  #   scopes_overlap?(%{}, %{os: "debian"})           => true  (wildcard)
  #   scopes_overlap?(%{os: "debian"}, %{os: "debian"}) => true  (identical)
  #   scopes_overlap?(%{os: "debian"}, %{os: "redhat"}) => false (conflicting value)
  #   scopes_overlap?(%{os: "debian"}, %{arch: "x86"})  => true  (no shared keys)
  defp scopes_overlap?(scope_a, scope_b)
       when map_size(scope_a) == 0 or map_size(scope_b) == 0,
       do: true

  defp scopes_overlap?(scope_a, scope_b) do
    # Find keys present in both scopes using set intersection.
    shared_keys =
      MapSet.intersection(
        MapSet.new(Map.keys(scope_a)),
        MapSet.new(Map.keys(scope_b))
      )

    # Scopes overlap if ALL shared keys have identical values.
    # If there are no shared keys, the scopes are orthogonal and
    # considered overlapping (conservative approach — better to
    # flag a false positive than miss a real conflict).
    Enum.all?(shared_keys, fn key ->
      Map.get(scope_a, key) == Map.get(scope_b, key)
    end)
  end
end
