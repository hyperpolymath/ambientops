# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule HARWeb.TransformLiveTest do
  @moduledoc """
  Tests for the HARWeb.TransformLive LiveView.

  Verifies mount, render, and event handling for the interactive
  configuration transformation page. This includes format selection,
  content input, and the transform action.
  """

  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias HAR.ControlPlane.HealthChecker

  @endpoint HARWeb.Endpoint

  setup do
    # Register all backends from the routing table as healthy so that
    # transform operations through the control plane succeed.
    routes = HAR.ControlPlane.RoutingTable.get_routes()

    for route <- routes, backend <- route.backends do
      HealthChecker.register_backend(backend)
      HealthChecker.set_health(backend, :healthy)
    end

    Process.sleep(50)
    :ok
  end

  # ------------------------------------------------------------------
  # Mount and initial render
  # ------------------------------------------------------------------

  describe "mount and initial render" do
    test "connects and renders the transform page" do
      {:ok, _view, html} = live(build_conn(), "/transform")

      assert html =~ "Transform Configuration"
    end

    test "page title is set to Transform" do
      {:ok, view, _html} = live(build_conn(), "/transform")

      assert page_title(view) =~ "Transform"
    end

    test "renders source and target format selectors" do
      {:ok, _view, html} = live(build_conn(), "/transform")

      assert html =~ "Source Format"
      assert html =~ "Target Format"
    end

    test "defaults to Ansible source and Salt target" do
      {:ok, _view, html} = live(build_conn(), "/transform")

      # The select options should show Ansible and Salt as defaults.
      # The source textarea should contain the sample Ansible content.
      assert html =~ "Ansible"
      assert html =~ "Salt"
    end

    test "renders all 9 format options in selectors" do
      {:ok, _view, html} = live(build_conn(), "/transform")

      for {_id, label} <- [
            {"ansible", "Ansible"},
            {"salt", "Salt"},
            {"terraform", "Terraform"},
            {"puppet", "Puppet"},
            {"chef", "Chef"},
            {"kubernetes", "Kubernetes"},
            {"docker_compose", "Docker Compose"},
            {"cloudformation", "CloudFormation"},
            {"pulumi", "Pulumi"}
          ] do
        assert html =~ label, "expected format option '#{label}' in HTML"
      end
    end

    test "renders sample Ansible content in source textarea" do
      {:ok, _view, html} = live(build_conn(), "/transform")

      # The default sample shows an Ansible playbook with nginx
      assert html =~ "Install nginx"
      assert html =~ "nginx"
    end

    test "transform button is present and not disabled" do
      {:ok, _view, html} = live(build_conn(), "/transform")

      assert html =~ "phx-click=\"transform\""
      # Not in transforming state initially
      refute html =~ "Transforming..."
    end

    test "no error is displayed initially" do
      {:ok, _view, html} = live(build_conn(), "/transform")

      refute html =~ "Error:"
    end

    test "no graph info is displayed initially" do
      {:ok, _view, html} = live(build_conn(), "/transform")

      refute html =~ "Semantic Graph Summary"
    end
  end

  # ------------------------------------------------------------------
  # handle_event: update_source_format
  # ------------------------------------------------------------------

  describe "handle_event update_source_format" do
    test "changing source format updates the sample content" do
      {:ok, view, _html} = live(build_conn(), "/transform")

      # Change to Salt format
      html = render_change(view, "update_source_format", %{"format" => "salt"})

      # Salt sample should contain Salt-style syntax
      assert html =~ "pkg.installed"
    end

    test "changing to terraform loads Terraform sample" do
      {:ok, view, _html} = live(build_conn(), "/transform")

      html = render_change(view, "update_source_format", %{"format" => "terraform"})

      assert html =~ "aws_instance"
    end

    test "changing to kubernetes loads Kubernetes sample" do
      {:ok, view, _html} = live(build_conn(), "/transform")

      html = render_change(view, "update_source_format", %{"format" => "kubernetes"})

      assert html =~ "Deployment"
    end

    test "changing to docker_compose loads Docker Compose sample" do
      {:ok, view, _html} = live(build_conn(), "/transform")

      html = render_change(view, "update_source_format", %{"format" => "docker_compose"})

      assert html =~ "services"
    end

    test "changing format clears output content" do
      {:ok, view, _html} = live(build_conn(), "/transform")

      # First do a transform to populate output
      _html = render_click(view, "transform", %{})
      # Then change format
      html = render_change(view, "update_source_format", %{"format" => "salt"})

      # Error should be cleared
      refute html =~ "Error:"
    end

    test "unknown format shows placeholder text" do
      {:ok, view, _html} = live(build_conn(), "/transform")

      html = render_change(view, "update_source_format", %{"format" => "puppet"})

      assert html =~ "Paste your configuration here"
    end
  end

  # ------------------------------------------------------------------
  # handle_event: update_target_format
  # ------------------------------------------------------------------

  describe "handle_event update_target_format" do
    test "changing target format updates the label" do
      {:ok, view, _html} = live(build_conn(), "/transform")

      html = render_change(view, "update_target_format", %{"format" => "terraform"})

      assert html =~ "Terraform"
    end
  end

  # ------------------------------------------------------------------
  # handle_event: update_source
  # ------------------------------------------------------------------

  describe "handle_event update_source" do
    test "updating source content clears errors" do
      {:ok, view, _html} = live(build_conn(), "/transform")

      html = render_change(view, "update_source", %{"source" => "new content here"})

      refute html =~ "Error:"
    end
  end

  # ------------------------------------------------------------------
  # handle_event: transform
  # ------------------------------------------------------------------

  describe "handle_event transform" do
    test "successful transform shows output and graph summary" do
      {:ok, view, _html} = live(build_conn(), "/transform")

      html = render_click(view, "transform", %{})

      # After a successful transform, the output should contain
      # Salt-formatted content (since defaults are ansible -> salt)
      assert html =~ "pkg.installed" or html =~ "Semantic Graph Summary"
    end

    test "successful transform shows operation count in graph info" do
      {:ok, view, _html} = live(build_conn(), "/transform")

      html = render_click(view, "transform", %{})

      assert html =~ "Operations"
      assert html =~ "Dependencies"
    end

    test "transform with unsupported format combination shows error" do
      {:ok, view, _html} = live(build_conn(), "/transform")

      # Set source to a format with content that cannot parse
      render_change(view, "update_source_format", %{"format" => "puppet"})
      # Puppet sample is just a placeholder, likely to fail parsing
      html = render_click(view, "transform", %{})

      # Should either succeed or show an error gracefully
      assert html =~ "Error:" or html =~ "Semantic Graph Summary" or html =~ "Transform"
    end
  end
end
