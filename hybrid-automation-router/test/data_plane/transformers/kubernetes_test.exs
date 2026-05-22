# SPDX-License-Identifier: MPL-2.0
defmodule HAR.DataPlane.Transformers.KubernetesTest do
  @moduledoc """
  Tests for the Kubernetes manifest transformer.

  Verifies that semantic graph operations are correctly converted to
  Kubernetes YAML manifests including Deployments, Services, ConfigMaps,
  Secrets, PVCs, Jobs, CronJobs, and RBAC resources. Multi-document
  YAML output is separated by ---.
  """

  use ExUnit.Case, async: true

  alias HAR.DataPlane.Transformers.Kubernetes
  alias HAR.Semantic.{Graph, Operation}

  describe "transform/2 - Deployment" do
    test "transforms container_deployment_create to Deployment manifest" do
      graph =
        build_graph([
          Operation.new(:container_deployment_create, %{
            name: "web-app",
            replicas: 3,
            containers: [%{name: "app", image: "nginx:latest", ports: [80]}]
          })
        ])

      assert {:ok, output} = Kubernetes.transform(graph)
      assert is_binary(output)
      assert output =~ "Deployment"
      assert output =~ "web-app"
      assert output =~ "nginx:latest"
      assert output =~ "apps/v1"
    end

    test "uses default namespace when not specified" do
      graph =
        build_graph([
          Operation.new(:container_deployment_create, %{
            name: "api",
            containers: [%{name: "api", image: "api:v1"}]
          })
        ])

      assert {:ok, output} = Kubernetes.transform(graph)
      assert output =~ "default"
    end

    test "uses custom namespace from opts" do
      graph =
        build_graph([
          Operation.new(:container_deployment_create, %{
            name: "api",
            containers: [%{name: "api", image: "api:v1"}]
          })
        ])

      assert {:ok, output} = Kubernetes.transform(graph, namespace: "production")
      assert output =~ "production"
    end
  end

  describe "transform/2 - Service" do
    test "transforms service_create to Service manifest" do
      graph =
        build_graph([
          Operation.new(:service_create, %{
            name: "web-svc",
            type: "ClusterIP",
            ports: [%{port: 80, target_port: 8080}]
          })
        ])

      assert {:ok, output} = Kubernetes.transform(graph)
      assert is_binary(output)
      assert output =~ "Service"
      assert output =~ "web-svc"
      assert output =~ "ClusterIP"
    end
  end

  describe "transform/2 - ConfigMap" do
    test "transforms config_create to ConfigMap manifest" do
      graph =
        build_graph([
          Operation.new(:config_create, %{
            name: "app-config",
            data: %{DATABASE_URL: "postgres://localhost/db"}
          })
        ])

      assert {:ok, output} = Kubernetes.transform(graph)
      assert is_binary(output)
      assert output =~ "ConfigMap"
      assert output =~ "app-config"
    end
  end

  describe "transform/2 - Secret" do
    test "transforms secret_create to Secret manifest" do
      graph =
        build_graph([
          Operation.new(:secret_create, %{
            name: "db-credentials",
            type: "Opaque",
            string_data: %{"password" => "s3cret"}
          })
        ])

      assert {:ok, output} = Kubernetes.transform(graph)
      assert is_binary(output)
      assert output =~ "Secret"
      assert output =~ "db-credentials"
      assert output =~ "Opaque"
    end
  end

  describe "transform/2 - PersistentVolumeClaim" do
    test "transforms storage_volume_create to PVC manifest" do
      graph =
        build_graph([
          Operation.new(:storage_volume_create, %{
            name: "data-vol",
            storage: "10Gi",
            access_modes: ["ReadWriteOnce"]
          })
        ])

      assert {:ok, output} = Kubernetes.transform(graph)
      assert is_binary(output)
      assert output =~ "PersistentVolumeClaim"
      assert output =~ "data-vol"
      assert output =~ "10Gi"
    end
  end

  describe "transform/2 - CronJob" do
    test "transforms cron_create to CronJob manifest" do
      graph =
        build_graph([
          Operation.new(:cron_create, %{
            name: "backup-job",
            schedule: "0 2 * * *",
            containers: [%{name: "backup", image: "backup-tool:latest"}]
          })
        ])

      assert {:ok, output} = Kubernetes.transform(graph)
      assert is_binary(output)
      assert output =~ "CronJob"
      assert output =~ "backup-job"
      assert output =~ "0 2 * * *"
    end
  end

  describe "transform/2 - multiple resources" do
    test "produces multi-document YAML separated by ---" do
      graph =
        build_graph([
          Operation.new(:container_deployment_create, %{
            name: "web",
            containers: [%{name: "web", image: "nginx:latest"}]
          }),
          Operation.new(:service_create, %{
            name: "web-svc",
            ports: [%{port: 80, target_port: 80}]
          })
        ])

      assert {:ok, output} = Kubernetes.transform(graph)
      assert is_binary(output)
      assert output =~ "---"
      assert output =~ "Deployment"
      assert output =~ "Service"
    end
  end

  describe "transform/2 - HAR header" do
    test "includes HAR and Kubernetes generation comment" do
      graph =
        build_graph([
          Operation.new(:namespace_create, %{name: "test-ns"})
        ])

      assert {:ok, output} = Kubernetes.transform(graph)
      assert output =~ "Generated by HAR"
      assert output =~ "Kubernetes"
    end
  end

  describe "validate/1" do
    test "validates a well-formed graph" do
      graph =
        build_graph([
          Operation.new(:container_deployment_create, %{
            name: "app",
            containers: [%{name: "app", image: "app:v1"}]
          })
        ])

      assert :ok = Kubernetes.validate(graph)
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
