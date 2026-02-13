# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule SystemObservatory.Forecasting do
  @moduledoc """
  Forecasting module for trend prediction and resource exhaustion warnings.

  Uses linear regression on time series data to predict future values
  and identify potential resource exhaustion.

  ## Philosophy

  Forecasting in System Observatory:
  - **Predicts** but never acts
  - **Warns** but never modifies
  - **Suggests** timelines for human review
  - Is **advisory only** - all predictions have uncertainty bounds

  ## Capabilities

  - Linear trend extrapolation
  - Resource exhaustion prediction (disk, memory)
  - Threshold breach forecasting
  - Rate of change analysis

  ## Example

      # Get all forecasts
      forecasts = SystemObservatory.Forecasting.generate()

      # Predict when disk will be full
      {:ok, forecast} = SystemObservatory.Forecasting.predict_exhaustion("disk_usage", 100)
  """

  alias SystemObservatory.Metrics.Store

  @type forecast :: %{
          metric_name: String.t(),
          forecast_type: :exhaustion | :threshold | :trend,
          current_value: number(),
          predicted_value: number(),
          prediction_at: DateTime.t(),
          confidence: float(),
          message: String.t(),
          data_points: non_neg_integer(),
          generated_at: DateTime.t()
        }

  @doc """
  Generate forecasts for all metrics with sufficient data.

  Requires at least 3 data points per metric for forecasting.
  """
  @spec generate() :: [forecast()]
  def generate do
    metrics = Store.all_fresh()

    metrics
    |> Enum.group_by(& &1.name)
    |> Enum.filter(fn {_name, values} -> length(values) >= 3 end)
    |> Enum.flat_map(&generate_forecasts_for_metric/1)
    |> Enum.sort_by(& &1.confidence, :desc)
  end

  @doc """
  Predict when a metric will reach an exhaustion threshold.

  Useful for resource metrics like disk usage, memory usage.

  ## Parameters

  - `metric_name` - Name of the metric to analyze
  - `threshold` - Value at which exhaustion occurs (e.g., 100 for percentage)

  ## Returns

  - `{:ok, forecast}` - Forecast with predicted exhaustion time
  - `{:error, :insufficient_data}` - Not enough data points
  - `{:error, :not_trending}` - Metric is stable or decreasing
  """
  @spec predict_exhaustion(String.t(), number()) ::
          {:ok, forecast()} | {:error, :insufficient_data | :not_trending}
  def predict_exhaustion(metric_name, threshold) do
    metrics = Store.get_fresh(metric_name)

    cond do
      length(metrics) < 3 ->
        {:error, :insufficient_data}

      true ->
        sorted = Enum.sort_by(metrics, & &1.timestamp, DateTime)
        {slope, _intercept} = linear_regression(sorted)

        cond do
          slope <= 0 ->
            {:error, :not_trending}

          true ->
            current = List.last(sorted).value
            current_time = List.last(sorted).timestamp

            # Solve for time when value = threshold
            # threshold = slope * t + intercept
            # t = (threshold - intercept) / slope
            time_to_threshold = (threshold - current) / slope
            seconds_to_exhaustion = round(time_to_threshold * 3600)

            if seconds_to_exhaustion > 0 do
              predicted_at = DateTime.add(current_time, seconds_to_exhaustion, :second)
              days = div(seconds_to_exhaustion, 86400)

              {:ok,
               %{
                 metric_name: metric_name,
                 forecast_type: :exhaustion,
                 current_value: current,
                 predicted_value: threshold,
                 prediction_at: predicted_at,
                 confidence: calculate_confidence(sorted, slope),
                 message: format_exhaustion_message(metric_name, days, current, threshold),
                 data_points: length(sorted),
                 generated_at: DateTime.utc_now()
               }}
            else
              {:error, :not_trending}
            end
        end
    end
  end

  @doc """
  Predict when a metric will breach a warning threshold.
  """
  @spec predict_threshold_breach(String.t(), number()) ::
          {:ok, forecast()} | {:error, :insufficient_data | :not_trending | :already_breached}
  def predict_threshold_breach(metric_name, threshold) do
    metrics = Store.get_fresh(metric_name)

    cond do
      length(metrics) < 3 ->
        {:error, :insufficient_data}

      true ->
        sorted = Enum.sort_by(metrics, & &1.timestamp, DateTime)
        current = List.last(sorted).value

        if current >= threshold do
          {:error, :already_breached}
        else
          {slope, _intercept} = linear_regression(sorted)

          if slope <= 0 do
            {:error, :not_trending}
          else
            time_to_threshold = (threshold - current) / slope
            seconds_to_breach = round(time_to_threshold * 3600)
            predicted_at = DateTime.add(DateTime.utc_now(), seconds_to_breach, :second)
            hours = div(seconds_to_breach, 3600)

            {:ok,
             %{
               metric_name: metric_name,
               forecast_type: :threshold,
               current_value: current,
               predicted_value: threshold,
               prediction_at: predicted_at,
               confidence: calculate_confidence(sorted, slope),
               message: "#{metric_name} will breach #{threshold} in approximately #{hours} hours",
               data_points: length(sorted),
               generated_at: DateTime.utc_now()
             }}
          end
        end
    end
  end

  @doc """
  Analyze the trend for a metric.

  Returns trend direction and rate of change.
  """
  @spec analyze_trend(String.t()) ::
          {:ok, map()} | {:error, :insufficient_data}
  def analyze_trend(metric_name) do
    metrics = Store.get_fresh(metric_name)

    if length(metrics) < 3 do
      {:error, :insufficient_data}
    else
      sorted = Enum.sort_by(metrics, & &1.timestamp, DateTime)
      {slope, _intercept} = linear_regression(sorted)

      direction =
        cond do
          slope > 0.01 -> :increasing
          slope < -0.01 -> :decreasing
          true -> :stable
        end

      {:ok,
       %{
         metric_name: metric_name,
         direction: direction,
         rate_per_hour: slope,
         current_value: List.last(sorted).value,
         data_points: length(sorted),
         analyzed_at: DateTime.utc_now()
       }}
    end
  end

  # Private functions

  defp generate_forecasts_for_metric({name, metrics}) do
    sorted = Enum.sort_by(metrics, & &1.timestamp, DateTime)
    {slope, _intercept} = linear_regression(sorted)

    forecasts = []

    # Check for usage metrics approaching 100%
    forecasts =
      if is_usage_metric?(name) and slope > 0 do
        case predict_exhaustion(name, 100) do
          {:ok, forecast} -> [forecast | forecasts]
          _ -> forecasts
        end
      else
        forecasts
      end

    # Check for warning thresholds
    forecasts =
      cond do
        is_usage_metric?(name) and slope > 0 ->
          case predict_threshold_breach(name, 85) do
            {:ok, forecast} -> [forecast | forecasts]
            _ -> forecasts
          end

        true ->
          forecasts
      end

    # Add general trend forecast
    forecasts =
      if abs(slope) > 0.01 do
        current = List.last(sorted).value
        predicted_24h = current + slope * 24

        [
          %{
            metric_name: name,
            forecast_type: :trend,
            current_value: current,
            predicted_value: predicted_24h,
            prediction_at: DateTime.add(DateTime.utc_now(), 86400, :second),
            confidence: calculate_confidence(sorted, slope),
            message: format_trend_message(name, slope, current, predicted_24h),
            data_points: length(sorted),
            generated_at: DateTime.utc_now()
          }
          | forecasts
        ]
      else
        forecasts
      end

    forecasts
  end

  # Simple linear regression: y = mx + b
  # Returns {slope, intercept}
  defp linear_regression(metrics) do
    n = length(metrics)

    # Convert timestamps to hours from first data point
    first_time = hd(metrics).timestamp

    points =
      Enum.map(metrics, fn m ->
        hours = DateTime.diff(m.timestamp, first_time, :second) / 3600.0
        {hours, m.value}
      end)

    sum_x = Enum.reduce(points, 0, fn {x, _}, acc -> acc + x end)
    sum_y = Enum.reduce(points, 0, fn {_, y}, acc -> acc + y end)
    sum_xy = Enum.reduce(points, 0, fn {x, y}, acc -> acc + x * y end)
    sum_x2 = Enum.reduce(points, 0, fn {x, _}, acc -> acc + x * x end)

    # Avoid division by zero
    denominator = n * sum_x2 - sum_x * sum_x

    if abs(denominator) < 0.0001 do
      {0.0, sum_y / n}
    else
      slope = (n * sum_xy - sum_x * sum_y) / denominator
      intercept = (sum_y - slope * sum_x) / n
      {slope, intercept}
    end
  end

  defp calculate_confidence(metrics, slope) do
    n = length(metrics)

    # More data points = higher confidence
    data_factor = min(0.4, n * 0.05)

    # Stronger trend = higher confidence
    trend_factor = min(0.4, abs(slope) * 0.1)

    # Base confidence
    base = 0.2

    min(0.95, base + data_factor + trend_factor)
  end

  defp is_usage_metric?(name) do
    String.contains?(name, ["usage", "percent", "used"]) or
      String.ends_with?(name, ["_pct", "_percent"])
  end

  defp format_exhaustion_message(name, days, current, threshold) do
    current_f = current / 1
    rounded = Float.round(current_f * 1.0, 1)

    cond do
      days == 0 ->
        "#{name} at #{rounded}% - will reach #{threshold}% within 24 hours"

      days == 1 ->
        "#{name} at #{rounded}% - will reach #{threshold}% in approximately 1 day"

      days < 7 ->
        "#{name} at #{rounded}% - will reach #{threshold}% in approximately #{days} days"

      days < 30 ->
        weeks = div(days, 7)
        "#{name} at #{rounded}% - will reach #{threshold}% in approximately #{weeks} week(s)"

      true ->
        "#{name} at #{rounded}% - will reach #{threshold}% in approximately #{div(days, 30)} month(s)"
    end
  end

  defp format_trend_message(name, slope, current, predicted) do
    direction = if slope > 0, do: "increasing", else: "decreasing"
    rate = abs(slope) * 1.0

    "#{name} is #{direction} at #{Float.round(rate, 2)}/hour. " <>
      "Current: #{Float.round(current * 1.0, 1)}, predicted in 24h: #{Float.round(predicted * 1.0, 1)}"
  end
end
