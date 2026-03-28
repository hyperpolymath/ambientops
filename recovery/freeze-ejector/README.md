# system-freeze-ejector

Off-machine kernel dump for system recovery - preserves state during crashes for later analysis and restoration.

## Overview

Part of the [ambientops](https://github.com/hyperpolymath/ambientops) platform for system resilience.

When a system becomes unresponsive or is about to crash, `system-freeze-ejector` captures the current state and ejects it to off-machine storage (network, USB) before the system goes down completely.

## Concept

```
┌─────────────────────────────────────────────────────────────┐
│                    SYSTEM FREEZE DETECTED                    │
│                                                              │
│  ┌──────────┐    ┌──────────────┐    ┌──────────────────┐   │
│  │ Watchdog │───▶│ State Capture│───▶│ Network/USB Dump │   │
│  │ Trigger  │    │   - Memory   │    │   - Crash dump   │   │
│  │          │    │   - Processes│    │   - Session data │   │
│  │          │    │   - Open files│   │   - Recovery key │   │
│  └──────────┘    └──────────────┘    └──────────────────┘   │
│                                                ▼             │
│                                       ┌──────────────────┐   │
│                                       │ Remote Recovery  │   │
│                                       │    Server        │   │
│                                       └──────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Features (Planned)

- **Watchdog integration**: Detect system freezes via hardware/software watchdog
- **Minimal kernel footprint**: Works even when userspace is frozen
- **Multiple ejection targets**: Network (NFS, SSH), USB, serial
- **State prioritization**: Capture most critical data first
- **Recovery integration**: Works with `system-flare` for graceful halts

## Related Projects

| Project | Relationship | Description |
|---------|--------------|-------------|
| [ambientops](https://github.com/hyperpolymath/ambientops) | Parent | Umbrella platform |
| [system-flare](https://github.com/hyperpolymath/system-flare) | Sibling | Graceful emergency halt |
| [system-emergency-room](https://github.com/hyperpolymath/system-emergency-room) | Sibling | Triage and stabilization |

## License

PMPL-1.0-or-later
