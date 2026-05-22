# SPDX-License-Identifier: MPL-2.0
defmodule HAR.DataPlane.Transformers.PulumiTest do
  @moduledoc """
  Tests for the Pulumi YAML transformer.

  Verifies that semantic graph operations are correctly converted to
  Pulumi declarative YAML configuration with multi-cloud resource types
  (AWS, GCP, Azure), Kubernetes support, Docker support, dependency
  tracking via options.dependsOn, and output generation.
  """

  use ExUnit.Case, async: true

  alias HAR.DataPlane.Transformers.Pulumi
  alias HAR.Semantic.{Graph, Operation, Dependency}

  describe "transform/2 - AWS resources" do
    test "transforms vm_create to aws:ec2/instance:Instance" do
      graph =
        build_graph([
          Operation.new(:vm_create, %{
            name: "web-server",
            ami: "ami-12345678",
            instance_type: "t3.micro"
          })
        ])

      assert {:ok, output} = Pulumi.transform(graph, provider: :aws)
      assert is_binary(output)
      assert output =~ "aws:ec2/instance:Instance"
      assert output =~ "web-server"
    end

    test "transforms storage_bucket_create to aws:s3/bucket:Bucket" do
      graph =
        build_graph([
          Operation.new(:storage_bucket_create, %{
            name: "data-bucket"
          })
        ])

      assert {:ok, output} = Pulumi.transform(graph, provider: :aws)
      assert output =~ "aws:s3/bucket:Bucket"
    end

    test "transforms function_create to aws:lambda/function:Function" do
      graph =
        build_graph([
          Operation.new(:function_create, %{
            name: "event-handler",
            runtime: "python3.12",
            handler: "main.handler"
          })
        ])

      assert {:ok, output} = Pulumi.transform(graph, provider: :aws)
      assert output =~ "aws:lambda/function:Function"
    end
  end

  describe "transform/2 - GCP resources" do
    test "transforms vm_create to gcp:compute/instance:Instance for GCP" do
      graph =
        build_graph([
          Operation.new(:vm_create, %{
            name: "gcp-server",
            instance_type: "e2-micro"
          })
        ])

      assert {:ok, output} = Pulumi.transform(graph, provider: :gcp)
      assert output =~ "gcp:compute/instance:Instance"
    end
  end

  describe "transform/2 - Azure resources" do
    test "transforms vm_create to azure:compute for Azure" do
      graph =
        build_graph([
          Operation.new(:vm_create, %{
            name: "azure-server",
            instance_type: "Standard_B2s"
          })
        ])

      assert {:ok, output} = Pulumi.transform(graph, provider: :azure)
      assert output =~ "azure:compute"
    end
  end

  describe "transform/2 - Kubernetes resources" do
    test "transforms container_deployment_create to k8s Deployment" do
      graph =
        build_graph([
          Operation.new(:container_deployment_create, %{
            name: "k8s-app",
            replicas: 2,
            containers: [%{name: "app", image: "myapp:v1"}]
          })
        ])

      assert {:ok, output} = Pulumi.transform(graph, provider: :kubernetes)
      assert output =~ "kubernetes:apps/v1:Deployment"
    end
  end

  describe "transform/2 - project metadata" do
    test "includes project name in output" do
      graph =
        build_graph([
          Operation.new(:storage_bucket_create, %{name: "test"})
        ])

      assert {:ok, output} = Pulumi.transform(graph, project_name: "my-infra")
      assert output =~ "my-infra"
    end

    test "uses default project name when not specified" do
      graph =
        build_graph([
          Operation.new(:storage_bucket_create, %{name: "test"})
        ])

      assert {:ok, output} = Pulumi.transform(graph)
      assert output =~ "har-generated"
    end

    test "includes runtime in output" do
      graph =
        build_graph([
          Operation.new(:storage_bucket_create, %{name: "test"})
        ])

      assert {:ok, output} = Pulumi.transform(graph)
      assert output =~ "yaml"
    end
  end

  describe "transform/2 - dependencies" do
    test "generates dependsOn from graph edges" do
      vpc_op =
        Operation.new(:network_vpc_create, %{name: "vpc", cidr_block: "10.0.0.0/16"}, id: "op1")

      subnet_op =
        Operation.new(:network_subnet_create, %{name: "subnet", cidr_block: "10.0.1.0/24"},
          id: "op2"
        )

      dep = Dependency.new("op1", "op2", :requires)

      graph =
        Graph.new(
          vertices: [vpc_op, subnet_op],
          edges: [dep],
          metadata: %{source: :test}
        )

      assert {:ok, output} = Pulumi.transform(graph, provider: :aws)
      assert is_binary(output)
      assert output =~ "dependsOn"
    end
  end

  describe "transform/2 - multiple resources" do
    test "produces YAML with multiple resources" do
      graph =
        build_graph([
          Operation.new(:network_vpc_create, %{name: "vpc", cidr_block: "10.0.0.0/16"}),
          Operation.new(:storage_bucket_create, %{name: "data"}),
          Operation.new(:function_create, %{
            name: "handler",
            runtime: "nodejs20.x",
            handler: "index.handler"
          })
        ])

      assert {:ok, output} = Pulumi.transform(graph, provider: :aws)
      assert output =~ "resources"
    end
  end

  describe "transform/2 - HAR header" do
    test "includes HAR and Pulumi generation comment" do
      graph =
        build_graph([
          Operation.new(:storage_bucket_create, %{name: "test"})
        ])

      assert {:ok, output} = Pulumi.transform(graph)
      assert output =~ "Generated by HAR"
      assert output =~ "Pulumi"
    end
  end

  describe "validate/1" do
    test "validates a well-formed graph" do
      graph =
        build_graph([
          Operation.new(:vm_create, %{name: "server", instance_type: "t3.micro"})
        ])

      assert :ok = Pulumi.validate(graph)
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
