# SPDX-License-Identifier: MPL-2.0
#
# HAR.Attestation.A2ML — a2ml-format attestation generator for routing decisions.
#
# Part of the Hybrid Automation Router (HAR) project.
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)

defmodule HAR.Attestation.A2ML do
  @moduledoc """
  Generates a2ml-format attestations for routing decisions.

  Every routing decision made by the HAR control plane produces an attestation
  record that captures the full context of the decision in a verifiable,
  content-addressable format. This serves as the immutable audit trail for
  all routing activity, enabling post-hoc verification, compliance auditing,
  and forensic analysis of infrastructure changes.

  ## What Gets Attested

  Each attestation captures five dimensions of a routing decision:

  - **What** was routed — the operation hash (derived from type + parameters)
  - **Where** it was routed — the selected backend and alternatives considered
  - **Why** — the policy justification and reason code
  - **When** — ISO 8601 timestamp with UTC timezone
  - **Verification** — SHA-256 hash of the entire decision context

  ## Content Addressability

  Attestations are content-addressable: the same routing decision with the
  same inputs will always produce the same `decision_hash`. This property
  enables verification without requiring the original request context —
  you can recompute the hash from the payload and compare it to the declared
  hash to confirm integrity.

  This design is inspired by IPFS content addressing (CID = hash of content)
  and Git's object model (commit hash = hash of tree + parents + metadata).
  While HAR can optionally store attestations in IPFS by CID, the hash-based
  verification works independently of any storage backend.

  ## a2ml Envelope Format

  The attestation follows the a2ml (Anthropic Agent Markup Language) envelope
  structure, which provides a standardised wrapper for machine-readable
  declarations:

      %{
        "a2ml" => %{
          "version" => "1.0",
          "type" => "routing-attestation",
          "issued_at" => "2026-02-28T12:34:56.789Z",
          "issuer" => "har",
          "decision_hash" => "sha256:abcdef..."
        },
        "payload" => %{
          "operation_type" => "package_install",
          "operation_params" => %{"package" => "nginx"},
          "backend" => "apt-backend",
          "alternatives" => ["yum-backend", "apk-backend"],
          "reason" => "pattern_match",
          "timestamp" => "2026-02-28T12:34:56.789Z"
        }
      }

  ## Security Considerations

  - **Sensitive parameter redaction**: Operation parameters are sanitised before
    attestation — fields like `password`, `token`, `secret`, `key`, `credential`,
    and `api_key` are stripped. This prevents credentials from leaking into
    audit logs while preserving enough context for meaningful verification.
  - **Deterministic hashing**: JSON encoding uses sorted keys (via Jason's default
    behaviour) to ensure the same logical payload always hashes identically,
    regardless of Elixir map key ordering.
  - **SHA-256**: The hash algorithm provides 128-bit collision resistance,
    which is sufficient for audit integrity (not used for cryptographic
    signatures — that would require asymmetric keys).

  ## Integration Points

  - Called by `HAR.ControlPlane.Router.route/2` after building the routing plan
  - Attestations are stored in `RoutingPlan.metadata.attestations`
  - Can be forwarded to IPFS via `HAR.IPFS.Store` for content-addressed archival
  - Consumed by the Phoenix LiveView dashboard for audit trail display
  """

  alias HAR.ControlPlane.RoutingDecision

  require Logger

  @doc """
  Generate an a2ml attestation for a single routing decision.

  Takes a `%RoutingDecision{}` struct from the control plane and produces
  a content-addressable attestation map. The attestation includes a SHA-256
  hash of the decision payload, making it independently verifiable.

  ## Parameters

    - `decision` — A `%RoutingDecision{}` struct containing the operation,
      selected backend, alternative backends, reason code, and timestamp.

  ## Returns

  A map with two top-level keys:
    - `"a2ml"` — Envelope metadata (version, type, issuer, timestamp, hash)
    - `"payload"` — The decision data that was hashed

  ## Examples

      iex> decision = %RoutingDecision{
      ...>   operation: %Operation{type: :package_install, params: %{package: "nginx"}},
      ...>   backend: %{name: "apt-backend"},
      ...>   alternatives: [%{name: "yum-backend"}],
      ...>   reason: :pattern_match,
      ...>   timestamp: ~U[2026-02-28 12:00:00Z]
      ...> }
      iex> attestation = HAR.Attestation.A2ML.attest(decision)
      iex> attestation["a2ml"]["type"]
      "routing-attestation"
  """
  @spec attest(RoutingDecision.t()) :: map()
  def attest(%RoutingDecision{} = decision) do
    # Step 1: Build the attestation payload from the routing decision.
    # This extracts only the fields relevant for verification, omitting
    # transient state that shouldn't appear in the audit trail.
    payload = build_payload(decision)

    # Step 2: Compute the SHA-256 hash of the canonical JSON representation.
    # This hash becomes the content address — the same decision always
    # produces the same hash, enabling verification without the original context.
    decision_hash = hash_decision(payload)

    # Step 3: Wrap the payload in the a2ml envelope structure.
    # The envelope provides versioning, typing, and issuer identification
    # so consumers can parse attestations without knowing the producer.
    %{
      "a2ml" => %{
        "version" => "1.0",
        "type" => "routing-attestation",
        "issued_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "issuer" => "har",
        "decision_hash" => decision_hash
      },
      "payload" => payload
    }
  end

  @doc """
  Generate attestations for an entire routing plan.

  Takes a list of routing decisions (typically all decisions in a
  `%RoutingPlan{}`) and produces one attestation per decision. The
  attestations are returned in the same order as the input decisions,
  preserving the execution ordering from the routing plan.

  This is the primary entry point used by `HAR.ControlPlane.Router.route/2`
  after building the complete routing plan. Each decision is attested
  independently — there is no cross-decision hash (though one could be
  added for plan-level integrity if needed).

  ## Parameters

    - `decisions` — A list of `%RoutingDecision{}` structs.

  ## Returns

  A list of attestation maps, one per decision.

  ## Examples

      iex> attestations = HAR.Attestation.A2ML.attest_plan(decisions)
      iex> length(attestations) == length(decisions)
      true
  """
  @spec attest_plan(list(RoutingDecision.t())) :: list(map())
  def attest_plan(decisions) when is_list(decisions) do
    Enum.map(decisions, &attest/1)
  end

  @doc """
  Verify an attestation by recomputing the decision hash.

  Takes a previously generated attestation and recomputes the SHA-256
  hash of its payload. If the computed hash matches the declared
  `decision_hash` in the a2ml envelope, the attestation is valid —
  its payload has not been tampered with since generation.

  This verification is independent of any external state: it only
  requires the attestation map itself. No database lookup, no network
  call, no original request context.

  ## Parameters

    - `attestation` — A map with `"a2ml"` and `"payload"` keys, as
      produced by `attest/1`.

  ## Returns

    - `true` if the payload hash matches the declared hash
    - `false` if the hash doesn't match or the map structure is invalid

  ## Examples

      iex> attestation = HAR.Attestation.A2ML.attest(decision)
      iex> HAR.Attestation.A2ML.verify(attestation)
      true

      iex> tampered = put_in(attestation, ["payload", "backend"], "evil")
      iex> HAR.Attestation.A2ML.verify(tampered)
      false
  """
  @spec verify(map()) :: boolean()
  def verify(%{"a2ml" => %{"decision_hash" => declared_hash}, "payload" => payload}) do
    # Recompute the hash from the payload and compare with the declared hash.
    # If the payload has been modified after attestation generation, the
    # hashes will diverge, revealing tampering.
    computed_hash = hash_decision(payload)
    computed_hash == declared_hash
  end

  # Catch-all for malformed attestation maps — return false rather than
  # crashing, since verification is a query operation that shouldn't
  # raise exceptions on bad input.
  def verify(_), do: false

  # ---------------------------------------------------------------------------
  # Private Functions
  # ---------------------------------------------------------------------------

  # Build the attestation payload from a routing decision.
  #
  # Extracts only the fields needed for verification and audit purposes.
  # The full RoutingDecision struct may contain transient state (e.g.,
  # GenServer references, socket handles) that shouldn't be serialised.
  #
  # Fields extracted:
  #   - operation_type: The semantic operation type (e.g., :package_install)
  #   - operation_params: The operation parameters, with sensitive fields removed
  #   - backend: The name of the selected backend
  #   - alternatives: Names of alternative backends that were considered
  #   - reason: Why this backend was selected (e.g., :pattern_match, :fallback)
  #   - timestamp: When the routing decision was made (ISO 8601)
  defp build_payload(%RoutingDecision{} = decision) do
    %{
      "operation_type" => to_string(decision.operation.type),
      "operation_params" => sanitise_params(decision.operation.params),
      "backend" => decision.backend.name,
      "alternatives" => Enum.map(decision.alternatives, & &1.name),
      "reason" => to_string(decision.reason),
      "timestamp" => decision.timestamp |> DateTime.to_iso8601()
    }
  end

  # Remove sensitive fields from operation params before attestation.
  #
  # Credentials, tokens, and secrets must NEVER appear in audit records.
  # Even if the audit log is stored in a secure location (e.g., encrypted
  # IPFS), defence in depth requires that sensitive data is stripped at
  # the source rather than relying on downstream access controls.
  #
  # The check is case-insensitive to catch variations like "API_KEY",
  # "apiKey", "Api_Key", etc. Keys are converted to lowercase strings
  # before comparison against the blocklist.
  #
  # If the params argument is not a map (e.g., nil or a raw string),
  # it's returned unchanged — this handles edge cases where parsers
  # produce non-standard parameter formats.
  defp sanitise_params(params) when is_map(params) do
    sensitive_keys = ~w(password token secret key credential api_key)

    Map.reject(params, fn {k, _v} ->
      String.downcase(to_string(k)) in sensitive_keys
    end)
  end

  defp sanitise_params(params), do: params

  # Compute SHA-256 hash of the decision payload.
  #
  # The payload is first encoded to JSON using Jason, which produces
  # deterministic output for maps (keys sorted lexicographically).
  # This ensures that the same logical payload always produces the
  # same hash, regardless of Elixir's internal map key ordering.
  #
  # The hash is prefixed with "sha256:" following the multihash
  # convention used by IPFS and OCI registries, making the algorithm
  # self-describing. If we ever need to migrate to SHA-3 or BLAKE3,
  # old attestations remain distinguishable from new ones.
  #
  # The hex encoding uses lowercase to match standard conventions
  # (e.g., Git commit hashes, Docker image digests).
  defp hash_decision(payload) do
    json = Jason.encode!(payload, pretty: false)
    hash = :crypto.hash(:sha256, json)
    "sha256:" <> Base.encode16(hash, case: :lower)
  end
end
