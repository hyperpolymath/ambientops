# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule SystemObservatory.VeriSimDB do
  @moduledoc """
  VeriSimDB HTTP client for durable metric persistence.

  Wraps the VeriSimDB hexad API so the metrics store can dual-write:
  the in-memory ring buffer stays fast for recent reads while VeriSimDB
  provides a crash-safe historical record that survives restarts.

  ## Configuration

  The base URL is read from the `VERISIMDB_URL` environment variable at
  runtime, falling back to `http://localhost:8080`.

  ```
  VERISIMDB_URL=http://verisimdb.internal:8080
  ```

  ## VeriSimDB API surface used

  | Method | Path                     | Purpose                          |
  |--------|--------------------------|----------------------------------|
  | POST   | /api/v1/hexads           | Persist a single metric hexad    |
  | GET    | /api/v1/hexads/{id}      | Retrieve a hexad by ID           |
  | GET    | /api/v1/query            | Run a VQL query                  |
  | GET    | /health                  | Liveness check                   |

  ## Advisory data contract

  All data written via this module is marked `advisory: true` in the hexad
  payload — consistent with the CRIT-003 requirement that JuSys data is
  never authoritative.
  """

  require Logger

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Persist a metric to VeriSimDB as a hexad document.

  The metric map is the same shape produced by `SystemObservatory.Metrics.Store`.
  On success returns `{:ok, id}` where `id` is the VeriSimDB-assigned hexad ID.
  On failure returns `{:error, reason}` — callers should treat this as a
  non-fatal background write failure; the ring buffer is unaffected.
  """
  @spec store_metric(map()) :: {:ok, String.t()} | {:error, term()}
  def store_metric(metric) do
    payload = metric_to_hexad(metric)

    case post("/api/v1/hexads", payload) do
      {:ok, %{"id" => id}} ->
        {:ok, id}

      {:ok, body} ->
        # VeriSimDB responded 2xx but without an id field — treat as ok
        Logger.debug("[VeriSimDB] store_metric: unexpected body shape: #{inspect(body)}")
        {:ok, nil}

      {:error, reason} = err ->
        Logger.warning("[VeriSimDB] store_metric failed: #{inspect(reason)}")
        err
    end
  end

  @doc """
  Retrieve a single hexad by its VeriSimDB ID.

  Returns `{:ok, hexad}` on success, `{:error, :not_found}` for 404, or
  `{:error, reason}` for other failures.
  """
  @spec get_hexad(String.t()) :: {:ok, map()} | {:error, :not_found} | {:error, term()}
  def get_hexad(id) when is_binary(id) do
    get("/api/v1/hexads/#{URI.encode(id)}")
  end

  @doc """
  Run a VQL query against VeriSimDB.

  `vql` is a raw VQL string.  Optional `opts` map is forwarded as query
  parameters (e.g. `%{"limit" => 100}`).

  Returns `{:ok, results}` where `results` is a list of hexads, or
  `{:error, reason}`.

  ## Example

      VeriSimDB.query("metric.name = \"cpu.usage\"", %{"limit" => 50})
  """
  @spec query(String.t(), map()) :: {:ok, list(map())} | {:error, term()}
  def query(vql, opts \\ %{}) when is_binary(vql) do
    params = Map.merge(%{"q" => vql}, opts)

    case get("/api/v1/query", params) do
      {:ok, %{"results" => results}} when is_list(results) ->
        {:ok, results}

      {:ok, results} when is_list(results) ->
        # Some VeriSimDB versions return the list directly
        {:ok, results}

      {:ok, body} ->
        Logger.debug("[VeriSimDB] query: unexpected shape: #{inspect(body)}")
        {:ok, []}

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Query historical metrics by name.

  Convenience wrapper around `query/2` that filters by metric name.
  Returns up to `limit` results ordered by timestamp descending.
  """
  @spec query_by_name(String.t(), non_neg_integer()) ::
          {:ok, list(map())} | {:error, term()}
  def query_by_name(name, limit \\ 1000) when is_binary(name) and is_integer(limit) do
    vql = ~s(payload.name = "#{String.replace(name, ~s("), ~s(\\"))}")
    query(vql, %{"limit" => limit})
  end

  @doc """
  Perform a health check against VeriSimDB.

  Returns `:ok` if VeriSimDB is reachable and healthy, `{:error, reason}`
  otherwise.
  """
  @spec health_check() :: :ok | {:error, term()}
  def health_check do
    case get("/health") do
      {:ok, _} -> :ok
      {:error, _} = err -> err
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Build the hexad payload from an observatory metric map.
  # VeriSimDB hexads carry an opaque `payload` field — we embed the full
  # metric there plus top-level advisory and provenance fields.
  @spec metric_to_hexad(map()) :: map()
  defp metric_to_hexad(metric) do
    %{
      # Top-level hexad metadata
      "type" => "observatory.metric",
      "source" => Map.get(metric, :source, "unknown"),
      "advisory" => Map.get(metric, :advisory, true),
      # Timestamps as ISO 8601 strings
      "recorded_at" => format_datetime(Map.get(metric, :timestamp)),
      "derived_at" => format_datetime(Map.get(metric, :derived_at)),
      # Embed the full metric as the hexad payload so VQL can filter on it
      "payload" => %{
        "name" => metric.name,
        "value" => metric.value,
        "tags" => metric.tags,
        "ttl_seconds" => Map.get(metric, :ttl_seconds, 3600)
      }
    }
  end

  # Format a DateTime or nil to ISO 8601 string.
  @spec format_datetime(DateTime.t() | nil) :: String.t() | nil
  defp format_datetime(nil), do: nil
  defp format_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_datetime(other), do: inspect(other)

  # Return the configured VeriSimDB base URL.
  # Reads VERISIMDB_URL at call time so runtime changes are picked up.
  @spec base_url() :: String.t()
  defp base_url do
    System.get_env("VERISIMDB_URL", "http://localhost:8080")
  end

  # Perform an HTTP GET.  `params` are encoded as query string parameters.
  @spec get(String.t(), map()) :: {:ok, term()} | {:error, term()}
  defp get(path, params \\ %{}) do
    url = base_url() <> path

    req_opts =
      [url: url, decode_body: true]
      |> then(fn opts ->
        if map_size(params) > 0, do: Keyword.put(opts, :params, params), else: opts
      end)

    case Req.get(req_opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: 404}} ->
        {:error, :not_found}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, exception} ->
        {:error, {:request_failed, Exception.message(exception)}}
    end
  end

  # Perform an HTTP POST with a JSON body.
  @spec post(String.t(), map()) :: {:ok, term()} | {:error, term()}
  defp post(path, body) when is_map(body) do
    url = base_url() <> path

    case Req.post(url: url, json: body, decode_body: true) do
      {:ok, %Req.Response{status: status, body: response_body}} when status in 200..299 ->
        {:ok, response_body}

      {:ok, %Req.Response{status: status, body: response_body}} ->
        {:error, {:http_error, status, response_body}}

      {:error, exception} ->
        {:error, {:request_failed, Exception.message(exception)}}
    end
  end
end
