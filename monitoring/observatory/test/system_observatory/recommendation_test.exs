# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule SystemObservatory.RecommendationTest do
  use ExUnit.Case

  alias SystemObservatory.Recommendation
  alias SystemObservatory.Metrics.Store
  alias SystemObservatory.Correlator

  setup do
    start_supervised!(Store)
    start_supervised!(Correlator)
    :ok
  end

  describe "generate/0" do
    test "returns empty list when no data" do
      recommendations = Recommendation.generate()
      assert recommendations == []
    end

    test "generates recommendation for high CPU" do
      :ok = Store.record("cpu_usage", 95, %{}, source: "scanner")
      recommendations = Recommendation.generate()

      assert length(recommendations) == 1
      [rec] = recommendations
      assert rec.type == :corrective
      assert rec.priority == :high
      assert String.contains?(rec.summary, "CPU")
    end

    test "generates recommendation for high disk usage" do
      :ok = Store.record("disk_usage", 90, %{}, source: "scanner")
      recommendations = Recommendation.generate()

      assert length(recommendations) == 1
      [rec] = recommendations
      assert rec.priority == :critical
      assert String.contains?(rec.summary, "Disk")
    end

    test "generates investigative recommendation for correlations" do
      {:ok, _} = Correlator.record_event(:change, "package-manager", %{package: "openssl"})
      {:ok, _} = Correlator.record_event(:anomaly, "ssl-service", %{error: "handshake failed"})

      recommendations = Recommendation.generate()

      investigative = Enum.filter(recommendations, &(&1.type == :investigative))
      assert length(investigative) >= 1
    end

    test "includes generated_at and id in recommendations" do
      :ok = Store.record("cpu_usage", 95, %{}, source: "scanner")
      [rec] = Recommendation.generate()

      assert String.starts_with?(rec.id, "rec-")
      assert %DateTime{} = rec.generated_at
    end

    test "sorts recommendations by priority" do
      :ok = Store.record("cpu_usage", 95, %{}, source: "scanner")
      :ok = Store.record("disk_usage", 90, %{}, source: "scanner")

      recommendations = Recommendation.generate()

      # Disk (critical) should come before CPU (high)
      priorities = Enum.map(recommendations, & &1.priority)
      assert hd(priorities) == :critical
    end
  end

  describe "generate_json/0" do
    test "returns valid JSON" do
      :ok = Store.record("cpu_usage", 95, %{}, source: "scanner")
      {:ok, json} = Recommendation.generate_json()

      assert {:ok, decoded} = Jason.decode(json)
      assert Map.has_key?(decoded, "recommendations")
      assert Map.has_key?(decoded, "schema_version")
      assert Map.has_key?(decoded, "generated_at")
    end

    test "converts atoms to strings in JSON" do
      :ok = Store.record("cpu_usage", 95, %{}, source: "scanner")
      {:ok, json} = Recommendation.generate_json()
      {:ok, decoded} = Jason.decode(json)

      [rec] = decoded["recommendations"]
      assert rec["type"] == "corrective"
      assert rec["priority"] == "high"
    end
  end

  describe "by_type/1" do
    test "filters recommendations by type" do
      :ok = Store.record("cpu_usage", 95, %{}, source: "scanner")
      {:ok, _} = Correlator.record_event(:change, "system", %{})
      {:ok, _} = Correlator.record_event(:anomaly, "app", %{})

      corrective = Recommendation.by_type(:corrective)
      investigative = Recommendation.by_type(:investigative)

      assert Enum.all?(corrective, &(&1.type == :corrective))
      assert Enum.all?(investigative, &(&1.type == :investigative))
    end
  end

  describe "by_min_priority/1" do
    test "filters recommendations by minimum priority" do
      :ok = Store.record("cpu_usage", 95, %{}, source: "scanner")
      :ok = Store.record("disk_usage", 90, %{}, source: "scanner")

      critical = Recommendation.by_min_priority(:critical)
      high_and_above = Recommendation.by_min_priority(:high)

      assert length(critical) == 1
      assert length(high_and_above) == 2
    end
  end

  describe "action_template" do
    test "includes actionable template for threshold violations" do
      :ok = Store.record("cpu_usage", 95, %{}, source: "scanner")
      [rec] = Recommendation.generate()

      assert rec.action_template.action == "address_threshold"
      assert rec.action_template.metric_name == "cpu_usage"
      assert rec.action_template.current_value == 95
    end

    test "includes context for correlation-based recommendations" do
      {:ok, _} = Correlator.record_event(:change, "package", %{name: "nginx"})
      {:ok, _} = Correlator.record_event(:anomaly, "web-server", %{error: "connection refused"})

      investigative = Recommendation.by_type(:investigative)
      assert length(investigative) >= 1

      [rec] = investigative
      assert rec.action_template.action == "investigate"
      assert Map.has_key?(rec.action_template, :context)
    end
  end

  describe "supporting_evidence" do
    test "links recommendations to source data" do
      :ok = Store.record("cpu_usage", 95, %{}, source: "scanner")
      [rec] = Recommendation.generate()

      assert length(rec.supporting_evidence) >= 1
      [evidence] = rec.supporting_evidence
      assert evidence.type == "metric"
    end
  end

  describe "confidence scoring" do
    test "threshold violations have high confidence" do
      :ok = Store.record("cpu_usage", 95, %{}, source: "scanner")
      [rec] = Recommendation.generate()

      assert rec.confidence >= 0.7
    end
  end
end
