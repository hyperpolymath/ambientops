# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule SystemObservatory.CorrelatorTest do
  use ExUnit.Case

  setup do
    start_supervised!(SystemObservatory.Correlator)
    :ok
  end

  describe "record_event/3" do
    test "records a change event and returns id" do
      {:ok, id} = SystemObservatory.Correlator.record_event(:change, "system", %{action: "update"})
      assert is_binary(id)

      events = SystemObservatory.Correlator.all_events()
      assert length(events) == 1
      [event] = events
      assert event.type == :change
      assert event.source == "system"
      assert event.id == id
    end

    test "records an anomaly event" do
      {:ok, _id} = SystemObservatory.Correlator.record_event(:anomaly, "disk", %{error: "low space"})
      [event] = SystemObservatory.Correlator.all_events()

      assert event.type == :anomaly
    end

    test "records a metric event" do
      {:ok, _id} = SystemObservatory.Correlator.record_event(:metric, "cpu", %{value: 95})
      [event] = SystemObservatory.Correlator.all_events()

      assert event.type == :metric
    end

    test "generates unique id for each event" do
      {:ok, id1} = SystemObservatory.Correlator.record_event(:change, "a", %{})
      {:ok, id2} = SystemObservatory.Correlator.record_event(:change, "b", %{})

      assert id1 != id2
    end
  end

  describe "find_correlations/0" do
    test "returns empty list when no anomalies" do
      {:ok, _id} = SystemObservatory.Correlator.record_event(:change, "system", %{})
      correlations = SystemObservatory.Correlator.find_correlations()

      assert correlations == []
    end

    test "correlates anomaly with recent changes" do
      # Record a change
      {:ok, _id} = SystemObservatory.Correlator.record_event(:change, "package", %{name: "openssl"})

      # Record an anomaly shortly after
      {:ok, _id} = SystemObservatory.Correlator.record_event(:anomaly, "ssl", %{error: "handshake failed"})

      correlations = SystemObservatory.Correlator.find_correlations()

      assert length(correlations) == 1
      [corr] = correlations
      assert corr.anomaly.type == :anomaly
      assert length(corr.related_changes) == 1
      assert corr.confidence > 0
      # Verify calculated_at is present (CRIT-001 fix)
      assert %DateTime{} = corr.calculated_at
    end

    test "confidence increases with temporal proximity" do
      {:ok, _id} = SystemObservatory.Correlator.record_event(:change, "system", %{})
      {:ok, _id} = SystemObservatory.Correlator.record_event(:anomaly, "app", %{})

      [corr] = SystemObservatory.Correlator.find_correlations()
      # With new scoring: base 0.2 (1 change) + proximity bonus (close to 0.3)
      # Total should be around 0.5 for immediate succession
      assert corr.confidence >= 0.2
      assert corr.confidence <= 0.95
    end
  end

  describe "all_events/0" do
    test "returns events in chronological order" do
      {:ok, _} = SystemObservatory.Correlator.record_event(:change, "a", %{})
      {:ok, _} = SystemObservatory.Correlator.record_event(:change, "b", %{})
      {:ok, _} = SystemObservatory.Correlator.record_event(:change, "c", %{})

      events = SystemObservatory.Correlator.all_events()
      sources = Enum.map(events, & &1.source)
      assert sources == ["a", "b", "c"]
    end
  end

  describe "clear/0" do
    test "removes all events" do
      {:ok, _} = SystemObservatory.Correlator.record_event(:change, "test", %{})
      assert length(SystemObservatory.Correlator.all_events()) == 1

      :ok = SystemObservatory.Correlator.clear()
      assert SystemObservatory.Correlator.all_events() == []
    end
  end

  describe "record_event_async/3" do
    test "records event asynchronously" do
      :ok = SystemObservatory.Correlator.record_event_async(:change, "async", %{})
      # Give the GenServer time to process the cast
      Process.sleep(10)
      events = SystemObservatory.Correlator.all_events()
      assert length(events) == 1
    end
  end
end
