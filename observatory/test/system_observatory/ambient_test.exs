# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule SystemObservatory.AmbientTest do
  use ExUnit.Case

  alias SystemObservatory.Ambient

  setup do
    {:ok, _pid} = SystemObservatory.Metrics.Store.start_link([])
    :ok
  end

  describe "generate_from/2" do
    test "generates calm ambient payload with default theme" do
      payload = Ambient.generate_from(%{disk_percent: 20, memory_percent: 30, cpu_percent: 10})

      assert payload["version"] == "1.0.0"
      assert payload["theme_id"] == "default"
      assert payload["indicator"]["state"] == "calm"
      assert payload["indicator"]["icon"] == "sun"
      assert payload["indicator"]["color"] == "#4CAF50"
      assert payload["badge"]["visible"] == false
      assert payload["badge"]["count"] == 0
    end

    test "generates watch ambient payload" do
      payload = Ambient.generate_from(%{disk_percent: 85, memory_percent: 30, cpu_percent: 10})

      assert payload["indicator"]["state"] == "watch"
      assert payload["indicator"]["icon"] == "cloud"
      assert payload["indicator"]["animation"] == "pulse"
      assert payload["badge"]["visible"] == true
      assert payload["badge"]["count"] == 1
    end

    test "generates act ambient payload" do
      payload = Ambient.generate_from(%{disk_percent: 95, memory_percent: 92, cpu_percent: 10})

      assert payload["indicator"]["state"] == "act"
      assert payload["indicator"]["icon"] == "storm"
      assert payload["badge"]["count"] == 2
    end

    test "generates ambient payload with tech theme" do
      payload = Ambient.generate_from(
        %{disk_percent: 50, memory_percent: 50, cpu_percent: 50},
        "tech"
      )

      assert payload["theme_id"] == "tech"
      assert payload["indicator"]["icon"] == "SYS_OK"
      assert payload["indicator"]["color"] == "#00FF00"
    end

    test "popover includes metrics for default theme" do
      payload = Ambient.generate_from(%{disk_percent: 50, memory_percent: 60, cpu_percent: 40})

      assert is_list(payload["popover"]["metrics"])
      assert length(payload["popover"]["metrics"]) > 0
    end

    test "popover excludes metrics for minimal theme" do
      payload = Ambient.generate_from(
        %{disk_percent: 50, memory_percent: 60, cpu_percent: 40},
        "minimal"
      )

      assert payload["popover"]["metrics"] == []
    end

    test "schedule adjusts refresh interval by state" do
      calm = Ambient.generate_from(%{disk_percent: 10, memory_percent: 10, cpu_percent: 10})
      assert calm["schedule"]["refresh_interval_seconds"] == 60

      watch = Ambient.generate_from(%{disk_percent: 85, memory_percent: 10, cpu_percent: 10})
      assert watch["schedule"]["refresh_interval_seconds"] == 30

      act = Ambient.generate_from(%{disk_percent: 95, memory_percent: 10, cpu_percent: 10})
      assert act["schedule"]["refresh_interval_seconds"] == 10
    end

    test "quick_actions populated for watch state" do
      payload = Ambient.generate_from(%{disk_percent: 85, memory_percent: 10, cpu_percent: 10})

      assert is_list(payload["quick_actions"])
      assert length(payload["quick_actions"]) > 0

      action = List.first(payload["quick_actions"])
      assert Map.has_key?(action, "id")
      assert Map.has_key?(action, "label")
    end
  end
end
