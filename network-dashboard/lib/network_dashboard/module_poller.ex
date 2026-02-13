# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule NetworkDashboard.ModulePoller do
  @moduledoc """
  Polls the FlatRacoon orchestrator /api/modules endpoint for module status.
  Broadcasts updates to connected LiveView clients.
  """
  use GenServer

  require Logger

  def start_link(opts) do
    interval = Keyword.get(opts, :interval, :timer.seconds(10))
    GenServer.start_link(__MODULE__, %{interval: interval}, name: __MODULE__)
  end

  def get_modules do
    GenServer.call(__MODULE__, :get_modules)
  end

  @impl true
  def init(%{interval: interval}) do
    schedule_poll(interval)
    {:ok, %{modules: [], interval: interval}}
  end

  @impl true
  def handle_call(:get_modules, _from, state) do
    {:reply, state.modules, state}
  end

  @impl true
  def handle_info(:poll, state) do
    modules = fetch_modules()
    Phoenix.PubSub.broadcast(NetworkDashboard.PubSub, "modules", {:modules_updated, modules})
    schedule_poll(state.interval)
    {:noreply, %{state | modules: modules}}
  end

  defp fetch_modules do
    orchestrator_url = System.get_env("ORCHESTRATOR_URL", "http://localhost:4000")

    case Req.get("#{orchestrator_url}/api/modules") do
      {:ok, %{status: 200, body: body}} when is_list(body) ->
        body

      {:ok, %{status: status}} ->
        Logger.warning("Orchestrator returned status #{status}")
        []

      {:error, reason} ->
        Logger.warning("Failed to reach orchestrator: #{inspect(reason)}")
        []
    end
  end

  defp schedule_poll(interval) do
    Process.send_after(self(), :poll, interval)
  end
end
