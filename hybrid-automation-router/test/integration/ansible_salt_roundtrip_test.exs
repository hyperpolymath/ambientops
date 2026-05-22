# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule HAR.Integration.AnsibleSaltRoundtripTest do
  use ExUnit.Case, async: true

  alias HAR.DataPlane.Parsers.Ansible, as: AnsibleParser
  alias HAR.DataPlane.Transformers.Salt, as: SaltTransformer
  alias HAR.DataPlane.Transformers.Ansible, as: AnsibleTransformer

  describe "Ansible -> Salt round-trip" do
    test "converts simple package install" do
      ansible_yaml = """
      - hosts: webservers
        tasks:
          - name: Install nginx
            apt:
              name: nginx
              state: present
      """

      # Parse Ansible -> Graph
      {:ok, graph} = AnsibleParser.parse(ansible_yaml)
      assert length(graph.vertices) == 1

      # Transform Graph -> Salt SLS
      {:ok, salt_sls} = SaltTransformer.transform(graph, [])
      assert is_binary(salt_sls)
      assert salt_sls =~ "pkg.installed"
      assert salt_sls =~ "nginx"
    end

    test "converts multiple tasks with dependencies" do
      ansible_yaml = """
      - hosts: webservers
        tasks:
          - name: Install nginx
            apt:
              name: nginx
              state: present
          - name: Start nginx
            service:
              name: nginx
              state: started
          - name: Copy config
            copy:
              src: nginx.conf
              dest: /etc/nginx/nginx.conf
      """

      {:ok, graph} = AnsibleParser.parse(ansible_yaml)
      assert length(graph.vertices) == 3

      # Salt should have corresponding states
      {:ok, salt_sls} = SaltTransformer.transform(graph, [])
      assert salt_sls =~ "pkg.installed"
      assert salt_sls =~ "service.running"
      assert salt_sls =~ "file.managed"
    end

    test "preserves user management operations" do
      ansible_yaml = """
      - hosts: all
        tasks:
          - name: Create deploy user
            user:
              name: deployer
              shell: /bin/bash
      """

      {:ok, graph} = AnsibleParser.parse(ansible_yaml)
      {:ok, salt_sls} = SaltTransformer.transform(graph, [])
      assert salt_sls =~ "user.present"
      assert salt_sls =~ "deployer"
    end
  end

  describe "Ansible -> Ansible round-trip" do
    test "parses and regenerates playbook" do
      original = """
      - hosts: webservers
        tasks:
          - name: Install nginx
            apt:
              name: nginx
              state: present
      """

      {:ok, graph} = AnsibleParser.parse(original)
      {:ok, regenerated} = AnsibleTransformer.transform(graph, [])

      assert is_binary(regenerated)
      # Regenerated should contain key elements
      assert regenerated =~ "nginx"
      # Note: exact format may differ but semantics preserved
    end
  end

  describe "Salt -> Ansible round-trip" do
    test "converts salt state to ansible playbook" do
      salt_sls = """
      install_nginx:
        pkg.installed:
          - name: nginx
      start_nginx:
        service.running:
          - name: nginx
          - enable: True
      """

      {:ok, graph} = HAR.DataPlane.Parsers.Salt.parse(salt_sls)
      assert length(graph.vertices) >= 2

      {:ok, ansible_yaml} = AnsibleTransformer.transform(graph, [])
      assert is_binary(ansible_yaml)
      assert ansible_yaml =~ "nginx"
    end
  end
end
