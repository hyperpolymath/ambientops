# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule SystemObservatory.Metrics.StoreTest do
  use ExUnit.Case

  setup do
    start_supervised!(SystemObservatory.Metrics.Store)
    :ok
  end

  describe "record/3" do
    test "records a metric with name and value" do
      :ok = SystemObservatory.Metrics.Store.record("cpu_usage", 45.5)
      metrics = SystemObservatory.Metrics.Store.all()

      assert length(metrics) == 1
      [metric] = metrics
      assert metric.name == "cpu_usage"
      assert metric.value == 45.5
    end

    test "records metric with tags" do
      :ok = SystemObservatory.Metrics.Store.record("disk_free", 1024, %{drive: "C:"})
      [metric] = SystemObservatory.Metrics.Store.all()

      assert metric.tags == %{drive: "C:"}
    end

    test "records timestamp automatically" do
      :ok = SystemObservatory.Metrics.Store.record("test", 1)
      [metric] = SystemObservatory.Metrics.Store.all()

      assert %DateTime{} = metric.timestamp
    end
  end

  describe "get/1" do
    test "filters metrics by name" do
      :ok = SystemObservatory.Metrics.Store.record("cpu", 10)
      :ok = SystemObservatory.Metrics.Store.record("memory", 20)
      :ok = SystemObservatory.Metrics.Store.record("cpu", 15)

      cpu_metrics = SystemObservatory.Metrics.Store.get("cpu")
      assert length(cpu_metrics) == 2
      assert Enum.all?(cpu_metrics, fn m -> m.name == "cpu" end)
    end

    test "returns empty list when no matches" do
      :ok = SystemObservatory.Metrics.Store.record("cpu", 10)
      assert SystemObservatory.Metrics.Store.get("disk") == []
    end
  end

  describe "all/0" do
    test "returns all metrics in chronological order" do
      :ok = SystemObservatory.Metrics.Store.record("a", 1)
      :ok = SystemObservatory.Metrics.Store.record("b", 2)
      :ok = SystemObservatory.Metrics.Store.record("c", 3)

      metrics = SystemObservatory.Metrics.Store.all()
      assert length(metrics) == 3
      assert Enum.map(metrics, & &1.name) == ["a", "b", "c"]
    end
  end

  describe "clear/0" do
    test "removes all metrics" do
      :ok = SystemObservatory.Metrics.Store.record("test", 1)
      assert length(SystemObservatory.Metrics.Store.all()) == 1

      :ok = SystemObservatory.Metrics.Store.clear()
      assert SystemObservatory.Metrics.Store.all() == []
    end
  end

  describe "provenance tracking (CRIT-003)" do
    test "records source when provided" do
      :ok = SystemObservatory.Metrics.Store.record("cpu", 50, %{}, source: "node-scanner")
      [metric] = SystemObservatory.Metrics.Store.all()

      assert metric.source == "node-scanner"
    end

    test "defaults source to 'unknown' when not provided" do
      :ok = SystemObservatory.Metrics.Store.record("cpu", 50)
      [metric] = SystemObservatory.Metrics.Store.all()

      assert metric.source == "unknown"
    end

    test "records derived_at timestamp" do
      :ok = SystemObservatory.Metrics.Store.record("cpu", 50)
      [metric] = SystemObservatory.Metrics.Store.all()

      assert %DateTime{} = metric.derived_at
    end

    test "all metrics are marked as advisory" do
      :ok = SystemObservatory.Metrics.Store.record("cpu", 50)
      [metric] = SystemObservatory.Metrics.Store.all()

      assert metric.advisory == true
    end
  end

  describe "TTL and staleness" do
    test "records ttl_seconds with default value" do
      :ok = SystemObservatory.Metrics.Store.record("cpu", 50)
      [metric] = SystemObservatory.Metrics.Store.all()

      assert metric.ttl_seconds == 3600
    end

    test "records custom ttl when provided" do
      :ok = SystemObservatory.Metrics.Store.record("cpu", 50, %{}, ttl: 60)
      [metric] = SystemObservatory.Metrics.Store.all()

      assert metric.ttl_seconds == 60
    end

    test "stale?/1 returns false for fresh metric" do
      :ok = SystemObservatory.Metrics.Store.record("cpu", 50)
      [metric] = SystemObservatory.Metrics.Store.all()

      assert SystemObservatory.Metrics.Store.stale?(metric) == false
    end

    test "all_fresh/0 returns only non-stale metrics" do
      :ok = SystemObservatory.Metrics.Store.record("cpu", 50)
      fresh = SystemObservatory.Metrics.Store.all_fresh()

      assert length(fresh) == 1
    end

    test "get_fresh/1 returns only non-stale metrics for name" do
      :ok = SystemObservatory.Metrics.Store.record("cpu", 50)
      :ok = SystemObservatory.Metrics.Store.record("memory", 70)
      fresh = SystemObservatory.Metrics.Store.get_fresh("cpu")

      assert length(fresh) == 1
      assert hd(fresh).name == "cpu"
    end
  end
end
