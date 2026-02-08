# SPDX-License-Identifier: AGPL-3.0-or-later

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
