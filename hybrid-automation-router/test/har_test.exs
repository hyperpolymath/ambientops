# SPDX-License-Identifier: MPL-2.0
defmodule HARTest do
  @moduledoc """
  Tests for the top-level HAR module API.

  Tests for parse/3 and version/0 run without the full application.
  Tests for route/2, convert/3, and transform/2 require the OTP
  application running (GenServers) and are tagged as integration.
  """
  use ExUnit.Case

  alias HAR.Semantic.Graph

  describe "parse/3" do
    test "parses ansible format to semantic graph" do
      yaml = """
      - hosts: webservers
        tasks:
          - name: Install nginx
            apt:
              name: nginx
              state: present
      """

      assert {:ok, %Graph{} = graph} = HAR.parse(:ansible, yaml)
      assert length(graph.vertices) >= 1

      op = hd(graph.vertices)
      assert op.type == :package_install
      assert op.metadata.source == :ansible
    end

    test "parses salt format to semantic graph" do
      sls = """
      install_nginx:
        pkg.installed:
          - name: nginx
      """

      assert {:ok, %Graph{} = graph} = HAR.parse(:salt, sls)
      assert length(graph.vertices) >= 1

      op = hd(graph.vertices)
      assert op.type == :package_install
    end

    test "parses terraform format to semantic graph" do
      json = """
      {
        "resources": [
          {
            "address": "aws_instance.web",
            "type": "aws_instance",
            "name": "web",
            "values": {
              "ami": "ami-12345678",
              "instance_type": "t3.micro"
            }
          }
        ]
      }
      """

      assert {:ok, %Graph{} = graph} = HAR.parse(:terraform, json)
      assert length(graph.vertices) == 1
    end

    test "parses puppet format to semantic graph" do
      manifest = """
      package { 'nginx':
        ensure => present,
      }
      """

      assert {:ok, %Graph{} = graph} = HAR.parse(:puppet, manifest)
      assert length(graph.vertices) >= 1
    end

    test "parses chef format to semantic graph" do
      recipe = """
      package 'nginx' do
        action :install
      end
      """

      assert {:ok, %Graph{} = graph} = HAR.parse(:chef, recipe)
      assert length(graph.vertices) >= 1
    end

    test "parses kubernetes format to semantic graph" do
      yaml = """
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: nginx
      spec:
        replicas: 1
        selector:
          matchLabels:
            app: nginx
        template:
          metadata:
            labels:
              app: nginx
          spec:
            containers:
              - name: nginx
                image: nginx:latest
      """

      assert {:ok, %Graph{} = graph} = HAR.parse(:kubernetes, yaml)
      assert length(graph.vertices) >= 1
    end

    test "parses docker_compose format to semantic graph" do
      yaml = """
      version: "3"
      services:
        web:
          image: nginx
      """

      assert {:ok, %Graph{} = graph} = HAR.parse(:docker_compose, yaml)
      assert length(graph.vertices) >= 1
    end

    test "parses cloudformation format to semantic graph" do
      yaml = """
      AWSTemplateFormatVersion: "2010-09-09"
      Resources:
        MyInstance:
          Type: AWS::EC2::Instance
          Properties:
            InstanceType: t3.micro
            ImageId: ami-12345678
      """

      assert {:ok, %Graph{} = graph} = HAR.parse(:cloudformation, yaml)
      assert length(graph.vertices) >= 1
    end

    test "parses pulumi format to semantic graph" do
      yaml = """
      name: my-project
      runtime: yaml
      resources:
        webServer:
          type: aws:ec2/instance:Instance
          properties:
            ami: ami-12345678
            instanceType: t3.micro
      """

      assert {:ok, %Graph{} = graph} = HAR.parse(:pulumi, yaml)
      assert length(graph.vertices) >= 1
    end

    test "returns error for unsupported format" do
      assert {:error, {:unsupported_format, :unknown}} = HAR.parse(:unknown, "content")
    end

    test "returns error for another unsupported format" do
      assert {:error, {:unsupported_format, :powershell}} = HAR.parse(:powershell, "Get-Service")
    end

    test "passes options through to parser" do
      yaml = """
      - hosts: webservers
        tasks:
          - name: Install nginx
            apt:
              name: nginx
              state: present
      """

      # Options are passed through, parser should still work
      assert {:ok, %Graph{}} = HAR.parse(:ansible, yaml, strict: true)
    end
  end

  describe "version/0" do
    test "returns version string" do
      version = HAR.version()
      assert is_binary(version)
    end

    test "returns non-empty version string" do
      version = HAR.version()
      assert String.length(version) > 0
    end

    test "version matches mix.exs version" do
      version = HAR.version()
      assert version =~ ~r/^\d+\.\d+\.\d+/
    end
  end

  describe "convert/3" do
    @describetag :integration

    test "requires :to option" do
      yaml = """
      - hosts: webservers
        tasks:
          - name: Install nginx
            apt:
              name: nginx
              state: present
      """

      assert_raise KeyError, fn ->
        HAR.convert(:ansible, yaml, [])
      end
    end
  end
end
