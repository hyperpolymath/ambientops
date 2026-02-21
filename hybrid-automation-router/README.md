# HAR - Hybrid Automation Router

[![Hex.pm](https://img.shields.io/hexpm/v/har.svg)](https://hex.pm/packages/har)
[![Hex Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/har)
[![CI](https://github.com/hyperpolymath/hybrid-automation-router/actions/workflows/ci.yml/badge.svg)](https://github.com/hyperpolymath/hybrid-automation-router/actions)
image:https://img.shields.io/badge/License-PMPL--1.0-blue.svg[License: PMPL-1.0,link="https://github.com/hyperpolymath/palimpsest-license"]

**Think BGP for infrastructure automation.** HAR treats configuration management like network packet routing - it parses configs from any IaC tool (Ansible, Salt, Terraform), extracts semantic operations, and routes/transforms them to any target format.

## Installation

Add `har` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:har, "~> 1.0.0-rc1"}
  ]
end
```

Then run:

```bash
mix deps.get
```

## Quick Start

### CLI Usage

HAR provides three mix tasks for command-line usage:

```bash
# Parse an IaC file to semantic graph (JSON output)
mix har.parse examples/ansible/webserver.yml --format ansible

# Transform semantic graph to target format
mix har.transform graph.json --to terraform

# End-to-end conversion
mix har.convert examples/ansible/webserver.yml --to salt
mix har.convert examples/terraform/webserver.tf --to ansible
```

### Programmatic Usage

```elixir
# Parse Ansible playbook to semantic graph
{:ok, graph} = HAR.DataPlane.Parsers.Ansible.parse(ansible_yaml)

# Route to Salt backend
{:ok, plan} = HAR.ControlPlane.Router.route(graph, target: :salt)

# Transform to Salt SLS
{:ok, salt_config} = HAR.DataPlane.Transformers.Salt.transform(graph)

# Or use the convenience function
{:ok, salt_config} = HAR.convert(:ansible, ansible_yaml, to: :salt)
```

## Features

### Universal IaC Translation

Convert between any supported IaC tools:

| Source | Target | Status |
|--------|--------|--------|
| Ansible | Salt, Terraform | ✅ |
| Salt | Ansible, Terraform | ✅ |
| Terraform | Ansible, Salt | ✅ |

### Semantic Understanding

HAR understands infrastructure operations at a semantic level:

- **Package Management**: `package_install`, `package_remove`, `package_upgrade`
- **Service Control**: `service_start`, `service_stop`, `service_restart`, `service_enable`
- **File Operations**: `file_create`, `file_template`, `file_copy`, `file_permissions`
- **User Management**: `user_create`, `user_delete`, `user_modify`
- **Network Config**: `compute_instance_create`, `network_create`, `firewall_rule_create`

### Intelligent Routing

Pattern-based routing with health checking and policy enforcement:

```elixir
# Route with policies
{:ok, plan} = HAR.ControlPlane.Router.route(graph,
  target: :salt,
  policies: [:security, :compliance],
  allow_fallback: true
)
```

### Control Plane Components

- **Router**: Pattern matching to backends
- **RoutingTable**: YAML-configurable routing patterns
- **HealthChecker**: HTTP, TCP, and function-based health checks
- **PolicyEngine**: Allow/deny/prefer rules with condition matching

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Control Plane                           │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │   Router    │  │HealthChecker│  │PolicyEngine │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
└─────────────────────────────────────────────────────────────┘
                           │
┌─────────────────────────────────────────────────────────────┐
│                       Data Plane                             │
│  ┌─────────────────┐              ┌─────────────────┐       │
│  │     Parsers     │              │  Transformers   │       │
│  │ Ansible │ Salt  │  ──────────► │ Ansible │ Salt  │       │
│  │ Terraform       │  Semantic    │ Terraform       │       │
│  └─────────────────┘    Graph     └─────────────────┘       │
└─────────────────────────────────────────────────────────────┘
```

### Semantic Graph IR

HAR uses a directed graph as its intermediate representation:

```elixir
%HAR.Semantic.Graph{
  vertices: [
    %HAR.Semantic.Operation{
      id: "op_1",
      type: :package_install,
      params: %{name: "nginx"},
      target: %{os: "debian"}
    },
    %HAR.Semantic.Operation{
      id: "op_2",
      type: :service_start,
      params: %{name: "nginx"}
    }
  ],
  edges: [
    %HAR.Semantic.Dependency{
      from: "op_1",
      to: "op_2",
      type: :requires
    }
  ]
}
```

## Deployment

### Container (nerdctl/podman/docker)

```bash
# Build and run (auto-detects runtime: nerdctl > podman > docker)
./deploy/run.sh build
./deploy/run.sh up

# Or manually
nerdctl build -t har:latest -f deploy/Containerfile .
nerdctl compose -f deploy/compose.yaml up -d
```

### Native (guix/nix)

```bash
# Guix (preferred)
guix build -f deploy/guix/har.scm

# Nix (fallback)
cd deploy/nix && nix build
```

### Development Shell

```bash
./deploy/run.sh dev
# Or
nix develop deploy/nix
```

## Configuration

### Routing Table

Configure routing patterns in `priv/routing_table.yaml`:

```yaml
routes:
  - pattern:
      operation: package_install
      target:
        os: debian
    backends:
      - name: apt
        priority: 100
      - name: ansible.apt
        priority: 50

  - pattern:
      operation: service_start
    backends:
      - name: systemd
        priority: 100
```

### Policies

Add custom policies to the PolicyEngine:

```elixir
HAR.ControlPlane.PolicyEngine.add_policy(%{
  name: "production_only_terraform",
  type: :deny,
  priority: 100,
  condition: %{environment: :production, backend_type: :terraform},
  action: %{reason: "Terraform not allowed in production"}
})
```

## Supported Formats

### Parsers

| Format | File Types | Features |
|--------|------------|----------|
| Ansible | `.yml`, `.yaml` | Playbooks, roles, tasks |
| Salt | `.sls` | States, pillars |
| Terraform | `.tf`, `.tf.json` | HCL and JSON plan output |

### Transformers

| Format | Output | Features |
|--------|--------|----------|
| Ansible | YAML | Playbooks with handlers |
| Salt | YAML | States with requisites |
| Terraform | HCL/JSON | AWS, GCP, Azure providers |

## Testing

```bash
# Run all tests
mix test

# Run with coverage
mix coveralls

# Type checking
mix dialyzer

# Linting
mix credo
```

## Documentation

- [Architecture Overview](docs/FINAL_ARCHITECTURE.md)
- [Control Plane Design](docs/CONTROL_PLANE_ARCHITECTURE.md)
- [Data Plane Design](docs/DATA_PLANE_ARCHITECTURE.md)
- [Security Model](docs/HAR_SECURITY.md)
- [IoT/IIoT Integration](docs/IOT_IIOT_ARCHITECTURE.md)
- [Deployment Guide](docs/SELF_HOSTED_DEPLOYMENT.md)

## Roadmap

- [x] **1.0.0-rc1**: Core parsers/transformers, routing engine, CLI
- [ ] **1.0.0**: Documentation, Hex.pm release, benchmarks
- [ ] **1.1.0**: Distributed routing (libcluster/horde)
- [ ] **1.2.0**: IPFS integration
- [ ] **2.0.0**: Web dashboard, Phoenix LiveView

## Contributing

See [CONTRIBUTING.adoc](CONTRIBUTING.adoc) for guidelines.

## License

MPL-2.0 - See [LICENSE](LICENSE) for details.

## Links

- [GitHub](https://github.com/hyperpolymath/hybrid-automation-router)
- [Hex.pm](https://hex.pm/packages/har)
- [Documentation](https://hexdocs.pm/har)
