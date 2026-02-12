# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule SystemObservatory.CLI do
  @moduledoc """
  Command-line interface for System Observatory.

  ## Commands

  - `status` - Show current system status
  - `ingest <path>` - Ingest a run bundle from Operating Theatre
  - `recommend` - Get recommendations based on current state
  - `query <metric> [--since <duration>]` - Query metrics
  - `version` - Show version information

  ## Usage

      mix sysobs status
      mix sysobs ingest /path/to/run-bundle/
      mix sysobs recommend
      mix sysobs query disk.usage --since 7d
  """

  alias SystemObservatory.Metrics.Store
  alias SystemObservatory.Correlator
  alias SystemObservatory.BundleIngestion
  alias SystemObservatory.Recommendation

  @doc """
  Main entry point for CLI commands.
  """
  def main(args) do
    {opts, args, _invalid} =
      OptionParser.parse(args,
        strict: [
          since: :string,
          format: :string,
          priority: :string,
          help: :boolean
        ],
        aliases: [
          s: :since,
          f: :format,
          p: :priority,
          h: :help
        ]
      )

    case args do
      ["status" | _] -> status(opts)
      ["ingest", path] -> ingest(path, opts)
      ["ingest"] -> error("Usage: sysobs ingest <path>")
      ["recommend" | _] -> recommend(opts)
      ["query", metric | _] -> query(metric, opts)
      ["query"] -> error("Usage: sysobs query <metric> [--since <duration>]")
      ["version" | _] -> version()
      ["help" | _] -> help()
      [] -> help()
      [cmd | _] -> error("Unknown command: #{cmd}. Use 'help' for usage.")
    end
  end

  @doc """
  Show current system status.
  """
  def status(_opts \\ []) do
    metrics_count = length(Store.all())
    fresh_count = length(Store.all_fresh())
    events_count = length(Correlator.all_events())
    correlations = Correlator.find_correlations()

    output("""
    System Observatory Status
    ========================

    Version: #{SystemObservatory.version()}
    Schema:  #{SystemObservatory.schema_version()}
    Mode:    Observation only (never modifies)

    Metrics Store
    -------------
    Total metrics:  #{metrics_count}
    Fresh metrics:  #{fresh_count}
    Stale metrics:  #{metrics_count - fresh_count}

    Correlator
    ----------
    Total events:   #{events_count}
    Correlations:   #{length(correlations)}

    Recent correlations with high confidence:
    #{format_correlations(correlations)}
    """)
  end

  @doc """
  Ingest a run bundle from Operating Theatre.
  """
  def ingest(path, _opts \\ []) do
    result =
      if File.dir?(path) do
        BundleIngestion.ingest_directory(path)
      else
        BundleIngestion.ingest_file(path)
      end

    case result do
      {:ok, info} ->
        output("""
        Bundle ingested successfully
        ---------------------------
        Bundle ID:        #{info.bundle_id}
        Metrics recorded: #{info.metrics_recorded}
        Events recorded:  #{info.events_recorded}
        """)

      {:error, :enoent} ->
        error("File or directory not found: #{path}")

      {:error, reason} ->
        error("Failed to ingest bundle: #{inspect(reason)}")
    end
  end

  @doc """
  Show recommendations based on current state.
  """
  def recommend(opts \\ []) do
    recommendations =
      case opts[:priority] do
        "critical" -> Recommendation.by_min_priority(:critical)
        "high" -> Recommendation.by_min_priority(:high)
        "medium" -> Recommendation.by_min_priority(:medium)
        _ -> Recommendation.generate()
      end

    case opts[:format] do
      "json" ->
        case Recommendation.generate_json() do
          {:ok, json} -> output(json)
          {:error, reason} -> error("Failed to generate JSON: #{inspect(reason)}")
        end

      _ ->
        output("""
        Recommendations
        ===============

        #{format_recommendations(recommendations)}
        """)
    end
  end

  @doc """
  Query metrics by name.
  """
  def query(metric_name, opts \\ []) do
    metrics =
      case opts[:since] do
        nil ->
          Store.get_fresh(metric_name)

        duration ->
          since = parse_duration(duration)

          Store.get(metric_name)
          |> Enum.filter(fn m ->
            DateTime.compare(m.timestamp, since) == :gt
          end)
      end

    if Enum.empty?(metrics) do
      output("No metrics found for '#{metric_name}'")
    else
      output("""
      Metrics: #{metric_name}
      #{String.duplicate("=", String.length("Metrics: " <> metric_name))}

      #{format_metrics(metrics)}
      """)
    end
  end

  @doc """
  Show version information.
  """
  def version do
    output("""
    System Observatory v#{SystemObservatory.version()}
    Schema version: #{SystemObservatory.schema_version()}

    Part of the AmbientOps ecosystem.
    Observes and recommends. Never modifies.
    """)
  end

  @doc """
  Show help information.
  """
  def help do
    output("""
    System Observatory - Observability layer for AmbientOps
    =======================================================

    USAGE:
        sysobs <command> [options]

    COMMANDS:
        status              Show current system status
        ingest <path>       Ingest a run bundle from Operating Theatre
        recommend           Get recommendations based on current state
        query <metric>      Query metrics by name
        version             Show version information
        help                Show this help message

    OPTIONS:
        --since, -s <dur>   Filter by duration (e.g., 1h, 7d, 30m)
        --format, -f <fmt>  Output format (text, json)
        --priority, -p <p>  Filter by minimum priority (critical, high, medium, low)
        --help, -h          Show help for a command

    EXAMPLES:
        sysobs status
        sysobs ingest /path/to/run-bundle/
        sysobs recommend --format json
        sysobs query cpu_usage --since 24h

    PHILOSOPHY:
        System Observatory observes and recommends.
        It NEVER applies changes or modifies system state.
    """)
  end

  # Formatters

  defp format_correlations([]), do: "  (none)"

  defp format_correlations(correlations) do
    correlations
    |> Enum.filter(&(&1.confidence >= 0.3))
    |> Enum.take(5)
    |> Enum.map(fn c ->
      "  - #{c.anomaly.source}: #{length(c.related_changes)} change(s), " <>
        "confidence: #{Float.round(c.confidence * 100, 1)}%"
    end)
    |> Enum.join("\n")
    |> case do
      "" -> "  (none with confidence >= 30%)"
      text -> text
    end
  end

  defp format_recommendations([]), do: "(no recommendations)"

  defp format_recommendations(recommendations) do
    recommendations
    |> Enum.with_index(1)
    |> Enum.map(fn {rec, i} ->
      """
      #{i}. [#{rec.priority |> Atom.to_string() |> String.upcase()}] #{rec.summary}
         Type: #{rec.type}
         Confidence: #{Float.round(rec.confidence * 100, 1)}%
         Action: #{rec.action_template.action}
      """
    end)
    |> Enum.join("\n")
  end

  defp format_metrics(metrics) do
    metrics
    |> Enum.map(fn m ->
      timestamp = DateTime.to_iso8601(m.timestamp)
      source = m.source || "unknown"
      "  #{timestamp}  #{m.value}  (source: #{source})"
    end)
    |> Enum.join("\n")
  end

  defp parse_duration(duration) do
    now = DateTime.utc_now()

    {amount, unit} =
      case Regex.run(~r/^(\d+)([hdmw])$/, duration) do
        [_, amount, "h"] -> {String.to_integer(amount), :hour}
        [_, amount, "d"] -> {String.to_integer(amount), :day}
        [_, amount, "m"] -> {String.to_integer(amount), :minute}
        [_, amount, "w"] -> {String.to_integer(amount), :week}
        _ -> {24, :hour}
      end

    seconds =
      case unit do
        :minute -> amount * 60
        :hour -> amount * 3600
        :day -> amount * 86400
        :week -> amount * 604_800
      end

    DateTime.add(now, -seconds, :second)
  end

  # Output helpers

  defp output(text) do
    IO.puts(text)
    :ok
  end

  defp error(message) do
    IO.puts(:stderr, "Error: #{message}")
    :error
  end
end
