# SPDX-License-Identifier: MPL-2.0

defmodule ServiceAutopsy.ReportStore do
  @moduledoc """
  In-memory store for completed autopsy reports.

  Maintains a bounded ring buffer of recent autopsy reports.
  Reports are evidence-envelope conformant maps.

  ## CRITICAL: Advisory Data Only (CRIT-003 compliance)

  Autopsy reports are ephemeral observational records. They are NOT
  authoritative audit trails. For durable records, forward envelopes
  to the Operating Theatre receipt system.

  ## Author

  Jonathan D.A. Jewell
  """

  use GenServer

  @max_reports 100

  # --- Client API ---

  @doc """
  Start the report store.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Store an autopsy report.
  """
  @spec store(map()) :: :ok
  def store(report) do
    GenServer.cast(__MODULE__, {:store, report})
  end

  @doc """
  Get the N most recent reports.
  """
  @spec recent(non_neg_integer()) :: [map()]
  def recent(count \\ 10) do
    GenServer.call(__MODULE__, {:recent, count})
  end

  @doc """
  Get all stored reports.
  """
  @spec all() :: [map()]
  def all do
    GenServer.call(__MODULE__, :all)
  end

  @doc """
  Get a report by envelope_id.
  """
  @spec get(String.t()) :: map() | nil
  def get(envelope_id) do
    GenServer.call(__MODULE__, {:get, envelope_id})
  end

  @doc """
  Get reports for a specific unit name.
  """
  @spec for_unit(String.t()) :: [map()]
  def for_unit(unit_name) do
    GenServer.call(__MODULE__, {:for_unit, unit_name})
  end

  @doc """
  Clear all stored reports.
  """
  @spec clear() :: :ok
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  # --- Server Callbacks ---

  @impl true
  def init(_opts) do
    {:ok, %{reports: []}}
  end

  @impl true
  def handle_cast({:store, report}, state) do
    reports = [report | state.reports] |> Enum.take(@max_reports)
    {:noreply, %{state | reports: reports}}
  end

  @impl true
  def handle_call({:recent, count}, _from, state) do
    {:reply, Enum.take(state.reports, count), state}
  end

  @impl true
  def handle_call(:all, _from, state) do
    {:reply, state.reports, state}
  end

  @impl true
  def handle_call({:get, envelope_id}, _from, state) do
    report = Enum.find(state.reports, fn r -> r["envelope_id"] == envelope_id end)
    {:reply, report, state}
  end

  @impl true
  def handle_call({:for_unit, unit_name}, _from, state) do
    reports = Enum.filter(state.reports, fn r ->
      get_in(r, ["subject", "name"]) == unit_name
    end)
    {:reply, reports, state}
  end

  @impl true
  def handle_call(:clear, _from, state) do
    {:reply, :ok, %{state | reports: []}}
  end
end
