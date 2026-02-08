# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule SystemObservatory.BundleIngestionTest do
  use ExUnit.Case

  alias SystemObservatory.BundleIngestion
  alias SystemObservatory.Metrics.Store
  alias SystemObservatory.Correlator

  setup do
    start_supervised!(Store)
    start_supervised!(Correlator)
    :ok
  end

  describe "ingest/2" do
    test "ingests bundle with snapshot metrics" do
      bundle = %{
        "id" => "test-bundle-001",
        "timestamp" => "2026-01-09T10:00:00Z",
        "snapshot" => %{"disk_free" => 1024, "memory_used" => 8192}
      }

      {:ok, result} = BundleIngestion.ingest(bundle)

      assert result.bundle_id == "test-bundle-001"
      assert result.metrics_recorded == 2

      metrics = Store.all()
      assert length(metrics) == 2
    end

    test "ingests bundle with findings as events" do
      bundle = %{
        "id" => "test-bundle-002",
        "findings" => [
          %{"type" => "low_disk", "severity" => "warning"},
          %{"type" => "high_cpu", "severity" => "anomaly"}
        ]
      }

      {:ok, result} = BundleIngestion.ingest(bundle)

      assert result.events_recorded == 2

      events = Correlator.all_events()
      assert length(events) == 2
    end

    test "ingests bundle with applied changes as events" do
      bundle = %{
        "id" => "test-bundle-003",
        "applied" => [
          %{"action" => "cleanup", "status" => "success"},
          %{"action" => "restart", "status" => "success"}
        ]
      }

      {:ok, result} = BundleIngestion.ingest(bundle)

      assert result.events_recorded == 2

      events = Correlator.all_events()
      assert length(events) == 2
      assert Enum.all?(events, fn e -> e.type == :change end)
    end

    test "generates bundle_id if not provided" do
      bundle = %{"snapshot" => %{"cpu" => 50}}

      {:ok, result} = BundleIngestion.ingest(bundle)

      assert String.starts_with?(result.bundle_id, "bundle-")
    end

    test "uses provided source option" do
      bundle = %{
        "id" => "test-bundle-004",
        "snapshot" => %{"cpu" => 50}
      }

      {:ok, _result} = BundleIngestion.ingest(bundle, source: "custom-scanner")

      [metric] = Store.all()
      assert metric.source == "custom-scanner"
    end

    test "handles empty bundle" do
      bundle = %{}

      {:ok, result} = BundleIngestion.ingest(bundle)

      assert result.metrics_recorded == 0
      assert result.events_recorded == 0
    end

    test "handles nil sections gracefully" do
      bundle = %{
        "id" => "test-bundle-005",
        "snapshot" => nil,
        "findings" => nil,
        "applied" => nil
      }

      {:ok, result} = BundleIngestion.ingest(bundle)

      assert result.metrics_recorded == 0
      assert result.events_recorded == 0
    end

    test "classifies critical findings as anomalies" do
      bundle = %{
        "findings" => [%{"severity" => "critical", "message" => "disk full"}]
      }

      {:ok, _result} = BundleIngestion.ingest(bundle)

      [event] = Correlator.all_events()
      assert event.type == :anomaly
    end

    test "classifies warning findings as metrics" do
      bundle = %{
        "findings" => [%{"severity" => "warning", "message" => "disk low"}]
      }

      {:ok, _result} = BundleIngestion.ingest(bundle)

      [event] = Correlator.all_events()
      assert event.type == :metric
    end
  end

  describe "ingest_file/2" do
    test "returns error for non-existent file" do
      result = BundleIngestion.ingest_file("/nonexistent/bundle.json")

      assert {:error, :enoent} = result
    end
  end

  describe "complete ingestion workflow" do
    test "full bundle with all sections enables correlation" do
      # Simulate a complete run bundle
      bundle = %{
        "id" => "run-2026-01-09-001",
        "timestamp" => "2026-01-09T10:00:00Z",
        "source" => "operating-theatre",
        "snapshot" => %{
          "disk_free_gb" => 50,
          "memory_used_mb" => 4096,
          "cpu_percent" => 45
        },
        "findings" => [
          %{"type" => "disk_trend", "severity" => "warning", "message" => "disk usage increasing"}
        ],
        "applied" => [
          %{"action" => "log_cleanup", "target" => "/var/log", "status" => "success"}
        ]
      }

      {:ok, result} = BundleIngestion.ingest(bundle)

      assert result.metrics_recorded == 3
      assert result.events_recorded == 2
      assert result.bundle_id == "run-2026-01-09-001"

      # Verify correlation is possible
      correlations = Correlator.find_correlations()
      # No anomalies recorded (only warnings), so no correlations expected
      assert correlations == []
    end

    test "bundle with anomaly finding can correlate with changes" do
      bundle = %{
        "id" => "run-with-anomaly",
        "applied" => [%{"action" => "config_change", "status" => "success"}],
        "findings" => [%{"type" => "service_crash", "severity" => "error"}]
      }

      {:ok, _result} = BundleIngestion.ingest(bundle)

      correlations = Correlator.find_correlations()
      assert length(correlations) == 1

      [corr] = correlations
      assert corr.anomaly.data["type"] == "service_crash"
      assert length(corr.related_changes) == 1
    end
  end
end
