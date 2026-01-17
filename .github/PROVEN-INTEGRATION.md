# proven Integration Plan

This document outlines the recommended [proven](https://github.com/hyperpolymath/proven) modules for AmbientOps.

## Recommended Modules

| Module | Purpose | Priority |
|--------|---------|----------|
| SafeStateMachine | State machines with invertibility proofs for system tool state management | High |
| SafeResource | Resource lifecycle with leak prevention for system resource management | High |
| SafeTransaction | ACID transactions with isolation proofs for system operations | High |
| SafeProvenance | Change tracking with audit proofs for operation history | Medium |

## Integration Notes

AmbientOps as a cross-platform system tools ecosystem for everyday users requires trustworthy operation:

- **SafeStateMachine** models the states of system operations (scanning, cleaning, optimizing, idle). The `ReversibleOp` type enables users to undo operations, critical for building trust with "know-nothing" users who may make mistakes.

- **SafeResource** ensures system resources (disk space, memory, handles) are properly tracked and released. The "hospital" mental model means system health must be verifiable - `LeakDetector` proves no resources are leaked.

- **SafeTransaction** enables multi-step system operations to be atomic. A cleanup operation either completes fully or rolls back, preventing the half-broken states that erode user trust.

- **SafeProvenance** tracks what AmbientOps did and when. For users who distrust "optimizers" (rightfully so given scammy competition), tamper-evident audit trails prove AmbientOps did exactly what it claimed.

These modules support AmbientOps' mission of providing trustworthy tools without fearware or scams.

## Related

- [proven library](https://github.com/hyperpolymath/proven)
- [Idris 2 documentation](https://idris2.readthedocs.io/)
