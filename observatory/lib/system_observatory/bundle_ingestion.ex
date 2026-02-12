# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule SystemObservatory.BundleIngestion do
  @moduledoc """
  Run bundle ingestion from Operating Theatre.

  Processes run bundles containing snapshot, findings, plan, and applied sections.
  Extracts metrics and events for correlation and analysis.

  ## Bundle Format

  Run bundles from Operating Theatre contain:
  - `snapshot` - System state at the time of the run
  - `findings` - What was discovered (anomalies, issues)
  - `plan` - What actions were planned
  - `applied` - What changes were actually applied

  ## Example

      bundle = %{
        "id" => "run-2026-01-09-001",
        "timestamp" => "2026-01-09T10:00:00Z",
        "snapshot" => %{"disk_free" => 1024, "memory_used" => 8192},
        "findings" => [%{"type" => "low_disk", "severity" => "warning"}],
        "plan" => [%{"action" => "cleanup", "target" => "/tmp"}],
        "applied" => [%{"action" => "cleanup", "status" => "success"}]
      }

      SystemObservatory.BundleIngestion.ingest(bundle)
  """

  alias SystemObservatory.Metrics.Store
  alias SystemObservatory.Correlator

  @type bundle :: %{
          optional(String.t()) => any(),
          required(String.t()) =>
            String.t() | map() | [map()]
        }

  @type ingest_result :: %{
          metrics_recorded: non_neg_integer(),
          events_recorded: non_neg_integer(),
          bundle_id: String.t()
        }

  @doc """
  Ingest a run bundle from Operating Theatre.

  Extracts metrics from snapshot data and records events from findings/changes.

  ## Options

  - `:source` - Override the source identifier (default: from bundle or "operating-theatre")
  """
  @spec ingest(bundle(), keyword()) :: {:ok, ingest_result()} | {:error, term()}
  def ingest(bundle, opts \\ []) do
    with {:ok, bundle_id} <- extract_bundle_id(bundle),
         {:ok, timestamp} <- extract_timestamp(bundle) do
      source = Keyword.get(opts, :source, bundle["source"] || "operating-theatre")

      metrics_count = ingest_snapshot(bundle["snapshot"], source, timestamp)
      findings_count = ingest_findings(bundle["findings"], source, timestamp)
      applied_count = ingest_applied(bundle["applied"], source, timestamp)

      {:ok,
       %{
         metrics_recorded: metrics_count,
         events_recorded: findings_count + applied_count,
         bundle_id: bundle_id
       }}
    end
  end

  @doc """
  Ingest a run bundle from a JSON file path.
  """
  @spec ingest_file(Path.t(), keyword()) :: {:ok, ingest_result()} | {:error, term()}
  def ingest_file(path, opts \\ []) do
    with {:ok, content} <- File.read(path),
         {:ok, bundle} <- Jason.decode(content) do
      ingest(bundle, opts)
    end
  end

  @doc """
  Ingest a run bundle from a directory containing bundle files.

  Expects the directory to contain:
  - `manifest.json` - Bundle metadata
  - `snapshot.json` - System state snapshot (optional)
  - `findings.json` - Discovered issues (optional)
  - `plan.json` - Planned actions (optional)
  - `applied.json` - Applied changes (optional)
  """
  @spec ingest_directory(Path.t(), keyword()) :: {:ok, ingest_result()} | {:error, term()}
  def ingest_directory(dir_path, opts \\ []) do
    manifest_path = Path.join(dir_path, "manifest.json")

    with {:ok, manifest_content} <- File.read(manifest_path),
         {:ok, manifest} <- Jason.decode(manifest_content) do
      bundle =
        manifest
        |> maybe_load_file(dir_path, "snapshot")
        |> maybe_load_file(dir_path, "findings")
        |> maybe_load_file(dir_path, "plan")
        |> maybe_load_file(dir_path, "applied")

      ingest(bundle, opts)
    end
  end

  @doc """
  Ingest an EvidenceEnvelope from hardware-crash-team or other AmbientOps tools.

  Accepts the contract-schema format (evidence-envelope.schema.json) and extracts
  metrics from artifacts and findings for correlation.

  ## Example

      envelope = %{
        "version" => "1.0.0",
        "envelope_id" => "uuid-here",
        "created_at" => "2026-02-12T10:00:00Z",
        "source" => %{"tool" => "hardware-crash-team", "host" => %{"hostname" => "myhost"}},
        "artifacts" => [%{"artifact_id" => "uuid", "type" => "report", "path" => "scan.json"}],
        "findings" => [%{"finding_id" => "f1", "severity" => "critical", "category" => "performance", "title" => "Zombie GPU"}]
      }

      SystemObservatory.BundleIngestion.ingest_envelope(envelope)
  """
  @spec ingest_envelope(map(), keyword()) :: {:ok, ingest_result()} | {:error, term()}
  def ingest_envelope(envelope, opts \\ []) do
    with {:ok, _version} <- validate_envelope_version(envelope),
         {:ok, envelope_id} <- extract_envelope_id(envelope),
         {:ok, timestamp} <- extract_timestamp(envelope) do
      source_tool = get_in(envelope, ["source", "tool"]) || "unknown"
      source = Keyword.get(opts, :source, source_tool)

      # Record findings as events
      findings = envelope["findings"] || []
      findings_count = ingest_envelope_findings(findings, source, timestamp)

      # Record metrics if present
      metrics_count =
        case envelope["metrics"] do
          m when is_map(m) -> ingest_snapshot(m, source, timestamp)
          _ -> 0
        end

      # Record artifact count as a metric
      artifacts = envelope["artifacts"] || []
      Store.record("envelope_artifacts", length(artifacts), %{"envelope_id" => envelope_id}, source: source)

      {:ok,
       %{
         metrics_recorded: metrics_count + 1,
         events_recorded: findings_count,
         bundle_id: envelope_id
       }}
    end
  end

  @doc """
  Ingest an EvidenceEnvelope from a JSON file path.
  """
  @spec ingest_envelope_file(Path.t(), keyword()) :: {:ok, ingest_result()} | {:error, term()}
  def ingest_envelope_file(path, opts \\ []) do
    with {:ok, content} <- File.read(path),
         {:ok, envelope} <- Jason.decode(content) do
      ingest_envelope(envelope, opts)
    end
  end

  # Private functions

  defp extract_bundle_id(%{"id" => id}) when is_binary(id), do: {:ok, id}
  defp extract_bundle_id(%{"bundle_id" => id}) when is_binary(id), do: {:ok, id}

  defp extract_bundle_id(_bundle) do
    # Generate an ID if none provided
    id = "bundle-" <> (:crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false))
    {:ok, id}
  end

  defp extract_timestamp(%{"timestamp" => ts}) when is_binary(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, dt, _offset} -> {:ok, dt}
      {:error, _} -> {:ok, DateTime.utc_now()}
    end
  end

  defp extract_timestamp(_bundle), do: {:ok, DateTime.utc_now()}

  defp ingest_snapshot(nil, _source, _timestamp), do: 0
  defp ingest_snapshot(snapshot, _source, _timestamp) when not is_map(snapshot), do: 0

  defp ingest_snapshot(snapshot, source, _timestamp) do
    snapshot
    |> Enum.filter(fn {_k, v} -> is_number(v) end)
    |> Enum.each(fn {name, value} ->
      Store.record(to_string(name), value, %{}, source: source)
    end)
    |> then(fn _ -> map_size(snapshot) end)
  end

  defp ingest_findings(nil, _source, _timestamp), do: 0
  defp ingest_findings(findings, _source, _timestamp) when not is_list(findings), do: 0

  defp ingest_findings(findings, source, _timestamp) do
    Enum.each(findings, fn finding ->
      event_type =
        case finding["severity"] || finding["type"] do
          s when s in ["critical", "error", "anomaly"] -> :anomaly
          _ -> :metric
        end

      Correlator.record_event(event_type, source, finding)
    end)

    length(findings)
  end

  defp ingest_applied(nil, _source, _timestamp), do: 0
  defp ingest_applied(applied, _source, _timestamp) when not is_list(applied), do: 0

  defp ingest_applied(applied, source, _timestamp) do
    Enum.each(applied, fn change ->
      Correlator.record_event(:change, source, change)
    end)

    length(applied)
  end

  defp validate_envelope_version(%{"version" => v}) when is_binary(v), do: {:ok, v}
  defp validate_envelope_version(_), do: {:error, :missing_version}

  defp extract_envelope_id(%{"envelope_id" => id}) when is_binary(id), do: {:ok, id}
  defp extract_envelope_id(_), do: {:error, :missing_envelope_id}

  defp ingest_envelope_findings(findings, source, _timestamp) when is_list(findings) do
    Enum.each(findings, fn finding ->
      severity = finding["severity"] || "info"

      event_type =
        case severity do
          s when s in ["critical", "high"] -> :anomaly
          "medium" -> :metric
          _ -> :metric
        end

      event_data = %{
        "finding_id" => finding["finding_id"],
        "severity" => severity,
        "category" => finding["category"],
        "title" => finding["title"],
        "auto_fixable" => finding["auto_fixable"] || false
      }

      Correlator.record_event(event_type, source, event_data)
    end)

    length(findings)
  end

  defp ingest_envelope_findings(_, _source, _timestamp), do: 0

  defp maybe_load_file(bundle, dir_path, key) do
    file_path = Path.join(dir_path, "#{key}.json")

    case File.read(file_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, data} -> Map.put(bundle, key, data)
          {:error, _} -> bundle
        end

      {:error, _} ->
        bundle
    end
  end
end
