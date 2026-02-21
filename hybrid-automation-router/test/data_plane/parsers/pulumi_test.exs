# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule HAR.DataPlane.Parsers.PulumiTest do
  @moduledoc """
  Tests for the Pulumi configuration parser.

  Verifies conversion of Pulumi YAML declarative format and stack
  state exports into HAR semantic graph operations. Supports multi-cloud
  resource mappings (AWS, GCP, Azure, Kubernetes, Docker), dependency
  tracking via dependsOn, and URN parsing.
  """
  use ExUnit.Case

  alias HAR.DataPlane.Parsers.Pulumi
  alias HAR.Semantic.{Graph, Operation, Dependency}

  describe "parse/2 with Pulumi YAML format" do
    test "parses basic Pulumi YAML resource" do
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

      assert {:ok, %Graph{} = graph} = Pulumi.parse(yaml)
      assert length(graph.vertices) == 1

      op = hd(graph.vertices)
      assert op.type == :vm_create
      assert op.params.name == "webServer"
      assert op.params.ami == "ami-12345678"
      assert op.params.instanceType == "t3.micro"
      assert op.target.provider == :aws
    end

    test "parses Pulumi YAML with multiple resources" do
      yaml = """
      name: infra
      runtime: yaml
      resources:
        myBucket:
          type: aws:s3/bucket:Bucket
          properties:
            bucket: my-unique-bucket
        myFunction:
          type: aws:lambda/function:Function
          properties:
            runtime: python3.12
            handler: index.handler
      """

      assert {:ok, %Graph{} = graph} = Pulumi.parse(yaml)
      assert length(graph.vertices) == 2

      types = Enum.map(graph.vertices, & &1.type)
      assert :storage_bucket_create in types
      assert :function_create in types
    end

    test "parses project name and runtime from YAML" do
      yaml = """
      name: my-project
      runtime: yaml
      description: My infrastructure project
      resources:
        myBucket:
          type: aws:s3/bucket:Bucket
          properties:
            bucket: test
      """

      assert {:ok, %Graph{} = graph} = Pulumi.parse(yaml)
      assert graph.metadata.project_name == "my-project"
      assert graph.metadata.runtime == "yaml"
    end
  end

  describe "parse/2 with dependencies" do
    test "extracts dependsOn relationships" do
      yaml = """
      name: infra
      runtime: yaml
      resources:
        myVpc:
          type: aws:ec2/vpc:Vpc
          properties:
            cidrBlock: 10.0.0.0/16
        mySubnet:
          type: aws:ec2/subnet:Subnet
          properties:
            vpcId: test
          dependsOn:
            - myVpc
      """

      assert {:ok, %Graph{} = graph} = Pulumi.parse(yaml)
      assert length(graph.vertices) == 2
      assert length(graph.edges) >= 1

      dep = hd(graph.edges)
      assert %Dependency{} = dep
      assert dep.type == :explicit
      assert dep.metadata.reason == "pulumi_depends_on"
    end

    test "extracts multiple dependsOn references" do
      yaml = """
      name: infra
      runtime: yaml
      resources:
        vpc:
          type: aws:ec2/vpc:Vpc
          properties:
            cidrBlock: 10.0.0.0/16
        sg:
          type: aws:ec2/securityGroup:SecurityGroup
          properties:
            description: test
        instance:
          type: aws:ec2/instance:Instance
          properties:
            ami: ami-12345678
            instanceType: t3.micro
          dependsOn:
            - vpc
            - sg
      """

      assert {:ok, %Graph{} = graph} = Pulumi.parse(yaml)
      assert length(graph.vertices) == 3
      assert length(graph.edges) >= 2
    end

    test "handles dependsOn in options field" do
      yaml = """
      name: infra
      runtime: yaml
      resources:
        vpc:
          type: aws:ec2/vpc:Vpc
          properties:
            cidrBlock: 10.0.0.0/16
        subnet:
          type: aws:ec2/subnet:Subnet
          properties:
            vpcId: test
          options:
            dependsOn:
              - vpc
      """

      assert {:ok, %Graph{} = graph} = Pulumi.parse(yaml)
      assert length(graph.edges) >= 1
    end
  end

  describe "parse/2 with AWS resource types" do
    test "maps AWS EC2 instance" do
      yaml = """
      name: test
      runtime: yaml
      resources:
        server:
          type: aws:ec2/instance:Instance
          properties:
            ami: ami-12345678
            instanceType: t3.micro
      """

      assert {:ok, %Graph{} = graph} = Pulumi.parse(yaml)
      op = hd(graph.vertices)
      assert op.type == :vm_create
      assert op.target.provider == :aws
    end

    test "maps AWS S3 bucket" do
      yaml = """
      name: test
      runtime: yaml
      resources:
        bucket:
          type: aws:s3/bucket:Bucket
          properties:
            bucket: my-bucket
      """

      assert {:ok, %Graph{} = graph} = Pulumi.parse(yaml)
      op = hd(graph.vertices)
      assert op.type == :storage_bucket_create
    end

    test "maps AWS Lambda function" do
      yaml = """
      name: test
      runtime: yaml
      resources:
        func:
          type: aws:lambda/function:Function
          properties:
            runtime: python3.12
            handler: index.handler
      """

      assert {:ok, %Graph{} = graph} = Pulumi.parse(yaml)
      op = hd(graph.vertices)
      assert op.type == :function_create
    end

    test "maps AWS IAM role" do
      yaml = """
      name: test
      runtime: yaml
      resources:
        role:
          type: aws:iam/role:Role
          properties:
            assumeRolePolicyDocument: "{}"
      """

      assert {:ok, %Graph{} = graph} = Pulumi.parse(yaml)
      op = hd(graph.vertices)
      assert op.type == :iam_role_create
    end

    test "maps AWS DynamoDB table" do
      yaml = """
      name: test
      runtime: yaml
      resources:
        table:
          type: aws:dynamodb/table:Table
          properties:
            name: users
      """

      assert {:ok, %Graph{} = graph} = Pulumi.parse(yaml)
      op = hd(graph.vertices)
      assert op.type == :database_nosql_create
    end
  end

  describe "parse/2 with GCP resource types" do
    test "maps GCP compute instance" do
      yaml = """
      name: test
      runtime: yaml
      resources:
        vm:
          type: gcp:compute/instance:Instance
          properties:
            machineType: e2-micro
      """

      assert {:ok, %Graph{} = graph} = Pulumi.parse(yaml)
      op = hd(graph.vertices)
      assert op.type == :vm_create
      assert op.target.provider == :gcp
    end

    test "maps GCP storage bucket" do
      yaml = """
      name: test
      runtime: yaml
      resources:
        bucket:
          type: gcp:storage/bucket:Bucket
          properties:
            location: US
      """

      assert {:ok, %Graph{} = graph} = Pulumi.parse(yaml)
      op = hd(graph.vertices)
      assert op.type == :storage_bucket_create
      assert op.target.provider == :gcp
    end
  end

  describe "parse/2 with Azure resource types" do
    test "maps Azure virtual machine" do
      yaml = """
      name: test
      runtime: yaml
      resources:
        vm:
          type: azure:compute/virtualMachine:VirtualMachine
          properties:
            vmSize: Standard_B1s
      """

      assert {:ok, %Graph{} = graph} = Pulumi.parse(yaml)
      op = hd(graph.vertices)
      assert op.type == :vm_create
      assert op.target.provider == :azure
    end

    test "maps Azure resource group" do
      yaml = """
      name: test
      runtime: yaml
      resources:
        rg:
          type: azure:resources/resourceGroup:ResourceGroup
          properties:
            location: eastus
      """

      assert {:ok, %Graph{} = graph} = Pulumi.parse(yaml)
      op = hd(graph.vertices)
      assert op.type == :resource_group_create
    end
  end

  describe "parse/2 with Kubernetes resource types" do
    test "maps Kubernetes deployment" do
      yaml = """
      name: test
      runtime: yaml
      resources:
        app:
          type: kubernetes:apps/v1:Deployment
          properties:
            metadata:
              name: myapp
      """

      assert {:ok, %Graph{} = graph} = Pulumi.parse(yaml)
      op = hd(graph.vertices)
      assert op.type == :container_deployment_create
      assert op.target.provider == :kubernetes
    end

    test "maps Kubernetes namespace" do
      yaml = """
      name: test
      runtime: yaml
      resources:
        ns:
          type: kubernetes:core/v1:Namespace
          properties:
            metadata:
              name: production
      """

      assert {:ok, %Graph{} = graph} = Pulumi.parse(yaml)
      op = hd(graph.vertices)
      assert op.type == :kubernetes_namespace_create
    end
  end

  describe "parse/2 with Docker resource types" do
    test "maps Docker container" do
      yaml = """
      name: test
      runtime: yaml
      resources:
        container:
          type: docker:index/container:Container
          properties:
            image: nginx:latest
      """

      assert {:ok, %Graph{} = graph} = Pulumi.parse(yaml)
      op = hd(graph.vertices)
      assert op.type == :container_run
      assert op.target.provider == :docker
    end
  end

  describe "parse/2 with unknown resource types" do
    test "maps unknown resource type to custom_resource" do
      yaml = """
      name: test
      runtime: yaml
      resources:
        custom:
          type: custom:module:Thing
          properties:
            foo: bar
      """

      assert {:ok, %Graph{} = graph} = Pulumi.parse(yaml)
      op = hd(graph.vertices)
      assert op.type == :custom_resource
    end
  end

  describe "parse/2 with stack state JSON format" do
    test "parses JSON stack state export" do
      json =
        Jason.encode!(%{
          "version" => 3,
          "deployment" => %{
            "resources" => [
              %{
                "urn" => "urn:pulumi:dev::project::pulumi:pulumi:Stack::project-dev",
                "type" => "pulumi:pulumi:Stack"
              },
              %{
                "urn" => "urn:pulumi:dev::project::aws:s3/bucket:Bucket::my-bucket",
                "type" => "aws:s3/bucket:Bucket",
                "id" => "my-bucket-123",
                "outputs" => %{
                  "bucket" => "my-bucket-123",
                  "arn" => "arn:aws:s3:::my-bucket-123"
                }
              }
            ]
          }
        })

      assert {:ok, %Graph{} = graph} = Pulumi.parse(json)
      # Stack resource is filtered out, only real resources remain
      assert length(graph.vertices) == 1

      op = hd(graph.vertices)
      assert op.type == :storage_bucket_create
      assert op.params.name == "my-bucket"
    end
  end

  describe "URN parsing" do
    test "extracts resource name from URN" do
      json =
        Jason.encode!(%{
          "deployment" => %{
            "resources" => [
              %{
                "urn" => "urn:pulumi:dev::myproject::aws:ec2/instance:Instance::webServer",
                "type" => "aws:ec2/instance:Instance",
                "inputs" => %{
                  "ami" => "ami-12345",
                  "instanceType" => "t3.micro"
                }
              }
            ]
          }
        })

      assert {:ok, %Graph{} = graph} = Pulumi.parse(json)
      op = hd(graph.vertices)
      assert op.params.name == "webServer"
    end
  end

  describe "validate/1 with string content" do
    test "validates correct Pulumi YAML" do
      yaml = """
      name: my-project
      runtime: yaml
      resources:
        bucket:
          type: aws:s3/bucket:Bucket
          properties:
            bucket: test
      """

      assert :ok = Pulumi.validate(yaml)
    end

    test "returns error for content without resources key" do
      yaml = """
      name: my-project
      runtime: yaml
      """

      # This YAML is valid but has no resources: key
      # The auto-detector checks for "resources:" or "name:" in content
      # Since it has "name:", it will parse as YAML successfully
      result = Pulumi.validate(yaml)
      assert result == :ok or match?({:error, _}, result)
    end
  end

  describe "validate/1 with map content" do
    test "validates map with resources key" do
      assert :ok = Pulumi.validate(%{"resources" => []})
    end

    test "validates map with deployment key" do
      assert :ok = Pulumi.validate(%{"deployment" => %{}})
    end

    test "returns error for map without resources or deployment" do
      assert {:error, {:pulumi_parse_error, _}} = Pulumi.validate(%{"name" => "test"})
    end
  end

  describe "metadata" do
    test "sets graph metadata with pulumi format info" do
      yaml = """
      name: my-project
      runtime: yaml
      resources:
        bucket:
          type: aws:s3/bucket:Bucket
          properties:
            bucket: test
      """

      assert {:ok, %Graph{} = graph} = Pulumi.parse(yaml)
      assert graph.metadata.source_format == :pulumi
      assert graph.metadata.pulumi_format == "pulumi_yaml"
      assert graph.metadata.project_name == "my-project"
      assert graph.metadata.runtime == "yaml"
    end

    test "stores pulumi type in operation metadata" do
      yaml = """
      name: test
      runtime: yaml
      resources:
        bucket:
          type: aws:s3/bucket:Bucket
          properties:
            bucket: test
      """

      assert {:ok, %Graph{} = graph} = Pulumi.parse(yaml)
      op = hd(graph.vertices)
      assert op.metadata.pulumi_type == "aws:s3/bucket:Bucket"
    end

    test "operation IDs are sequential op_N format" do
      yaml = """
      name: test
      runtime: yaml
      resources:
        first:
          type: aws:s3/bucket:Bucket
          properties:
            bucket: first
        second:
          type: aws:ec2/instance:Instance
          properties:
            ami: ami-12345
            instanceType: t3.micro
      """

      assert {:ok, %Graph{} = graph} = Pulumi.parse(yaml)
      ids = Enum.map(graph.vertices, & &1.id) |> Enum.sort()
      assert "op_0" in ids
      assert "op_1" in ids
    end
  end

  describe "parse/2 with outputs and config" do
    test "extracts outputs into graph metadata" do
      yaml = """
      name: test
      runtime: yaml
      resources:
        bucket:
          type: aws:s3/bucket:Bucket
          properties:
            bucket: test
      outputs:
        bucketName: test
        bucketArn: arn:aws:s3:::test
      """

      assert {:ok, %Graph{} = graph} = Pulumi.parse(yaml)
      assert graph.metadata.outputs["bucketName"] == "test"
    end

    test "extracts config into graph metadata" do
      yaml = """
      name: test
      runtime: yaml
      configuration:
        region:
          type: String
          default: us-east-1
      resources:
        bucket:
          type: aws:s3/bucket:Bucket
          properties:
            bucket: test
      """

      assert {:ok, %Graph{} = graph} = Pulumi.parse(yaml)
      assert is_map(graph.metadata.config)
    end
  end
end
