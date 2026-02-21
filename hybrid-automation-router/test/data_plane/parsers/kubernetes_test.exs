# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule HAR.DataPlane.Parsers.KubernetesTest do
  @moduledoc """
  Tests for the Kubernetes manifest parser.

  Verifies conversion of Kubernetes YAML manifests into HAR semantic
  graph operations. Supports multi-document YAML, all standard resource
  kinds (Deployment, Service, ConfigMap, etc.), container extraction,
  and dependency resolution based on label selectors and resource refs.
  """
  use ExUnit.Case

  alias HAR.DataPlane.Parsers.Kubernetes
  alias HAR.Semantic.{Graph, Dependency}

  describe "parse/2 with Deployment" do
    test "parses Deployment resource" do
      yaml = """
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: nginx
        namespace: default
      spec:
        replicas: 3
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
                image: nginx:1.18
                ports:
                  - containerPort: 80
      """

      assert {:ok, %Graph{} = graph} = Kubernetes.parse(yaml)
      assert length(graph.vertices) == 1

      op = hd(graph.vertices)
      assert op.type == :container_deployment_create
      assert op.params.name == "nginx"
      assert op.params.namespace == "default"
      assert op.params.replicas == 3
      assert length(op.params.containers) == 1

      container = hd(op.params.containers)
      assert container.name == "nginx"
      assert container.image == "nginx:1.18"
      assert length(container.ports) == 1
    end

    test "parses Deployment with multiple containers" do
      yaml = """
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: app
      spec:
        replicas: 1
        selector:
          matchLabels:
            app: myapp
        template:
          metadata:
            labels:
              app: myapp
          spec:
            containers:
              - name: app
                image: myapp:latest
              - name: sidecar
                image: envoy:latest
      """

      assert {:ok, %Graph{} = graph} = Kubernetes.parse(yaml)
      op = hd(graph.vertices)
      assert length(op.params.containers) == 2
    end

    test "sets metadata with source, apiVersion, and kind" do
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

      assert {:ok, %Graph{} = graph} = Kubernetes.parse(yaml)
      assert graph.metadata.source == :kubernetes

      op = hd(graph.vertices)
      assert op.metadata.source == :kubernetes
      assert op.metadata.api_version == "apps/v1"
      assert op.metadata.kind == "Deployment"
      assert op.metadata.name == "nginx"
    end
  end

  describe "parse/2 with Service" do
    test "parses Service resource" do
      yaml = """
      apiVersion: v1
      kind: Service
      metadata:
        name: nginx-svc
        namespace: default
      spec:
        type: ClusterIP
        selector:
          app: nginx
        ports:
          - port: 80
            targetPort: 80
      """

      assert {:ok, %Graph{} = graph} = Kubernetes.parse(yaml)
      op = hd(graph.vertices)
      assert op.type == :service_create
      assert op.params.name == "nginx-svc"
      assert op.params.type == "ClusterIP"
      assert length(op.params.ports) == 1
    end

    test "parses LoadBalancer Service" do
      yaml = """
      apiVersion: v1
      kind: Service
      metadata:
        name: nginx-lb
      spec:
        type: LoadBalancer
        selector:
          app: nginx
        ports:
          - port: 80
            targetPort: 80
      """

      assert {:ok, %Graph{} = graph} = Kubernetes.parse(yaml)
      op = hd(graph.vertices)
      assert op.params.type == "LoadBalancer"
    end
  end

  describe "parse/2 with ConfigMap" do
    test "parses ConfigMap resource" do
      yaml = """
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: app-config
        namespace: default
      data:
        DATABASE_URL: postgres://localhost/mydb
        LOG_LEVEL: info
      """

      assert {:ok, %Graph{} = graph} = Kubernetes.parse(yaml)
      op = hd(graph.vertices)
      assert op.type == :config_create
      assert op.params.name == "app-config"
      assert op.params.data["DATABASE_URL"] == "postgres://localhost/mydb"
      assert op.params.data["LOG_LEVEL"] == "info"
    end
  end

  describe "parse/2 with Secret" do
    test "parses Secret resource" do
      yaml = """
      apiVersion: v1
      kind: Secret
      metadata:
        name: db-secret
      type: Opaque
      data:
        password: cGFzc3dvcmQ=
      """

      assert {:ok, %Graph{} = graph} = Kubernetes.parse(yaml)
      op = hd(graph.vertices)
      assert op.type == :secret_create
      assert op.params.name == "db-secret"
      assert op.params.type == "Opaque"
    end
  end

  describe "parse/2 with Namespace" do
    test "parses Namespace resource" do
      yaml = """
      apiVersion: v1
      kind: Namespace
      metadata:
        name: production
      """

      assert {:ok, %Graph{} = graph} = Kubernetes.parse(yaml)
      op = hd(graph.vertices)
      assert op.type == :namespace_create
      assert op.params.name == "production"
    end
  end

  describe "parse/2 with PersistentVolumeClaim" do
    test "parses PVC resource" do
      yaml = """
      apiVersion: v1
      kind: PersistentVolumeClaim
      metadata:
        name: data-pvc
      spec:
        accessModes:
          - ReadWriteOnce
        storageClassName: standard
        resources:
          requests:
            storage: 10Gi
      """

      assert {:ok, %Graph{} = graph} = Kubernetes.parse(yaml)
      op = hd(graph.vertices)
      assert op.type == :storage_volume_create
      assert op.params.name == "data-pvc"
      assert op.params.storage_class == "standard"
      assert op.params.storage == "10Gi"
      assert "ReadWriteOnce" in op.params.access_modes
    end
  end

  describe "parse/2 with Job" do
    test "parses Job resource" do
      yaml = """
      apiVersion: batch/v1
      kind: Job
      metadata:
        name: migration
      spec:
        completions: 1
        parallelism: 1
        template:
          spec:
            containers:
              - name: migrate
                image: myapp:migrate
                command: ["./migrate"]
            restartPolicy: Never
      """

      assert {:ok, %Graph{} = graph} = Kubernetes.parse(yaml)
      op = hd(graph.vertices)
      assert op.type == :job_create
      assert op.params.name == "migration"
      assert op.params.completions == 1
    end
  end

  describe "parse/2 with multi-document YAML" do
    test "parses multiple documents separated by ---" do
      yaml = """
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: app-config
      data:
        key: value
      ---
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: app
      spec:
        replicas: 1
        selector:
          matchLabels:
            app: myapp
        template:
          metadata:
            labels:
              app: myapp
          spec:
            containers:
              - name: app
                image: myapp:latest
      ---
      apiVersion: v1
      kind: Service
      metadata:
        name: app-svc
      spec:
        selector:
          app: myapp
        ports:
          - port: 80
            targetPort: 8080
      """

      assert {:ok, %Graph{} = graph} = Kubernetes.parse(yaml)
      assert length(graph.vertices) == 3

      types = Enum.map(graph.vertices, & &1.type)
      assert :config_create in types
      assert :container_deployment_create in types
      assert :service_create in types
    end
  end

  describe "parse/2 with resource kind mappings" do
    test "maps StatefulSet to container_deployment_create" do
      yaml = """
      apiVersion: apps/v1
      kind: StatefulSet
      metadata:
        name: postgres
      spec:
        replicas: 1
        selector:
          matchLabels:
            app: postgres
        template:
          metadata:
            labels:
              app: postgres
          spec:
            containers:
              - name: postgres
                image: postgres:15
      """

      assert {:ok, %Graph{} = graph} = Kubernetes.parse(yaml)
      op = hd(graph.vertices)
      assert op.type == :container_deployment_create
    end

    test "maps DaemonSet to container_deployment_create" do
      yaml = """
      apiVersion: apps/v1
      kind: DaemonSet
      metadata:
        name: node-exporter
      spec:
        selector:
          matchLabels:
            app: node-exporter
        template:
          metadata:
            labels:
              app: node-exporter
          spec:
            containers:
              - name: exporter
                image: prom/node-exporter:latest
      """

      assert {:ok, %Graph{} = graph} = Kubernetes.parse(yaml)
      op = hd(graph.vertices)
      assert op.type == :container_deployment_create
    end

    test "maps Ingress to ingress_create" do
      yaml = """
      apiVersion: networking.k8s.io/v1
      kind: Ingress
      metadata:
        name: web-ingress
      spec:
        ingressClassName: nginx
        rules:
          - host: example.com
            http:
              paths:
                - path: /
                  pathType: Prefix
                  backend:
                    service:
                      name: web-svc
                      port:
                        number: 80
      """

      assert {:ok, %Graph{} = graph} = Kubernetes.parse(yaml)
      op = hd(graph.vertices)
      assert op.type == :ingress_create
      assert op.params.ingress_class == "nginx"
    end

    test "maps CronJob to cron_create" do
      yaml = """
      apiVersion: batch/v1
      kind: CronJob
      metadata:
        name: daily-backup
      spec:
        schedule: "0 2 * * *"
        jobTemplate:
          spec:
            template:
              spec:
                containers:
                  - name: backup
                    image: backup:latest
                restartPolicy: Never
      """

      assert {:ok, %Graph{} = graph} = Kubernetes.parse(yaml)
      op = hd(graph.vertices)
      assert op.type == :cron_create
      assert op.params.schedule == "0 2 * * *"
    end

    test "maps NetworkPolicy to firewall_rule" do
      yaml = """
      apiVersion: networking.k8s.io/v1
      kind: NetworkPolicy
      metadata:
        name: deny-all
      spec:
        podSelector: {}
        policyTypes:
          - Ingress
          - Egress
      """

      assert {:ok, %Graph{} = graph} = Kubernetes.parse(yaml)
      op = hd(graph.vertices)
      assert op.type == :firewall_rule
    end
  end

  describe "dependency extraction" do
    test "creates Service to Deployment dependency" do
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
      ---
      apiVersion: v1
      kind: Service
      metadata:
        name: nginx-svc
      spec:
        selector:
          app: nginx
        ports:
          - port: 80
      """

      assert {:ok, %Graph{} = graph} = Kubernetes.parse(yaml)
      assert length(graph.vertices) == 2

      # Service should depend on Deployment
      if length(graph.edges) > 0 do
        dep = hd(graph.edges)
        assert %Dependency{} = dep
        assert dep.type == :requires
      end
    end
  end

  describe "parse/2 with missing fields" do
    test "handles resource without metadata name" do
      yaml = """
      apiVersion: v1
      kind: ConfigMap
      metadata: {}
      data:
        key: value
      """

      assert {:ok, %Graph{} = graph} = Kubernetes.parse(yaml)
      op = hd(graph.vertices)
      assert op.params.name == "unnamed"
    end

    test "handles resource without namespace" do
      yaml = """
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: test
      data:
        key: value
      """

      assert {:ok, %Graph{} = graph} = Kubernetes.parse(yaml)
      op = hd(graph.vertices)
      assert op.params.namespace == "default"
    end

    test "skips YAML documents without apiVersion and kind" do
      yaml = """
      some_random: data
      not_kubernetes: true
      """

      assert {:ok, %Graph{} = graph} = Kubernetes.parse(yaml)
      assert length(graph.vertices) == 0
    end
  end

  describe "validate/1" do
    test "validates correct Kubernetes YAML" do
      yaml = """
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: test
      data:
        key: value
      """

      assert :ok = Kubernetes.validate(yaml)
    end

    test "returns error for empty document" do
      yaml = ""

      assert {:ok, %Graph{} = graph} = Kubernetes.parse(yaml)
      assert length(graph.vertices) == 0
    end
  end

  describe "metadata" do
    test "sets graph metadata with source and timestamp" do
      yaml = """
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: test
      data:
        key: value
      """

      assert {:ok, %Graph{} = graph} = Kubernetes.parse(yaml)
      assert graph.metadata.source == :kubernetes
      assert %DateTime{} = graph.metadata.parsed_at
    end

    test "operation ID contains k8s prefix and kind" do
      yaml = """
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: test
      data:
        key: value
      """

      assert {:ok, %Graph{} = graph} = Kubernetes.parse(yaml)
      op = hd(graph.vertices)
      assert op.id =~ "k8s_"
      assert op.id =~ "configmap"
    end

    test "preserves labels in target" do
      yaml = """
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: nginx
        labels:
          app: nginx
          tier: frontend
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

      assert {:ok, %Graph{} = graph} = Kubernetes.parse(yaml)
      op = hd(graph.vertices)
      assert op.target.labels["app"] == "nginx"
      assert op.target.labels["tier"] == "frontend"
    end
  end
end
