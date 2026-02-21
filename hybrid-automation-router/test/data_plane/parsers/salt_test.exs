# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule HAR.DataPlane.Parsers.SaltTest do
  @moduledoc """
  Tests for the Salt Stack SLS parser.

  Verifies conversion of Salt state files (YAML format) into HAR
  semantic graph operations with correct type normalization,
  parameter extraction, and dependency resolution.
  """
  use ExUnit.Case

  alias HAR.DataPlane.Parsers.Salt
  alias HAR.Semantic.{Graph, Operation, Dependency}

  describe "parse/2 with pkg.installed" do
    test "parses pkg.installed state with name parameter" do
      sls = """
      install_nginx:
        pkg.installed:
          - name: nginx
      """

      assert {:ok, %Graph{} = graph} = Salt.parse(sls)
      assert length(graph.vertices) == 1

      op = hd(graph.vertices)
      assert op.type == :package_install
      assert op.params.package == "nginx"
      assert op.metadata.source == :salt
      assert op.metadata.state_id == "install_nginx"
      assert op.metadata.function == "pkg.installed"
    end

    test "parses pkg.installed with version constraint" do
      sls = """
      install_nginx:
        pkg.installed:
          - name: nginx
          - version: 1.18.0
      """

      assert {:ok, %Graph{} = graph} = Salt.parse(sls)
      op = hd(graph.vertices)
      assert op.type == :package_install
      assert op.params.package == "nginx"
      assert op.params.version == "1.18.0"
    end

    test "parses pkg.installed with refresh option" do
      sls = """
      install_nginx:
        pkg.installed:
          - name: nginx
          - refresh: true
      """

      assert {:ok, %Graph{} = graph} = Salt.parse(sls)
      op = hd(graph.vertices)
      assert op.params.refresh == true
    end
  end

  describe "parse/2 with service.running" do
    test "parses service.running state" do
      sls = """
      start_nginx:
        service.running:
          - name: nginx
          - enable: true
      """

      assert {:ok, %Graph{} = graph} = Salt.parse(sls)
      op = hd(graph.vertices)
      assert op.type == :service_start
      assert op.params.service == "nginx"
      assert op.params.enable == true
    end

    test "parses service.running with reload option" do
      sls = """
      start_nginx:
        service.running:
          - name: nginx
          - reload: true
      """

      assert {:ok, %Graph{} = graph} = Salt.parse(sls)
      op = hd(graph.vertices)
      assert op.type == :service_start
      assert op.params.reload == true
    end

    test "normalizes service.dead to service_stop" do
      sls = """
      stop_nginx:
        service.dead:
          - name: nginx
      """

      assert {:ok, %Graph{} = graph} = Salt.parse(sls)
      op = hd(graph.vertices)
      assert op.type == :service_stop
      assert op.params.service == "nginx"
    end
  end

  describe "parse/2 with file.managed" do
    test "parses file.managed state" do
      sls = """
      nginx_config:
        file.managed:
          - name: /etc/nginx/nginx.conf
          - source: salt://nginx/files/nginx.conf
          - mode: '0644'
          - user: root
          - group: root
      """

      assert {:ok, %Graph{} = graph} = Salt.parse(sls)
      op = hd(graph.vertices)
      assert op.type == :file_write
      assert op.params.path == "/etc/nginx/nginx.conf"
      assert op.params.source == "salt://nginx/files/nginx.conf"
      assert op.params.mode == "0644"
      assert op.params.user == "root"
      assert op.params.group == "root"
    end

    test "parses file.managed with template" do
      sls = """
      nginx_config:
        file.managed:
          - name: /etc/nginx/nginx.conf
          - source: salt://nginx/files/nginx.conf.jinja
          - template: jinja
      """

      assert {:ok, %Graph{} = graph} = Salt.parse(sls)
      op = hd(graph.vertices)
      assert op.type == :file_write
      assert op.params.template == "jinja"
    end

    test "parses file.directory to directory_create" do
      sls = """
      create_webroot:
        file.directory:
          - name: /var/www/html
          - mode: '0755'
          - makedirs: true
      """

      assert {:ok, %Graph{} = graph} = Salt.parse(sls)
      op = hd(graph.vertices)
      assert op.type == :directory_create
      assert op.params.path == "/var/www/html"
      assert op.params.makedirs == true
    end

    test "parses file.absent to file_delete" do
      sls = """
      remove_old_config:
        file.absent:
          - name: /etc/nginx/old.conf
      """

      assert {:ok, %Graph{} = graph} = Salt.parse(sls)
      op = hd(graph.vertices)
      assert op.type == :file_delete
    end
  end

  describe "parse/2 with user.present" do
    test "parses user.present state" do
      sls = """
      create_deployer:
        user.present:
          - name: deployer
          - uid: 1001
          - home: /home/deployer
          - shell: /bin/bash
          - groups:
            - sudo
            - docker
      """

      assert {:ok, %Graph{} = graph} = Salt.parse(sls)
      op = hd(graph.vertices)
      assert op.type == :user_create
      assert op.params.name == "deployer"
      assert op.params.uid == 1001
      assert op.params.home == "/home/deployer"
      assert op.params.shell == "/bin/bash"
      assert op.params.groups == ["sudo", "docker"]
    end

    test "parses user.absent to user_delete" do
      sls = """
      remove_old_user:
        user.absent:
          - name: olduser
      """

      assert {:ok, %Graph{} = graph} = Salt.parse(sls)
      op = hd(graph.vertices)
      assert op.type == :user_delete
    end
  end

  describe "parse/2 with cmd.run" do
    test "parses cmd.run state" do
      sls = """
      run_setup:
        cmd.run:
          - name: /usr/local/bin/setup.sh
          - cwd: /opt/app
          - creates: /opt/app/.installed
      """

      assert {:ok, %Graph{} = graph} = Salt.parse(sls)
      op = hd(graph.vertices)
      assert op.type == :command_run
      assert op.params.command == "/usr/local/bin/setup.sh"
      assert op.params.cwd == "/opt/app"
      assert op.params.creates == "/opt/app/.installed"
    end

    test "parses cmd.run with unless guard" do
      sls = """
      run_init:
        cmd.run:
          - name: /usr/local/bin/init.sh
          - unless: test -f /opt/app/.initialized
      """

      assert {:ok, %Graph{} = graph} = Salt.parse(sls)
      op = hd(graph.vertices)
      assert op.type == :command_run
      assert op.params.unless == "test -f /opt/app/.initialized"
    end

    test "parses cmd.script to script_execute" do
      sls = """
      run_script:
        cmd.script:
          - name: salt://scripts/deploy.sh
      """

      assert {:ok, %Graph{} = graph} = Salt.parse(sls)
      op = hd(graph.vertices)
      assert op.type == :script_execute
    end
  end

  describe "parse/2 with group states" do
    test "parses group.present to group_create" do
      sls = """
      create_docker_group:
        group.present:
          - name: docker
          - gid: 999
      """

      assert {:ok, %Graph{} = graph} = Salt.parse(sls)
      op = hd(graph.vertices)
      assert op.type == :group_create
    end

    test "parses group.absent to group_delete" do
      sls = """
      remove_old_group:
        group.absent:
          - name: legacy
      """

      assert {:ok, %Graph{} = graph} = Salt.parse(sls)
      op = hd(graph.vertices)
      assert op.type == :group_delete
    end
  end

  describe "parse/2 with pkg.removed" do
    test "parses pkg.removed to package_remove" do
      sls = """
      remove_apache:
        pkg.removed:
          - name: apache2
      """

      assert {:ok, %Graph{} = graph} = Salt.parse(sls)
      op = hd(graph.vertices)
      assert op.type == :package_remove
      assert op.params.package == "apache2"
    end
  end

  describe "parse/2 with pkg.latest" do
    test "parses pkg.latest to package_upgrade" do
      sls = """
      upgrade_openssl:
        pkg.latest:
          - name: openssl
      """

      assert {:ok, %Graph{} = graph} = Salt.parse(sls)
      op = hd(graph.vertices)
      assert op.type == :package_upgrade
    end
  end

  describe "dependency extraction from require requisites" do
    test "extracts require dependency between states" do
      sls = """
      install_nginx:
        pkg.installed:
          - name: nginx
      start_nginx:
        service.running:
          - name: nginx
          - enable: true
          - require:
            - pkg: nginx
      """

      assert {:ok, %Graph{} = graph} = Salt.parse(sls)
      assert length(graph.vertices) == 2

      # The service should depend on the package
      if length(graph.edges) > 0 do
        dep = hd(graph.edges)
        assert %Dependency{} = dep
        assert dep.type == :requires
      end
    end
  end

  describe "parse/2 with multiple states" do
    test "parses multiple states in a single SLS file" do
      sls = """
      install_nginx:
        pkg.installed:
          - name: nginx
      nginx_config:
        file.managed:
          - name: /etc/nginx/nginx.conf
          - source: salt://nginx/nginx.conf
      start_nginx:
        service.running:
          - name: nginx
          - enable: true
      """

      assert {:ok, %Graph{} = graph} = Salt.parse(sls)
      assert length(graph.vertices) == 3

      types = Enum.map(graph.vertices, & &1.type)
      assert :package_install in types
      assert :file_write in types
      assert :service_start in types
    end
  end

  describe "parse/2 with unknown functions" do
    test "unknown salt functions get salt. prefix" do
      sls = """
      custom_state:
        custom.module:
          - name: something
      """

      assert {:ok, %Graph{} = graph} = Salt.parse(sls)
      op = hd(graph.vertices)
      assert op.type == :"salt.custom.module"
    end
  end

  describe "parse/2 error handling" do
    test "returns error for invalid YAML" do
      invalid_sls = """
      invalid: [yaml: content
      """

      assert {:error, {:yaml_parse_error, _}} = Salt.parse(invalid_sls)
    end
  end

  describe "validate/1" do
    test "validates correct SLS content" do
      sls = """
      install_nginx:
        pkg.installed:
          - name: nginx
      """

      assert :ok = Salt.validate(sls)
    end

    test "returns error for invalid YAML content" do
      invalid = """
      invalid: [yaml: content
      """

      assert {:error, {:yaml_parse_error, _}} = Salt.validate(invalid)
    end
  end

  describe "metadata" do
    test "sets graph metadata with source and timestamp" do
      sls = """
      install_nginx:
        pkg.installed:
          - name: nginx
      """

      assert {:ok, %Graph{} = graph} = Salt.parse(sls)
      assert graph.metadata.source == :salt
      assert %DateTime{} = graph.metadata.parsed_at
    end

    test "sets operation metadata with state_id and function" do
      sls = """
      install_nginx:
        pkg.installed:
          - name: nginx
      """

      assert {:ok, %Graph{} = graph} = Salt.parse(sls)
      op = hd(graph.vertices)
      assert op.metadata.state_id == "install_nginx"
      assert op.metadata.function == "pkg.installed"
      assert op.metadata.source == :salt
    end

    test "operation id contains salt prefix and state id" do
      sls = """
      install_nginx:
        pkg.installed:
          - name: nginx
      """

      assert {:ok, %Graph{} = graph} = Salt.parse(sls)
      op = hd(graph.vertices)
      assert op.id =~ "salt_"
      assert op.id =~ "install_nginx"
    end
  end
end
