# SPDX-License-Identifier: MPL-2.0
defmodule HAR.DataPlane.Transformers.Pulumi do
  @moduledoc """
  Transformer for Pulumi YAML format.

  Converts HAR semantic graph to Pulumi declarative YAML configuration.

  ## Features

  - Multi-cloud resource generation (AWS, GCP, Azure)
  - Kubernetes resource support
  - Docker resource support
  - Dependency tracking via options.dependsOn
  - Output generation
  - Configuration variables
  """

  @behaviour HAR.DataPlane.Transformer

  alias HAR.Semantic.Graph
  require Logger

  # Semantic operation to Pulumi type mapping
  @operation_type_mappings %{
    # AWS mappings
    vm_create: "aws:ec2/instance:Instance",
    network_vpc_create: "aws:ec2/vpc:Vpc",
    network_subnet_create: "aws:ec2/subnet:Subnet",
    firewall_rule_create: "aws:ec2/securityGroup:SecurityGroup",
    network_interface_create: "aws:ec2/networkInterface:NetworkInterface",
    network_elastic_ip_create: "aws:ec2/eip:Eip",
    ssh_key_create: "aws:ec2/keyPair:KeyPair",
    storage_bucket_create: "aws:s3/bucket:Bucket",
    storage_object_create: "aws:s3/bucketObject:BucketObject",
    function_create: "aws:lambda/function:Function",
    database_create: "aws:rds/instance:Instance",
    database_cluster_create: "aws:rds/cluster:Cluster",
    database_nosql_create: "aws:dynamodb/table:Table",
    queue_create: "aws:sqs/queue:Queue",
    notification_topic_create: "aws:sns/topic:Topic",
    iam_role_create: "aws:iam/role:Role",
    iam_policy_create: "aws:iam/policy:Policy",
    user_create: "aws:iam/user:User",
    group_create: "aws:iam/group:Group",
    kubernetes_cluster_create: "aws:eks/cluster:Cluster",
    container_cluster_create: "aws:ecs/cluster:Cluster",
    container_service_create: "aws:ecs/service:Service",
    dns_zone_create: "aws:route53/zone:Zone",
    dns_record_create: "aws:route53/record:Record",
    certificate_create: "aws:acm/certificate:Certificate",
    load_balancer_create: "aws:elasticloadbalancingv2/loadBalancer:LoadBalancer",
    secret_create: "aws:secretsmanager/secret:Secret",
    encryption_key_create: "aws:kms/key:Key",

    # Kubernetes mappings (when provider is kubernetes)
    kubernetes_namespace_create: "kubernetes:core/v1:Namespace",
    container_deployment_create: "kubernetes:apps/v1:Deployment",
    container_statefulset_create: "kubernetes:apps/v1:StatefulSet",
    container_daemonset_create: "kubernetes:apps/v1:DaemonSet",
    kubernetes_service_create: "kubernetes:core/v1:Service",
    config_create: "kubernetes:core/v1:ConfigMap",
    kubernetes_ingress_create: "kubernetes:networking.k8s.io/v1:Ingress",
    kubernetes_job_create: "kubernetes:batch/v1:Job",
    kubernetes_cronjob_create: "kubernetes:batch/v1:CronJob",
    storage_pvc_create: "kubernetes:core/v1:PersistentVolumeClaim",

    # Docker mappings
    container_run: "docker:index/container:Container",
    container_image_build: "docker:index/image:Image",
    network_create: "docker:network:Network",
    storage_volume_create: "docker:volume:Volume"
  }

  # Provider-specific type overrides
  @gcp_type_mappings %{
    vm_create: "gcp:compute/instance:Instance",
    network_vpc_create: "gcp:compute/network:Network",
    network_subnet_create: "gcp:compute/subnetwork:Subnetwork",
    firewall_rule_create: "gcp:compute/firewall:Firewall",
    storage_bucket_create: "gcp:storage/bucket:Bucket",
    function_create: "gcp:cloudfunctions/function:Function",
    database_create: "gcp:sql/databaseInstance:DatabaseInstance",
    kubernetes_cluster_create: "gcp:container/cluster:Cluster",
    dns_zone_create: "gcp:dns/managedZone:ManagedZone",
    dns_record_create: "gcp:dns/recordSet:RecordSet",
    secret_create: "gcp:secretmanager/secret:Secret"
  }

  @azure_type_mappings %{
    vm_create: "azure:compute/virtualMachine:VirtualMachine",
    network_vpc_create: "azure:network/virtualNetwork:VirtualNetwork",
    network_subnet_create: "azure:network/subnet:Subnet",
    firewall_rule_create: "azure:network/networkSecurityGroup:NetworkSecurityGroup",
    storage_bucket_create: "azure:storage/account:Account",
    function_create: "azure:web/functionApp:FunctionApp",
    database_create: "azure:sql/database:Database",
    kubernetes_cluster_create: "azure:containerservice/kubernetesCluster:KubernetesCluster",
    dns_zone_create: "azure:dns/zone:Zone",
    secret_create: "azure:keyvault/secret:Secret"
  }

  @impl true
  def transform(%Graph{} = graph, opts \\ []) do
    with {:ok, sorted_ops} <- Graph.topological_sort(graph),
         {:ok, pulumi} <- operations_to_pulumi(sorted_ops, graph, opts),
         {:ok, yaml} <- format_pulumi(pulumi, opts) do
      {:ok, yaml}
    end
  end

  @impl true
  def validate(%Graph{} = graph) do
    case Graph.topological_sort(graph) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:invalid_graph, reason}}
    end
  end

  defp operations_to_pulumi(operations, graph, opts) do
    project_name = Keyword.get(opts, :project_name, "har-generated")
    runtime = Keyword.get(opts, :runtime, "yaml")
    description = Keyword.get(opts, :description, "Generated by HAR")
    provider = Keyword.get(opts, :provider, :aws)

    # Build operation_id -> resource_name lookup
    op_to_name = build_op_name_map(operations)

    # Build dependencies map
    deps_map = build_dependency_map(graph.edges, op_to_name)

    resources =
      operations
      |> Enum.map(fn op ->
        build_resource(op, provider, deps_map, opts)
      end)
      |> Enum.reject(&is_nil/1)
      |> Map.new()

    outputs = build_outputs(operations, graph, opts)
    config = build_config(graph, opts)

    pulumi = %{
      "name" => project_name,
      "runtime" => runtime,
      "description" => description
    }

    pulumi = if resources != %{}, do: Map.put(pulumi, "resources", resources), else: pulumi
    pulumi = if outputs != %{}, do: Map.put(pulumi, "outputs", outputs), else: pulumi
    pulumi = if config != %{}, do: Map.put(pulumi, "configuration", config), else: pulumi

    {:ok, pulumi}
  end

  defp build_op_name_map(operations) do
    operations
    |> Enum.map(fn op ->
      name = op.params[:name] || "resource_#{op.id}"
      {op.id, name}
    end)
    |> Map.new()
  end

  defp build_dependency_map(edges, op_to_name) do
    Enum.reduce(edges, %{}, fn dep, acc ->
      to_name = Map.get(op_to_name, dep.to)
      from_name = Map.get(op_to_name, dep.from)

      if to_name && from_name do
        Map.update(acc, to_name, [from_name], fn deps -> [from_name | deps] end)
      else
        acc
      end
    end)
  end

  defp build_resource(op, provider, deps_map, opts) do
    name = op.params[:name] || "resource_#{op.id}"
    pulumi_type = get_pulumi_type(op.type, op.target, provider, opts)

    return_nil = pulumi_type == nil or op.type == :stack_root or op.type == :provider_config

    if return_nil do
      nil
    else
      properties = build_properties(op, pulumi_type, opts)
      deps = Map.get(deps_map, name, [])

      resource = %{
        "type" => pulumi_type,
        "properties" => properties
      }

      resource =
        if deps != [] do
          Map.put(resource, "options", %{"dependsOn" => Enum.map(deps, &"${#{&1}}")})
        else
          resource
        end

      # Add protection if specified
      resource =
        if op.metadata[:protect] do
          put_in(resource, ["options", "protect"], true)
        else
          resource
        end

      {name, resource}
    end
  end

  defp get_pulumi_type(op_type, target, default_provider, _opts) do
    # Determine provider from target or use default
    provider =
      case target do
        %{provider: p} when p != :unknown -> p
        _ -> default_provider
      end

    # Get type mapping based on provider
    case provider do
      :gcp ->
        Map.get(@gcp_type_mappings, op_type) || Map.get(@operation_type_mappings, op_type)

      :azure ->
        Map.get(@azure_type_mappings, op_type) || Map.get(@operation_type_mappings, op_type)

      :kubernetes ->
        get_kubernetes_type(op_type)

      :docker ->
        get_docker_type(op_type)

      _ ->
        Map.get(@operation_type_mappings, op_type)
    end
  end

  defp get_kubernetes_type(op_type) do
    k8s_types = %{
      container_deployment_create: "kubernetes:apps/v1:Deployment",
      container_statefulset_create: "kubernetes:apps/v1:StatefulSet",
      container_daemonset_create: "kubernetes:apps/v1:DaemonSet",
      kubernetes_service_create: "kubernetes:core/v1:Service",
      kubernetes_namespace_create: "kubernetes:core/v1:Namespace",
      config_create: "kubernetes:core/v1:ConfigMap",
      secret_create: "kubernetes:core/v1:Secret",
      storage_pvc_create: "kubernetes:core/v1:PersistentVolumeClaim",
      kubernetes_ingress_create: "kubernetes:networking.k8s.io/v1:Ingress"
    }

    Map.get(k8s_types, op_type) || Map.get(@operation_type_mappings, op_type)
  end

  defp get_docker_type(op_type) do
    docker_types = %{
      container_run: "docker:index/container:Container",
      container_image_build: "docker:index/image:Image",
      network_create: "docker:index/network:Network",
      storage_volume_create: "docker:index/volume:Volume"
    }

    Map.get(docker_types, op_type) || Map.get(@operation_type_mappings, op_type)
  end

  defp build_properties(op, pulumi_type, _opts) do
    params = op.params

    cond do
      # AWS EC2 Instance
      String.contains?(pulumi_type, "ec2/instance") ->
        build_ec2_instance_props(params)

      # AWS VPC
      String.contains?(pulumi_type, "ec2/vpc") or String.contains?(pulumi_type, "compute/network") ->
        build_vpc_props(params)

      # AWS Subnet
      String.contains?(pulumi_type, "ec2/subnet") or String.contains?(pulumi_type, "subnetwork") ->
        build_subnet_props(params)

      # Security Group / Firewall
      String.contains?(pulumi_type, "securityGroup") or String.contains?(pulumi_type, "firewall") ->
        build_security_group_props(params)

      # S3 Bucket / Storage
      String.contains?(pulumi_type, "s3/bucket") or
          String.contains?(pulumi_type, "storage/bucket") ->
        build_bucket_props(params)

      # Lambda / Cloud Functions
      String.contains?(pulumi_type, "lambda/function") or
          String.contains?(pulumi_type, "cloudfunctions") ->
        build_function_props(params)

      # RDS / SQL Database
      String.contains?(pulumi_type, "rds/instance") or
          String.contains?(pulumi_type, "sql/database") ->
        build_database_props(params)

      # DynamoDB
      String.contains?(pulumi_type, "dynamodb/table") ->
        build_dynamodb_props(params)

      # SQS Queue
      String.contains?(pulumi_type, "sqs/queue") ->
        build_queue_props(params)

      # SNS Topic
      String.contains?(pulumi_type, "sns/topic") or String.contains?(pulumi_type, "pubsub/topic") ->
        build_topic_props(params)

      # IAM Role
      String.contains?(pulumi_type, "iam/role") ->
        build_iam_role_props(params)

      # Kubernetes Deployment
      String.contains?(pulumi_type, "apps/v1:Deployment") ->
        build_k8s_deployment_props(params)

      # Kubernetes Service
      String.contains?(pulumi_type, "core/v1:Service") ->
        build_k8s_service_props(params)

      # Kubernetes ConfigMap
      String.contains?(pulumi_type, "core/v1:ConfigMap") ->
        build_k8s_configmap_props(params)

      # Kubernetes Namespace
      String.contains?(pulumi_type, "core/v1:Namespace") ->
        build_k8s_namespace_props(params)

      # Docker Container
      String.contains?(pulumi_type, "docker:") and String.contains?(pulumi_type, "Container") ->
        build_docker_container_props(params)

      # Default: pass through params
      true ->
        build_generic_props(params)
    end
  end

  # Property builders for specific resource types

  defp build_ec2_instance_props(params) do
    props = %{}
    props = add_if_present(props, "ami", params[:ami] || params[:image_id])
    props = add_if_present(props, "instanceType", params[:instance_type] || params[:size])
    props = add_if_present(props, "keyName", params[:key_name] || params[:ssh_key])
    props = add_if_present(props, "subnetId", params[:subnet_id] || ref_if_name(params[:subnet]))
    props = add_if_present(props, "vpcSecurityGroupIds", params[:security_groups])
    props = add_if_present(props, "tags", build_tags(params))
    props = add_if_present(props, "userData", params[:user_data])
    props = add_if_present(props, "iamInstanceProfile", params[:iam_profile])
    props
  end

  defp build_vpc_props(params) do
    props = %{}
    props = add_if_present(props, "cidrBlock", params[:cidr_block] || params[:cidr])
    props = add_if_present(props, "enableDnsHostnames", params[:enable_dns_hostnames])
    props = add_if_present(props, "enableDnsSupport", params[:enable_dns_support])
    props = add_if_present(props, "tags", build_tags(params))
    props
  end

  defp build_subnet_props(params) do
    props = %{}
    props = add_if_present(props, "vpcId", params[:vpc_id] || ref_if_name(params[:vpc]))
    props = add_if_present(props, "cidrBlock", params[:cidr_block] || params[:cidr])
    props = add_if_present(props, "availabilityZone", params[:availability_zone] || params[:az])
    props = add_if_present(props, "mapPublicIpOnLaunch", params[:map_public_ip])
    props = add_if_present(props, "tags", build_tags(params))
    props
  end

  defp build_security_group_props(params) do
    props = %{}
    props = add_if_present(props, "vpcId", params[:vpc_id] || ref_if_name(params[:vpc]))
    props = add_if_present(props, "description", params[:description])
    props = build_ingress(props, params[:ingress] || params[:rules])
    props = build_egress(props, params[:egress])
    props = add_if_present(props, "tags", build_tags(params))
    props
  end

  defp build_bucket_props(params) do
    props = %{}
    props = add_if_present(props, "bucket", params[:name])
    props = add_if_present(props, "acl", params[:acl])
    props = add_if_present(props, "versioning", params[:versioning])
    props = add_if_present(props, "tags", build_tags(params))

    props =
      if params[:encryption] do
        Map.put(props, "serverSideEncryptionConfiguration", %{
          "rule" => %{
            "applyServerSideEncryptionByDefault" => %{
              "sseAlgorithm" => params[:encryption]
            }
          }
        })
      else
        props
      end

    props
  end

  defp build_function_props(params) do
    props = %{}
    props = add_if_present(props, "functionName", params[:name])
    props = add_if_present(props, "runtime", params[:runtime])
    props = add_if_present(props, "handler", params[:handler])
    props = add_if_present(props, "role", params[:role] || ref_if_name(params[:iam_role]))
    props = add_if_present(props, "memorySize", params[:memory] || params[:memory_size])
    props = add_if_present(props, "timeout", params[:timeout])
    props = add_if_present(props, "environment", build_environment(params[:environment]))
    props = add_if_present(props, "s3Bucket", params[:s3_bucket])
    props = add_if_present(props, "s3Key", params[:s3_key])
    props = add_if_present(props, "tags", build_tags(params))
    props
  end

  defp build_database_props(params) do
    props = %{}
    props = add_if_present(props, "identifier", params[:name])
    props = add_if_present(props, "engine", params[:engine])
    props = add_if_present(props, "engineVersion", params[:engine_version])
    props = add_if_present(props, "instanceClass", params[:instance_class] || params[:size])

    props =
      add_if_present(
        props,
        "allocatedStorage",
        params[:storage_size] || params[:allocated_storage]
      )

    props = add_if_present(props, "username", params[:username] || params[:master_username])
    props = add_if_present(props, "password", params[:password] || params[:master_password])
    props = add_if_present(props, "dbSubnetGroupName", params[:subnet_group])
    props = add_if_present(props, "vpcSecurityGroupIds", params[:security_groups])
    props = add_if_present(props, "multiAz", params[:multi_az])
    props = add_if_present(props, "publiclyAccessible", params[:publicly_accessible])
    props = add_if_present(props, "storageEncrypted", params[:encrypted])
    props = add_if_present(props, "tags", build_tags(params))
    props
  end

  defp build_dynamodb_props(params) do
    props = %{}
    props = add_if_present(props, "name", params[:name])
    props = add_if_present(props, "billingMode", params[:billing_mode])

    props =
      if params[:hash_key] do
        attrs = [%{"name" => params[:hash_key], "type" => params[:hash_key_type] || "S"}]

        attrs =
          if params[:range_key] do
            attrs ++ [%{"name" => params[:range_key], "type" => params[:range_key_type] || "S"}]
          else
            attrs
          end

        props
        |> Map.put("attributes", attrs)
        |> Map.put("hashKey", params[:hash_key])
        |> add_if_present("rangeKey", params[:range_key])
      else
        props
      end

    props = add_if_present(props, "tags", build_tags(params))
    props
  end

  defp build_queue_props(params) do
    props = %{}
    props = add_if_present(props, "name", params[:name])
    props = add_if_present(props, "fifoQueue", params[:fifo])
    props = add_if_present(props, "visibilityTimeoutSeconds", params[:visibility_timeout])
    props = add_if_present(props, "messageRetentionSeconds", params[:retention_period])
    props = add_if_present(props, "maxMessageSize", params[:max_message_size])
    props = add_if_present(props, "delaySeconds", params[:delay])
    props = add_if_present(props, "tags", build_tags(params))
    props
  end

  defp build_topic_props(params) do
    props = %{}
    props = add_if_present(props, "name", params[:name])
    props = add_if_present(props, "displayName", params[:display_name])
    props = add_if_present(props, "fifoTopic", params[:fifo])
    props = add_if_present(props, "tags", build_tags(params))
    props
  end

  defp build_iam_role_props(params) do
    props = %{}
    props = add_if_present(props, "name", params[:name])
    props = add_if_present(props, "path", params[:path])
    props = add_if_present(props, "description", params[:description])

    props =
      if params[:assume_role_policy] do
        Map.put(props, "assumeRolePolicy", Jason.encode!(params[:assume_role_policy]))
      else
        props
      end

    props = add_if_present(props, "tags", build_tags(params))
    props
  end

  defp build_k8s_deployment_props(params) do
    metadata = %{"name" => params[:name]}
    metadata = add_if_present(metadata, "namespace", params[:namespace])
    metadata = add_if_present(metadata, "labels", params[:labels])

    containers = params[:containers] || []

    container_specs =
      Enum.map(containers, fn c ->
        spec = %{"name" => c[:name] || "main", "image" => c[:image]}
        spec = add_if_present(spec, "ports", build_container_ports(c[:ports]))
        spec = add_if_present(spec, "env", build_k8s_env(c[:env]))
        spec = add_if_present(spec, "resources", c[:resources])
        spec = add_if_present(spec, "volumeMounts", c[:volume_mounts])
        spec
      end)

    spec = %{
      "replicas" => params[:replicas] || 1,
      "selector" => %{
        "matchLabels" => params[:selector] || params[:labels] || %{"app" => params[:name]}
      },
      "template" => %{
        "metadata" => %{
          "labels" => params[:labels] || %{"app" => params[:name]}
        },
        "spec" => %{
          "containers" => container_specs
        }
      }
    }

    %{"metadata" => metadata, "spec" => spec}
  end

  defp build_k8s_service_props(params) do
    metadata = %{"name" => params[:name]}
    metadata = add_if_present(metadata, "namespace", params[:namespace])
    metadata = add_if_present(metadata, "labels", params[:labels])

    spec = %{}
    spec = add_if_present(spec, "type", params[:service_type] || params[:type])
    spec = add_if_present(spec, "selector", params[:selector] || %{"app" => params[:name]})
    spec = add_if_present(spec, "ports", build_k8s_service_ports(params[:ports]))

    %{"metadata" => metadata, "spec" => spec}
  end

  defp build_k8s_configmap_props(params) do
    metadata = %{"name" => params[:name]}
    metadata = add_if_present(metadata, "namespace", params[:namespace])
    metadata = add_if_present(metadata, "labels", params[:labels])

    props = %{"metadata" => metadata}
    props = add_if_present(props, "data", params[:data])
    props = add_if_present(props, "binaryData", params[:binary_data])
    props
  end

  defp build_k8s_namespace_props(params) do
    metadata = %{"name" => params[:name]}
    metadata = add_if_present(metadata, "labels", params[:labels])

    %{"metadata" => metadata}
  end

  defp build_docker_container_props(params) do
    props = %{}
    props = add_if_present(props, "name", params[:name])
    props = add_if_present(props, "image", params[:image])
    props = add_if_present(props, "command", params[:command])
    props = add_if_present(props, "envs", build_docker_env(params[:environment]))
    props = add_if_present(props, "ports", build_docker_ports(params[:ports]))
    props = add_if_present(props, "volumes", build_docker_volumes(params[:volumes]))
    props = add_if_present(props, "networks_advanced", params[:networks])
    props = add_if_present(props, "restart", params[:restart])
    props
  end

  defp build_generic_props(params) do
    # Filter out internal params
    params
    |> Map.drop([:name, :pulumi_type])
    |> stringify_keys()
  end

  # Helper functions

  defp add_if_present(map, _key, nil), do: map
  defp add_if_present(map, _key, []), do: map
  defp add_if_present(map, _key, m) when is_map(m) and map_size(m) == 0, do: map
  defp add_if_present(map, key, value), do: Map.put(map, key, value)

  defp ref_if_name(nil), do: nil
  defp ref_if_name(name) when is_binary(name), do: "${#{name}.id}"
  defp ref_if_name(other), do: other

  defp build_tags(params) do
    tags = params[:tags] || %{}

    if params[:name] && !Map.has_key?(tags, "Name") && !Map.has_key?(tags, :Name) do
      Map.put(tags, "Name", params[:name])
    else
      tags
    end
    |> stringify_keys()
    |> case do
      t when map_size(t) == 0 -> nil
      t -> t
    end
  end

  defp build_environment(nil), do: nil

  defp build_environment(env) when is_map(env) do
    %{"variables" => stringify_keys(env)}
  end

  defp build_environment(env) when is_list(env) do
    vars =
      Enum.reduce(env, %{}, fn
        %{name: n, value: v}, acc -> Map.put(acc, n, v)
        %{"name" => n, "value" => v}, acc -> Map.put(acc, n, v)
        _, acc -> acc
      end)

    if map_size(vars) > 0, do: %{"variables" => vars}, else: nil
  end

  defp build_ingress(props, nil), do: props
  defp build_ingress(props, []), do: props

  defp build_ingress(props, rules) when is_list(rules) do
    ingress =
      Enum.map(rules, fn rule ->
        r = %{}
        r = add_if_present(r, "protocol", rule[:protocol] || "tcp")
        r = add_if_present(r, "fromPort", rule[:from_port] || rule[:port])
        r = add_if_present(r, "toPort", rule[:to_port] || rule[:port])
        r = add_if_present(r, "cidrBlocks", List.wrap(rule[:cidr] || rule[:cidr_blocks]))
        r = add_if_present(r, "description", rule[:description])
        r
      end)

    Map.put(props, "ingress", ingress)
  end

  defp build_egress(props, nil), do: props
  defp build_egress(props, []), do: props

  defp build_egress(props, rules) when is_list(rules) do
    egress =
      Enum.map(rules, fn rule ->
        r = %{}
        r = add_if_present(r, "protocol", rule[:protocol] || "-1")
        r = add_if_present(r, "fromPort", rule[:from_port] || 0)
        r = add_if_present(r, "toPort", rule[:to_port] || 0)

        r =
          add_if_present(
            r,
            "cidrBlocks",
            List.wrap(rule[:cidr] || rule[:cidr_blocks] || ["0.0.0.0/0"])
          )

        r
      end)

    Map.put(props, "egress", egress)
  end

  defp build_container_ports(nil), do: nil
  defp build_container_ports([]), do: nil

  defp build_container_ports(ports) when is_list(ports) do
    Enum.map(ports, fn
      %{containerPort: port} -> %{"containerPort" => port}
      %{container_port: port} -> %{"containerPort" => port}
      port when is_integer(port) -> %{"containerPort" => port}
      port when is_map(port) -> stringify_keys(port)
    end)
  end

  defp build_k8s_env(nil), do: nil
  defp build_k8s_env([]), do: nil

  defp build_k8s_env(env) when is_list(env) do
    Enum.map(env, fn
      %{name: n, value: v} -> %{"name" => n, "value" => v}
      %{"name" => n, "value" => v} -> %{"name" => n, "value" => v}
      e when is_map(e) -> stringify_keys(e)
    end)
  end

  defp build_k8s_env(env) when is_map(env) do
    Enum.map(env, fn {k, v} -> %{"name" => to_string(k), "value" => v} end)
  end

  defp build_k8s_service_ports(nil), do: nil
  defp build_k8s_service_ports([]), do: nil

  defp build_k8s_service_ports(ports) when is_list(ports) do
    Enum.map(ports, fn
      %{port: port, targetPort: target} ->
        %{"port" => port, "targetPort" => target}

      %{port: port, target_port: target} ->
        %{"port" => port, "targetPort" => target}

      port when is_integer(port) ->
        %{"port" => port, "targetPort" => port}

      port when is_map(port) ->
        stringify_keys(port)
    end)
  end

  defp build_docker_env(nil), do: nil

  defp build_docker_env(env) when is_map(env) do
    Enum.map(env, fn {k, v} -> "#{k}=#{v}" end)
  end

  defp build_docker_env(env) when is_list(env), do: env

  defp build_docker_ports(nil), do: nil
  defp build_docker_ports([]), do: nil

  defp build_docker_ports(ports) when is_list(ports) do
    Enum.map(ports, fn
      %{internal: internal, external: external} ->
        %{"internal" => internal, "external" => external}

      %{target: target, published: published} ->
        %{"internal" => target, "external" => published}

      port when is_integer(port) ->
        %{"internal" => port, "external" => port}

      port when is_binary(port) ->
        case String.split(port, ":") do
          [ext, int] ->
            %{"internal" => String.to_integer(int), "external" => String.to_integer(ext)}

          [p] ->
            %{"internal" => String.to_integer(p), "external" => String.to_integer(p)}
        end

      port when is_map(port) ->
        stringify_keys(port)
    end)
  end

  defp build_docker_volumes(nil), do: nil
  defp build_docker_volumes([]), do: nil

  defp build_docker_volumes(volumes) when is_list(volumes) do
    Enum.map(volumes, fn
      %{host_path: host, container_path: container} ->
        %{"hostPath" => host, "containerPath" => container}

      %{source: source, target: target} ->
        %{"hostPath" => source, "containerPath" => target}

      vol when is_binary(vol) ->
        case String.split(vol, ":") do
          [host, container] -> %{"hostPath" => host, "containerPath" => container}
          [path] -> %{"containerPath" => path}
        end

      vol when is_map(vol) ->
        stringify_keys(vol)
    end)
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), stringify_value(v)}
      {k, v} -> {k, stringify_value(v)}
    end)
  end

  defp stringify_keys(other), do: other

  defp stringify_value(v) when is_map(v), do: stringify_keys(v)
  defp stringify_value(v) when is_list(v), do: Enum.map(v, &stringify_value/1)
  defp stringify_value(v), do: v

  defp build_outputs(_operations, graph, _opts) do
    # Extract outputs from graph metadata
    graph.metadata[:outputs] || %{}
  end

  defp build_config(graph, _opts) do
    # Extract config from graph metadata
    graph.metadata[:config] || %{}
  end

  defp format_pulumi(pulumi, _opts) do
    yaml = """
    # Generated by HAR (Hybrid Automation Router)
    # Pulumi YAML Configuration
    """

    case HAR.Utils.YamlFormatter.to_yaml(pulumi) do
      {:ok, yaml_content} -> {:ok, yaml <> yaml_content}
      {:error, reason} -> {:error, reason}
    end
  end
end
