# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule SystemObservatory.Ambient do
  @moduledoc """
  Ambient payload generation for the Ward UI.

  Generates `AmbientPayload` conforming to `ambient-payload.schema.json`
  from `SystemWeather` + a theme pack.

  ## CRITICAL: Advisory Data Only (CRIT-003 compliance)

  Ambient payloads drive UI presentation only.
  They NEVER carry commands or modify system state.
  """

  alias SystemObservatory.Weather
  alias SystemObservatory.Themes

  @doc """
  Generate an ambient payload using the default theme.
  """
  @spec generate() :: map()
  def generate do
    generate_with_theme("default")
  end

  @doc """
  Generate an ambient payload with a specific theme.
  """
  @spec generate_with_theme(String.t()) :: map()
  def generate_with_theme(theme_id) do
    weather = Weather.generate()
    theme = Themes.get(theme_id)
    build_payload(weather, theme)
  end

  @doc """
  Generate an ambient payload from explicit weather data and theme.
  Useful for testing and snapshot-based generation.
  """
  @spec generate_from(map(), String.t()) :: map()
  def generate_from(readings, theme_id \\ "default") do
    weather = Weather.generate_from(readings)
    theme = Themes.get(theme_id)
    build_payload(weather, theme)
  end

  defp build_payload(weather, theme) do
    state = String.to_atom(weather["state"])
    theme_state = Themes.apply_state(theme, state)

    %{
      "version" => "1.0.0",
      "timestamp" => weather["timestamp"],
      "theme_id" => theme["id"],
      "indicator" => build_indicator(weather, theme_state),
      "badge" => build_badge(weather, theme_state),
      "popover" => build_popover(weather, theme),
      "notifications" => build_notifications(weather),
      "quick_actions" => build_quick_actions(weather),
      "schedule" => %{
        "refresh_interval_seconds" => refresh_interval(state),
        "next_refresh" => next_refresh_time(state)
      }
    }
  end

  defp build_indicator(weather, theme_state) do
    %{
      "icon" => theme_state["icon"],
      "color" => theme_state["color"],
      "animation" => theme_state["animation"],
      "state" => weather["state"],
      "tooltip" => weather["summary"]
    }
  end

  defp build_badge(weather, theme_state) do
    categories = weather["categories"] || %{}
    issue_count = Enum.count(categories, fn {_k, v} -> v["state"] != "calm" end)

    %{
      "visible" => issue_count > 0,
      "count" => issue_count,
      "color" => theme_state["color"]
    }
  end

  defp build_popover(weather, theme) do
    state = weather["state"]
    summary = weather["summary"]
    headline = Themes.format_headline(theme, state, summary)

    categories = weather["categories"] || %{}
    show_metrics = theme["popover"]["show_metrics"]
    max_metrics = theme["popover"]["max_metrics"]

    metrics =
      if show_metrics do
        categories
        |> Enum.take(max_metrics)
        |> Enum.map(fn {name, cat} ->
          %{
            "label" => name,
            "value" => cat["metric_value"],
            "unit" => cat["metric_unit"],
            "state" => cat["state"]
          }
        end)
      else
        []
      end

    %{
      "headline" => headline,
      "metrics" => metrics,
      "last_updated" => weather["timestamp"]
    }
  end

  defp build_notifications(weather) do
    notif = weather["notifications"] || %{}

    %{
      "should_notify" => Map.get(notif, "should_notify", false),
      "notification_type" => Map.get(notif, "notification_type", "silent"),
      "snooze_options" => Map.get(notif, "snooze_options", [])
    }
  end

  defp build_quick_actions(weather) do
    actions = weather["actions"] || []

    Enum.map(actions, fn action ->
      %{
        "id" => action["action_id"],
        "label" => action["label"],
        "description" => action["description"],
        "priority" => action["priority"]
      }
    end)
  end

  defp refresh_interval(:calm), do: 60
  defp refresh_interval(:watch), do: 30
  defp refresh_interval(:act), do: 10

  defp next_refresh_time(state) do
    seconds = refresh_interval(state)
    DateTime.utc_now()
    |> DateTime.add(seconds, :second)
    |> DateTime.to_iso8601()
  end
end
