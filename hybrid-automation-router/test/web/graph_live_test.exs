# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule HARWeb.GraphLiveTest do
  @moduledoc """
  Tests for the HARWeb.GraphLive LiveView.

  Verifies that the graph visualization page mounts correctly with a
  given graph ID parameter and renders the expected placeholder content.
  """

  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint HARWeb.Endpoint

  describe "mount and render" do
    test "connects and renders the graph page with given ID" do
      {:ok, _view, html} = live(build_conn(), "/graph/test-graph-123")

      assert html =~ "Semantic Graph"
      assert html =~ "test-graph-123"
    end

    test "page title is set to Graph View" do
      {:ok, view, _html} = live(build_conn(), "/graph/abc-456")

      assert page_title(view) =~ "Graph View"
    end

    test "renders placeholder message for upcoming visualization" do
      {:ok, _view, html} = live(build_conn(), "/graph/my-graph")

      assert html =~ "Interactive graph visualization coming in v1.1"
    end

    test "contains back link to transform page" do
      {:ok, _view, html} = live(build_conn(), "/graph/some-id")

      assert html =~ ~s(href="/transform")
      assert html =~ "Back to Transform"
    end

    test "renders different graph IDs correctly" do
      for id <- ["uuid-001", "demo-graph", "7f3a9b2c"] do
        {:ok, _view, html} = live(build_conn(), "/graph/#{id}")
        assert html =~ id
      end
    end
  end
end
