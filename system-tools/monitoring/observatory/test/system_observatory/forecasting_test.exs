# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule SystemObservatory.ForecastingTest do
  use ExUnit.Case

  alias SystemObservatory.Forecasting
  alias SystemObservatory.Metrics.Store

  setup do
    start_supervised!(Store)
    :ok
  end

  describe "generate/0" do
    test "returns empty list when no data" do
      forecasts = Forecasting.generate()
      assert forecasts == []
    end

    test "returns empty list with insufficient data points" do
      :ok = Store.record("cpu_usage", 50)
      :ok = Store.record("cpu_usage", 55)

      forecasts = Forecasting.generate()
      assert forecasts == []
    end

    test "generates forecasts with sufficient data" do
      :ok = Store.record("cpu_usage", 50)
      Process.sleep(10)
      :ok = Store.record("cpu_usage", 55)
      Process.sleep(10)
      :ok = Store.record("cpu_usage", 60)

      forecasts = Forecasting.generate()
      # Should have at least one trend forecast
      assert length(forecasts) >= 1
    end

    test "sorts forecasts by confidence" do
      # Record increasing trend
      Enum.each(1..5, fn i ->
        :ok = Store.record("disk_usage", 50 + i * 5)
        Process.sleep(5)
      end)

      forecasts = Forecasting.generate()
      confidences = Enum.map(forecasts, & &1.confidence)

      # Should be sorted descending
      assert confidences == Enum.sort(confidences, :desc)
    end
  end

  describe "predict_exhaustion/2" do
    test "returns error with insufficient data" do
      :ok = Store.record("disk_usage", 50)

      result = Forecasting.predict_exhaustion("disk_usage", 100)
      assert result == {:error, :insufficient_data}
    end

    test "returns error when not trending up" do
      :ok = Store.record("disk_usage", 50)
      Process.sleep(5)
      :ok = Store.record("disk_usage", 45)
      Process.sleep(5)
      :ok = Store.record("disk_usage", 40)

      result = Forecasting.predict_exhaustion("disk_usage", 100)
      assert result == {:error, :not_trending}
    end

    test "predicts exhaustion for increasing trend" do
      :ok = Store.record("disk_usage", 50)
      Process.sleep(5)
      :ok = Store.record("disk_usage", 60)
      Process.sleep(5)
      :ok = Store.record("disk_usage", 70)

      {:ok, forecast} = Forecasting.predict_exhaustion("disk_usage", 100)

      assert forecast.metric_name == "disk_usage"
      assert forecast.forecast_type == :exhaustion
      assert forecast.current_value == 70
      assert forecast.predicted_value == 100
      assert %DateTime{} = forecast.prediction_at
      assert forecast.confidence > 0
    end

    test "includes human-readable message" do
      Enum.each(1..5, fn i ->
        :ok = Store.record("disk_usage", 50 + i * 5)
        Process.sleep(5)
      end)

      {:ok, forecast} = Forecasting.predict_exhaustion("disk_usage", 100)

      assert String.contains?(forecast.message, "disk_usage")
      assert String.contains?(forecast.message, "100%")
    end
  end

  describe "predict_threshold_breach/2" do
    test "returns error when already breached" do
      :ok = Store.record("cpu_usage", 90)
      Process.sleep(5)
      :ok = Store.record("cpu_usage", 92)
      Process.sleep(5)
      :ok = Store.record("cpu_usage", 95)

      result = Forecasting.predict_threshold_breach("cpu_usage", 85)
      assert result == {:error, :already_breached}
    end

    test "predicts threshold breach" do
      :ok = Store.record("cpu_usage", 50)
      Process.sleep(5)
      :ok = Store.record("cpu_usage", 60)
      Process.sleep(5)
      :ok = Store.record("cpu_usage", 70)

      {:ok, forecast} = Forecasting.predict_threshold_breach("cpu_usage", 85)

      assert forecast.forecast_type == :threshold
      assert forecast.predicted_value == 85
      assert String.contains?(forecast.message, "breach")
    end
  end

  describe "analyze_trend/1" do
    test "returns error with insufficient data" do
      :ok = Store.record("test", 50)

      result = Forecasting.analyze_trend("test")
      assert result == {:error, :insufficient_data}
    end

    test "detects increasing trend" do
      :ok = Store.record("test", 10)
      Process.sleep(5)
      :ok = Store.record("test", 20)
      Process.sleep(5)
      :ok = Store.record("test", 30)

      {:ok, analysis} = Forecasting.analyze_trend("test")

      assert analysis.direction == :increasing
      assert analysis.rate_per_hour > 0
    end

    test "detects decreasing trend" do
      :ok = Store.record("test", 30)
      Process.sleep(5)
      :ok = Store.record("test", 20)
      Process.sleep(5)
      :ok = Store.record("test", 10)

      {:ok, analysis} = Forecasting.analyze_trend("test")

      assert analysis.direction == :decreasing
      assert analysis.rate_per_hour < 0
    end

    test "detects stable trend" do
      :ok = Store.record("test", 50)
      Process.sleep(5)
      :ok = Store.record("test", 50)
      Process.sleep(5)
      :ok = Store.record("test", 50)

      {:ok, analysis} = Forecasting.analyze_trend("test")

      assert analysis.direction == :stable
    end

    test "includes current value and data points" do
      :ok = Store.record("test", 10)
      Process.sleep(5)
      :ok = Store.record("test", 20)
      Process.sleep(5)
      :ok = Store.record("test", 30)

      {:ok, analysis} = Forecasting.analyze_trend("test")

      assert analysis.current_value == 30
      assert analysis.data_points == 3
    end
  end

  describe "forecast structure" do
    test "includes all required fields" do
      Enum.each(1..5, fn i ->
        :ok = Store.record("memory_usage", 40 + i * 5)
        Process.sleep(5)
      end)

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
      Enum.each(1..10, fn i ->
        :ok = Store.record("test_usage", 40 + i * 3)
        Process.sleep(5)
      end)

      forecasts = Forecasting.generate()

      Enum.each(forecasts, fn f ->
        assert f.confidence >= 0
        assert f.confidence <= 1
      end)
    end
  end
end
