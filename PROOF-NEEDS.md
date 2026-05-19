# Proof Requirements

## Current state
- `src/abi/Types.idr` (194 lines) — System operations types
- `src/abi/Layout.idr` (177 lines) — Memory layout
- `src/abi/Foreign.idr` (217 lines) — FFI declarations
- No dangerous patterns in ABI layer
- 109K lines; includes emergency-room, session-sentinel, and system management tools
- Claims: "panic-safe intake", safety and trust principles

## What needs proving
- **Emergency room idempotency**: Prove that emergency stabilization operations are idempotent (running twice does not cause harm)
- **Session sentinel state machine**: Prove the session lifecycle (start -> active -> suspended -> terminated) has no invalid transitions or resource leaks
- **Service restart safety**: Prove restart/recovery operations do not corrupt persistent state
- **Privilege escalation prevention**: Prove system operations respect the principle of least privilege (no operation escalates beyond its declared scope)
- **Rollback atomicity**: Prove that failed operations roll back completely (no partial state)

## Tracked unproven obligations — dnfinition reversibility subsystem

The following obligations are referenced by the `PROOF STATUS` / `HONESTY
NOTE` headers in `total-update/ada/dnfinition/src/{reversibility,safety}/*`.
They were previously expressed as SPARK ghost/lemma bodies stubbed to
`return True` / `null;` (proof theatre). SPARK_Mode is now `Off` on those
units and the obligations are recorded here as the authoritative,
**UNPROVEN** list (Idris2 is the intended model — see Recommended prover).
The SPARK Theatre Gate (`.github/workflows/spark-proof-gate.yml`) prevents
any of these units silently regressing to a false "verified" claim.

| ID | Unit | Obligation |
|----|------|------------|
| O-REV-1 | `reversibility_types.ads` | `Snapshot_Exists`: a snapshot referenced by a non-null `Snapshot_ID` is actually present in backend storage. |
| O-REV-2 | `reversibility_types.ads` | `Snapshot_Is_Valid`: a `Valid`-state snapshot is restorable. |
| O-REV-3 | `reversibility_types.ads` | `System_State_Matches_Snapshot`: after a `Completed` rollback, on-disk system state equals the snapshot's captured state (rollback atomicity / no partial state). Subsumes the "Rollback atomicity" item above. |
| O-REV-4 | `reversibility_types.ads` | Monotonic snapshot IDs: issued IDs strictly increase and are never reused after deletion. |
| O-SAFE-1 | `safety_invariant.ads` | The invariant "every modifying operation is preceded by a recovery point" (`Invariant_Holds`) is preserved by all state-update operations. |
| O-SAFE-2 | `safety_boundary.ads` | The token-typed API (`Recovery_Point_Token`) admits no path that performs a modifying `Safe_*` operation without a valid recovery point, i.e. the runtime-enforced invariant is also statically unviolable. |

Status: **none of O-REV-1..4 / O-SAFE-1..2 are checked at compile time or
runtime today.** They are honest debt, not regressions, and are
deliberately *not* claimed as proven anywhere in the source.

## Recommended prover
- **Idris2** — State machines and idempotency properties are natural fits for dependent types

## Priority
- **MEDIUM** — AmbientOps manages system operations where incorrect behavior can destabilize the host. The emergency-room and session-sentinel components have the highest proof priority within the monorepo.
