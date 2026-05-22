# SPDX-License-Identifier: MPL-2.0
defmodule HAR.DataPlane.Transformers.AnsibleTest do
  @moduledoc """
  Tests for the Ansible transformer.

  Verifies that semantic graph operations are correctly converted to
  Ansible playbook YAML format with proper module selection, task naming,
  and OS-aware package manager routing.
  """

  use ExUnit.Case, async: true

  alias HAR.DataPlane.Transformers.Ansible
  alias HAR.Semantic.{Graph, Operation}

  describe "transform/2 - package operations" do
    test "transforms package_install to generic package task" do
      graph =
        build_graph([
          Operation.new(:package_install, %{package: "nginx"})
        ])

      assert {:ok, output} = Ansible.transform(graph)
      assert is_binary(output)
      assert output =~ "nginx"
      assert output =~ "Install"
      assert output =~ "package"
    end

    test "transforms package_install with debian OS to apt module" do
      graph =
        build_graph([
          Operation.new(:package_install, %{package: "nginx"}, target: %{os: "debian"})
        ])

      assert {:ok, output} = Ansible.transform(graph, os: "debian")
      assert is_binary(output)
      assert output =~ "apt"
      assert output =~ "nginx"
    end

    test "transforms package_install with fedora OS to dnf module" do
      graph =
        build_graph([
          Operation.new(:package_install, %{package: "httpd"})
        ])

      assert {:ok, output} = Ansible.transform(graph, os: "fedora")
      assert is_binary(output)
      assert output =~ "dnf"
      assert output =~ "httpd"
    end

    test "transforms package_install with centos OS to yum module" do
      graph =
        build_graph([
          Operation.new(:package_install, %{package: "vim"})
        ])

      assert {:ok, output} = Ansible.transform(graph, os: "centos")
      assert is_binary(output)
      assert output =~ "yum"
    end
  end

  describe "transform/2 - service operations" do
    test "transforms service_start to service task with started state" do
      graph =
        build_graph([
          Operation.new(:service_start, %{service: "nginx"})
        ])

      assert {:ok, output} = Ansible.transform(graph)
      assert is_binary(output)
      assert output =~ "service"
      assert output =~ "nginx"
      assert output =~ "started"
    end

    test "transforms service_stop to service task with stopped state" do
      graph =
        build_graph([
          Operation.new(:service_stop, %{service: "apache2"})
        ])

      assert {:ok, output} = Ansible.transform(graph)
      assert output =~ "stopped"
      assert output =~ "apache2"
    end
  end

  describe "transform/2 - file operations" do
    test "transforms file_write to copy task with dest" do
      graph =
        build_graph([
          Operation.new(:file_write, %{path: "/etc/app.conf", content: "key=value"})
        ])

      assert {:ok, output} = Ansible.transform(graph)
      assert is_binary(output)
      assert output =~ "copy"
      assert output =~ "/etc/app.conf"
    end
  end

  describe "transform/2 - user operations" do
    test "transforms user_create to user task" do
      graph =
        build_graph([
          Operation.new(:user_create, %{name: "deploy", shell: "/bin/bash"})
        ])

      assert {:ok, output} = Ansible.transform(graph)
      assert is_binary(output)
      assert output =~ "user"
      assert output =~ "deploy"
      assert output =~ "present"
    end
  end

  describe "transform/2 - command operations" do
    test "transforms command_run to command task" do
      graph =
        build_graph([
          Operation.new(:command_run, %{command: "echo hello"})
        ])

      assert {:ok, output} = Ansible.transform(graph)
      assert is_binary(output)
      assert output =~ "command"
      assert output =~ "echo hello"
    end
  end

  describe "transform/2 - playbook options" do
    test "uses default hosts 'all' when no hosts option given" do
      graph =
        build_graph([
          Operation.new(:package_install, %{package: "curl"})
        ])

      assert {:ok, output} = Ansible.transform(graph)
      assert output =~ "all"
    end

    test "uses custom hosts option" do
      graph =
        build_graph([
          Operation.new(:package_install, %{package: "curl"})
        ])

      assert {:ok, output} = Ansible.transform(graph, hosts: "webservers")
      assert output =~ "webservers"
    end

    test "multiple operations produce multiple tasks" do
      graph =
        build_graph([
          Operation.new(:package_install, %{package: "nginx"}),
          Operation.new(:service_start, %{service: "nginx"}),
          Operation.new(:file_write, %{
            path: "/etc/nginx/nginx.conf",
            content: "worker_processes 4;"
          })
        ])

      assert {:ok, output} = Ansible.transform(graph)
      assert is_binary(output)
      assert output =~ "nginx"
      assert output =~ "service"
      assert output =~ "copy"
    end
  end

  describe "validate/1" do
    test "validates a well-formed graph" do
      graph = build_graph([Operation.new(:package_install, %{package: "nginx"})])
      assert :ok = Ansible.validate(graph)
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
