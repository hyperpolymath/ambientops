# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule HARWeb.RouterTest do
  @moduledoc """
  Tests for the HARWeb.Router module.

  Verifies that all routes are properly defined, pipeline assignments are
  correct, and route paths map to the expected controllers and LiveViews.
  These tests inspect the compiled router metadata rather than making HTTP
  requests, so they can run async.
  """

  use ExUnit.Case, async: true

  alias HARWeb.Router

  # ------------------------------------------------------------------
  # Helper: extract all routes from the compiled router
  # ------------------------------------------------------------------

  @routes Router.__routes__()

  defp find_route(method, path) do
    Enum.find(@routes, fn route ->
      route.verb == method and route.path == path
    end)
  end

  # ------------------------------------------------------------------
  # Browser pipeline routes (LiveViews)
  # ------------------------------------------------------------------

  describe "browser pipeline - LiveView routes" do
    test "root path / routes to DashboardLive" do
      route = find_route(:get, "/")
      assert route, "expected GET / route to exist"
      assert route.plug == Phoenix.LiveView.Plug

      {module, action, _opts, _extra} = route.metadata.phoenix_live_view
      assert module == HARWeb.DashboardLive
      assert action == :index
    end

    test "/transform routes to TransformLive" do
      route = find_route(:get, "/transform")
      assert route, "expected GET /transform route to exist"
      assert route.plug == Phoenix.LiveView.Plug

      {module, action, _opts, _extra} = route.metadata.phoenix_live_view
      assert module == HARWeb.TransformLive
      assert action == :index
    end

    test "/graph/:id routes to GraphLive" do
      route = find_route(:get, "/graph/:id")
      assert route, "expected GET /graph/:id route to exist"
      assert route.plug == Phoenix.LiveView.Plug

      {module, action, _opts, _extra} = route.metadata.phoenix_live_view
      assert module == HARWeb.GraphLive
      assert action == :show
    end
  end

  # ------------------------------------------------------------------
  # API pipeline routes (TransformController)
  # ------------------------------------------------------------------

  describe "API pipeline routes" do
    test "POST /api/transform routes to TransformController :transform" do
      route = find_route(:post, "/api/transform")
      assert route, "expected POST /api/transform route to exist"
      assert route.plug == HARWeb.TransformController
      assert route.plug_opts == :transform
    end

    test "POST /api/parse routes to TransformController :parse" do
      route = find_route(:post, "/api/parse")
      assert route, "expected POST /api/parse route to exist"
      assert route.plug == HARWeb.TransformController
      assert route.plug_opts == :parse
    end

    test "GET /api/formats routes to TransformController :formats" do
      route = find_route(:get, "/api/formats")
      assert route, "expected GET /api/formats route to exist"
      assert route.plug == HARWeb.TransformController
      assert route.plug_opts == :formats
    end
  end

  # ------------------------------------------------------------------
  # Pipeline verification via plug type inspection
  # ------------------------------------------------------------------

  describe "pipelines" do
    test "browser routes use Phoenix.LiveView.Plug (LiveView)" do
      route = find_route(:get, "/")
      assert route.plug == Phoenix.LiveView.Plug
    end

    test "API routes use the TransformController directly" do
      route = find_route(:get, "/api/formats")
      assert route.plug == HARWeb.TransformController
    end

    test "browser and API routes use different plug modules" do
      browser_route = find_route(:get, "/")
      api_route = find_route(:get, "/api/formats")
      assert browser_route.plug != api_route.plug
    end
  end

  # ------------------------------------------------------------------
  # Route completeness
  # ------------------------------------------------------------------

  describe "route completeness" do
    test "all expected paths are defined" do
      expected_paths = [
        "/",
        "/transform",
        "/graph/:id",
        "/api/transform",
        "/api/parse",
        "/api/formats"
      ]

      defined_paths = Enum.map(@routes, & &1.path)

      for path <- expected_paths do
        assert path in defined_paths,
               "expected route #{path} to be defined, got: #{inspect(defined_paths)}"
      end
    end

    test "API scope has exactly 3 routes" do
      api_routes = Enum.filter(@routes, fn r -> String.starts_with?(r.path, "/api") end)
      assert length(api_routes) == 3
    end

    test "browser scope has exactly 3 LiveView routes" do
      browser_routes =
        Enum.filter(@routes, fn r ->
          r.plug == Phoenix.LiveView.Plug
        end)

      assert length(browser_routes) == 3
    end
  end

  # ------------------------------------------------------------------
  # Route HTTP method verification
  # ------------------------------------------------------------------

  describe "HTTP methods" do
    test "transform API is POST" do
      route = find_route(:post, "/api/transform")
      assert route, "POST /api/transform should exist"
    end

    test "parse API is POST" do
      route = find_route(:post, "/api/parse")
      assert route, "POST /api/parse should exist"
    end

    test "formats API is GET" do
      route = find_route(:get, "/api/formats")
      assert route, "GET /api/formats should exist"
    end

    test "no DELETE routes exist" do
      delete_routes = Enum.filter(@routes, fn r -> r.verb == :delete end)
      assert delete_routes == []
    end

    test "no PUT routes exist" do
      put_routes = Enum.filter(@routes, fn r -> r.verb == :put end)
      assert put_routes == []
    end
  end
end
