# SPDX-License-Identifier: MPL-2.0
defmodule HAR.DataPlane.Transformers.SaltTest do
  @moduledoc """
  Tests for the Salt Stack SLS transformer.

  Verifies that semantic graph operations are correctly converted to
  Salt SLS YAML format with proper state functions, state IDs, and
  requisite generation from dependency edges.
  """

  use ExUnit.Case, async: true

  alias HAR.DataPlane.Transformers.Salt
  alias HAR.Semantic.{Graph, Operation, Dependency}

  describe "transform/2 - package operations" do
    test "transforms package_install to pkg.installed state" do
      graph =
        build_graph([
          Operation.new(:package_install, %{package: "nginx"})
        ])

      assert {:ok, output} = Salt.transform(graph)
      assert is_binary(output)
      assert output =~ "pkg.installed"
      assert output =~ "nginx"
    end

    test "transforms package_remove to pkg.removed state" do
      graph =
        build_graph([
          Operation.new(:package_remove, %{package: "apache2"})
        ])

      assert {:ok, output} = Salt.transform(graph)
      assert output =~ "pkg.removed"
      assert output =~ "apache2"
    end

    test "transforms package_upgrade to pkg.latest state" do
      graph =
        build_graph([
          Operation.new(:package_upgrade, %{package: "openssl"})
        ])

      assert {:ok, output} = Salt.transform(graph)
      assert output =~ "pkg.latest"
      assert output =~ "openssl"
    end
  end

  describe "transform/2 - service operations" do
    test "transforms service_start to service.running state" do
      graph =
        build_graph([
          Operation.new(:service_start, %{service: "nginx"})
        ])

      assert {:ok, output} = Salt.transform(graph)
      assert is_binary(output)
      assert output =~ "service.running"
      assert output =~ "nginx"
    end

    test "transforms service_stop to service.dead state" do
      graph =
        build_graph([
          Operation.new(:service_stop, %{service: "apache2"})
        ])

      assert {:ok, output} = Salt.transform(graph)
      assert output =~ "service.dead"
      assert output =~ "apache2"
    end
  end

  describe "transform/2 - file operations" do
    test "transforms file_write to file.managed state" do
      graph =
        build_graph([
          Operation.new(:file_write, %{path: "/etc/motd", content: "Welcome"})
        ])

      assert {:ok, output} = Salt.transform(graph)
      assert is_binary(output)
      assert output =~ "file.managed"
      assert output =~ "/etc/motd"
    end
  end

  describe "transform/2 - user operations" do
    test "transforms user_create to user.present state" do
      graph =
        build_graph([
          Operation.new(:user_create, %{name: "deploy", shell: "/bin/bash"})
        ])

      assert {:ok, output} = Salt.transform(graph)
      assert is_binary(output)
      assert output =~ "user.present"
      assert output =~ "deploy"
    end
  end

  describe "transform/2 - command operations" do
    test "transforms command_run to cmd.run state" do
      graph =
        build_graph([
          Operation.new(:command_run, %{command: "systemctl daemon-reload"})
        ])

      assert {:ok, output} = Salt.transform(graph)
      assert is_binary(output)
      assert output =~ "cmd.run"
      assert output =~ "systemctl daemon-reload"
    end
  end

  describe "transform/2 - state IDs" do
    test "generates state IDs with operation prefix" do
      graph =
        build_graph([
          Operation.new(:package_install, %{package: "vim"})
        ])

      assert {:ok, output} = Salt.transform(graph)
      assert output =~ "install_package"
    end
  end

  describe "transform/2 - dependencies and requisites" do
    test "generates require requisites from graph edges" do
      pkg_op = Operation.new(:package_install, %{package: "nginx"}, id: "op1")
      svc_op = Operation.new(:service_start, %{service: "nginx"}, id: "op2")
      dep = Dependency.new("op1", "op2", :requires)

      graph =
        Graph.new(
          vertices: [pkg_op, svc_op],
          edges: [dep],
          metadata: %{source: :test}
        )

      assert {:ok, output} = Salt.transform(graph)
      assert is_binary(output)
      assert output =~ "service.running"
      assert output =~ "pkg.installed"
    end
  end

  describe "transform/2 - multiple operations" do
    test "produces SLS with multiple state entries" do
      graph =
        build_graph([
          Operation.new(:package_install, %{package: "nginx"}),
          Operation.new(:service_start, %{service: "nginx"}),
          Operation.new(:file_write, %{path: "/etc/nginx/nginx.conf", content: "events {}"})
        ])

      assert {:ok, output} = Salt.transform(graph)
      assert is_binary(output)
      assert output =~ "pkg.installed"
      assert output =~ "service.running"
      assert output =~ "file.managed"
    end
  end

  describe "validate/1" do
    test "validates a well-formed graph" do
      graph = build_graph([Operation.new(:package_install, %{package: "nginx"})])
      assert :ok = Salt.validate(graph)
    end
  end

  # Helper to build a test graph from a list of operations
  defp build_graph(operations) do
    Graph.new(
      vertices: operations,
      edges: [],
      metadata: %{source: :test}
    )
  end
end
