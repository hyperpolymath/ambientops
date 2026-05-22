# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Plug middleware for per-IP token-bucket rate limiting on HAR API endpoints.
#
# Identifies clients by remote IP and delegates to
# HAR.Security.Manager.check_rate_limit/1.  Rejected requests receive
# 429 Too Many Requests with a Retry-After header.

defmodule HAR.Security.RateLimitPlug do
  @moduledoc """
  Plug middleware that enforces per-IP rate limiting using token buckets.

  Delegates to `HAR.Security.Manager.check_rate_limit/1` with the
  client's remote IP as the bucket key.

  ## Usage in a Phoenix pipeline

      pipeline :rate_limited_api do
        plug :accepts, ["json"]
        plug HAR.Security.RateLimitPlug
        plug HAR.Security.ApiKeyPlug
      end

  ## Options

  - `:client_id_fn` - a 1-arity function `(conn -> String.t())` to extract
    the client identifier.  Defaults to the remote IP address.
  """

  @behaviour Plug

  import Plug.Conn
  require Logger

  @impl true
  def init(opts) do
    %{
      client_id_fn: Keyword.get(opts, :client_id_fn, &default_client_id/1)
    }
  end

  @impl true
  def call(conn, %{client_id_fn: client_id_fn}) do
    client_id = client_id_fn.(conn)

    case HAR.Security.Manager.check_rate_limit(client_id) do
      :ok ->
        conn
        |> assign(:rate_limit_client, client_id)

      {:error, :rate_limited, retry_after_ms} ->
        retry_after_s = max(div(retry_after_ms, 1000), 1)

        Logger.warning("Rate limit exceeded for client #{client_id}")

        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_after_s))
        |> put_resp_content_type("application/json")
        |> send_resp(
          429,
          Jason.encode!(%{
            error: "rate_limited",
            message: "Too many requests — retry after #{retry_after_s} seconds",
            retry_after_seconds: retry_after_s
          })
        )
        |> halt()
    end
  end

  # Default client identifier: remote IP address as a string.
  defp default_client_id(conn) do
    conn.remote_ip
    |> :inet.ntoa()
    |> List.to_string()
  end
end
