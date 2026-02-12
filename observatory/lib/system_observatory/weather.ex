# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule SystemObservatory.Weather do
  @moduledoc """
  System Weather generation for the Ward ambient UI.

  Reads latest metrics from the store, evaluates thresholds,
  and generates a system-weather.schema.json conformant payload.

  ## CRITICAL: Advisory Data Only (CRIT-003 compliance)

  Weather reports are derived from advisory metrics. They indicate
  system trends but are NOT authoritative state. The Ward UI uses
  these to set ambient mood (calm/watch/act) and suggest actions.
  """

  alias SystemObservatory.Metrics.Store

  @disk_warning_percent 80
  @disk_critical_percent 90
  @memory_warning_percent 75
  @memory_critical_percent 90
  @cpu_warning_percent 80
  @cpu_critical_percent 95
  @version "1.0.0"

  @type weather_state :: :calm | :watch | :act
  @type trend_direction :: :improving | :stable | :degrading

  @doc """
  Generate a system weather report from current metrics.

  Returns a map conforming to system-weather.schema.json.
  """
  @spec generate() :: map()
  def generate do
    metrics = Store.all_fresh()

    categories = %{
      "disk" => evaluate_disk(metrics),
      "memory" => evaluate_memory(metrics),
      "cpu" => evaluate_cpu(metrics)
    }

    overall_state = determine_overall_state(categories)
    summary = generate_summary(overall_state, categories)
    actions = generate_actions(overall_state, categories)
    trends = calculate_trends(metrics)

    %{
      "version" => @version,
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "state" => Atom.to_string(overall_state),
      "summary" => summary,
      "categories" => categories,
      "notifications" => generate_notifications(overall_state),
      "actions" => actions,
      "trends" => trends,
      "source" => %{
        "tool" => "sysobs",
        "last_scan" => last_scan_time(metrics),
        "scan_profile" => "continuous"
      }
    }
  end

  @doc """
  Generate weather from an explicit set of readings (for testing or external data).
  """
  @spec generate_from(map()) :: map()
  def generate_from(readings) do
    disk_pct = Map.get(readings, :disk_percent, 0)
    mem_pct = Map.get(readings, :memory_percent, 0)
    cpu_pct = Map.get(readings, :cpu_percent, 0)

    categories = %{
      "disk" => evaluate_threshold("disk", disk_pct, @disk_warning_percent, @disk_critical_percent, "%"),
      "memory" => evaluate_threshold("memory", mem_pct, @memory_warning_percent, @memory_critical_percent, "%"),
      "cpu" => evaluate_threshold("cpu", cpu_pct, @cpu_warning_percent, @cpu_critical_percent, "%")
    }

    overall_state = determine_overall_state(categories)
    summary = generate_summary(overall_state, categories)

    %{
      "version" => @version,
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "state" => Atom.to_string(overall_state),
      "summary" => summary,
      "categories" => categories,
      "notifications" => generate_notifications(overall_state),
      "actions" => generate_actions(overall_state, categories),
      "source" => %{
        "tool" => "sysobs",
        "scan_profile" => "snapshot"
      }
    }
  end

  # Category evaluations

  defp evaluate_disk(metrics) do
    disk_metrics = Enum.filter(metrics, fn m -> String.starts_with?(m.name, "disk_") end)
    value = latest_value(disk_metrics, "disk_usage_percent") || 0
    evaluate_threshold("disk", value, @disk_warning_percent, @disk_critical_percent, "%")
  end

  defp evaluate_memory(metrics) do
    mem_metrics = Enum.filter(metrics, fn m -> String.starts_with?(m.name, "memory_") end)
    value = latest_value(mem_metrics, "memory_usage_percent") || 0
    evaluate_threshold("memory", value, @memory_warning_percent, @memory_critical_percent, "%")
  end

  defp evaluate_cpu(metrics) do
    cpu_metrics = Enum.filter(metrics, fn m -> String.starts_with?(m.name, "cpu_") end)
    value = latest_value(cpu_metrics, "cpu_load_percent") || 0
    evaluate_threshold("cpu", value, @cpu_warning_percent, @cpu_critical_percent, "%")
  end

  defp evaluate_threshold(_name, value, warning, critical, unit) do
    {state, summary} =
      cond do
        value >= critical ->
          {:act, "Critical: #{value}#{unit} usage"}

        value >= warning ->
          {:watch, "Elevated: #{value}#{unit} usage"}

        true ->
          {:calm, "Normal: #{value}#{unit} usage"}
      end

    %{
      "state" => Atom.to_string(state),
      "summary" => summary,
      "metric_value" => value,
      "metric_unit" => unit,
      "threshold_warning" => warning,
      "threshold_critical" => critical
    }
  end

  # State determination

  defp determine_overall_state(categories) do
    states =
      categories
      |> Map.values()
      |> Enum.map(fn cat -> String.to_atom(cat["state"]) end)

    cond do
      :act in states -> :act
      :watch in states -> :watch
      true -> :calm
    end
  end

  # Summary generation

  defp generate_summary(:calm, _categories) do
    "All systems nominal. No action needed."
  end

  defp generate_summary(:watch, categories) do
    watching =
      categories
      |> Enum.filter(fn {_k, v} -> v["state"] == "watch" end)
      |> Enum.map(fn {k, _v} -> k end)
      |> Enum.join(", ")

    "Monitoring #{watching}. No immediate action required."
  end

  defp generate_summary(:act, categories) do
    acting =
      categories
      |> Enum.filter(fn {_k, v} -> v["state"] == "act" end)
      |> Enum.map(fn {k, v} -> "#{k} (#{v["summary"]})" end)
      |> Enum.join(", ")

    "Action recommended: #{acting}"
  end

  # Notifications

  defp generate_notifications(:calm) do
    %{
      "should_notify" => false,
      "notification_type" => "silent"
    }
  end

  defp generate_notifications(:watch) do
    %{
      "should_notify" => true,
      "notification_type" => "badge",
      "snooze_options" => [
        %{"label" => "1 hour", "duration_seconds" => 3600},
        %{"label" => "4 hours", "duration_seconds" => 14400}
      ]
    }
  end

  defp generate_notifications(:act) do
    %{
      "should_notify" => true,
      "notification_type" => "toast",
      "snooze_options" => [
        %{"label" => "30 minutes", "duration_seconds" => 1800},
        %{"label" => "1 hour", "duration_seconds" => 3600}
      ]
    }
  end

  # Actions

  defp generate_actions(:calm, _categories), do: []

  defp generate_actions(:watch, categories) do
    categories
    |> Enum.filter(fn {_k, v} -> v["state"] == "watch" end)
    |> Enum.map(fn {k, _v} ->
      %{
        "action_id" => "investigate_#{k}",
        "label" => "Investigate #{k}",
        "description" => "Open Operating Theatre for #{k} diagnostics",
        "priority" => "medium",
        "handler" => "open_theatre",
        "parameters" => %{"category" => k}
      }
    end)
  end

  defp generate_actions(:act, categories) do
    categories
    |> Enum.filter(fn {_k, v} -> v["state"] == "act" end)
    |> Enum.map(fn {k, _v} ->
      %{
        "action_id" => "fix_#{k}",
        "label" => "Fix #{k} now",
        "description" => "Open Emergency Room for immediate #{k} remediation",
        "priority" => "high",
        "handler" => "open_a_and_e",
        "parameters" => %{"category" => k}
      }
    end)
  end

  # Trends

  defp calculate_trends(metrics) do
    %{
      "disk_usage" => calculate_single_trend(metrics, "disk_usage_percent"),
      "memory_pressure" => calculate_single_trend(metrics, "memory_usage_percent"),
      "cpu_load" => calculate_single_trend(metrics, "cpu_load_percent"),
      "overall" => %{"direction" => "stable"}
    }
  end

  defp calculate_single_trend(metrics, name) do
    values =
      metrics
      |> Enum.filter(fn m -> m.name == name end)
      |> Enum.sort_by(fn m -> m.timestamp end, DateTime)
      |> Enum.map(fn m -> m.value end)

    direction =
      case values do
        [a, b | _rest] when b > a + 5 -> "degrading"
        [a, b | _rest] when b < a - 5 -> "improving"
        _ -> "stable"
      end

    %{"direction" => direction}
  end

  # Helpers

  defp latest_value(metrics, name) do
    metrics
    |> Enum.filter(fn m -> m.name == name end)
    |> Enum.sort_by(fn m -> m.timestamp end, {:desc, DateTime})
    |> List.first()
    |> case do
      nil -> nil
      m -> m.value
    end
  end

  defp last_scan_time(metrics) do
    case metrics do
      [latest | _] -> DateTime.to_iso8601(latest.timestamp)
      [] -> nil
    end
  end
end
