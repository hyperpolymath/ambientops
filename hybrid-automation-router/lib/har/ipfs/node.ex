# SPDX-License-Identifier: MPL-2.0
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

  # --- IPFS Daemon HTTP API Integration ---
  #
  # Uses Erlang's built-in :httpc client (from :inets) to avoid adding
  # external HTTP dependencies. The IPFS HTTP API uses POST for all
  # endpoints and multipart/form-data for file uploads.

  @doc false
  @spec store_to_daemon(binary(), String.t()) :: {:ok, String.t()} | {:error, term()}
  defp store_to_daemon(content, endpoint) do
    ensure_inets_started()

    # IPFS /api/v0/add expects multipart/form-data with the file content.
    # Build a minimal multipart body with a single "file" part.
    boundary = "----ElixirIPFS#{System.unique_integer([:positive])}"

    body =
      "--#{boundary}\r\n" <>
        "Content-Disposition: form-data; name=\"file\"; filename=\"config\"\r\n" <>
        "Content-Type: application/octet-stream\r\n" <>
        "\r\n" <>
        content <>
        "\r\n" <>
        "--#{boundary}--\r\n"

    url = String.to_charlist("#{endpoint}/api/v0/add")
    content_type = String.to_charlist("multipart/form-data; boundary=#{boundary}")

    request = {url, [], content_type, body}

    case :httpc.request(:post, request, [{:timeout, 10_000}], []) do
      {:ok, {{_http_ver, 200, _reason}, _headers, response_body}} ->
        # IPFS returns JSON: {"Name":"config","Hash":"Qm...","Size":"..."}
        parse_add_response(to_string(response_body))

      {:ok, {{_http_ver, status, _reason}, _headers, response_body}} ->
        Logger.warning(
          "IPFS store failed (HTTP #{status}): #{String.slice(to_string(response_body), 0..200)}"
        )

        {:error, {:ipfs_http_error, status}}

      {:error, reason} ->
        Logger.debug("IPFS store connection failed: #{inspect(reason)}")
        {:error, {:connection_failed, reason}}
    end
  end

  @doc false
  @spec retrieve_from_daemon(String.t(), String.t()) :: {:ok, binary()} | {:error, term()}
  defp retrieve_from_daemon(cid, endpoint) do
    ensure_inets_started()

    # IPFS /api/v0/cat takes the CID as a query parameter "arg".
    url = String.to_charlist("#{endpoint}/api/v0/cat?arg=#{cid}")

    request = {url, [], ~c"application/octet-stream", []}

    case :httpc.request(:post, request, [{:timeout, 30_000}], []) do
      {:ok, {{_http_ver, 200, _reason}, _headers, response_body}} ->
        {:ok, to_string(response_body)}

      {:ok, {{_http_ver, status, _reason}, _headers, response_body}} ->
        Logger.warning(
          "IPFS retrieve failed (HTTP #{status}): #{String.slice(to_string(response_body), 0..200)}"
        )

        {:error, {:ipfs_http_error, status}}

      {:error, reason} ->
        Logger.debug("IPFS retrieve connection failed: #{inspect(reason)}")
        {:error, {:connection_failed, reason}}
    end
  end

  @doc false
  @spec pin_on_daemon(String.t(), String.t()) :: :ok | {:error, term()}
  defp pin_on_daemon(cid, endpoint) do
    ensure_inets_started()

    # IPFS /api/v0/pin/add takes the CID as a query parameter "arg".
    url = String.to_charlist("#{endpoint}/api/v0/pin/add?arg=#{cid}")

    request = {url, [], ~c"application/octet-stream", []}

    case :httpc.request(:post, request, [{:timeout, 30_000}], []) do
      {:ok, {{_http_ver, 200, _reason}, _headers, _response_body}} ->
        :ok

      {:ok, {{_http_ver, status, _reason}, _headers, response_body}} ->
        Logger.warning(
          "IPFS pin failed (HTTP #{status}): #{String.slice(to_string(response_body), 0..200)}"
        )

        {:error, {:ipfs_http_error, status}}

      {:error, reason} ->
        Logger.debug("IPFS pin connection failed: #{inspect(reason)}")
        {:error, {:connection_failed, reason}}
    end
  end

  # Ensures the :inets and :ssl applications are started, which are
  # required by :httpc. Safe to call multiple times (idempotent).
  @spec ensure_inets_started() :: :ok
  defp ensure_inets_started do
    :inets.start()
    :ssl.start()
    :ok
  end

  # Parses the JSON response from IPFS /api/v0/add.
  # Extracts the "Hash" field which is the CID of the stored content.
  # Uses a simple regex to avoid requiring a JSON library dependency.
  @spec parse_add_response(String.t()) :: {:ok, String.t()} | {:error, term()}
  defp parse_add_response(body) do
    case Regex.run(~r/"Hash"\s*:\s*"([^"]+)"/, body) do
      [_, cid] ->
        {:ok, cid}

      nil ->
        Logger.warning("IPFS add response missing Hash field: #{String.slice(body, 0..200)}")
        {:error, :invalid_response}
    end
  end
end
