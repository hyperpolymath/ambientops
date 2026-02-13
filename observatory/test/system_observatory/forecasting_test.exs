# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule SystemObservatory.ForecastingTest do
  use ExUnit.Case

  alias SystemObservatory.Forecasting
  alias SystemObservatory.Metrics.Store

  setup do
    start_supervised!(Store)
    :ok
  end

  # Helper: create a base timestamp far enough in the future to avoid TTL staleness
  defp base_time do
    DateTime.utc_now()
  end

  # Helper: record values spaced 1 hour apart
  defp record_hourly(name, values) do
    base = base_time()

    values
    |> Enum.with_index()
    |> Enum.each(fn {value, i} ->
      ts = DateTime.add(base, i * 3600, :second)
      :ok = Store.record_at(name, value, ts)
    end)
  end

  describe "generate/0" do
    test "returns empty list when no data" do
      forecasts = Forecasting.generate()
      assert forecasts == []
    end

    test "returns empty list with insufficient data points" do
      record_hourly("cpu_usage", [50, 55])

      forecasts = Forecasting.generate()
      assert forecasts == []
    end

    test "generates forecasts with sufficient data" do
      record_hourly("cpu_usage", [50, 55, 60])

      forecasts = Forecasting.generate()
      # Should have at least one trend forecast
      assert length(forecasts) >= 1
    end

    test "sorts forecasts by confidence" do
      record_hourly("disk_usage", [55, 60, 65, 70, 75])

      forecasts = Forecasting.generate()
      confidences = Enum.map(forecasts, & &1.confidence)

      # Should be sorted descending
      assert confidences == Enum.sort(confidences, :desc)
    end
  end

  describe "predict_exhaustion/2" do
    test "returns error with insufficient data" do
      record_hourly("disk_usage", [50])

      result = Forecasting.predict_exhaustion("disk_usage", 100)
      assert result == {:error, :insufficient_data}
    end

    test "returns error when not trending up" do
      record_hourly("disk_usage", [50, 45, 40])

      result = Forecasting.predict_exhaustion("disk_usage", 100)
      assert result == {:error, :not_trending}
    end

    test "predicts exhaustion for increasing trend" do
      record_hourly("disk_usage", [50, 60, 70])

      {:ok, forecast} = Forecasting.predict_exhaustion("disk_usage", 100)

      assert forecast.metric_name == "disk_usage"
      assert forecast.forecast_type == :exhaustion
      assert forecast.current_value == 70
      assert forecast.predicted_value == 100
      assert %DateTime{} = forecast.prediction_at
      assert forecast.confidence > 0
    end

    test "includes human-readable message" do
      record_hourly("disk_usage", [55, 60, 65, 70, 75])

      {:ok, forecast} = Forecasting.predict_exhaustion("disk_usage", 100)

      assert String.contains?(forecast.message, "disk_usage")
      assert String.contains?(forecast.message, "100%")
    end
  end

  describe "predict_threshold_breach/2" do
    test "returns error when already breached" do
      record_hourly("cpu_usage", [90, 92, 95])

      result = Forecasting.predict_threshold_breach("cpu_usage", 85)
      assert result == {:error, :already_breached}
    end

    test "predicts threshold breach" do
      record_hourly("cpu_usage", [50, 60, 70])

      {:ok, forecast} = Forecasting.predict_threshold_breach("cpu_usage", 85)

      assert forecast.forecast_type == :threshold
      assert forecast.predicted_value == 85
      assert String.contains?(forecast.message, "breach")
    end
  end

  describe "analyze_trend/1" do
    test "returns error with insufficient data" do
      record_hourly("test", [50])

      result = Forecasting.analyze_trend("test")
      assert result == {:error, :insufficient_data}
    end

    test "detects increasing trend" do
      record_hourly("test", [10, 20, 30])

      {:ok, analysis} = Forecasting.analyze_trend("test")

      assert analysis.direction == :increasing
      assert analysis.rate_per_hour > 0
    end

    test "detects decreasing trend" do
      record_hourly("test", [30, 20, 10])

      {:ok, analysis} = Forecasting.analyze_trend("test")

      assert analysis.direction == :decreasing
      assert analysis.rate_per_hour < 0
    end

    test "detects stable trend" do
      record_hourly("test", [50, 50, 50])

      {:ok, analysis} = Forecasting.analyze_trend("test")

      assert analysis.direction == :stable
    end

    test "includes current value and data points" do
      record_hourly("test", [10, 20, 30])

      {:ok, analysis} = Forecasting.analyze_trend("test")

      assert analysis.current_value == 30
      assert analysis.data_points == 3
    end
  end

  describe "forecast structure" do
    test "includes all required fields" do
      record_hourly("memory_usage", [45, 50, 55, 60, 65])

      [forecast | _] = Forecasting.generate()

      assert Map.has_key?(forecast, :metric_name)
      assert Map.has_key?(forecast, :forecast_type)
      assert Map.has_key?(forecast, :current_value)
      assert Map.has_key?(forecast, :predicted_value)
      assert Map.has_key?(forecast, :prediction_at)
      assert Map.has_key?(forecast, :confidence)
      assert Map.has_key?(forecast, :message)
      assert Map.has_key?(forecast, :data_points)
      assert Map.has_key?(forecast, :generated_at)
    end

    test "confidence is bounded between 0 and 1" do
      record_hourly("test_usage", [43, 46, 49, 52, 55, 58, 61, 64, 67, 70])

      forecasts = Forecasting.generate()

      Enum.each(forecasts, fn f ->
        assert f.confidence >= 0
        assert f.confidence <= 1
      end)
    end
  end
end
