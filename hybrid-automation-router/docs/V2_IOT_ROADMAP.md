# HAR v2 IoT/IIoT Roadmap

**Version:** 2.0 Planning Document
**Status:** Draft
**Based On:** IOT_IIOT_ARCHITECTURE.md

## Overview

HAR v2 extends the infrastructure automation router from traditional servers (thousands-millions) to IoT/IIoT devices (billions). This roadmap outlines implementation phases following the architecture specification.

## Release Timeline

| Version | Focus | Target |
|---------|-------|--------|
| v1.0 | Server IaC (Ansible/Salt/Terraform/etc) | Current |
| v1.1 | Web UI + Graph Visualization | v1.0+2mo |
| v2.0-alpha | IPv6 Classification + Device Registry | v1.1+3mo |
| v2.0-beta | Lightweight Agents + HARCP | v2.0-alpha+3mo |
| v2.0-rc | Edge Computing + Security Tiers | v2.0-beta+3mo |
| v2.0 | Production IoT/IIoT Support | v2.0-rc+2mo |
| v2.1 | Matter/Thread Protocol | v2.0+4mo |
| v2.2 | LoRaWAN + 5G Integration | v2.1+4mo |

## Phase 1: IPv6 Device Classification (v2.0-alpha)

### Goals
- IPv6 subnet-based device type classification
- Device registry with capability tracking
- DNS-based device discovery (mDNS/DNS-SD)

### Implementation

#### 1.1 IPv6 Addressing Module

```elixir
# lib/har/iot/ipv6_classifier.ex
defmodule HAR.IoT.IPv6Classifier do
  @moduledoc """
  Classifies devices by IPv6 subnet prefix.

  Subnet hierarchy:
  - /32: Organization
  - /48: Device class (servers, IoT, IIoT, edge)
  - /64: Device type within class
  """

  @type device_class :: :server | :iot | :iiot | :edge | :unknown
  @type device_type :: atom()

  @spec classify(String.t()) :: {device_class(), device_type()}
  def classify(ipv6_address)

  @spec subnet_for_type(device_type()) :: String.t()
  def subnet_for_type(type)

  @spec devices_in_subnet(String.t()) :: [HAR.IoT.Device.t()]
  def devices_in_subnet(subnet_prefix)
end
```

#### 1.2 Device Registry

```elixir
# lib/har/iot/device_registry.ex
defmodule HAR.IoT.DeviceRegistry do
  @moduledoc """
  Distributed device registry using Horde.
  """

  use Horde.Registry

  @type device :: %{
    mac: String.t(),
    ipv6: String.t(),
    type: atom(),
    manufacturer: String.t(),
    model: String.t(),
    firmware: String.t(),
    capabilities: [atom()],
    security_tier: :low | :medium | :high | :critical,
    last_seen: DateTime.t()
  }

  @spec register(mac :: String.t(), device()) :: :ok | {:error, term()}
  @spec lookup_by_mac(String.t()) :: {:ok, device()} | :not_found
  @spec lookup_by_ipv6(String.t()) :: {:ok, device()} | :not_found
  @spec devices_by_type(atom()) :: [device()]
  @spec devices_by_capability(atom()) :: [device()]
end
```

#### 1.3 mDNS Discovery

```elixir
# lib/har/iot/discovery/mdns.ex
defmodule HAR.IoT.Discovery.MDNS do
  @moduledoc """
  Discover devices via mDNS/DNS-SD.

  Listens for _har._tcp.local services.
  """

  use GenServer

  @service_type "_har._tcp.local"

  @spec start_discovery() :: :ok
  @spec stop_discovery() :: :ok
  @spec discovered_devices() :: [HAR.IoT.Device.t()]
end
```

### Deliverables
- [ ] `HAR.IoT.IPv6Classifier` module
- [ ] `HAR.IoT.DeviceRegistry` with Horde distribution
- [ ] `HAR.IoT.Discovery.MDNS` client
- [ ] DNS TXT record parser for capabilities
- [ ] IPv6 pattern matching in routing table
- [ ] Tests: IPv6 classification, registry operations

### Dependencies
- erlang-mdns or custom mDNS implementation
- Horde for distributed registry

---

## Phase 2: Lightweight Agents (v2.0-beta)

### Goals
- Minimal Elixir agent for Linux-capable IoT
- C agent specification for constrained devices
- HAR Control Protocol (HARCP) specification

### Implementation

#### 2.1 Elixir IoT Agent

```elixir
# lib/har/agent/iot.ex
defmodule HAR.Agent.IoT do
  @moduledoc """
  Lightweight HAR agent for IoT devices.

  Target footprint: ~10MB memory
  Runs on: Linux (ARM, RISC-V, x86), Nerves
  """

  use GenServer

  @spec connect(cluster_address :: String.t(), opts :: keyword()) :: :ok
  @spec execute(HAR.Semantic.Operation.t()) :: :ok | {:error, term()}
  @spec report_capabilities() :: [atom()]
  @spec report_status() :: map()
end
```

#### 2.2 HARCP Protocol

```elixir
# lib/har/protocol/harcp.ex
defmodule HAR.Protocol.HARCP do
  @moduledoc """
  HAR Control Protocol - lightweight binary protocol.

  Transport: CoAP or MQTT
  Auth: Ed25519 signatures
  """

  @type message_type ::
    :execute |        # HAR → Device
    :ack |            # Device → HAR
    :status |         # Device → HAR
    :capability_query |   # HAR → Device
    :capability_response  # Device → HAR

  @type packet :: %{
    version: 1,
    type: message_type(),
    operation_id: binary(),  # 16 bytes UUID
    payload: binary(),
    signature: binary()      # 64 bytes Ed25519
  }

  @spec encode(packet()) :: binary()
  @spec decode(binary()) :: {:ok, packet()} | {:error, term()}
  @spec sign(binary(), private_key :: binary()) :: binary()
  @spec verify(binary(), signature :: binary(), public_key :: binary()) :: boolean()
end
```

#### 2.3 C Agent SDK Specification

```
har-agent-c/
├── include/
│   ├── har_agent.h       # Main API
│   ├── har_protocol.h    # HARCP encoding
│   └── har_crypto.h      # Ed25519 signatures
├── src/
│   ├── har_agent.c       # Agent implementation
│   ├── har_protocol.c    # Protocol handling
│   └── har_crypto.c      # Crypto (TweetNaCl)
├── examples/
│   ├── freertos/         # FreeRTOS example
│   ├── zephyr/           # Zephyr RTOS example
│   └── baremetal/        # Bare-metal example
└── CMakeLists.txt
```

### Deliverables
- [ ] `HAR.Agent.IoT` GenServer
- [ ] `HAR.Protocol.HARCP` encoder/decoder
- [ ] CoAP transport layer
- [ ] MQTT transport layer
- [ ] C agent SDK specification (header files)
- [ ] C reference implementation (FreeRTOS)
- [ ] Tests: Protocol encoding, agent communication

### Dependencies
- coap_ex for CoAP transport
- emqtt or tortoise for MQTT transport
- ed25519 for signatures

---

## Phase 3: Edge Computing (v2.0-rc)

### Goals
- Edge HAR nodes for local routing
- Offline operation with cached decisions
- Cloud-edge synchronization

### Implementation

#### 3.1 Edge Node

```elixir
# lib/har/edge/node.ex
defmodule HAR.Edge.Node do
  @moduledoc """
  HAR edge node for local IoT routing.

  Features:
  - Local routing cache
  - Offline operation
  - Cloud sync when available
  """

  use GenServer

  @spec start_link(opts :: keyword()) :: GenServer.on_start()
  @spec route_local(HAR.Semantic.Operation.t()) :: HAR.ControlPlane.RoutingDecision.t()
  @spec sync_with_cloud() :: :ok | {:error, term()}
  @spec cache_status() :: map()
end
```

#### 3.2 Routing Cache

```elixir
# lib/har/edge/cache.ex
defmodule HAR.Edge.Cache do
  @moduledoc """
  Local cache for routing decisions.

  TTL-based expiration with fallback to defaults.
  """

  use GenServer

  @default_ttl :timer.hours(1)

  @spec cache_decision(operation :: term(), decision :: term()) :: :ok
  @spec get_cached(operation :: term()) :: {:ok, term()} | :miss
  @spec invalidate(pattern :: term()) :: :ok
  @spec stats() :: %{hits: integer(), misses: integer(), size: integer()}
end
```

#### 3.3 Cloud Sync

```elixir
# lib/har/edge/cloud_sync.ex
defmodule HAR.Edge.CloudSync do
  @moduledoc """
  Synchronize edge node with central HAR cloud.

  Sync items:
  - Routing table updates
  - Device registry changes
  - Policy updates
  """

  use GenServer

  @spec force_sync() :: :ok | {:error, term()}
  @spec last_sync() :: DateTime.t() | nil
  @spec pending_changes() :: integer()
end
```

### Deliverables
- [ ] `HAR.Edge.Node` supervisor
- [ ] `HAR.Edge.Cache` with TTL
- [ ] `HAR.Edge.CloudSync` bidirectional sync
- [ ] Offline routing fallback
- [ ] Conflict resolution for divergent states
- [ ] Tests: Cache behavior, offline operation, sync

---

## Phase 4: Security Tiers (v2.0-rc)

### Goals
- Tiered authentication by device class
- Certificate management for devices
- Security tier enforcement in routing

### Implementation

#### 4.1 Security Tier Module

```elixir
# lib/har/security/device_auth.ex
defmodule HAR.Security.DeviceAuth do
  @moduledoc """
  Device authentication with security tiers.

  Tiers:
  - :low - Self-signed (dev/test)
  - :medium - Device cert (consumer IoT)
  - :high - Mutual TLS + VPN (industrial)
  - :critical - HSM-backed (safety systems)
  """

  @type tier :: :low | :medium | :high | :critical

  @spec authenticate(ipv6 :: String.t(), cert :: binary()) ::
    {:ok, HAR.IoT.Device.t()} | {:error, term()}

  @spec security_tier_for(ipv6 :: String.t()) :: tier()

  @spec verify_tier_requirements(device :: HAR.IoT.Device.t(), tier()) :: boolean()
end
```

#### 4.2 Certificate Manager

```elixir
# lib/har/security/cert_manager.ex
defmodule HAR.Security.CertManager do
  @moduledoc """
  Device certificate lifecycle management.
  """

  @spec issue_device_cert(device_id :: String.t(), tier :: atom()) ::
    {:ok, cert :: binary(), key :: binary()} | {:error, term()}

  @spec revoke_cert(serial :: String.t()) :: :ok
  @spec verify_cert_chain(cert :: binary()) :: {:ok, device_id :: String.t()} | {:error, term()}
  @spec expiring_soon(days :: integer()) :: [%{device_id: String.t(), expires: DateTime.t()}]
end
```

### Deliverables
- [ ] `HAR.Security.DeviceAuth` with tier enforcement
- [ ] `HAR.Security.CertManager` lifecycle
- [ ] HSM integration interface (for :critical tier)
- [ ] VPN verification for :high tier
- [ ] MAC binding as secondary check
- [ ] Tests: Auth flows, cert operations

---

## Phase 5: Industrial Protocols (v2.0)

### Goals
- Modbus TCP transformer for PLCs
- OPC-UA transformer for industrial systems
- BACnet transformer for building automation

### Implementation

#### 5.1 Modbus Backend

```elixir
# lib/har/backends/modbus.ex
defmodule HAR.Backends.Modbus do
  @moduledoc """
  Transform semantic operations to Modbus TCP commands.
  """

  @type modbus_command :: %{
    function: 0x01..0xFF,
    address: non_neg_integer(),
    value: binary()
  }

  @spec transform(HAR.Semantic.Operation.t()) :: [modbus_command()]
  @spec execute(commands :: [modbus_command()], host :: String.t()) :: :ok | {:error, term()}
end
```

#### 5.2 OPC-UA Backend

```elixir
# lib/har/backends/opcua.ex
defmodule HAR.Backends.OPCUA do
  @moduledoc """
  Transform semantic operations to OPC-UA method calls.
  """

  @spec transform(HAR.Semantic.Operation.t()) :: [opcua_call()]
  @spec connect(endpoint :: String.t(), opts :: keyword()) :: {:ok, session} | {:error, term()}
  @spec execute(session, calls :: [opcua_call()]) :: :ok | {:error, term()}
end
```

### Deliverables
- [ ] `HAR.Backends.Modbus` transformer
- [ ] `HAR.Backends.OPCUA` transformer
- [ ] `HAR.Backends.BACnet` transformer
- [ ] Protocol-specific routing patterns
- [ ] Tests: Protocol transformations

---

## Phase 6: Monitoring & Telemetry (v2.0)

### Goals
- Device-level metrics collection
- Fleet-wide dashboards
- Anomaly alerting

### Implementation

#### 6.1 IoT Telemetry

```elixir
# lib/har/iot/telemetry.ex
defmodule HAR.IoT.Telemetry do
  @moduledoc """
  Telemetry events for IoT operations.
  """

  @events [
    [:har, :iot, :device, :operation],
    [:har, :iot, :device, :connect],
    [:har, :iot, :device, :disconnect],
    [:har, :iot, :agent, :heartbeat],
    [:har, :iot, :edge, :cache_hit],
    [:har, :iot, :edge, :cache_miss]
  ]

  def attach_handlers()
end
```

#### 6.2 Fleet Dashboard

- Device heatmap by subnet
- Operations/sec by device type
- Offline device alerts
- Certificate expiry warnings
- Firmware version compliance

### Deliverables
- [ ] `HAR.IoT.Telemetry` event definitions
- [ ] Prometheus metrics exporter
- [ ] Grafana dashboard templates
- [ ] LiveView fleet dashboard
- [ ] Alert rules for common issues

---

## Phase 7: Future Protocols (v2.1+)

### v2.1: Matter/Thread Support

```elixir
# lib/har/protocols/matter.ex
defmodule HAR.Protocols.Matter do
  @moduledoc """
  Matter protocol support for smart home devices.

  Features:
  - Thread mesh networking
  - Device commissioning
  - Multi-admin support
  """
end
```

### v2.2: LoRaWAN Integration

```elixir
# lib/har/protocols/lorawan.ex
defmodule HAR.Protocols.LoRaWAN do
  @moduledoc """
  LoRaWAN support for low-power wide-area devices.

  Features:
  - Gateway management
  - Device provisioning
  - Downlink scheduling
  """
end
```

### v2.3: 5G Network Slicing

```elixir
# lib/har/protocols/network_slice.ex
defmodule HAR.Protocols.NetworkSlice do
  @moduledoc """
  5G network slice management for QoS.

  Features:
  - Slice allocation by operation priority
  - Latency guarantees for critical operations
  """
end
```

---

## Performance Targets

| Metric | Target | Notes |
|--------|--------|-------|
| Device registration | <100ms | Via edge node |
| Local routing decision | <5ms | Cached at edge |
| Cloud routing decision | <50ms | Via central HAR |
| Agent memory (Elixir) | <10MB | Linux IoT devices |
| Agent binary (C) | <100KB | Constrained devices |
| Devices per edge node | 10,000 | Single gateway |
| Total devices | 1B+ | Hierarchical routing |

---

## Migration Path

### From v1.x to v2.0

1. **No breaking changes** to server IaC
2. IoT features are additive modules
3. Existing routing tables remain compatible
4. New IPv6 patterns extend routing table format

### Gradual Adoption

```yaml
# v1.x routing table (still works in v2.0)
routes:
  - pattern:
      operation: package.install
    backends:
      - type: apt

# v2.0 IoT extension
routes:
  - pattern:
      target:
        ipv6_prefix: "2001:db8:2::/48"
    backends:
      - type: coap_light_control
```

---

## Dependencies Summary

### New Dependencies for v2.0

| Package | Purpose | Version |
|---------|---------|---------|
| horde | Distributed registry | ~> 0.8 |
| coap_ex | CoAP protocol | ~> 0.1 |
| tortoise | MQTT client | ~> 0.10 |
| x509 | Certificate handling | ~> 0.8 |
| ed25519 | Signatures | ~> 1.4 |

### Optional Dependencies

| Package | Purpose | When Needed |
|---------|---------|-------------|
| modbux | Modbus TCP | Industrial PLCs |
| opcua | OPC-UA client | Industrial systems |
| bacnet | BACnet client | Building automation |

---

## Success Criteria

### v2.0-alpha
- [ ] Register 1000 simulated devices
- [ ] Route by IPv6 subnet
- [ ] Discover devices via mDNS

### v2.0-beta
- [ ] Connect 100 real IoT devices (Nerves)
- [ ] HARCP communication working
- [ ] C agent compiles for FreeRTOS

### v2.0-rc
- [ ] Edge node handles 10k devices
- [ ] Offline operation for 24h
- [ ] Security tiers enforced

### v2.0
- [ ] Production deployment guide
- [ ] Industrial protocol demos
- [ ] Performance benchmarks published

---

## References

- [IOT_IIOT_ARCHITECTURE.md](./IOT_IIOT_ARCHITECTURE.md) - Full architecture
- [HAR_SECURITY.md](./HAR_SECURITY.md) - Security model
- [FINAL_ARCHITECTURE.md](./FINAL_ARCHITECTURE.md) - Core architecture
- [CONTROL_PLANE_ARCHITECTURE.md](./CONTROL_PLANE_ARCHITECTURE.md) - Routing design
