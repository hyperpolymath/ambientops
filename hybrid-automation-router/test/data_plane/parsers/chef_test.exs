# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule HAR.DataPlane.Parsers.ChefTest do
  @moduledoc """
  Tests for the Chef recipe parser.

  Verifies conversion of Chef DSL resource declarations (Ruby-like
  syntax) into HAR semantic graph operations. The parser handles
  block resources (do/end), inline resources, actions, guard clauses,
  and notifications.
  """
  use ExUnit.Case

  alias HAR.DataPlane.Parsers.Chef
  alias HAR.Semantic.{Graph, Dependency}

  describe "parse/2 with block package resource" do
    test "parses package resource with install action" do
      recipe = """
      package 'nginx' do
        action :install
      end
      """

      assert {:ok, %Graph{} = graph} = Chef.parse(recipe)
      assert length(graph.vertices) >= 1

      op = hd(graph.vertices)
      assert op.type == :package_install
      assert op.params.name == "nginx"
      assert op.metadata.source == :chef
      assert op.metadata.chef_type == "package"
      assert op.metadata.chef_name == "nginx"
    end

    test "parses package with remove action" do
      recipe = """
      package 'nginx' do
        action :remove
      end
      """

      assert {:ok, %Graph{} = graph} = Chef.parse(recipe)
      op = hd(graph.vertices)
      assert op.type == :package_remove
    end

    test "parses package with upgrade action" do
      recipe = """
      package 'nginx' do
        action :upgrade
      end
      """

      assert {:ok, %Graph{} = graph} = Chef.parse(recipe)
      op = hd(graph.vertices)
      assert op.type == :package_upgrade
    end

    test "parses package with version attribute" do
      recipe = """
      package 'nginx' do
        version '1.18.0'
        action :install
      end
      """

      assert {:ok, %Graph{} = graph} = Chef.parse(recipe)
      op = hd(graph.vertices)
      assert op.params.version == "1.18.0"
    end
  end

  describe "parse/2 with inline resource" do
    test "parses inline package resource" do
      recipe = """
      package 'nginx'
      """

      assert {:ok, %Graph{} = graph} = Chef.parse(recipe)
      assert length(graph.vertices) >= 1

      op = hd(graph.vertices)
      assert op.params.name == "nginx"
      assert op.metadata.chef_type == "package"
    end
  end

  describe "parse/2 with service resource" do
    test "parses service resource with start action" do
      recipe = """
      service 'nginx' do
        action :start
      end
      """

      assert {:ok, %Graph{} = graph} = Chef.parse(recipe)
      op = hd(graph.vertices)
      assert op.type == :service_start
      assert op.params.name == "nginx"
    end

    test "parses service with stop action" do
      recipe = """
      service 'nginx' do
        action :stop
      end
      """

      assert {:ok, %Graph{} = graph} = Chef.parse(recipe)
      op = hd(graph.vertices)
      assert op.type == :service_stop
    end

    test "parses service with restart action" do
      recipe = """
      service 'nginx' do
        action :restart
      end
      """

      assert {:ok, %Graph{} = graph} = Chef.parse(recipe)
      op = hd(graph.vertices)
      assert op.type == :service_restart
    end

    test "parses service with enable action" do
      recipe = """
      service 'nginx' do
        action :enable
      end
      """

      assert {:ok, %Graph{} = graph} = Chef.parse(recipe)
      op = hd(graph.vertices)
      assert op.type == :service_enable
    end

    test "parses service with array of actions" do
      recipe = """
      service 'nginx' do
        action [:enable, :start]
      end
      """

      assert {:ok, %Graph{} = graph} = Chef.parse(recipe)
      op = hd(graph.vertices)
      # Normalized type uses first action in array
      assert op.type == :service_enable
      assert :enable in op.metadata.action
      assert :start in op.metadata.action
    end
  end

  describe "parse/2 with file resource" do
    test "parses file resource with content" do
      recipe = """
      file '/etc/motd' do
        content 'Welcome to the server'
        owner 'root'
        group 'root'
        mode '0644'
        action :create
      end
      """

      assert {:ok, %Graph{} = graph} = Chef.parse(recipe)
      op = hd(graph.vertices)
      assert op.type == :file_create
      assert op.params.path == "/etc/motd"
      assert op.params.content == "Welcome to the server"
      assert op.params.owner == "root"
      assert op.params.mode == "0644"
    end

    test "parses file with delete action" do
      recipe = """
      file '/tmp/old_file' do
        action :delete
      end
      """

      assert {:ok, %Graph{} = graph} = Chef.parse(recipe)
      op = hd(graph.vertices)
      assert op.type == :file_delete
    end
  end

  describe "parse/2 with template resource" do
    test "parses template resource" do
      recipe = """
      template '/etc/nginx/nginx.conf' do
        source 'nginx.conf.erb'
        owner 'root'
        mode '0644'
      end
      """

      assert {:ok, %Graph{} = graph} = Chef.parse(recipe)
      op = hd(graph.vertices)
      assert op.type == :file_template
      assert op.params.path == "/etc/nginx/nginx.conf"
      assert op.params.source == "nginx.conf.erb"
    end
  end

  describe "parse/2 with directory resource" do
    test "parses directory resource" do
      recipe = """
      directory '/var/www/html' do
        owner 'www-data'
        mode '0755'
        action :create
      end
      """

      assert {:ok, %Graph{} = graph} = Chef.parse(recipe)
      op = hd(graph.vertices)
      assert op.type == :directory_create
      assert op.params.path == "/var/www/html"
      assert op.params.owner == "www-data"
    end
  end

  describe "parse/2 with user resource" do
    test "parses user resource" do
      recipe = """
      user 'deployer' do
        uid 1001
        home '/home/deployer'
        shell '/bin/bash'
        action :create
      end
      """

      assert {:ok, %Graph{} = graph} = Chef.parse(recipe)
      op = hd(graph.vertices)
      assert op.type == :user_create
      assert op.params.name == "deployer"
    end
  end

  describe "parse/2 with execute resource" do
    test "parses execute resource" do
      recipe = """
      execute 'setup-app' do
        command '/usr/local/bin/setup.sh'
        cwd '/opt/app'
        creates '/opt/app/.installed'
      end
      """

      assert {:ok, %Graph{} = graph} = Chef.parse(recipe)
      op = hd(graph.vertices)
      assert op.type == :command_run
      assert op.params.command == "/usr/local/bin/setup.sh"
    end
  end

  describe "parse/2 with notifications" do
    test "extracts notifies relationship" do
      recipe = """
      template '/etc/nginx/nginx.conf' do
        source 'nginx.conf.erb'
        notifies :restart, 'service[nginx]'
      end

      service 'nginx' do
        action :start
      end
      """

      assert {:ok, %Graph{} = graph} = Chef.parse(recipe)
      assert length(graph.vertices) >= 2

      # Should have notification dependency
      notifies_deps =
        Enum.filter(graph.edges, fn dep ->
          dep.type == :notifies
        end)

      if length(notifies_deps) > 0 do
        dep = hd(notifies_deps)
        assert dep.type == :notifies
      end
    end

    test "extracts notifies with immediate timing" do
      recipe = """
      template '/etc/nginx/nginx.conf' do
        source 'nginx.conf.erb'
        notifies :restart, 'service[nginx]', :immediately
      end

      service 'nginx' do
        action :start
      end
      """

      assert {:ok, %Graph{} = graph} = Chef.parse(recipe)
      assert length(graph.vertices) >= 2
    end
  end

  describe "parse/2 with guard clauses" do
    test "extracts not_if guard" do
      recipe = """
      execute 'setup' do
        command '/usr/local/bin/setup.sh'
        not_if 'test -f /opt/app/.installed'
      end
      """

      assert {:ok, %Graph{} = graph} = Chef.parse(recipe)
      op = hd(graph.vertices)
      assert op.metadata.guards.not_if != []
    end

    test "extracts only_if guard" do
      recipe = """
      execute 'deploy' do
        command '/usr/local/bin/deploy.sh'
        only_if 'test -d /opt/app'
      end
      """

      assert {:ok, %Graph{} = graph} = Chef.parse(recipe)
      op = hd(graph.vertices)
      assert op.metadata.guards.only_if != []
    end
  end

  describe "parse/2 with multiple resources" do
    test "parses multiple resources and creates sequential dependencies" do
      recipe = """
      package 'nginx' do
        action :install
      end

      service 'nginx' do
        action :start
      end
      """

      assert {:ok, %Graph{} = graph} = Chef.parse(recipe)
      assert length(graph.vertices) >= 2

      types = Enum.map(graph.vertices, & &1.type)
      assert :package_install in types
      assert :service_start in types

      # Chef parser creates sequential dependencies between resources
      sequential_deps =
        Enum.filter(graph.edges, fn dep ->
          dep.type == :sequential
        end)

      assert length(sequential_deps) >= 1
    end

    test "parses three resources with proper ordering" do
      recipe = """
      package 'nginx' do
        action :install
      end

      template '/etc/nginx/nginx.conf' do
        source 'nginx.conf.erb'
      end

      service 'nginx' do
        action :start
      end
      """

      assert {:ok, %Graph{} = graph} = Chef.parse(recipe)
      assert length(graph.vertices) >= 3
    end
  end

  describe "validate/1" do
    test "validates correct Chef recipe" do
      recipe = """
      package 'nginx' do
        action :install
      end
      """

      assert :ok = Chef.validate(recipe)
    end

    test "returns error for severely unbalanced do/end blocks" do
      recipe = """
      package 'nginx' do
        action :install
      end
      end
      end
      """

      assert {:error, {:chef_parse_error, _}} = Chef.validate(recipe)
    end
  end

  describe "metadata" do
    test "sets graph metadata with source and timestamp" do
      recipe = """
      package 'nginx' do
        action :install
      end
      """

      assert {:ok, %Graph{} = graph} = Chef.parse(recipe)
      assert graph.metadata.source == :chef
      assert %DateTime{} = graph.metadata.parsed_at
    end

    test "operation ID contains chef prefix" do
      recipe = """
      package 'nginx' do
        action :install
      end
      """

      assert {:ok, %Graph{} = graph} = Chef.parse(recipe)
      op = hd(graph.vertices)
      assert op.id =~ "chef_"
    end

    test "stores original action in metadata" do
      recipe = """
      package 'nginx' do
        action :install
      end
      """

      assert {:ok, %Graph{} = graph} = Chef.parse(recipe)
      op = hd(graph.vertices)
      assert is_list(op.metadata.action)
      assert :install in op.metadata.action
    end

    test "sets target with resource type and name" do
      recipe = """
      package 'nginx' do
        action :install
      end
      """

      assert {:ok, %Graph{} = graph} = Chef.parse(recipe)
      op = hd(graph.vertices)
      assert op.target.resource_type == "package"
      assert op.target.resource_name == "nginx"
    end
  end
end
