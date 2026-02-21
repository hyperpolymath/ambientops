# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>

defmodule HAR.Integration.ConvertTest do
  @moduledoc "End-to-end conversion tests using HAR.convert/3"
  use ExUnit.Case, async: false

  alias HAR.ControlPlane.HealthChecker

  setup do
    # Register all backends from the routing table as healthy so routing succeeds.
    routes = HAR.ControlPlane.RoutingTable.get_routes()

    for route <- routes, backend <- route.backends do
      HealthChecker.register_backend(backend)
      HealthChecker.set_health(backend, :healthy)
    end

    Process.sleep(50)
    :ok
  end

  describe "HAR.convert/3" do
    test "converts Ansible to Salt" do
      ansible = """
      - hosts: webservers
        tasks:
          - name: Install nginx
            apt:
              name: nginx
              state: present
      """

      assert {:ok, result} = HAR.convert(:ansible, ansible, to: :salt)
      assert is_binary(result)
      assert result =~ "pkg.installed"
    end

    test "converts Ansible to Terraform" do
      ansible = """
      - hosts: webservers
        tasks:
          - name: Install nginx
            apt:
              name: nginx
              state: present
      """

      assert {:ok, result} = HAR.convert(:ansible, ansible, to: :terraform)
      assert is_binary(result)
    end

    test "converts Salt to Ansible" do
      salt = """
      install_nginx:
        pkg.installed:
          - name: nginx
      """

      assert {:ok, result} = HAR.convert(:salt, salt, to: :ansible)
      assert is_binary(result)
      assert result =~ "nginx"
    end

    test "returns error for unsupported source format" do
      assert {:error, {:unsupported_format, :unknown}} =
               HAR.convert(:unknown, "content", to: :salt)
    end

    test "converts multi-task Ansible playbook" do
      ansible = """
      - hosts: all
        tasks:
          - name: Install packages
            apt:
              name: nginx
              state: present
          - name: Start service
            service:
              name: nginx
              state: started
          - name: Create user
            user:
              name: deployer
              shell: /bin/bash
      """

      assert {:ok, result} = HAR.convert(:ansible, ansible, to: :salt)
      assert is_binary(result)
      assert result =~ "pkg.installed"
      assert result =~ "service.running"
      assert result =~ "user.present"
    end
  end
end
