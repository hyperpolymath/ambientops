# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule HARWeb.DashboardLiveTest do
  @moduledoc """
  Tests for the HARWeb.DashboardLive LiveView.

  Verifies that the dashboard mounts correctly, renders the expected
  content (hero section, stats, supported formats list, and how-it-works
  section), and assigns correct values.
  """

  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint HARWeb.Endpoint

  describe "mount and render" do
    test "connects and renders the dashboard page" do
      {:ok, _view, html} = live(build_conn(), "/")

      # The hero section should contain the tagline
      assert html =~ "Think BGP for Infrastructure Automation"
      assert html =~ "Start Transforming"
    end

    test "page title is set to Dashboard" do
      {:ok, view, _html} = live(build_conn(), "/")

      assert page_title(view) =~ "Dashboard"
    end

    test "renders all 9 supported formats" do
      {:ok, _view, html} = live(build_conn(), "/")

      for name <- ~w(Ansible Salt Terraform Puppet Chef Kubernetes CloudFormation Pulumi) do
        assert html =~ name, "expected format '#{name}' to appear in dashboard HTML"
      end

      assert html =~ "Docker Compose"
    end

    test "renders stats section with numerical values" do
      {:ok, _view, html} = live(build_conn(), "/")

      # The dashboard shows 4 stat cards: formats, operations, routes, transformations
      assert html =~ "Supported Formats"
      assert html =~ "Operation Types"
      assert html =~ "Routing Rules"
      assert html =~ "Possible Transforms"
    end

    test "stats formats count matches supported formats list" do
      {:ok, _view, html} = live(build_conn(), "/")

      # 9 supported formats
      assert html =~ ">9<"
    end

    test "stats transformations count is n*(n-1) for n formats" do
      {:ok, _view, html} = live(build_conn(), "/")

      # 9 formats * 8 targets = 72 possible transformations
      assert html =~ ">72<"
    end

    test "renders how-it-works section with 3 steps" do
      {:ok, _view, html} = live(build_conn(), "/")

      assert html =~ "How It Works"
      assert html =~ "Parse"
      assert html =~ "Semantic Graph"
      assert html =~ "Transform"
    end

    test "contains link to /transform page" do
      {:ok, _view, html} = live(build_conn(), "/")

      assert html =~ ~s(href="/transform")
    end
  end
end
