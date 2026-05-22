# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Plug middleware for API key authentication on HAR API endpoints.
#
# Reads the `X-HAR-API-Key` header and validates it against the
# configured allow-list via HAR.Security.Manager.validate_api_key/1.
# Rejects unauthenticated requests with 401 Unauthorized.

defmodule HAR.Security.ApiKeyPlug do
  @moduledoc """
  Plug middleware that enforces API key authentication.

  Extracts the `X-HAR-API-Key` header from incoming requests and
  validates it via `HAR.Security.Manager.validate_api_key/1`.

  ## Usage in a Phoenix pipeline

      pipeline :authenticated_api do
        plug :accepts, ["json"]
        plug HAR.Security.ApiKeyPlug
      end

  ## Options

  - `:header` - the header name to read (default: `"x-har-api-key"`)
  - `:optional` - if `true`, missing keys pass through (default: `false`)
  """

  @behaviour Plug

  import Plug.Conn
  require Logger

  @default_header "x-har-api-key"

  @impl true
  def init(opts) do
    %{
      header: Keyword.get(opts, :header, @default_header),
      optional: Keyword.get(opts, :optional, false)
    }
  end

  @impl true
  def call(conn, %{header: header, optional: optional}) do
    key =
      conn
      |> get_req_header(header)
      |> List.first()

    cond do
      is_nil(key) and optional ->
        conn

      is_nil(key) ->
        Logger.warning("API request rejected — missing #{header} header")

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "missing_api_key", message: "X-HAR-API-Key header is required"}))
        |> halt()

      true ->
        case HAR.Security.Manager.validate_api_key(key) do
          {:ok, :valid} ->
            conn
            |> assign(:authenticated, true)

          {:error, reason} ->
            Logger.warning("API request rejected — invalid API key: #{inspect(reason)}")

            conn
            |> put_resp_content_type("application/json")
            |> send_resp(401, Jason.encode!(%{error: "invalid_api_key", message: "Invalid API key"}))
            |> halt()
        end
    end
  end
end
