# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule HAR.IPFS.Node do
  @moduledoc """
  IPFS integration for content-addressed configuration storage.

  Provides immutable versioning and global deduplication of configs.
  When the IPFS daemon is unavailable, content is stored in a local
  ETS cache with mock CID generation as a working fallback.

  ## Configuration

      config :har,
        ipfs_enabled: true,
        ipfs_endpoint: "http://localhost:5001"
  """

  use GenServer
  require Logger

  @ets_table :ipfs_cache
  @pins_table :ipfs_pins

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Store configuration in IPFS (or local cache when daemon unavailable).

  Returns content ID (CID) - cryptographic hash of content.

  ## Examples

      iex> HAR.IPFS.Node.store("nginx.conf contents")
      {:ok, "Qm..."}
  """
  @spec store(binary()) :: {:ok, String.t()} | {:error, term()}
  def store(content) when is_binary(content) do
    GenServer.call(__MODULE__, {:store, content})
  end

  @doc """
  Retrieve configuration from IPFS (or local cache) by CID.

  Checks the local ETS cache first, then attempts the IPFS daemon
  if enabled. Returns `{:error, :ipfs_unavailable}` when neither
  the cache nor daemon can serve the content.

  ## Examples

      iex> {:ok, cid} = HAR.IPFS.Node.store("my config")
      iex> HAR.IPFS.Node.retrieve(cid)
      {:ok, "my config"}
  """
  @spec retrieve(String.t()) :: {:ok, binary()} | {:error, term()}
  def retrieve(cid) when is_binary(cid) do
    GenServer.call(__MODULE__, {:retrieve, cid})
  end

  @doc """
  Pin a CID to prevent garbage collection.

  In local-cache mode, marks the CID as pinned in a separate ETS table.
  Pinned content will not be evicted by any future cache-management logic.

  ## Examples

      iex> {:ok, cid} = HAR.IPFS.Node.store("important config")
      iex> HAR.IPFS.Node.pin(cid)
      :ok
  """
  @spec pin(String.t()) :: :ok | {:error, term()}
  def pin(cid) when is_binary(cid) do
    GenServer.call(__MODULE__, {:pin, cid})
  end

  @doc """
  Return statistics about the IPFS node and local cache.

  ## Examples

      iex> HAR.IPFS.Node.stats()
      %{enabled: false, endpoint: "http://localhost:5001", cached_items: 0, pinned_items: 0}
  """
  @spec stats() :: map()
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    cache_table = ensure_ets_table(@ets_table, [:set, :protected])
    pins_table = ensure_ets_table(@pins_table, [:set, :protected])

    state = %{
      enabled: Application.get_env(:har, :ipfs_enabled, false),
      endpoint: Application.get_env(:har, :ipfs_endpoint, "http://localhost:5001"),
      cache_table: cache_table,
      pins_table: pins_table
    }

    if state.enabled do
      Logger.info("IPFS integration enabled, endpoint: #{state.endpoint}")
    else
      Logger.info("IPFS integration disabled, using local cache")
    end

    {:ok, state}
  end

  @impl true
  def handle_call({:store, content}, _from, state) do
    cid = generate_cid(content)

    if state.enabled do
      case store_to_daemon(content, state.endpoint) do
        {:ok, daemon_cid} ->
          # Cache locally as well for fast retrieval
          :ets.insert(state.cache_table, {daemon_cid, content})
          {:reply, {:ok, daemon_cid}, state}

        {:error, _reason} ->
          # Fallback to local cache with mock CID
          Logger.debug("IPFS daemon unavailable, storing locally with CID: #{cid}")
          :ets.insert(state.cache_table, {cid, content})
          {:reply, {:ok, cid}, state}
      end
    else
      # IPFS disabled - use local cache with mock CID
      :ets.insert(state.cache_table, {cid, content})
      {:reply, {:ok, cid}, state}
    end
  end

  def handle_call({:retrieve, cid}, _from, state) do
    # Always check local cache first
    case :ets.lookup(state.cache_table, cid) do
      [{^cid, content}] ->
        {:reply, {:ok, content}, state}

      [] ->
        if state.enabled do
          case retrieve_from_daemon(cid, state.endpoint) do
            {:ok, content} ->
              # Cache for next time
              :ets.insert(state.cache_table, {cid, content})
              {:reply, {:ok, content}, state}

            {:error, _reason} ->
              {:reply, {:error, :ipfs_unavailable}, state}
          end
        else
          {:reply, {:error, :ipfs_unavailable}, state}
        end
    end
  end

  def handle_call({:pin, cid}, _from, state) do
    # Check that the CID exists in cache or daemon
    case :ets.lookup(state.cache_table, cid) do
      [{^cid, _content}] ->
        :ets.insert(state.pins_table, {cid, DateTime.utc_now()})
        {:reply, :ok, state}

      [] ->
        if state.enabled do
          case pin_on_daemon(cid, state.endpoint) do
            :ok ->
              :ets.insert(state.pins_table, {cid, DateTime.utc_now()})
              {:reply, :ok, state}

            {:error, _reason} ->
              {:reply, {:error, :not_found}, state}
          end
        else
          {:reply, {:error, :not_found}, state}
        end
    end
  end

  def handle_call(:stats, _from, state) do
    stats = %{
      enabled: state.enabled,
      endpoint: state.endpoint,
      cached_items: :ets.info(state.cache_table, :size),
      pinned_items: :ets.info(state.pins_table, :size)
    }

    {:reply, stats, state}
  end

  # Internal Functions

  @doc false
  @spec generate_cid(binary()) :: String.t()
  def generate_cid(content) do
    hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
    "Qm" <> String.slice(hash, 0..44)
  end

  defp ensure_ets_table(name, opts) do
    case :ets.whereis(name) do
      :undefined ->
        :ets.new(name, opts ++ [:named_table])

      _ref ->
        # Table already exists (e.g., from a previous test run). Reuse it.
        name
    end
  end

  # Daemon interaction stubs - these will connect to the real IPFS HTTP API
  # when the daemon is available. For now they return errors to trigger fallback.

  defp store_to_daemon(_content, _endpoint) do
    # TODO: POST to /api/v0/add on the IPFS daemon
    {:error, :daemon_not_connected}
  end

  defp retrieve_from_daemon(_cid, _endpoint) do
    # TODO: POST to /api/v0/cat on the IPFS daemon
    {:error, :daemon_not_connected}
  end

  defp pin_on_daemon(_cid, _endpoint) do
    # TODO: POST to /api/v0/pin/add on the IPFS daemon
    {:error, :daemon_not_connected}
  end
end
