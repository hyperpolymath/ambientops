# SPDX-License-Identifier: MPL-2.0
defmodule HAR.DataPlane.Parsers.Pulumi do
  @moduledoc """
  Parser for Pulumi configurations (YAML format and stack state).

  Converts Pulumi infrastructure definitions into HAR semantic graph.

  ## Supported Formats

  - Pulumi YAML declarative format (Pulumi.yaml)
  - Pulumi stack state export (JSON)

  ## Features

  - Multi-cloud resource mapping (AWS, GCP, Azure, etc.)
  - Provider configuration extraction
  - Resource dependency tracking via dependsOn
  - Variable and output extraction
  - Config value handling
  """

  @behaviour HAR.DataPlane.Parser

  alias HAR.Semantic.{Graph, Operation, Dependency}
  require Logger

  # Resource type to semantic operation mapping
  # Pulumi uses URN format: urn:pulumi:stack::project::provider:module:Type::name
  @resource_type_mappings %{
    # AWS Resources
    "aws:ec2/instance:Instance" => :vm_create,
    "aws:ec2/vpc:Vpc" => :network_vpc_create,
    "aws:ec2/subnet:Subnet" => :network_subnet_create,
    "aws:ec2/securityGroup:SecurityGroup" => :firewall_rule_create,
    "aws:ec2/networkInterface:NetworkInterface" => :network_interface_create,
    "aws:ec2/eip:Eip" => :network_elastic_ip_create,
    "aws:ec2/keyPair:KeyPair" => :ssh_key_create,
    "aws:s3/bucket:Bucket" => :storage_bucket_create,
    "aws:s3/bucketObject:BucketObject" => :storage_object_create,
    "aws:s3/bucketPolicy:BucketPolicy" => :storage_bucket_policy_create,
    "aws:lambda/function:Function" => :function_create,
    "aws:lambda/permission:Permission" => :function_permission_create,
    "aws:lambda/eventSourceMapping:EventSourceMapping" => :function_event_mapping_create,
    "aws:rds/instance:Instance" => :database_create,
    "aws:rds/cluster:Cluster" => :database_cluster_create,
    "aws:rds/subnetGroup:SubnetGroup" => :database_subnet_group_create,
    "aws:dynamodb/table:Table" => :database_nosql_create,
    "aws:sqs/queue:Queue" => :queue_create,
    "aws:sns/topic:Topic" => :notification_topic_create,
    "aws:sns/topicSubscription:TopicSubscription" => :notification_subscription_create,
    "aws:iam/role:Role" => :iam_role_create,
    "aws:iam/policy:Policy" => :iam_policy_create,
    "aws:iam/rolePolicyAttachment:RolePolicyAttachment" => :iam_role_policy_attach,
    "aws:iam/user:User" => :user_create,
    "aws:iam/group:Group" => :group_create,
    "aws:iam/instanceProfile:InstanceProfile" => :iam_instance_profile_create,
    "aws:eks/cluster:Cluster" => :kubernetes_cluster_create,
    "aws:eks/nodeGroup:NodeGroup" => :kubernetes_node_group_create,
    "aws:ecs/cluster:Cluster" => :container_cluster_create,
    "aws:ecs/service:Service" => :container_service_create,
    "aws:ecs/taskDefinition:TaskDefinition" => :container_task_create,
    "aws:route53/zone:Zone" => :dns_zone_create,
    "aws:route53/record:Record" => :dns_record_create,
    "aws:acm/certificate:Certificate" => :certificate_create,
    "aws:cloudwatch/logGroup:LogGroup" => :logging_group_create,
    "aws:cloudwatch/metricAlarm:MetricAlarm" => :monitoring_alarm_create,
    "aws:elasticloadbalancingv2/loadBalancer:LoadBalancer" => :load_balancer_create,
    "aws:elasticloadbalancingv2/targetGroup:TargetGroup" => :load_balancer_target_group_create,
    "aws:elasticloadbalancingv2/listener:Listener" => :load_balancer_listener_create,
    "aws:apigateway/restApi:RestApi" => :api_gateway_create,
    "aws:apigatewayv2/api:Api" => :api_gateway_v2_create,
    "aws:secretsmanager/secret:Secret" => :secret_create,
    "aws:ssm/parameter:Parameter" => :config_parameter_create,
    "aws:kms/key:Key" => :encryption_key_create,

    # GCP Resources
    "gcp:compute/instance:Instance" => :vm_create,
    "gcp:compute/network:Network" => :network_vpc_create,
    "gcp:compute/subnetwork:Subnetwork" => :network_subnet_create,
    "gcp:compute/firewall:Firewall" => :firewall_rule_create,
    "gcp:compute/address:Address" => :network_elastic_ip_create,
    "gcp:storage/bucket:Bucket" => :storage_bucket_create,
    "gcp:storage/bucketObject:BucketObject" => :storage_object_create,
    "gcp:cloudfunctions/function:Function" => :function_create,
    "gcp:sql/databaseInstance:DatabaseInstance" => :database_create,
    "gcp:sql/database:Database" => :database_schema_create,
    "gcp:container/cluster:Cluster" => :kubernetes_cluster_create,
    "gcp:container/nodePool:NodePool" => :kubernetes_node_group_create,
    "gcp:cloudrun/service:Service" => :container_service_create,
    "gcp:pubsub/topic:Topic" => :notification_topic_create,
    "gcp:pubsub/subscription:Subscription" => :notification_subscription_create,
    "gcp:dns/managedZone:ManagedZone" => :dns_zone_create,
    "gcp:dns/recordSet:RecordSet" => :dns_record_create,
    "gcp:iam/serviceAccount:ServiceAccount" => :iam_service_account_create,
    "gcp:secretmanager/secret:Secret" => :secret_create,
    "gcp:kms/cryptoKey:CryptoKey" => :encryption_key_create,

    # Azure Resources
    "azure:compute/virtualMachine:VirtualMachine" => :vm_create,
    "azure:network/virtualNetwork:VirtualNetwork" => :network_vpc_create,
    "azure:network/subnet:Subnet" => :network_subnet_create,
    "azure:network/networkSecurityGroup:NetworkSecurityGroup" => :firewall_rule_create,
    "azure:network/publicIp:PublicIp" => :network_elastic_ip_create,
    "azure:storage/account:Account" => :storage_account_create,
    "azure:storage/container:Container" => :storage_container_create,
    "azure:storage/blob:Blob" => :storage_object_create,
    "azure:web/functionApp:FunctionApp" => :function_create,
    "azure:sql/server:Server" => :database_server_create,
    "azure:sql/database:Database" => :database_create,
    "azure:containerservice/kubernetesCluster:KubernetesCluster" => :kubernetes_cluster_create,
    "azure:containerregistry/registry:Registry" => :container_registry_create,
    "azure:dns/zone:Zone" => :dns_zone_create,
    "azure:dns/aRecord:ARecord" => :dns_record_create,
    "azure:keyvault/vault:Vault" => :key_vault_create,
    "azure:keyvault/secret:Secret" => :secret_create,
    "azure:resources/resourceGroup:ResourceGroup" => :resource_group_create,

    # Kubernetes Resources
    "kubernetes:core/v1:Namespace" => :kubernetes_namespace_create,
    "kubernetes:apps/v1:Deployment" => :container_deployment_create,
    "kubernetes:apps/v1:StatefulSet" => :container_statefulset_create,
    "kubernetes:apps/v1:DaemonSet" => :container_daemonset_create,
    "kubernetes:core/v1:Service" => :kubernetes_service_create,
    "kubernetes:core/v1:ConfigMap" => :config_create,
    "kubernetes:core/v1:Secret" => :secret_create,
    "kubernetes:core/v1:PersistentVolumeClaim" => :storage_pvc_create,
    "kubernetes:networking.k8s.io/v1:Ingress" => :kubernetes_ingress_create,
    "kubernetes:batch/v1:Job" => :kubernetes_job_create,
    "kubernetes:batch/v1:CronJob" => :kubernetes_cronjob_create,
    "kubernetes:rbac.authorization.k8s.io/v1:Role" => :kubernetes_role_create,
    "kubernetes:rbac.authorization.k8s.io/v1:RoleBinding" => :kubernetes_rolebinding_create,

    # Docker Resources
    "docker:index/container:Container" => :container_run,
    "docker:index/image:Image" => :container_image_build,
    "docker:index/network:Network" => :network_create,
    "docker:index/volume:Volume" => :storage_volume_create,

    # Generic/Fallback
    "pulumi:pulumi:Stack" => :stack_root,
    "pulumi:providers" => :provider_config
  }

  @impl true
  def parse(content, opts \\ [])

  def parse(content, opts) when is_binary(content) do
    format = Keyword.get(opts, :format, :auto)

    case detect_and_parse_format(content, format) do
      {:ok, parsed} -> build_graph(parsed, opts)
      {:error, reason} -> {:error, reason}
    end
  end

  def parse(content, opts) when is_map(content) do
    build_graph(content, opts)
  end

  @impl true
  def validate(content) when is_binary(content) do
    case detect_and_parse_format(content, :auto) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:pulumi_parse_error, reason}}
    end
  end

  def validate(content) when is_map(content) do
    cond do
      Map.has_key?(content, "resources") -> :ok
      Map.has_key?(content, :resources) -> :ok
      Map.has_key?(content, "deployment") -> :ok
      Map.has_key?(content, :deployment) -> :ok
      true -> {:error, {:pulumi_parse_error, "Missing resources or deployment key"}}
    end
  end

  # Format detection and parsing

  defp detect_and_parse_format(content, :auto) do
    cond do
      String.starts_with?(String.trim(content), "{") ->
        # JSON format (likely stack state export)
        parse_json(content)

      String.contains?(content, "resources:") or String.contains?(content, "name:") ->
        # YAML format (Pulumi.yaml)
        parse_yaml(content)

      true ->
        {:error, "Unable to detect Pulumi format"}
    end
  end

  defp detect_and_parse_format(content, :yaml), do: parse_yaml(content)
  defp detect_and_parse_format(content, :json), do: parse_json(content)
  defp detect_and_parse_format(content, :state), do: parse_json(content)

  defp parse_yaml(content) do
    case YamlElixir.read_from_string(content) do
      {:ok, parsed} -> {:ok, normalize_pulumi_yaml(parsed)}
      {:error, reason} -> {:error, {:yaml_parse_error, reason}}
    end
  end

  defp parse_json(content) do
    case Jason.decode(content) do
      {:ok, parsed} -> {:ok, normalize_pulumi_state(parsed)}
      {:error, reason} -> {:error, {:json_parse_error, reason}}
    end
  end

  # Normalize Pulumi YAML format to internal representation
  defp normalize_pulumi_yaml(yaml) when is_map(yaml) do
    resources = yaml["resources"] || %{}
    config = yaml["configuration"] || yaml["config"] || %{}
    variables = yaml["variables"] || %{}
    outputs = yaml["outputs"] || %{}

    %{
      "format" => "pulumi_yaml",
      "name" => yaml["name"],
      "runtime" => yaml["runtime"],
      "description" => yaml["description"],
      "resources" => normalize_yaml_resources(resources),
      "config" => config,
      "variables" => variables,
      "outputs" => outputs
    }
  end

  defp normalize_yaml_resources(resources) when is_map(resources) do
    Enum.map(resources, fn {name, definition} ->
      type = definition["type"] || "unknown"
      props = definition["properties"] || %{}
      opts = definition["options"] || %{}

      %{
        "name" => name,
        "type" => type,
        "properties" => props,
        "dependsOn" => opts["dependsOn"] || definition["dependsOn"] || [],
        "provider" => opts["provider"],
        "protect" => opts["protect"],
        "deleteBeforeReplace" => opts["deleteBeforeReplace"],
        "aliases" => opts["aliases"] || [],
        "customTimeouts" => opts["customTimeouts"]
      }
    end)
  end

  defp normalize_yaml_resources(_), do: []

  # Normalize Pulumi stack state export to internal representation
  defp normalize_pulumi_state(state) when is_map(state) do
    # Handle both full stack export and just deployment
    deployment = state["deployment"] || state
    resources = get_in(deployment, ["resources"]) || []

    %{
      "format" => "pulumi_state",
      "version" => state["version"],
      "resources" => normalize_state_resources(resources),
      "outputs" => get_outputs_from_state(resources),
      "config" => %{}
    }
  end

  defp normalize_state_resources(resources) when is_list(resources) do
    resources
    |> Enum.reject(fn r ->
      # Skip stack and provider resources
      type = r["type"] || ""
      type == "pulumi:pulumi:Stack" or String.starts_with?(type, "pulumi:providers:")
    end)
    |> Enum.map(fn resource ->
      %{
        "name" => extract_resource_name(resource["urn"]),
        "type" => resource["type"],
        "properties" => resource["outputs"] || resource["inputs"] || %{},
        "dependsOn" => extract_dependencies_from_urn(resource["dependencies"] || []),
        "provider" => resource["provider"],
        "id" => resource["id"],
        "urn" => resource["urn"]
      }
    end)
  end

  defp normalize_state_resources(_), do: []

  defp extract_resource_name(nil), do: "unnamed"

  defp extract_resource_name(urn) when is_binary(urn) do
    # URN format: urn:pulumi:stack::project::type::name
    case String.split(urn, "::") do
      [_, _, _, name] -> name
      _ -> urn
    end
  end

  defp extract_dependencies_from_urn(deps) when is_list(deps) do
    Enum.map(deps, &extract_resource_name/1)
  end

  defp extract_dependencies_from_urn(_), do: []

  defp get_outputs_from_state(resources) when is_list(resources) do
    # Find stack resource and extract outputs
    stack =
      Enum.find(resources, fn r ->
        (r["type"] || "") == "pulumi:pulumi:Stack"
      end)

    case stack do
      %{"outputs" => outputs} when is_map(outputs) -> outputs
      _ -> %{}
    end
  end

  # Graph building

  defp build_graph(parsed, opts) do
    resources = parsed["resources"] || []

    operations =
      resources
      |> Enum.with_index()
      |> Enum.map(fn {resource, index} ->
        build_operation(resource, index, opts)
      end)
      |> Enum.reject(&is_nil/1)

    dependencies = build_dependencies(resources, operations)

    graph = %Graph{
      vertices: operations,
      edges: dependencies,
      metadata: %{
        source_format: :pulumi,
        pulumi_format: parsed["format"],
        project_name: parsed["name"],
        runtime: parsed["runtime"],
        outputs: parsed["outputs"] || %{},
        config: parsed["config"] || %{}
      }
    }

    {:ok, graph}
  end

  defp build_operation(resource, index, _opts) do
    type = resource["type"] || "unknown"
    name = resource["name"] || "resource_#{index}"
    properties = resource["properties"] || %{}

    semantic_type = Map.get(@resource_type_mappings, type, :custom_resource)

    %Operation{
      id: "op_#{index}",
      type: semantic_type,
      params: build_params(type, name, properties, resource),
      target: extract_target(type),
      metadata: %{
        pulumi_type: type,
        pulumi_urn: resource["urn"],
        pulumi_id: resource["id"],
        provider: resource["provider"],
        protect: resource["protect"],
        aliases: resource["aliases"] || []
      }
    }
  end

  defp build_params(type, name, properties, resource) do
    base_params = %{
      name: name,
      pulumi_type: type
    }

    # Merge properties
    params = Map.merge(base_params, atomize_keys(properties))

    # Add resource options if present
    params =
      if resource["customTimeouts"] do
        Map.put(params, :timeouts, resource["customTimeouts"])
      else
        params
      end

    params =
      if resource["deleteBeforeReplace"] do
        Map.put(params, :delete_before_replace, resource["deleteBeforeReplace"])
      else
        params
      end

    params
  end

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) -> {String.to_atom(k), atomize_value(v)}
      {k, v} -> {k, atomize_value(v)}
    end)
  end

  defp atomize_keys(other), do: other

  defp atomize_value(v) when is_map(v), do: atomize_keys(v)
  defp atomize_value(v) when is_list(v), do: Enum.map(v, &atomize_value/1)
  defp atomize_value(v), do: v

  defp extract_target(type) do
    cond do
      String.starts_with?(type, "aws:") -> %{provider: :aws}
      String.starts_with?(type, "gcp:") -> %{provider: :gcp}
      String.starts_with?(type, "azure:") -> %{provider: :azure}
      String.starts_with?(type, "kubernetes:") -> %{provider: :kubernetes}
      String.starts_with?(type, "docker:") -> %{provider: :docker}
      String.starts_with?(type, "digitalocean:") -> %{provider: :digitalocean}
      String.starts_with?(type, "cloudflare:") -> %{provider: :cloudflare}
      true -> %{provider: :unknown}
    end
  end

  defp build_dependencies(resources, operations) do
    # Build name -> operation_id lookup
    name_to_op_id =
      Enum.zip(resources, operations)
      |> Enum.map(fn {resource, op} -> {resource["name"], op.id} end)
      |> Map.new()

    Enum.zip(resources, operations)
    |> Enum.flat_map(fn {resource, op} ->
      depends_on = resource["dependsOn"] || []

      Enum.flat_map(depends_on, fn dep_name ->
        dep_name = normalize_dependency_ref(dep_name)

        case Map.get(name_to_op_id, dep_name) do
          nil ->
            Logger.debug("Pulumi parser: unresolved dependency #{dep_name}")
            []

          dep_op_id ->
            [
              %Dependency{
                from: dep_op_id,
                to: op.id,
                type: :explicit,
                metadata: %{reason: "pulumi_depends_on"}
              }
            ]
        end
      end)
    end)
  end

  defp normalize_dependency_ref(ref) when is_binary(ref) do
    # Handle ${resource.name} style references
    cond do
      String.starts_with?(ref, "${") and String.ends_with?(ref, "}") ->
        ref
        |> String.trim_leading("${")
        |> String.trim_trailing("}")
        |> String.split(".")
        |> List.first()

      # Handle URN references
      String.starts_with?(ref, "urn:pulumi:") ->
        extract_resource_name(ref)

      true ->
        ref
    end
  end

  defp normalize_dependency_ref(ref), do: to_string(ref)
end
