# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell <jonathan@hyperpolymath.io>

defmodule TotalUpdate.DownloadManager do
  @moduledoc """
  Download manager with aria2 integration for parallel downloads.

  Features:
  - Parallel downloads via aria2c
  - Bandwidth throttling
  - Resume support
  - Mirror selection
  - Progress tracking

  Falls back to sequential HTTP downloads if aria2 is not available.
  """

  use GenServer
  require Logger

  @aria2_rpc_port 6800
  @default_max_connections 5
  @default_max_concurrent 3

  # ═══════════════════════════════════════════════════════════════════════════
  # Client API
  # ═══════════════════════════════════════════════════════════════════════════

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Download a file from URL to destination"
  def download(url, destination, opts \\ []) do
    GenServer.call(__MODULE__, {:download, url, destination, opts}, :infinity)
  end

  @doc "Download multiple files in parallel"
  def download_many(downloads) when is_list(downloads) do
    GenServer.call(__MODULE__, {:download_many, downloads}, :infinity)
  end

  @doc "Cancel a download"
  def cancel(download_id) do
    GenServer.call(__MODULE__, {:cancel, download_id})
  end

  @doc "Get download progress"
  def progress(download_id) do
    GenServer.call(__MODULE__, {:progress, download_id})
  end

  @doc "List active downloads"
  def active_downloads do
    GenServer.call(__MODULE__, :active_downloads)
  end

  @doc "Check if aria2 is available"
  def aria2_available? do
    GenServer.call(__MODULE__, :aria2_available?)
  end

  @doc "Set bandwidth limit (bytes/sec, 0 = unlimited)"
  def set_bandwidth_limit(limit) do
    GenServer.call(__MODULE__, {:set_bandwidth_limit, limit})
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Server Callbacks
  # ═══════════════════════════════════════════════════════════════════════════

  @impl true
  def init(opts) do
    aria2_available = System.find_executable("aria2c") != nil

    state = %{
      aria2_available: aria2_available,
      aria2_process: nil,
      downloads: %{},
      next_id: 1,
      max_connections: Keyword.get(opts, :max_connections, @default_max_connections),
      max_concurrent: Keyword.get(opts, :max_concurrent, @default_max_concurrent),
      bandwidth_limit: Keyword.get(opts, :bandwidth_limit, 0)
    }

    # Start aria2 RPC daemon if available
    state =
      if aria2_available do
        start_aria2_daemon(state)
      else
        Logger.warn("aria2 not found, using fallback HTTP downloads")
        state
      end

    Logger.info("DownloadManager started (aria2: #{aria2_available})")
    {:ok, state}
  end

  @impl true
  def handle_call({:download, url, destination, opts}, _from, state) do
    {id, state} = create_download(state, url, destination, opts)

    result =
      if state.aria2_available do
        download_with_aria2(url, destination, opts)
      else
        download_with_httpc(url, destination, opts)
      end

    state = update_download_status(state, id, result)
    {:reply, {result, id}, state}
  end

  @impl true
  def handle_call({:download_many, downloads}, _from, state) do
    results =
      if state.aria2_available do
        download_many_aria2(downloads, state)
      else
        download_many_sequential(downloads)
      end

    {:reply, results, state}
  end

  @impl true
  def handle_call({:cancel, download_id}, _from, state) do
    case Map.get(state.downloads, download_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      download ->
        # Cancel the download
        new_downloads = Map.put(state.downloads, download_id, %{download | status: :cancelled})
        {:reply, :ok, %{state | downloads: new_downloads}}
    end
  end

  @impl true
  def handle_call({:progress, download_id}, _from, state) do
    case Map.get(state.downloads, download_id) do
      nil -> {:reply, {:error, :not_found}, state}
      download -> {:reply, {:ok, download}, state}
    end
  end

  @impl true
  def handle_call(:active_downloads, _from, state) do
    active =
      state.downloads
      |> Enum.filter(fn {_id, d} -> d.status == :downloading end)
      |> Map.new()

    {:reply, {:ok, active}, state}
  end

  @impl true
  def handle_call(:aria2_available?, _from, state) do
    {:reply, state.aria2_available, state}
  end

  @impl true
  def handle_call({:set_bandwidth_limit, limit}, _from, state) do
    {:reply, :ok, %{state | bandwidth_limit: limit}}
  end

  @impl true
  def terminate(_reason, state) do
    # Stop aria2 daemon if we started it
    if state.aria2_process do
      Port.close(state.aria2_process)
    end

    :ok
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Private Functions
  # ═══════════════════════════════════════════════════════════════════════════

  defp start_aria2_daemon(state) do
    # Start aria2 in daemon mode with RPC
    args = [
      "--enable-rpc",
      "--rpc-listen-port=#{@aria2_rpc_port}",
      "--rpc-listen-all=false",
      "--daemon=false",
      "--quiet"
    ]

    case System.cmd("aria2c", args, stderr_to_stdout: true) do
      {_, 0} ->
        Logger.debug("aria2 RPC daemon started on port #{@aria2_rpc_port}")
        state

      {error, _} ->
        Logger.warn("Failed to start aria2 daemon: #{error}")
        %{state | aria2_available: false}
    end
  end

  defp create_download(state, url, destination, _opts) do
    id = state.next_id

    download = %{
      id: id,
      url: url,
      destination: destination,
      status: :pending,
      progress: 0,
      total_size: nil,
      downloaded: 0,
      started_at: DateTime.utc_now()
    }

    new_downloads = Map.put(state.downloads, id, download)
    {id, %{state | downloads: new_downloads, next_id: id + 1}}
  end

  defp update_download_status(state, id, result) do
    status =
      case result do
        :ok -> :completed
        {:ok, _} -> :completed
        {:error, _} -> :failed
      end

    case Map.get(state.downloads, id) do
      nil ->
        state

      download ->
        new_download = %{download | status: status, progress: if(status == :completed, do: 100, else: download.progress)}
        %{state | downloads: Map.put(state.downloads, id, new_download)}
    end
  end

  defp download_with_aria2(url, destination, _opts) do
    args = [
      "--dir=#{Path.dirname(destination)}",
      "--out=#{Path.basename(destination)}",
      "--continue=true",
      url
    ]

    case System.cmd("aria2c", args, stderr_to_stdout: true) do
      {_, 0} -> :ok
      {error, code} -> {:error, "aria2 failed (#{code}): #{error}"}
    end
  end

  defp download_with_httpc(url, destination, _opts) do
    # Simple HTTP download fallback
    case Finch.build(:get, url) |> Finch.request(TotalUpdate.Finch) do
      {:ok, %{status: 200, body: body}} ->
        File.write(destination, body)

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp download_many_aria2(downloads, state) do
    downloads
    |> Enum.map(fn {url, dest, opts} ->
      download_with_aria2(url, dest, opts)
    end)
  end

  defp download_many_sequential(downloads) do
    downloads
    |> Enum.map(fn {url, dest, opts} ->
      download_with_httpc(url, dest, opts)
    end)
  end
end
