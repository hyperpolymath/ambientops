# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule FeedbackATron.VeriSimDBClient do
  @moduledoc """
  VeriSimDB persistence layer for FeedbackATron.

  Responsibilities:
  - On startup: loads existing dedup index from VeriSimDB and warms the ETS cache.
  - On each submission: dual-writes to both ETS (fast path) and VeriSimDB (durable path).
  - Replaces JSONL flat-file audit writes with VeriSimDB hexad writes.

  VeriSimDB API used:
    POST /api/v1/hexads          — store a hexad record
    GET  /api/v1/hexads/{id}     — retrieve a hexad by ID
    GET  /api/v1/query           — execute a VQL query
    GET  /health                 — health check

  Configuration:
    VERISIMDB_URL  — base URL for the VeriSimDB instance (default: http://localhost:8080)

  ETS remains the fast lookup path; VeriSimDB supplies durability across restarts.
  """

  use GenServer
  require Logger

  @ets_table :feedback_submissions

  # Hexad record types stored in VeriSimDB
  @record_type_submission "feedback_a_tron.submission"
  @record_type_audit      "feedback_a_tron.audit"

  # ── Client API ────────────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Persist a submission record to VeriSimDB and dual-write the dedup entry into ETS.

  `submission` is a map matching the shape written by `Deduplicator` (keys: hash,
  title, platform, result, submitted_at).  `ets_payload` is the `%{platforms, submissions}`
  map already stored in ETS after the ETS write.
  """
  def persist_submission(submission, ets_payload) do
    GenServer.cast(__MODULE__, {:persist_submission, submission, ets_payload})
  end

  @doc """
  Persist an audit event to VeriSimDB, replacing a JSONL flat-file write.

  `event_type` is an atom; `data` is a plain map.  `session_id` ties the event to the
  originating AuditLog session.
  """
  def persist_audit(event_type, data, session_id) do
    GenServer.cast(__MODULE__, {:persist_audit, event_type, data, session_id})
  end

  @doc """
  Health-check the VeriSimDB endpoint.  Returns `:ok` or `{:error, reason}`.
  """
  def health_check do
    GenServer.call(__MODULE__, :health_check)
  end

  @doc """
  Return the base URL currently in use.
  """
  def base_url do
    GenServer.call(__MODULE__, :base_url)
  end

  # ── Server callbacks ───────────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    url = resolve_base_url()
    Logger.info("[VeriSimDBClient] Using VeriSimDB at #{url}")

    # Warm the ETS cache from durable storage after a short delay to let
    # the Deduplicator (and its ETS table) start first.
    Process.send_after(self(), :warm_cache, 500)

    {:ok, %{base_url: url}}
  end

  @impl true
  def handle_info(:warm_cache, state) do
    warm_ets_from_verisimdb(state.base_url)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:persist_submission, submission, ets_payload}, state) do
    hexad = build_submission_hexad(submission, ets_payload)
    post_hexad(state.base_url, hexad)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:persist_audit, event_type, data, session_id}, state) do
    hexad = build_audit_hexad(event_type, data, session_id)
    post_hexad(state.base_url, hexad)
    {:noreply, state}
  end

  @impl true
  def handle_call(:health_check, _from, state) do
    result = do_health_check(state.base_url)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:base_url, _from, state) do
    {:reply, state.base_url, state}
  end

  # ── Cache warm-up ──────────────────────────────────────────────────────────

  # Query VeriSimDB for all persisted submission records and insert them into ETS
  # so that the Deduplicator survives a restart with its full history intact.
  defp warm_ets_from_verisimdb(base_url) do
    Logger.info("[VeriSimDBClient] Warming ETS cache from VeriSimDB…")

    query_url = "#{base_url}/api/v1/query"

    params = [
      vql: "SELECT * FROM hexads WHERE record_type = '#{@record_type_submission}'"
    ]

    case Req.get(query_url, params: params) do
      {:ok, %{status: 200, body: %{"results" => results}}} when is_list(results) ->
        loaded = Enum.reduce(results, 0, fn hexad, count ->
          load_hexad_into_ets(hexad)
          count + 1
        end)

        Logger.info("[VeriSimDBClient] Warmed ETS with #{loaded} submission records from VeriSimDB.")

      {:ok, %{status: status, body: body}} ->
        Logger.warning("[VeriSimDBClient] Unexpected response during cache warm (#{status}): #{inspect(body)}")

      {:error, reason} ->
        Logger.warning("[VeriSimDBClient] VeriSimDB unavailable during cache warm — ETS starts cold. Reason: #{inspect(reason)}")
    end
  end

  # Deserialise one VeriSimDB hexad back into the ETS shape expected by Deduplicator.
  defp load_hexad_into_ets(%{"payload" => payload}) when is_map(payload) do
    hash         = payload["hash"]
    platforms    = payload["platforms"] || []
    raw_subs     = payload["submissions"] || []

    # Rehydrate submission timestamps back to DateTime structs.
    submissions =
      Enum.map(raw_subs, fn s ->
        submitted_at =
          case DateTime.from_iso8601(s["submitted_at"] || "") do
            {:ok, dt, _offset} -> dt
            _                  -> DateTime.utc_now()
          end

        %{
          hash:         s["hash"],
          title:        s["title"],
          platform:     String.to_existing_atom(s["platform"] || "github"),
          result:       s["result"],
          submitted_at: submitted_at
        }
      end)

    if hash && hash != "" do
      existing =
        case :ets.lookup(@ets_table, hash) do
          [{^hash, data}] -> data
          []              -> %{platforms: [], submissions: []}
        end

      # Merge: prefer newer in-memory entries; dedup platforms.
      merged = %{
        platforms:   (platforms ++ existing.platforms) |> Enum.uniq(),
        submissions: (submissions ++ existing.submissions)
                     |> Enum.uniq_by(& &1.hash)
      }

      :ets.insert(@ets_table, {hash, merged})
    end
  end

  defp load_hexad_into_ets(_), do: :skip

  # ── Hexad builders ─────────────────────────────────────────────────────────

  defp build_submission_hexad(submission, ets_payload) do
    # Serialise DateTime fields before JSON encoding.
    serialised_submissions =
      (ets_payload.submissions || [])
      |> Enum.map(fn s ->
        Map.update(s, :submitted_at, nil, &DateTime.to_iso8601/1)
        |> Map.update(:platform, nil, &to_string/1)
      end)

    %{
      record_type: @record_type_submission,
      id:          submission.hash,
      payload: %{
        hash:        submission.hash,
        title:       submission.title,
        platform:    to_string(submission.platform),
        result:      inspect(submission.result),
        submitted_at: DateTime.to_iso8601(submission.submitted_at),
        platforms:   Enum.map(ets_payload.platforms, &to_string/1),
        submissions: serialised_submissions
      },
      metadata: %{
        source:    "feedback_a_tron",
        version:   Application.spec(:ambientops_referrals, :vsn) |> to_string(),
        persisted_at: DateTime.to_iso8601(DateTime.utc_now())
      }
    }
  end

  defp build_audit_hexad(event_type, data, session_id) do
    %{
      record_type: @record_type_audit,
      payload: %{
        timestamp:  DateTime.to_iso8601(DateTime.utc_now()),
        session_id: session_id,
        event:      to_string(event_type),
        data:       data
      },
      metadata: %{
        source:  "feedback_a_tron",
        version: Application.spec(:ambientops_referrals, :vsn) |> to_string()
      }
    }
  end

  # ── HTTP helpers ───────────────────────────────────────────────────────────

  defp post_hexad(base_url, hexad) do
    url = "#{base_url}/api/v1/hexads"

    case Req.post(url, json: hexad) do
      {:ok, %{status: status}} when status in [200, 201, 202] ->
        :ok

      {:ok, %{status: status, body: body}} ->
        Logger.warning("[VeriSimDBClient] Hexad write returned #{status}: #{inspect(body)}")
        :ok

      {:error, reason} ->
        # Best-effort: log and continue — ETS already holds the data.
        Logger.warning("[VeriSimDBClient] Hexad write failed (VeriSimDB unreachable?): #{inspect(reason)}")
        :ok
    end
  end

  defp do_health_check(base_url) do
    case Req.get("#{base_url}/health") do
      {:ok, %{status: 200}} ->
        :ok

      {:ok, %{status: status, body: body}} ->
        {:error, {:unexpected_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp resolve_base_url do
    System.get_env("VERISIMDB_URL") || "http://localhost:8080"
  end
end
