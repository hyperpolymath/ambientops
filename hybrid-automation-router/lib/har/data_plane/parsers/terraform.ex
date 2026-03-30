defmodule HAR.DataPlane.Parsers.Terraform do
  @moduledoc """
  Parser for Terraform configurations.

  Supports two input formats:
  - JSON: Output from `terraform show -json` or `terraform plan -json`
  - HCL: Native Terraform configuration (enhanced pattern matching)

  Converts Terraform resources to HAR semantic graph operations.

  ## HCL Support

  Handles common HCL constructs:
  - Resource blocks with nested blocks (ingress, egress, etc.)
  - Data source blocks
  - Module blocks with source references
  - Variable and output blocks
  - Locals blocks
  - Provider blocks with aliases
  - Meta-arguments: count, for_each, depends_on, lifecycle
  - Dynamic blocks

  For full HCL fidelity, prefer `terraform plan -json` output.
  """

  @behaviour HAR.DataPlane.Parser

  alias HAR.Semantic.{Graph, Operation, Dependency}
  require Logger

  @impl true
  def parse(content, opts \\ []) when is_binary(content) do
    format = detect_format(content)

    with {:ok, parsed} <- do_parse(content, format),
         {:ok, operations} <- extract_operations(parsed, opts),
         {:ok, dependencies} <- build_dependencies(operations, parsed) do
      graph =
        Graph.new(
          vertices: operations,
          edges: dependencies,
          metadata: %{source: :terraform, format: format, parsed_at: DateTime.utc_now()}
        )

      {:ok, graph}
    end
  end

  @impl true
  def validate(content) when is_binary(content) do
    case detect_format(content) do
      :json -> validate_json(content)
      :hcl -> validate_hcl(content)
    end
  end

  # Format Detection

  defp detect_format(content) do
    trimmed = String.trim_leading(content)

    if String.starts_with?(trimmed, "{") or String.starts_with?(trimmed, "[") do
      :json
    else
      :hcl
    end
  end

  # Parsing

  defp do_parse(content, :json) do
    case Jason.decode(content) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, reason} -> {:error, {:json_parse_error, reason}}
    end
  end

  defp do_parse(content, :hcl) do
    # Enhanced HCL parser using recursive block extraction
    resources = parse_hcl_resources(content)
    data_sources = parse_hcl_data_sources(content)
    modules = parse_hcl_modules(content)
    variables = parse_hcl_variables(content)
    outputs = parse_hcl_outputs(content)
    locals = parse_hcl_locals(content)
    providers = parse_hcl_providers(content)

    {:ok,
     %{
       "format_version" => "1.0",
       "terraform_version" => "unknown",
       "resources" => resources ++ data_sources ++ modules,
       "variables" => variables,
       "outputs" => outputs,
       "locals" => locals,
       "providers" => providers
     }}
  end

  # Enhanced block parser that handles nested blocks recursively
  defp extract_block_body(content, start_pos) do
    # Find matching closing brace, accounting for nested blocks
    chars = String.graphemes(String.slice(content, start_pos..-1//1))
    extract_balanced_block(chars, 0, [])
  end

  defp extract_balanced_block([], _depth, acc), do: Enum.join(Enum.reverse(acc))

  defp extract_balanced_block(["{" | rest], depth, acc) do
    extract_balanced_block(rest, depth + 1, ["{" | acc])
  end

  defp extract_balanced_block(["}" | _rest], 1, acc) do
    # Found matching close brace
    Enum.join(Enum.reverse(acc))
  end

  defp extract_balanced_block(["}" | rest], depth, acc) when depth > 1 do
    extract_balanced_block(rest, depth - 1, ["}" | acc])
  end

  defp extract_balanced_block([char | rest], depth, acc) do
    extract_balanced_block(rest, depth, [char | acc])
  end

  defp parse_hcl_resources(content) do
    # Match resource blocks: resource "type" "name" { ... }
    # Use multi-pass: first find start positions, then extract full blocks
    resource_starts =
      Regex.scan(~r/resource\s+"([^"]+)"\s+"([^"]+)"\s*\{/s, content, return: :index)

    resource_starts
    |> Enum.map(fn [{start, len} | captures] ->
      [{_, _}, {type_start, type_len}, {name_start, name_len}] = [{start, len} | captures]
      type = String.slice(content, type_start, type_len)
      name = String.slice(content, name_start, name_len)
      body = extract_block_body(content, start + len)

      %{
        "address" => "#{type}.#{name}",
        "type" => type,
        "name" => name,
        "values" => parse_hcl_block_body(body),
        "depends_on" => extract_depends_on(body),
        "count" => extract_count(body),
        "for_each" => extract_for_each(body),
        "lifecycle" => extract_lifecycle(body)
      }
    end)
  end

  defp parse_hcl_data_sources(content) do
    # Match data blocks: data "type" "name" { ... }
    data_starts = Regex.scan(~r/data\s+"([^"]+)"\s+"([^"]+)"\s*\{/s, content, return: :index)

    data_starts
    |> Enum.map(fn [{start, len} | captures] ->
      [{_, _}, {type_start, type_len}, {name_start, name_len}] = [{start, len} | captures]
      type = String.slice(content, type_start, type_len)
      name = String.slice(content, name_start, name_len)
      body = extract_block_body(content, start + len)

      %{
        "address" => "data.#{type}.#{name}",
        "type" => "data.#{type}",
        "name" => name,
        "values" => parse_hcl_block_body(body),
        "depends_on" => extract_depends_on(body),
        "is_data_source" => true
      }
    end)
  end

  defp parse_hcl_modules(content) do
    # Match module blocks: module "name" { source = "..." ... }
    module_starts = Regex.scan(~r/module\s+"([^"]+)"\s*\{/s, content, return: :index)

    module_starts
    |> Enum.map(fn [{start, len} | captures] ->
      [{_, _}, {name_start, name_len}] = [{start, len} | captures]
      name = String.slice(content, name_start, name_len)
      body = extract_block_body(content, start + len)
      values = parse_hcl_block_body(body)

      %{
        "address" => "module.#{name}",
        "type" => "module",
        "name" => name,
        "values" => values,
        "source" => Map.get(values, "source"),
        "version" => Map.get(values, "version"),
        "depends_on" => extract_depends_on(body),
        "for_each" => extract_for_each(body),
        "count" => extract_count(body),
        "is_module" => true
      }
    end)
  end

  defp parse_hcl_variables(content) do
    # Match variable blocks: variable "name" { ... }
    var_starts = Regex.scan(~r/variable\s+"([^"]+)"\s*\{/s, content, return: :index)

    var_starts
    |> Enum.map(fn [{start, len} | captures] ->
      [{_, _}, {name_start, name_len}] = [{start, len} | captures]
      name = String.slice(content, name_start, name_len)
      body = extract_block_body(content, start + len)

      %{
        "name" => name,
        "default" => extract_default(body),
        "type" => extract_type(body),
        "description" => extract_description(body),
        "sensitive" => extract_sensitive(body),
        "validation" => extract_validation(body)
      }
    end)
    |> Map.new(fn v -> {v["name"], v} end)
  end

  defp parse_hcl_outputs(content) do
    # Match output blocks: output "name" { value = ... }
    output_starts = Regex.scan(~r/output\s+"([^"]+)"\s*\{/s, content, return: :index)

    output_starts
    |> Enum.map(fn [{start, len} | captures] ->
      [{_, _}, {name_start, name_len}] = [{start, len} | captures]
      name = String.slice(content, name_start, name_len)
      body = extract_block_body(content, start + len)

      %{
        "name" => name,
        "value" => extract_value(body),
        "description" => extract_description(body),
        "sensitive" => extract_sensitive(body)
      }
    end)
    |> Map.new(fn o -> {o["name"], o} end)
  end

  defp parse_hcl_locals(content) do
    # Match locals blocks: locals { ... }
    locals_starts = Regex.scan(~r/locals\s*\{/s, content, return: :index)

    locals_starts
    |> Enum.flat_map(fn [{start, len} | _] ->
      body = extract_block_body(content, start + len)
      parse_hcl_simple_attributes(body)
    end)
    |> Map.new()
  end

  defp parse_hcl_providers(content) do
    # Match provider blocks: provider "name" { ... } or provider "name" { alias = "..." }
    provider_starts = Regex.scan(~r/provider\s+"([^"]+)"\s*\{/s, content, return: :index)

    provider_starts
    |> Enum.map(fn [{start, len} | captures] ->
      [{_, _}, {name_start, name_len}] = [{start, len} | captures]
      name = String.slice(content, name_start, name_len)
      body = extract_block_body(content, start + len)
      values = parse_hcl_block_body(body)
      alias_name = Map.get(values, "alias")

      key =
        if alias_name do
          "#{name}.#{alias_name}"
        else
          name
        end

      {key,
       %{
         "name" => name,
         "alias" => alias_name,
         "values" => values
       }}
    end)
    |> Map.new()
  end

  # Enhanced block body parser that handles nested blocks
  defp parse_hcl_block_body(body) do
    # First, extract nested blocks
    nested_blocks = extract_nested_blocks(body)

    # Then extract simple attributes (excluding block content)
    attrs = parse_hcl_simple_attributes(body)

    # Merge nested blocks into attributes
    Map.merge(attrs, nested_blocks)
  end

  defp parse_hcl_simple_attributes(body) do
    # Parse key = value pairs, handling various formats
    # Avoid matching inside nested blocks by using a simplified approach

    lines = String.split(body, "\n")

    lines
    |> Enum.reduce({%{}, 0}, fn line, {acc, brace_depth} ->
      trimmed = String.trim(line)

      # Track brace depth to skip nested block content
      opens = String.graphemes(line) |> Enum.count(&(&1 == "{"))
      closes = String.graphemes(line) |> Enum.count(&(&1 == "}"))
      new_depth = brace_depth + opens - closes

      if brace_depth == 0 and not is_block_declaration?(trimmed) do
        case parse_attribute_line(trimmed) do
          {:ok, key, value} -> {Map.put(acc, key, value), new_depth}
          :skip -> {acc, new_depth}
        end
      else
        {acc, new_depth}
      end
    end)
    |> elem(0)
  end

  defp is_block_declaration?(line) do
    # Check if line starts a nested block
    String.match?(line, ~r/^\s*\w+\s*\{/) or
      String.match?(line, ~r/^\s*\w+\s+"[^"]*"\s*\{/) or
      String.match?(line, ~r/^\s*dynamic\s+"[^"]*"\s*\{/)
  end

  defp parse_attribute_line(line) do
    cond do
      # String value: key = "value"
      match = Regex.run(~r/^(\w+)\s*=\s*"(.*)"$/, line) ->
        [_, key, value] = match
        {:ok, key, value}

      # Heredoc: key = <<EOF ... EOF
      String.match?(line, ~r/^(\w+)\s*=\s*<</) ->
        :skip

      # List value: key = [...]
      match = Regex.run(~r/^(\w+)\s*=\s*\[(.+)\]$/, line) ->
        [_, key, list_content] = match
        {:ok, key, parse_list_value(list_content)}

      # Boolean/number: key = true/false/123
      match = Regex.run(~r/^(\w+)\s*=\s*(true|false|\d+(?:\.\d+)?)$/, line) ->
        [_, key, value] = match
        {:ok, key, parse_literal(value)}

      # Reference: key = var.name or local.name or resource.name
      match = Regex.run(~r/^(\w+)\s*=\s*(\w+(?:\.\w+)+)$/, line) ->
        [_, key, ref] = match
        {:ok, key, "${#{ref}}"}

      # Function call: key = func(...)
      match = Regex.run(~r/^(\w+)\s*=\s*(\w+\(.+\))$/, line) ->
        [_, key, expr] = match
        {:ok, key, expr}

      # Empty or comment line
      true ->
        :skip
    end
  end

  defp parse_list_value(content) do
    # Parse list items: "a", "b" or var.x, var.y
    ~r/"([^"]*)"|(\w+(?:\.\w+)+)/
    |> Regex.scan(content)
    |> Enum.map(fn
      [_, str, ""] -> str
      [_, "", ref] -> "${#{ref}}"
    end)
  end

  defp extract_nested_blocks(body) do
    # Extract named blocks like: ingress { ... }, egress { ... }, lifecycle { ... }
    block_regex = ~r/(\w+)\s*\{/s

    # Find all potential nested blocks
    Regex.scan(block_regex, body, return: :index)
    |> Enum.reduce(%{}, fn [{_start, _len} | captures], acc ->
      [{name_start, name_len}] = captures
      block_name = String.slice(body, name_start, name_len)

      # Skip meta-arguments handled separately
      if block_name in ~w(lifecycle dynamic) do
        acc
      else
        # Find opening brace position
        after_name = String.slice(body, (name_start + name_len)..-1//1)

        case Regex.run(~r/^\s*\{/, after_name, return: :index) do
          [{brace_offset, _}] ->
            block_start = name_start + name_len + brace_offset + 1
            block_body = extract_block_body(body, block_start)

            # Group repeated blocks (like multiple ingress rules)
            existing = Map.get(acc, block_name, [])
            parsed_block = parse_hcl_simple_attributes(block_body)
            Map.put(acc, block_name, existing ++ [parsed_block])

          nil ->
            acc
        end
      end
    end)
  end

  defp parse_literal("true"), do: true
  defp parse_literal("false"), do: false

  defp parse_literal(num) do
    if String.contains?(num, ".") do
      String.to_float(num)
    else
      String.to_integer(num)
    end
  rescue
    ArgumentError -> num
  end

  # Meta-argument extractors

  defp extract_count(body) do
    case Regex.run(~r/count\s*=\s*(.+)/, body) do
      [_, expr] -> String.trim(expr)
      nil -> nil
    end
  end

  defp extract_for_each(body) do
    case Regex.run(~r/for_each\s*=\s*(.+)/, body) do
      [_, expr] -> String.trim(expr)
      nil -> nil
    end
  end

  defp extract_lifecycle(body) do
    # Extract lifecycle block content
    case Regex.run(~r/lifecycle\s*\{([^}]+)\}/s, body) do
      [_, lifecycle_body] ->
        %{
          "create_before_destroy" => extract_bool(lifecycle_body, "create_before_destroy"),
          "prevent_destroy" => extract_bool(lifecycle_body, "prevent_destroy"),
          "ignore_changes" => extract_ignore_changes(lifecycle_body)
        }

      nil ->
        nil
    end
  end

  defp extract_bool(body, attr) do
    case Regex.run(~r/#{attr}\s*=\s*(true|false)/, body) do
      [_, "true"] -> true
      [_, "false"] -> false
      nil -> nil
    end
  end

  defp extract_ignore_changes(body) do
    case Regex.run(~r/ignore_changes\s*=\s*\[([^\]]*)\]/, body) do
      [_, changes] ->
        ~r/(\w+)/
        |> Regex.scan(changes)
        |> Enum.map(fn [_, attr] -> attr end)

      nil ->
        nil
    end
  end

  defp extract_description(body) do
    case Regex.run(~r/description\s*=\s*"([^"]*)"/, body) do
      [_, desc] -> desc
      nil -> nil
    end
  end

  defp extract_sensitive(body) do
    case Regex.run(~r/sensitive\s*=\s*(true|false)/, body) do
      [_, "true"] -> true
      [_, "false"] -> false
      nil -> false
    end
  end

  defp extract_validation(body) do
    case Regex.run(~r/validation\s*\{([^}]+)\}/s, body) do
      [_, validation_body] ->
        %{
          "condition" => extract_value_from_body(validation_body, "condition"),
          "error_message" => extract_string_value(validation_body, "error_message")
        }

      nil ->
        nil
    end
  end

  defp extract_value_from_body(body, key) do
    case Regex.run(~r/#{key}\s*=\s*(.+)/, body) do
      [_, value] -> String.trim(value)
      nil -> nil
    end
  end

  defp extract_string_value(body, key) do
    case Regex.run(~r/#{key}\s*=\s*"([^"]*)"/, body) do
      [_, value] -> value
      nil -> nil
    end
  end

  defp extract_depends_on(body) do
    depends_regex = ~r/depends_on\s*=\s*\[([^\]]*)\]/s

    case Regex.run(depends_regex, body) do
      [_, deps_content] ->
        ~r/(\w+\.\w+)/
        |> Regex.scan(deps_content)
        |> Enum.map(fn [_, ref] -> ref end)

      nil ->
        []
    end
  end

  defp extract_default(body) do
    case Regex.run(~r/default\s*=\s*"([^"]*)"/, body) do
      [_, value] -> value
      nil -> nil
    end
  end

  defp extract_type(body) do
    case Regex.run(~r/type\s*=\s*(\w+)/, body) do
      [_, type] -> type
      nil -> "string"
    end
  end

  defp extract_value(body) do
    case Regex.run(~r/value\s*=\s*(.+)/, body) do
      [_, value] -> String.trim(value)
      nil -> nil
    end
  end

  # Validation

  defp validate_json(content) do
    case Jason.decode(content) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:json_parse_error, reason}}
    end
  end

  defp validate_hcl(content) do
    # Basic HCL validation - check for balanced braces
    open = String.graphemes(content) |> Enum.count(&(&1 == "{"))
    close = String.graphemes(content) |> Enum.count(&(&1 == "}"))

    if open == close do
      :ok
    else
      {:error, {:hcl_parse_error, "Unbalanced braces: #{open} open, #{close} close"}}
    end
  end

  # Operation Extraction

  defp extract_operations(parsed, _opts) do
    resources = get_resources(parsed)

    operations =
      resources
      |> Enum.with_index()
      |> Enum.map(fn {resource, index} ->
        resource_to_operation(resource, index)
      end)

    {:ok, operations}
  end

  defp get_resources(%{"resources" => resources}) when is_list(resources), do: resources

  defp get_resources(%{"planned_values" => %{"root_module" => %{"resources" => resources}}}),
    do: resources

  defp get_resources(%{"values" => %{"root_module" => %{"resources" => resources}}}),
    do: resources

  defp get_resources(_), do: []

  defp resource_to_operation(resource, index) do
    type = Map.get(resource, "type", "unknown")
    name = Map.get(resource, "name", "unnamed")
    address = Map.get(resource, "address", "#{type}.#{name}")
    values = Map.get(resource, "values", %{})
    provider = extract_provider(type)

    Operation.new(
      normalize_resource_type(type),
      normalize_resource_params(type, values),
      id: generate_resource_id(address, index),
      target: %{
        provider: provider,
        region: Map.get(values, "region"),
        resource_address: address
      },
      metadata: %{
        source: :terraform,
        resource_type: type,
        resource_name: name,
        address: address,
        original_values: values
      }
    )
  end

  # Resource Type Normalization - maps Terraform resources to semantic operations

  # AWS Compute
  defp normalize_resource_type("aws_instance"), do: :compute_instance_create
  defp normalize_resource_type("aws_launch_template"), do: :compute_instance_create
  defp normalize_resource_type("aws_autoscaling_group"), do: :compute_instance_create

  # AWS Storage
  defp normalize_resource_type("aws_s3_bucket"), do: :storage_bucket_create
  defp normalize_resource_type("aws_s3_object"), do: :file_write
  defp normalize_resource_type("aws_ebs_volume"), do: :storage_volume_create

  # AWS Database
  defp normalize_resource_type("aws_db_instance"), do: :database_create
  defp normalize_resource_type("aws_rds_cluster"), do: :database_create
  defp normalize_resource_type("aws_dynamodb_table"), do: :database_create

  # AWS Networking
  defp normalize_resource_type("aws_vpc"), do: :network_create
  defp normalize_resource_type("aws_subnet"), do: :network_subnet_create
  defp normalize_resource_type("aws_security_group"), do: :firewall_rule
  defp normalize_resource_type("aws_security_group_rule"), do: :firewall_rule
  defp normalize_resource_type("aws_route_table"), do: :network_route
  defp normalize_resource_type("aws_internet_gateway"), do: :network_gateway_create
  defp normalize_resource_type("aws_nat_gateway"), do: :network_gateway_create
  defp normalize_resource_type("aws_lb"), do: :load_balancer_create
  defp normalize_resource_type("aws_alb"), do: :load_balancer_create

  # AWS IAM
  defp normalize_resource_type("aws_iam_user"), do: :user_create
  defp normalize_resource_type("aws_iam_group"), do: :group_create
  defp normalize_resource_type("aws_iam_role"), do: :role_create
  defp normalize_resource_type("aws_iam_policy"), do: :policy_create

  # AWS Lambda
  defp normalize_resource_type("aws_lambda_function"), do: :function_create

  # GCP Compute
  defp normalize_resource_type("google_compute_instance"), do: :compute_instance_create
  defp normalize_resource_type("google_compute_disk"), do: :storage_volume_create

  # GCP Storage
  defp normalize_resource_type("google_storage_bucket"), do: :storage_bucket_create
  defp normalize_resource_type("google_storage_bucket_object"), do: :file_write

  # GCP Database
  defp normalize_resource_type("google_sql_database_instance"), do: :database_create

  # GCP Networking
  defp normalize_resource_type("google_compute_network"), do: :network_create
  defp normalize_resource_type("google_compute_subnetwork"), do: :network_subnet_create
  defp normalize_resource_type("google_compute_firewall"), do: :firewall_rule

  # Azure Compute
  defp normalize_resource_type("azurerm_virtual_machine"), do: :compute_instance_create
  defp normalize_resource_type("azurerm_linux_virtual_machine"), do: :compute_instance_create
  defp normalize_resource_type("azurerm_windows_virtual_machine"), do: :compute_instance_create

  # Azure Storage
  defp normalize_resource_type("azurerm_storage_account"), do: :storage_bucket_create
  defp normalize_resource_type("azurerm_storage_container"), do: :storage_bucket_create
  defp normalize_resource_type("azurerm_managed_disk"), do: :storage_volume_create

  # Azure Database
  defp normalize_resource_type("azurerm_sql_database"), do: :database_create
  defp normalize_resource_type("azurerm_cosmosdb_account"), do: :database_create

  # Azure Networking
  defp normalize_resource_type("azurerm_virtual_network"), do: :network_create
  defp normalize_resource_type("azurerm_subnet"), do: :network_subnet_create
  defp normalize_resource_type("azurerm_network_security_group"), do: :firewall_rule

  # Kubernetes
  defp normalize_resource_type("kubernetes_deployment"), do: :container_deployment_create
  defp normalize_resource_type("kubernetes_service"), do: :service_create
  defp normalize_resource_type("kubernetes_config_map"), do: :config_create
  defp normalize_resource_type("kubernetes_secret"), do: :secret_create
  defp normalize_resource_type("kubernetes_namespace"), do: :namespace_create

  # Local/Null providers
  defp normalize_resource_type("null_resource"), do: :command_run
  defp normalize_resource_type("local_file"), do: :file_write
  defp normalize_resource_type("local_sensitive_file"), do: :file_write

  # Fallback for unknown resource types
  defp normalize_resource_type(type), do: String.to_existing_atom("terraform." <> type)

  # Parameter Normalization

  defp normalize_resource_params("aws_instance", values) do
    %{
      ami: Map.get(values, "ami"),
      instance_type: Map.get(values, "instance_type"),
      key_name: Map.get(values, "key_name"),
      vpc_security_group_ids: Map.get(values, "vpc_security_group_ids", []),
      subnet_id: Map.get(values, "subnet_id"),
      tags: Map.get(values, "tags", %{})
    }
  end

  defp normalize_resource_params("aws_s3_bucket", values) do
    %{
      bucket: Map.get(values, "bucket"),
      acl: Map.get(values, "acl"),
      versioning: Map.get(values, "versioning"),
      tags: Map.get(values, "tags", %{})
    }
  end

  defp normalize_resource_params("aws_security_group", values) do
    %{
      name: Map.get(values, "name"),
      description: Map.get(values, "description"),
      vpc_id: Map.get(values, "vpc_id"),
      ingress: Map.get(values, "ingress", []),
      egress: Map.get(values, "egress", []),
      tags: Map.get(values, "tags", %{})
    }
  end

  defp normalize_resource_params("aws_db_instance", values) do
    %{
      identifier: Map.get(values, "identifier"),
      engine: Map.get(values, "engine"),
      engine_version: Map.get(values, "engine_version"),
      instance_class: Map.get(values, "instance_class"),
      allocated_storage: Map.get(values, "allocated_storage"),
      storage_type: Map.get(values, "storage_type"),
      tags: Map.get(values, "tags", %{})
    }
  end

  defp normalize_resource_params("aws_vpc", values) do
    %{
      cidr_block: Map.get(values, "cidr_block"),
      enable_dns_hostnames: Map.get(values, "enable_dns_hostnames"),
      enable_dns_support: Map.get(values, "enable_dns_support"),
      tags: Map.get(values, "tags", %{})
    }
  end

  defp normalize_resource_params("aws_subnet", values) do
    %{
      vpc_id: Map.get(values, "vpc_id"),
      cidr_block: Map.get(values, "cidr_block"),
      availability_zone: Map.get(values, "availability_zone"),
      map_public_ip_on_launch: Map.get(values, "map_public_ip_on_launch"),
      tags: Map.get(values, "tags", %{})
    }
  end

  defp normalize_resource_params("aws_iam_user", values) do
    %{
      name: Map.get(values, "name"),
      path: Map.get(values, "path", "/"),
      tags: Map.get(values, "tags", %{})
    }
  end

  defp normalize_resource_params("aws_iam_role", values) do
    %{
      name: Map.get(values, "name"),
      assume_role_policy: Map.get(values, "assume_role_policy"),
      tags: Map.get(values, "tags", %{})
    }
  end

  defp normalize_resource_params("local_file", values) do
    %{
      path: Map.get(values, "filename"),
      content: Map.get(values, "content"),
      permissions: Map.get(values, "file_permission")
    }
  end

  defp normalize_resource_params("null_resource", values) do
    %{
      triggers: Map.get(values, "triggers", %{}),
      provisioners: extract_provisioners(values)
    }
  end

  defp normalize_resource_params(_type, values), do: values

  defp extract_provisioners(%{"provisioner" => provisioners}) when is_list(provisioners) do
    provisioners
  end

  defp extract_provisioners(_), do: []

  defp extract_provider(type) do
    case String.split(type, "_", parts: 2) do
      [provider, _] -> String.to_existing_atom(provider)
      _ -> :unknown
    end
  end

  # Dependency Building

  defp build_dependencies(operations, parsed) do
    resources = get_resources(parsed)

    # Build lookup table: address -> operation_id
    address_to_id =
      Enum.zip(resources, operations)
      |> Enum.map(fn {resource, operation} ->
        address = Map.get(resource, "address", "")
        {address, operation.id}
      end)
      |> Map.new()

    # Extract explicit depends_on dependencies
    explicit_deps =
      Enum.zip(resources, operations)
      |> Enum.flat_map(fn {resource, operation} ->
        depends_on = Map.get(resource, "depends_on", [])

        Enum.flat_map(depends_on, fn dep_address ->
          case Map.get(address_to_id, dep_address) do
            nil ->
              Logger.debug("Dependency not found: #{dep_address}")
              []

            dep_id ->
              [
                Dependency.new(dep_id, operation.id, :depends_on,
                  metadata: %{reason: "terraform_depends_on", source: dep_address}
                )
              ]
          end
        end)
      end)

    # Extract implicit dependencies from resource references in values
    implicit_deps =
      Enum.zip(resources, operations)
      |> Enum.flat_map(fn {resource, operation} ->
        values = Map.get(resource, "values", %{})
        refs = find_resource_references(values, address_to_id)

        Enum.flat_map(refs, fn ref_id ->
          if ref_id != operation.id do
            [
              Dependency.new(ref_id, operation.id, :requires,
                metadata: %{reason: "terraform_implicit_reference"}
              )
            ]
          else
            []
          end
        end)
      end)

    # Deduplicate dependencies
    all_deps =
      (explicit_deps ++ implicit_deps)
      |> Enum.uniq_by(fn dep -> {dep.from, dep.to, dep.type} end)

    {:ok, all_deps}
  end

  defp find_resource_references(values, address_to_id) when is_map(values) do
    values
    |> Enum.flat_map(fn {_key, value} ->
      find_resource_references(value, address_to_id)
    end)
  end

  defp find_resource_references(value, address_to_id) when is_binary(value) do
    # Look for resource references like ${aws_vpc.main.id} or aws_vpc.main
    ref_regex = ~r/(?:\$\{)?(\w+\.\w+)(?:\.\w+)*\}?/

    Regex.scan(ref_regex, value)
    |> Enum.flat_map(fn [_, ref] ->
      case Map.get(address_to_id, ref) do
        nil -> []
        id -> [id]
      end
    end)
  end

  defp find_resource_references(values, address_to_id) when is_list(values) do
    Enum.flat_map(values, &find_resource_references(&1, address_to_id))
  end

  defp find_resource_references(_, _), do: []

  # ID Generation

  defp generate_resource_id(address, index) do
    safe_address =
      address
      |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
      |> String.slice(0, 40)

    "tf_#{safe_address}_#{index}_#{:erlang.unique_integer([:positive])}"
  end
end
