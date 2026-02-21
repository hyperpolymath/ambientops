# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule SystemObservatory do
  @moduledoc """
  System Observatory - Observability layer for AmbientOps.

  ## Philosophy

  System Observatory **observes and recommends**. It never applies changes.

  - Observes (never acts)
  - Correlates (never executes)
  - Forecasts (never applies)
  - Recommends (never modifies)
  - NEVER source of truth

  ## Core Capabilities

  * **Metrics Store** — time series data from system scans
  * **Dashboard** — visualization of system health
  * **Change Timeline** — correlate anomalies with changes
  * **Forecasting** — predict resource exhaustion
  """

  @version "1.2.0"
  @schema_version "1.0"

  @doc """
  Returns the current version of System Observatory.
  """
  @spec version() :: String.t()
  def version, do: @version

  @doc """
  Returns the schema version for System Observatory data formats.
  """
  @spec schema_version() :: String.t()
  def schema_version, do: @schema_version

  @doc """
  Check if System Observatory is in observation-only mode (always true).

  System Observatory never modifies system state - it only observes.
  """
  @spec observation_only?() :: true
  def observation_only?, do: true
end
