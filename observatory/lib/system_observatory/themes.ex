# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule SystemObservatory.Themes do
  @moduledoc """
  Theme packs for Ward ambient UI.

  Themes control the visual presentation of system weather:
  icons, colors, animations, and popover formatting.

  ## Built-in Themes

  - `default` — Sun/cloud/storm with standard material colors
  - `minimal` — Text-only, no animations, monochrome
  - `tech` — Terminal-style, green/amber/red, no animations
  """

  @doc """
  Get a theme by ID. Returns default if theme not found.
  """
  @spec get(String.t()) :: map()
  def get(theme_id) do
    case Map.get(all(), theme_id) do
      nil -> Map.get(all(), "default")
      theme -> theme
    end
  end

  @doc """
  List all available theme IDs.
  """
  @spec list() :: [String.t()]
  def list do
    Map.keys(all())
  end

  @doc """
  Get all built-in themes.
  """
  @spec all() :: map()
  def all do
    %{
      "default" => default_theme(),
      "minimal" => minimal_theme(),
      "tech" => tech_theme()
    }
  end

  @doc """
  Apply a theme to a weather state, returning icon/color/animation.
  """
  @spec apply_state(map(), atom()) :: map()
  def apply_state(theme, state) when is_atom(state) do
    state_key = Atom.to_string(state)
    Map.get(theme["states"], state_key, theme["states"]["calm"])
  end

  @doc """
  Format a popover headline using the theme's format string.
  """
  @spec format_headline(map(), String.t(), String.t()) :: String.t()
  def format_headline(theme, state, summary) do
    theme["popover"]["headline_format"]
    |> String.replace("{state}", state)
    |> String.replace("{summary}", summary)
  end

  # Built-in themes

  defp default_theme do
    %{
      "id" => "default",
      "name" => "Default",
      "states" => %{
        "calm" => %{"icon" => "sun", "color" => "#4CAF50", "animation" => "none"},
        "watch" => %{"icon" => "cloud", "color" => "#FF9800", "animation" => "pulse"},
        "act" => %{"icon" => "storm", "color" => "#F44336", "animation" => "bounce"}
      },
      "popover" => %{
        "headline_format" => "{state} — {summary}",
        "show_metrics" => true,
        "max_metrics" => 4
      }
    }
  end

  defp minimal_theme do
    %{
      "id" => "minimal",
      "name" => "Minimal",
      "states" => %{
        "calm" => %{"icon" => "ok", "color" => "#808080", "animation" => "none"},
        "watch" => %{"icon" => "warn", "color" => "#808080", "animation" => "none"},
        "act" => %{"icon" => "crit", "color" => "#808080", "animation" => "none"}
      },
      "popover" => %{
        "headline_format" => "[{state}] {summary}",
        "show_metrics" => false,
        "max_metrics" => 0
      }
    }
  end

  defp tech_theme do
    %{
      "id" => "tech",
      "name" => "Tech",
      "states" => %{
        "calm" => %{"icon" => "SYS_OK", "color" => "#00FF00", "animation" => "none"},
        "watch" => %{"icon" => "SYS_WARN", "color" => "#FFBF00", "animation" => "none"},
        "act" => %{"icon" => "SYS_CRIT", "color" => "#FF0000", "animation" => "none"}
      },
      "popover" => %{
        "headline_format" => ">> {state}: {summary}",
        "show_metrics" => true,
        "max_metrics" => 6
      }
    }
  end
end
