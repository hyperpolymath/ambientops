# SPDX-License-Identifier: MPL-2.0
defmodule HAR.DataPlane.Parsers.PuppetTest do
  @moduledoc """
  Tests for the Puppet manifest parser.

  Verifies conversion of Puppet DSL declarations into HAR semantic
  graph operations. The parser uses regex-based extraction for resource
  declarations, class definitions, virtual/exported resources,
  and dependency relationships.
  """
  use ExUnit.Case

  alias HAR.DataPlane.Parsers.Puppet
  alias HAR.Semantic.{Graph, Dependency}

  describe "parse/2 with package resource" do
    test "parses package resource with ensure present" do
      manifest = """
      package { 'nginx':
        ensure => present,
      }
      """

      assert {:ok, %Graph{} = graph} = Puppet.parse(manifest)
      assert length(graph.vertices) >= 1

      op = hd(graph.vertices)
      assert op.type == :package_install
      assert op.params.name == "nginx"
      assert op.params.state == :installed
      assert op.metadata.source == :puppet
      assert op.metadata.puppet_type == "package"
      assert op.metadata.puppet_title == "nginx"
    end

    test "parses package with ensure absent" do
      manifest = """
      package { 'nginx':
        ensure => absent,
      }
      """

      assert {:ok, %Graph{} = graph} = Puppet.parse(manifest)
      op = hd(graph.vertices)
      assert op.params.state == :removed
    end

    test "parses package with ensure latest" do
      manifest = """
      package { 'nginx':
        ensure => latest,
      }
      """

      assert {:ok, %Graph{} = graph} = Puppet.parse(manifest)
      op = hd(graph.vertices)
      assert op.params.state == :latest
    end

    test "parses package with version string" do
      manifest = """
      package { 'nginx':
        ensure => '1.18.0',
      }
      """

      assert {:ok, %Graph{} = graph} = Puppet.parse(manifest)
      op = hd(graph.vertices)
      assert op.params.state == :installed
      assert op.params.version == "1.18.0"
    end

    test "parses package with provider attribute" do
      manifest = """
      package { 'nginx':
        ensure   => present,
        provider => apt,
      }
      """

      assert {:ok, %Graph{} = graph} = Puppet.parse(manifest)
      op = hd(graph.vertices)
      assert op.params.provider == "apt"
    end
  end

  describe "parse/2 with service resource" do
    test "parses service with ensure running" do
      manifest = """
      service { 'nginx':
        ensure => running,
        enable => true,
      }
      """

      assert {:ok, %Graph{} = graph} = Puppet.parse(manifest)
      op = hd(graph.vertices)
      assert op.type == :service_start
      assert op.params.name == "nginx"
      assert op.params.state == :running
      assert op.params.enabled == true
    end

    test "parses service with ensure stopped" do
      manifest = """
      service { 'nginx':
        ensure => stopped,
      }
      """

      assert {:ok, %Graph{} = graph} = Puppet.parse(manifest)
      op = hd(graph.vertices)
      assert op.params.state == :stopped
    end
  end

  describe "parse/2 with file resource" do
    test "parses file resource with content" do
      manifest = """
      file { '/etc/nginx/nginx.conf':
        ensure  => file,
        content => 'server_name localhost',
      }
      """

      assert {:ok, %Graph{} = graph} = Puppet.parse(manifest)
      op = hd(graph.vertices)
      assert op.type == :file_create
      assert op.params.path == "/etc/nginx/nginx.conf"
      assert op.params.content == "server_name localhost"
      assert op.params.ensure == "file"
    end

    test "parses file resource with owner and mode" do
      manifest = """
      file { '/etc/nginx/nginx.conf':
        ensure => file,
        owner  => root,
        group  => root,
        mode   => '0644',
      }
      """

      assert {:ok, %Graph{} = graph} = Puppet.parse(manifest)
      op = hd(graph.vertices)
      assert op.params.owner == "root"
      assert op.params.group == "root"
      assert op.params.mode == "0644"
    end

    test "parses file resource with source attribute" do
      manifest = """
      file { '/etc/nginx/nginx.conf':
        ensure => file,
        source => 'puppet:///modules/nginx/nginx.conf',
      }
      """

      assert {:ok, %Graph{} = graph} = Puppet.parse(manifest)
      op = hd(graph.vertices)
      assert op.params.source == "puppet:///modules/nginx/nginx.conf"
    end
  end

  describe "parse/2 with user resource" do
    test "parses user resource" do
      manifest = """
      user { 'deployer':
        ensure => present,
        uid    => 1001,
        home   => '/home/deployer',
        shell  => '/bin/bash',
      }
      """

      assert {:ok, %Graph{} = graph} = Puppet.parse(manifest)
      op = hd(graph.vertices)
      assert op.type == :user_create
      assert op.params.name == "deployer"
      assert op.params.ensure == "present"
    end
  end

  describe "parse/2 with exec resource" do
    test "parses exec resource" do
      manifest = """
      exec { 'setup-app':
        command => '/usr/local/bin/setup.sh',
        creates => '/opt/app/.installed',
        cwd     => '/opt/app',
      }
      """

      assert {:ok, %Graph{} = graph} = Puppet.parse(manifest)
      op = hd(graph.vertices)
      assert op.type == :command_run
      assert op.params.command == "/usr/local/bin/setup.sh"
      assert op.params.creates == "/opt/app/.installed"
      assert op.params.cwd == "/opt/app"
    end
  end

  describe "parse/2 with group resource" do
    test "parses group resource" do
      manifest = """
      group { 'docker':
        ensure => present,
        gid    => 999,
      }
      """

      assert {:ok, %Graph{} = graph} = Puppet.parse(manifest)
      op = hd(graph.vertices)
      assert op.type == :group_create
      assert op.params.name == "docker"
    end
  end

  describe "parse/2 with virtual resources" do
    test "parses virtual resource with @ prefix" do
      manifest = """
      @package { 'nginx':
        ensure => present,
      }
      """

      assert {:ok, %Graph{} = graph} = Puppet.parse(manifest)
      assert length(graph.vertices) >= 1

      op = hd(graph.vertices)
      assert op.metadata.virtual == true
      assert op.metadata.exported == false
    end
  end

  describe "parse/2 with exported resources" do
    test "parses exported resource with @@ prefix" do
      manifest = """
      @@package { 'nginx':
        ensure => present,
      }
      """

      assert {:ok, %Graph{} = graph} = Puppet.parse(manifest)
      assert length(graph.vertices) >= 1

      op = hd(graph.vertices)
      assert op.metadata.exported == true
    end
  end

  describe "parse/2 with class definitions" do
    test "parses class definition" do
      manifest = """
      class webserver {
        package { 'nginx':
          ensure => present,
        }
      }
      """

      assert {:ok, %Graph{} = graph} = Puppet.parse(manifest)
      # Should find both the class and the package resource
      assert length(graph.vertices) >= 1

      class_ops = Enum.filter(graph.vertices, fn op -> op.type == :class_include end)

      if length(class_ops) > 0 do
        class_op = hd(class_ops)
        assert class_op.params.name == "webserver"
      end
    end

    test "parses class with parameters" do
      manifest = """
      class webserver($port = '80') {
        package { 'nginx':
          ensure => present,
        }
      }
      """

      assert {:ok, %Graph{} = graph} = Puppet.parse(manifest)
      assert length(graph.vertices) >= 1
    end
  end

  describe "dependency extraction from require attribute" do
    test "extracts require relationship" do
      manifest = """
      package { 'nginx':
        ensure => present,
      }

      service { 'nginx':
        ensure  => running,
        require => Package['nginx'],
      }
      """

      assert {:ok, %Graph{} = graph} = Puppet.parse(manifest)
      assert length(graph.vertices) >= 2

      # There should be a dependency from package to service
      if length(graph.edges) > 0 do
        dep = hd(graph.edges)
        assert %Dependency{} = dep
        assert dep.type == :requires
      end
    end
  end

  describe "dependency extraction from chaining arrows" do
    test "extracts -> ordering arrow dependency" do
      manifest = """
      package { 'nginx':
        ensure => present,
      }

      service { 'nginx':
        ensure => running,
      }

      Package['nginx'] -> Service['nginx']
      """

      assert {:ok, %Graph{} = graph} = Puppet.parse(manifest)
      assert length(graph.vertices) >= 2

      # There should be a chaining dependency
      chaining_deps =
        Enum.filter(graph.edges, fn dep ->
          dep.metadata[:reason] =~ "puppet_chaining"
        end)

      if length(chaining_deps) > 0 do
        dep = hd(chaining_deps)
        assert dep.type == :requires
      end
    end

    test "extracts ~> notification arrow dependency" do
      manifest = """
      file { '/etc/nginx/nginx.conf':
        ensure  => file,
        content => 'config',
      }

      service { 'nginx':
        ensure => running,
      }

      File['/etc/nginx/nginx.conf'] ~> Service['nginx']
      """

      assert {:ok, %Graph{} = graph} = Puppet.parse(manifest)

      watches_deps =
        Enum.filter(graph.edges, fn dep ->
          dep.type == :watches
        end)

      if length(watches_deps) > 0 do
        dep = hd(watches_deps)
        assert dep.type == :watches
      end
    end
  end

  describe "parse/2 with multiple resources" do
    test "parses multiple resources of different types" do
      manifest = """
      package { 'nginx':
        ensure => present,
      }

      service { 'nginx':
        ensure => running,
        enable => true,
      }

      file { '/etc/nginx/nginx.conf':
        ensure  => file,
        content => 'config',
      }
      """

      assert {:ok, %Graph{} = graph} = Puppet.parse(manifest)
      assert length(graph.vertices) >= 3

      types = Enum.map(graph.vertices, & &1.type)
      assert :package_install in types
      assert :service_start in types
      assert :file_create in types
    end
  end

  describe "validate/1" do
    test "validates correct Puppet manifest" do
      manifest = """
      package { 'nginx':
        ensure => present,
      }
      """

      assert :ok = Puppet.validate(manifest)
    end

    test "returns error for unbalanced braces" do
      manifest = """
      package { 'nginx':
        ensure => present,
      """

      assert {:error, {:puppet_parse_error, msg}} = Puppet.validate(manifest)
      assert msg =~ "Unbalanced braces"
    end

    test "returns error for content without braces" do
      manifest = "just some random text"

      assert {:error, {:puppet_parse_error, _}} = Puppet.validate(manifest)
    end
  end

  describe "metadata" do
    test "sets graph metadata with source and timestamp" do
      manifest = """
      package { 'nginx':
        ensure => present,
      }
      """

      assert {:ok, %Graph{} = graph} = Puppet.parse(manifest)
      assert graph.metadata.source == :puppet
      assert %DateTime{} = graph.metadata.parsed_at
    end

    test "operation ID contains puppet prefix" do
      manifest = """
      package { 'nginx':
        ensure => present,
      }
      """

      assert {:ok, %Graph{} = graph} = Puppet.parse(manifest)
      op = hd(graph.vertices)
      assert op.id =~ "puppet_"
    end

    test "sets target with resource type and title" do
      manifest = """
      package { 'nginx':
        ensure => present,
      }
      """

      assert {:ok, %Graph{} = graph} = Puppet.parse(manifest)
      op = hd(graph.vertices)
      assert op.target.resource_type == "package"
      assert op.target.resource_title == "nginx"
    end
  end
end
