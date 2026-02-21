# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule SystemObservatory.Recommendation do
  @moduledoc """
  Recommendation output for Operating Theatre.

  Analyzes metrics and correlations to generate recommendations.
  System Observatory RECOMMENDS but NEVER applies changes.

  ## Philosophy

  Recommendations are:
  - **Advisory only** - Operating Theatre decides what to apply
  - **Non-prescriptive** - Multiple options when appropriate
  - **Confidence-scored** - Includes uncertainty estimates
  - **Traceable** - Links to source data and correlations

  ## Output Format

  Recommendations are structured for consumption by Operating Theatre:

      %{
        id: "rec-xxx",
        type: :preventive | :corrective | :investigative,
        priority: :critical | :high | :medium | :low,
        confidence: 0.0..1.0,
        summary: "Human-readable summary",
        action_template: %{...},
        supporting_evidence: [...],
        generated_at: ~U[...]
      }
  """

  alias SystemObservatory.Metrics.Store
  alias SystemObservatory.Correlator

  @type recommendation :: %{
          id: String.t(),
          type: :preventive | :corrective | :investigative,
          priority: :critical | :high | :medium | :low,
          confidence: float(),
          summary: String.t(),
          action_template: map(),
          supporting_evidence: [map()],
          generated_at: DateTime.t()
        }

  @doc """
  Generate recommendations based on current metrics and correlations.

  Returns a list of recommendations sorted by priority.
  """
  @spec generate() :: [recommendation()]
  def generate do
    recommendations =
      []
      |> add_correlation_recommendations()
      |> add_metric_threshold_recommendations()
      |> add_trend_recommendations()

    recommendations
    |> Enum.sort_by(&priority_score/1, :desc)
    |> Enum.map(&add_metadata/1)
  end

  @doc """
  Generate recommendations and format as JSON for Operating Theatre.
  """
  @spec generate_json() :: {:ok, String.t()} | {:error, term()}
  def generate_json do
    recommendations = generate()

    serializable =
      Enum.map(recommendations, fn rec ->
        rec
        |> Map.update!(:generated_at, &DateTime.to_iso8601/1)
        |> Map.update!(:type, &Atom.to_string/1)
        |> Map.update!(:priority, &Atom.to_string/1)
      end)

    Jason.encode(%{
      recommendations: serializable,
      generated_at: DateTime.to_iso8601(DateTime.utc_now()),
      schema_version: "1.0"
    })
  end

  @doc """
  Get recommendations filtered by type.
  """
  @spec by_type(:preventive | :corrective | :investigative) :: [recommendation()]
  def by_type(type) do
    generate()
    |> Enum.filter(&(&1.type == type))
  end

  @doc """
  Get recommendations filtered by minimum priority.
  """
  @spec by_min_priority(:critical | :high | :medium | :low) :: [recommendation()]
  def by_min_priority(min_priority) do
    min_score = priority_to_score(min_priority)

    generate()
    |> Enum.filter(&(priority_to_score(&1.priority) >= min_score))
  end

  # Recommendation generators

  defp add_correlation_recommendations(recs) do
    correlations = Correlator.find_correlations()

    correlation_recs =
      correlations
      |> Enum.filter(&(&1.confidence >= 0.3))
      |> Enum.map(&correlation_to_recommendation/1)

    recs ++ correlation_recs
  end

  defp add_metric_threshold_recommendations(recs) do
    metrics = Store.all_fresh()

    threshold_recs =
      metrics
      |> Enum.filter(&exceeds_threshold?/1)
      |> Enum.map(&threshold_to_recommendation/1)

    recs ++ threshold_recs
  end

  defp add_trend_recommendations(recs) do
    # Group metrics by name and analyze trends
    metrics = Store.all_fresh()

    trend_recs =
      metrics
      |> Enum.group_by(& &1.name)
      |> Enum.filter(fn {_name, values} -> length(values) >= 3 end)
      |> Enum.flat_map(&analyze_trend/1)

    recs ++ trend_recs
  end

  # Converters

  defp correlation_to_recommendation(correlation) do
    %{
      type: :investigative,
      priority: confidence_to_priority(correlation.confidence),
      confidence: correlation.confidence,
      summary:
        "Anomaly detected with #{length(correlation.related_changes)} related change(s). Investigation recommended.",
      action_template: %{
        action: "investigate",
        target: correlation.anomaly.source,
        context: %{
          anomaly_data: correlation.anomaly.data,
          related_changes: Enum.map(correlation.related_changes, & &1.data)
        }
      },
      supporting_evidence: [
        %{type: "correlation", data: correlation}
      ]
    }
  end

  defp threshold_to_recommendation(metric) do
    {severity, message} = threshold_violation(metric)

    %{
      type: :corrective,
      priority: severity,
      confidence: 0.8,
      summary: message,
      action_template: %{
        action: "address_threshold",
        metric_name: metric.name,
        current_value: metric.value
      },
      supporting_evidence: [
        %{type: "metric", data: metric}
      ]
    }
  end

  defp analyze_trend({name, metrics}) do
    sorted = Enum.sort_by(metrics, & &1.timestamp, DateTime)
    values = Enum.map(sorted, & &1.value)

    cond do
      trending_up?(values) and dangerous_metric?(name) ->
        [
          %{
            type: :preventive,
            priority: :medium,
            confidence: 0.6,
            summary: "#{name} is trending upward. Preventive action may be needed.",
            action_template: %{
              action: "monitor",
              metric_name: name,
              trend: "increasing"
            },
            supporting_evidence: Enum.map(metrics, &%{type: "metric", data: &1})
          }
        ]

      trending_down?(values) and resource_metric?(name) ->
        [
          %{
            type: :preventive,
            priority: :medium,
            confidence: 0.6,
            summary: "#{name} is trending downward. Resource may be depleting.",
            action_template: %{
              action: "monitor",
              metric_name: name,
              trend: "decreasing"
            },
            supporting_evidence: Enum.map(metrics, &%{type: "metric", data: &1})
          }
        ]

      true ->
        []
    end
  end

  # Helpers

  defp exceeds_threshold?(metric) do
    case metric.name do
      name when name in ["cpu_usage", "cpu_percent", "cpu"] -> metric.value > 90
      name when name in ["memory_usage", "memory_percent", "memory"] -> metric.value > 90
      name when name in ["disk_usage", "disk_percent"] -> metric.value > 85
      _ -> false
    end
  end

  defp threshold_violation(metric) do
    case metric.name do
      name when name in ["cpu_usage", "cpu_percent", "cpu"] ->
        {:high, "CPU usage at #{metric.value}% - exceeds 90% threshold"}

      name when name in ["memory_usage", "memory_percent", "memory"] ->
        {:high, "Memory usage at #{metric.value}% - exceeds 90% threshold"}

      name when name in ["disk_usage", "disk_percent"] ->
        {:critical, "Disk usage at #{metric.value}% - exceeds 85% threshold"}

      _ ->
        {:medium, "#{metric.name} at #{metric.value} - threshold exceeded"}
    end
  end

  defp dangerous_metric?(name) do
    String.contains?(name, ["usage", "error", "latency", "queue"])
  end

  defp resource_metric?(name) do
    String.contains?(name, ["free", "available", "remaining"])
  end

  defp trending_up?(values) when length(values) >= 3 do
    # Simple trend detection: last value > first value with consistent direction
    first = hd(values)
    last = List.last(values)
    middle = Enum.at(values, div(length(values), 2))

    last > first and middle >= first
  end

  defp trending_up?(_), do: false

  defp trending_down?(values) when length(values) >= 3 do
    first = hd(values)
    last = List.last(values)
    middle = Enum.at(values, div(length(values), 2))

    last < first and middle <= first
  end

  defp trending_down?(_), do: false

  defp confidence_to_priority(confidence) when confidence >= 0.8, do: :high
  defp confidence_to_priority(confidence) when confidence >= 0.5, do: :medium
  defp confidence_to_priority(_), do: :low

  defp priority_score(rec) do
    priority_to_score(rec.priority) + rec.confidence
  end

  defp priority_to_score(:critical), do: 4
  defp priority_to_score(:high), do: 3
  defp priority_to_score(:medium), do: 2
  defp priority_to_score(:low), do: 1

  defp add_metadata(rec) do
    rec
    |> Map.put(:id, generate_id())
    |> Map.put(:generated_at, DateTime.utc_now())
  end

  defp generate_id do
    "rec-" <> (:crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false))
  end
end
