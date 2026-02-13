# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule SystemObservatory.ThemesTest do
  use ExUnit.Case, async: true

  alias SystemObservatory.Themes

  describe "get/1" do
    test "returns default theme" do
      theme = Themes.get("default")
      assert theme["id"] == "default"
      assert theme["name"] == "Default"
      assert Map.has_key?(theme, "states")
      assert Map.has_key?(theme, "popover")
    end

    test "returns minimal theme" do
      theme = Themes.get("minimal")
      assert theme["id"] == "minimal"
      assert theme["states"]["calm"]["animation"] == "none"
      assert theme["states"]["watch"]["animation"] == "none"
    end

    test "returns tech theme" do
      theme = Themes.get("tech")
      assert theme["id"] == "tech"
      assert theme["states"]["calm"]["icon"] == "SYS_OK"
      assert theme["states"]["calm"]["color"] == "#00FF00"
    end

    test "returns default for unknown theme" do
      theme = Themes.get("nonexistent")
      assert theme["id"] == "default"
    end
  end

  describe "list/0" do
    test "returns all theme IDs" do
      ids = Themes.list()
      assert "default" in ids
      assert "minimal" in ids
      assert "tech" in ids
      assert length(ids) == 3
    end
  end

  describe "apply_state/2" do
    test "applies calm state from default theme" do
      theme = Themes.get("default")
      result = Themes.apply_state(theme, :calm)
      assert result["icon"] == "sun"
      assert result["color"] == "#4CAF50"
      assert result["animation"] == "none"
    end

    test "applies watch state from default theme" do
      theme = Themes.get("default")
      result = Themes.apply_state(theme, :watch)
      assert result["icon"] == "cloud"
      assert result["animation"] == "pulse"
    end

    test "applies act state from default theme" do
      theme = Themes.get("default")
      result = Themes.apply_state(theme, :act)
      assert result["icon"] == "storm"
      assert result["animation"] == "bounce"
    end
  end

  describe "format_headline/3" do
    test "formats headline with default theme" do
      theme = Themes.get("default")
      result = Themes.format_headline(theme, "calm", "All good")
      assert result == "calm — All good"
    end

    test "formats headline with tech theme" do
      theme = Themes.get("tech")
      result = Themes.format_headline(theme, "act", "CPU critical")
      assert result == ">> act: CPU critical"
    end

    test "formats headline with minimal theme" do
      theme = Themes.get("minimal")
      result = Themes.format_headline(theme, "watch", "Memory elevated")
      assert result == "[watch] Memory elevated"
    end
  end
end
