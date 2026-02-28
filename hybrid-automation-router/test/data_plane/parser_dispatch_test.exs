# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule HAR.DataPlane.ParserDispatchTest do
  @moduledoc """
  Tests for the HAR.DataPlane.Parser dispatch module.

  Verifies that `parse/3` correctly routes to the format-specific parser
  for every supported IaC format, and returns a descriptive error tuple
  for unsupported formats.
  """

  use ExUnit.Case, async: true

  alias HAR.DataPlane.Parser
  alias HAR.Semantic.Graph

  # ---------------------------------------------------------------------------
  # YAML-based format fixtures
  # ---------------------------------------------------------------------------

  @ansible_yaml """
  - hosts: all
    tasks:
      - name: Install nginx
        apt:
          name: nginx
          state: present
  """

  @salt_sls """
  nginx:
    pkg.installed: []
  """

  @kubernetes_yaml """
  apiVersion: v1
  kind: Pod
  metadata:
    name: nginx
  spec:
    containers:
      - name: nginx
        image: nginx:latest
  """

  @docker_compose_yaml """
  version: "3"
  services:
    web:
      image: nginx:latest
      ports:
        - "80:80"
  """

  @cloudformation_yaml """
  AWSTemplateFormatVersion: "2010-09-09"
  Resources:
    WebServer:
      Type: AWS::EC2::Instance
      Properties:
        InstanceType: t2.micro
        ImageId: ami-12345678
  """

  # ---------------------------------------------------------------------------
  # HCL fixture
  # ---------------------------------------------------------------------------

  @terraform_hcl ~S"""
  resource "aws_instance" "web" {
    ami           = "ami-12345678"
    instance_type = "t2.micro"
  }
  """

  # ---------------------------------------------------------------------------
  # Map-based format fixtures (parsers that accept structured data)
  # ---------------------------------------------------------------------------

  @puppet_manifest """
  class { 'nginx':
    ensure => present,
  }
  package { 'nginx':
    ensure => installed,
  }
  """

  @chef_recipe """
  package 'nginx' do
    action :install
  end
  """

  @pulumi_program """
  resources:
    - type: aws:ec2:Instance
      name: web
      properties:
        ami: ami-12345678
        instanceType: t2.micro
  """

  describe "parse/3 - supported formats" do
    test "dispatches :ansible to Ansible parser" do
      assert {:ok, %Graph{}} = Parser.parse(:ansible, @ansible_yaml)
    end

    test "dispatches :salt to Salt parser" do
      assert {:ok, %Graph{}} = Parser.parse(:salt, @salt_sls)
    end

    test "dispatches :terraform to Terraform parser" do
      assert {:ok, %Graph{}} = Parser.parse(:terraform, @terraform_hcl)
    end

    test "dispatches :puppet to Puppet parser" do
      assert {:ok, %Graph{}} = Parser.parse(:puppet, @puppet_manifest)
    end

    test "dispatches :chef to Chef parser" do
      assert {:ok, %Graph{}} = Parser.parse(:chef, @chef_recipe)
    end

    test "dispatches :kubernetes to Kubernetes parser" do
      assert {:ok, %Graph{}} = Parser.parse(:kubernetes, @kubernetes_yaml)
    end

    test "dispatches :docker_compose to DockerCompose parser" do
      assert {:ok, %Graph{}} = Parser.parse(:docker_compose, @docker_compose_yaml)
    end

    test "dispatches :cloudformation to CloudFormation parser" do
      assert {:ok, %Graph{}} = Parser.parse(:cloudformation, @cloudformation_yaml)
    end

    test "dispatches :pulumi to Pulumi parser" do
      assert {:ok, %Graph{}} = Parser.parse(:pulumi, @pulumi_program)
    end
  end

  describe "parse/3 - unsupported format" do
    test "returns error tuple for unknown format atom" do
      assert {:error, {:unsupported_format, :unknown_format}} =
               Parser.parse(:unknown_format, "some content")
    end
  end
end
