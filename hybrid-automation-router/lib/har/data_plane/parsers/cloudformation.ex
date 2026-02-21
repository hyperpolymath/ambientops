# SPDX-License-Identifier: MPL-2.0
defmodule HAR.DataPlane.Parsers.CloudFormation do
  @moduledoc """
  Parser for AWS CloudFormation templates (YAML/JSON).

  Converts CloudFormation resource definitions to HAR semantic graph operations.

  ## Supported Elements

  - Resources (EC2, S3, Lambda, RDS, VPC, etc.)
  - Parameters
  - Mappings
  - Conditions
  - Outputs
  - DependsOn relationships
  - Intrinsic functions (!Ref, !Sub, !GetAtt, etc.)

  ## Template Versions

  Supports AWS CloudFormation templates with standard AWS resource types.
  """

  @behaviour HAR.DataPlane.Parser

  alias HAR.Semantic.{Graph, Operation, Dependency}
  require Logger

  # Resource type to semantic operation mapping
  @resource_type_mappings %{
    # Compute
    "AWS::EC2::Instance" => :vm_create,
    "AWS::EC2::LaunchTemplate" => :vm_template_create,
    "AWS::AutoScaling::AutoScalingGroup" => :autoscaler_create,
    "AWS::AutoScaling::LaunchConfiguration" => :vm_template_create,
    "AWS::Lambda::Function" => :function_create,
    "AWS::ECS::Service" => :container_service_create,
    "AWS::ECS::TaskDefinition" => :container_task_create,
    "AWS::ECS::Cluster" => :container_cluster_create,
    "AWS::EKS::Cluster" => :kubernetes_cluster_create,
    "AWS::EKS::Nodegroup" => :kubernetes_nodegroup_create,
    # Storage
    "AWS::S3::Bucket" => :storage_bucket_create,
    "AWS::S3::BucketPolicy" => :storage_policy_create,
    "AWS::EBS::Volume" => :storage_volume_create,
    "AWS::EFS::FileSystem" => :storage_filesystem_create,
    # Database
    "AWS::RDS::DBInstance" => :database_create,
    "AWS::RDS::DBCluster" => :database_cluster_create,
    "AWS::DynamoDB::Table" => :database_table_create,
    "AWS::ElastiCache::CacheCluster" => :cache_create,
    "AWS::ElastiCache::ReplicationGroup" => :cache_cluster_create,
    # Networking
    "AWS::EC2::VPC" => :network_vpc_create,
    "AWS::EC2::Subnet" => :network_subnet_create,
    "AWS::EC2::RouteTable" => :network_route_table_create,
    "AWS::EC2::Route" => :network_route_create,
    "AWS::EC2::InternetGateway" => :network_gateway_create,
    "AWS::EC2::NatGateway" => :network_nat_create,
    "AWS::EC2::NetworkInterface" => :network_interface_create,
    "AWS::EC2::SecurityGroup" => :security_group_create,
    "AWS::EC2::EIP" => :network_eip_create,
    "AWS::ElasticLoadBalancingV2::LoadBalancer" => :load_balancer_create,
    "AWS::ElasticLoadBalancingV2::TargetGroup" => :load_balancer_target_create,
    "AWS::ElasticLoadBalancingV2::Listener" => :load_balancer_listener_create,
    "AWS::Route53::HostedZone" => :dns_zone_create,
    "AWS::Route53::RecordSet" => :dns_record_create,
    "AWS::CloudFront::Distribution" => :cdn_create,
    "AWS::ApiGateway::RestApi" => :api_gateway_create,
    "AWS::ApiGatewayV2::Api" => :api_gateway_create,
    # IAM
    "AWS::IAM::Role" => :role_create,
    "AWS::IAM::Policy" => :policy_create,
    "AWS::IAM::User" => :user_create,
    "AWS::IAM::Group" => :group_create,
    "AWS::IAM::InstanceProfile" => :instance_profile_create,
    # Messaging
    "AWS::SNS::Topic" => :notification_topic_create,
    "AWS::SQS::Queue" => :queue_create,
    "AWS::Events::Rule" => :event_rule_create,
    # Monitoring
    "AWS::CloudWatch::Alarm" => :alarm_create,
    "AWS::CloudWatch::Dashboard" => :dashboard_create,
    "AWS::Logs::LogGroup" => :log_group_create,
    # Secrets
    "AWS::SecretsManager::Secret" => :secret_create,
    "AWS::SSM::Parameter" => :parameter_create,
    "AWS::KMS::Key" => :encryption_key_create
  }

  @impl true
  def parse(content, opts \\ []) when is_binary(content) do
    with {:ok, template} <- parse_template(content),
         {:ok, resources} <- extract_resources(template),
         {:ok, operations} <- build_operations(resources, template, opts),
         {:ok, dependencies} <- build_dependencies(resources, operations) do
      graph =
        Graph.new(
          vertices: operations,
          edges: dependencies,
          metadata: %{
            source: :cloudformation,
            parsed_at: DateTime.utc_now(),
            template_version: Map.get(template, "AWSTemplateFormatVersion"),
            description: Map.get(template, "Description")
          }
        )

      {:ok, graph}
    end
  end

  @impl true
  def validate(content) when is_binary(content) do
    case parse_template(content) do
      {:ok, template} when is_map(template) ->
        if Map.has_key?(template, "Resources") do
          :ok
        else
          {:error, {:cloudformation_parse_error, "No Resources section found"}}
        end

      {:ok, _} ->
        {:error, {:cloudformation_parse_error, "Invalid CloudFormation template format"}}

      {:error, reason} ->
        {:error, {:cloudformation_parse_error, reason}}
    end
  end

  # Template parsing

  defp parse_template(content) do
    # Try YAML first, then JSON
    case YamlElixir.read_from_string(content) do
      {:ok, parsed} when is_map(parsed) ->
        {:ok, parsed}

      {:ok, _} ->
        {:error, "Template is not a valid map"}

      {:error, _yaml_error} ->
        # Try JSON
        case Jason.decode(content) do
          {:ok, parsed} when is_map(parsed) -> {:ok, parsed}
          {:ok, _} -> {:error, "Template is not a valid map"}
          {:error, reason} -> {:error, {:json_parse_error, reason}}
        end
    end
  end

  # Resource extraction

  defp extract_resources(template) do
    resources = Map.get(template, "Resources", %{})
    {:ok, resources}
  end

  # Operation building

  defp build_operations(resources, template, opts) do
    parameters = Map.get(template, "Parameters", %{})
    mappings = Map.get(template, "Mappings", %{})
    conditions = Map.get(template, "Conditions", %{})

    operations =
      resources
      |> Enum.with_index()
      |> Enum.map(fn {{logical_id, resource}, index} ->
        resource_to_operation(logical_id, resource, index, parameters, mappings, conditions, opts)
      end)

    {:ok, operations}
  end

  defp resource_to_operation(
         logical_id,
         resource,
         index,
         _parameters,
         _mappings,
         _conditions,
         _opts
       ) do
    resource_type = Map.get(resource, "Type", "Unknown")
    properties = Map.get(resource, "Properties", %{})
    metadata = Map.get(resource, "Metadata", %{})
    condition = Map.get(resource, "Condition")
    depends_on = Map.get(resource, "DependsOn", [])

    semantic_type = Map.get(@resource_type_mappings, resource_type, :cloudformation_resource)

    Operation.new(
      semantic_type,
      normalize_properties(resource_type, properties),
      id: generate_id(logical_id, index),
      metadata: %{
        source: :cloudformation,
        logical_id: logical_id,
        resource_type: resource_type,
        condition: condition,
        depends_on: List.wrap(depends_on),
        cfn_metadata: metadata
      }
    )
  end

  # Property normalization by resource type

  defp normalize_properties("AWS::EC2::Instance", props) do
    %{
      name: get_tag_value(props, "Name"),
      instance_type: Map.get(props, "InstanceType"),
      image_id: Map.get(props, "ImageId"),
      key_name: Map.get(props, "KeyName"),
      subnet_id: Map.get(props, "SubnetId"),
      security_group_ids: Map.get(props, "SecurityGroupIds", []),
      iam_instance_profile: Map.get(props, "IamInstanceProfile"),
      user_data: Map.get(props, "UserData"),
      tags: Map.get(props, "Tags", []),
      block_device_mappings: Map.get(props, "BlockDeviceMappings", [])
    }
  end

  defp normalize_properties("AWS::S3::Bucket", props) do
    %{
      name: Map.get(props, "BucketName"),
      access_control: Map.get(props, "AccessControl"),
      versioning: get_in(props, ["VersioningConfiguration", "Status"]),
      encryption: Map.get(props, "BucketEncryption"),
      cors_configuration: Map.get(props, "CorsConfiguration"),
      lifecycle_configuration: Map.get(props, "LifecycleConfiguration"),
      logging_configuration: Map.get(props, "LoggingConfiguration"),
      website_configuration: Map.get(props, "WebsiteConfiguration"),
      public_access_block: Map.get(props, "PublicAccessBlockConfiguration"),
      tags: Map.get(props, "Tags", [])
    }
  end

  defp normalize_properties("AWS::Lambda::Function", props) do
    %{
      name: Map.get(props, "FunctionName"),
      runtime: Map.get(props, "Runtime"),
      handler: Map.get(props, "Handler"),
      role: Map.get(props, "Role"),
      code: Map.get(props, "Code"),
      memory_size: Map.get(props, "MemorySize", 128),
      timeout: Map.get(props, "Timeout", 3),
      environment: get_in(props, ["Environment", "Variables"]),
      vpc_config: Map.get(props, "VpcConfig"),
      layers: Map.get(props, "Layers", []),
      tags: Map.get(props, "Tags", [])
    }
  end

  defp normalize_properties("AWS::RDS::DBInstance", props) do
    %{
      name: Map.get(props, "DBInstanceIdentifier"),
      engine: Map.get(props, "Engine"),
      engine_version: Map.get(props, "EngineVersion"),
      instance_class: Map.get(props, "DBInstanceClass"),
      allocated_storage: Map.get(props, "AllocatedStorage"),
      master_username: Map.get(props, "MasterUsername"),
      master_password: Map.get(props, "MasterUserPassword"),
      vpc_security_groups: Map.get(props, "VPCSecurityGroups", []),
      db_subnet_group: Map.get(props, "DBSubnetGroupName"),
      multi_az: Map.get(props, "MultiAZ", false),
      storage_encrypted: Map.get(props, "StorageEncrypted", false),
      tags: Map.get(props, "Tags", [])
    }
  end

  defp normalize_properties("AWS::EC2::VPC", props) do
    %{
      name: get_tag_value(props, "Name"),
      cidr_block: Map.get(props, "CidrBlock"),
      enable_dns_hostnames: Map.get(props, "EnableDnsHostnames", false),
      enable_dns_support: Map.get(props, "EnableDnsSupport", true),
      instance_tenancy: Map.get(props, "InstanceTenancy", "default"),
      tags: Map.get(props, "Tags", [])
    }
  end

  defp normalize_properties("AWS::EC2::Subnet", props) do
    %{
      name: get_tag_value(props, "Name"),
      vpc_id: Map.get(props, "VpcId"),
      cidr_block: Map.get(props, "CidrBlock"),
      availability_zone: Map.get(props, "AvailabilityZone"),
      map_public_ip_on_launch: Map.get(props, "MapPublicIpOnLaunch", false),
      tags: Map.get(props, "Tags", [])
    }
  end

  defp normalize_properties("AWS::EC2::SecurityGroup", props) do
    %{
      name: Map.get(props, "GroupName"),
      description: Map.get(props, "GroupDescription"),
      vpc_id: Map.get(props, "VpcId"),
      ingress_rules: Map.get(props, "SecurityGroupIngress", []),
      egress_rules: Map.get(props, "SecurityGroupEgress", []),
      tags: Map.get(props, "Tags", [])
    }
  end

  defp normalize_properties("AWS::IAM::Role", props) do
    %{
      name: Map.get(props, "RoleName"),
      assume_role_policy: Map.get(props, "AssumeRolePolicyDocument"),
      managed_policy_arns: Map.get(props, "ManagedPolicyArns", []),
      policies: Map.get(props, "Policies", []),
      path: Map.get(props, "Path", "/"),
      max_session_duration: Map.get(props, "MaxSessionDuration"),
      tags: Map.get(props, "Tags", [])
    }
  end

  defp normalize_properties("AWS::DynamoDB::Table", props) do
    %{
      name: Map.get(props, "TableName"),
      attribute_definitions: Map.get(props, "AttributeDefinitions", []),
      key_schema: Map.get(props, "KeySchema", []),
      billing_mode: Map.get(props, "BillingMode", "PROVISIONED"),
      provisioned_throughput: Map.get(props, "ProvisionedThroughput"),
      global_secondary_indexes: Map.get(props, "GlobalSecondaryIndexes", []),
      local_secondary_indexes: Map.get(props, "LocalSecondaryIndexes", []),
      stream_specification: Map.get(props, "StreamSpecification"),
      tags: Map.get(props, "Tags", [])
    }
  end

  defp normalize_properties("AWS::ECS::TaskDefinition", props) do
    %{
      family: Map.get(props, "Family"),
      container_definitions: Map.get(props, "ContainerDefinitions", []),
      cpu: Map.get(props, "Cpu"),
      memory: Map.get(props, "Memory"),
      network_mode: Map.get(props, "NetworkMode"),
      requires_compatibilities: Map.get(props, "RequiresCompatibilities", []),
      execution_role_arn: Map.get(props, "ExecutionRoleArn"),
      task_role_arn: Map.get(props, "TaskRoleArn"),
      volumes: Map.get(props, "Volumes", []),
      tags: Map.get(props, "Tags", [])
    }
  end

  defp normalize_properties("AWS::ElasticLoadBalancingV2::LoadBalancer", props) do
    %{
      name: Map.get(props, "Name"),
      type: Map.get(props, "Type", "application"),
      scheme: Map.get(props, "Scheme", "internet-facing"),
      subnets: Map.get(props, "Subnets", []),
      security_groups: Map.get(props, "SecurityGroups", []),
      ip_address_type: Map.get(props, "IpAddressType", "ipv4"),
      tags: Map.get(props, "Tags", [])
    }
  end

  defp normalize_properties(_resource_type, props) do
    # Generic fallback - include all properties
    Map.put(props, :tags, Map.get(props, "Tags", []))
  end

  defp get_tag_value(props, key) do
    tags = Map.get(props, "Tags", [])

    case Enum.find(tags, fn t -> Map.get(t, "Key") == key end) do
      nil -> nil
      tag -> Map.get(tag, "Value")
    end
  end

  # Dependency building

  defp build_dependencies(resources, operations) do
    # Build lookup: logical_id -> operation_id
    logical_id_lookup =
      Enum.map(operations, fn op -> {op.metadata[:logical_id], op.id} end)
      |> Map.new()

    deps =
      resources
      |> Enum.flat_map(fn {logical_id, resource} ->
        extract_resource_dependencies(logical_id, resource, logical_id_lookup)
      end)

    {:ok, deps}
  end

  defp extract_resource_dependencies(logical_id, resource, logical_id_lookup) do
    source_id = Map.get(logical_id_lookup, logical_id)

    if source_id do
      # Explicit DependsOn
      explicit_deps =
        resource
        |> Map.get("DependsOn", [])
        |> List.wrap()
        |> Enum.flat_map(fn dep_logical_id ->
          case Map.get(logical_id_lookup, dep_logical_id) do
            nil ->
              []

            dep_id ->
              [Dependency.new(dep_id, source_id, :requires, metadata: %{reason: "depends_on"})]
          end
        end)

      # Implicit dependencies from !Ref and !GetAtt
      properties = Map.get(resource, "Properties", %{})
      implicit_deps = extract_implicit_dependencies(properties, source_id, logical_id_lookup)

      explicit_deps ++ implicit_deps
    else
      []
    end
  end

  defp extract_implicit_dependencies(value, source_id, logical_id_lookup) when is_map(value) do
    cond do
      # !Ref
      Map.has_key?(value, "Ref") ->
        ref = Map.get(value, "Ref")

        case Map.get(logical_id_lookup, ref) do
          nil ->
            []

          dep_id when dep_id != source_id ->
            [Dependency.new(dep_id, source_id, :requires, metadata: %{reason: "ref"})]

          _ ->
            []
        end

      # !GetAtt
      Map.has_key?(value, "Fn::GetAtt") ->
        get_att = Map.get(value, "Fn::GetAtt")

        ref =
          case get_att do
            [logical_id | _] -> logical_id
            str when is_binary(str) -> str |> String.split(".") |> List.first()
            _ -> nil
          end

        if ref do
          case Map.get(logical_id_lookup, ref) do
            nil ->
              []

            dep_id when dep_id != source_id ->
              [Dependency.new(dep_id, source_id, :requires, metadata: %{reason: "get_att"})]

            _ ->
              []
          end
        else
          []
        end

      # Recurse into nested maps
      true ->
        value
        |> Map.values()
        |> Enum.flat_map(fn v ->
          extract_implicit_dependencies(v, source_id, logical_id_lookup)
        end)
    end
  end

  defp extract_implicit_dependencies(value, source_id, logical_id_lookup) when is_list(value) do
    Enum.flat_map(value, fn v ->
      extract_implicit_dependencies(v, source_id, logical_id_lookup)
    end)
  end

  defp extract_implicit_dependencies(_value, _source_id, _logical_id_lookup), do: []

  defp generate_id(logical_id, index) do
    safe_id =
      logical_id
      |> to_string()
      |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
      |> String.slice(0, 40)

    "cfn_#{safe_id}_#{index}"
  end
end
