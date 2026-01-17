# Proven Library Integration Plan

This document outlines how the [proven](https://github.com/hyperpolymath/proven) library's formally verified modules integrate with AmbientOps.

## Applicable Modules

### High Priority

| Module | Use Case | Formal Guarantee |
|--------|----------|------------------|
| `SafeStateMachine` | System procedure states | Valid state transitions |
| `SafeResource` | System resource lifecycle | Clean state management |
| `SafeProvenance` | Undo tokens and receipts | Tamper-evident history |

### Medium Priority

| Module | Use Case | Formal Guarantee |
|--------|----------|------------------|
| `SafeCapability` | Permission management | Least privilege |
| `SafeReversible` | Undo operations | `inverse . forward = id` |
| `SafeSchema` | Config validation | Type-safe settings |

## Integration Points by Department

### Ward (Ambient Guidance)

```
system_state → SafeMetric.validate → health_indicator
```

- SafeMetric for system health measurements
- SafeBuffer for ambient notification queue
- SafeSchema for dashboard configuration

### Emergency Room (Incident Handling)

```
:incident → :triaged → :contained → :resolved
```

SafeStateMachine ensures panic-safe incident handling:
- `intake`: incident → triaged
- `contain`: triaged → contained
- `resolve`: contained → resolved
- Each transition has safety guarantees

### Operating Room (Planned Procedures)

```
:scan → :plan → :apply → :undo → :receipt
```

The "Scan → Plan → Apply → Undo → Receipt" workflow maps to proven modules:

| Phase | proven Module | Guarantee |
|-------|---------------|-----------|
| Scan | SafeMetric | Valid measurements |
| Plan | SafeGraph | Valid dependency order |
| Apply | SafeStateMachine | Reversible application |
| Undo | SafeReversible | Exact state reversal |
| Receipt | SafeProvenance | Tamper-evident record |

### Records (Audit Trail)

```
operation → SafeProvenance.logEntry → hash-chained receipt
```

Every system modification creates:
- Before/after state hash
- Operation details
- Undo token (reversibility proof)
- Chain link to previous entry

## Safety Principles as Proofs

AmbientOps safety principles map to proven guarantees:

| Principle | proven Module | Proof |
|-----------|---------------|-------|
| No fearware | SafeMetric (accurate only) | ValidMetric |
| Evidence first | SafeProvenance | TamperFree |
| Scan is non-mutating | SafeResource (read-only) | NoMutation |
| Apply requires approval | SafeCapability | ExplicitConsent |
| Undo is first-class | SafeReversible | InverseExists |

## Hospital Model Verification

```idris
-- Ward: ambient state is always valid
WardInvariant : ValidState ward -> Safe ward

-- ER: incident handling terminates
ERTermination : Incident -> Eventually Resolved

-- OR: procedures are reversible
ORReversible : (proc : Procedure) -> inverse (apply proc) . apply proc = id

-- Records: history is tamper-evident
RecordsIntegrity : Chain -> HashIntegrity
```

## Implementation Notes

For the Julia dashboard and Elixir services:

```julia
# juliadashboard integration
using ProvenBindings: SafeMetric, SafeProvenance

function record_operation(op::Operation)
    SafeProvenance.log_entry(op)
end
```

## Status

- [ ] Add SafeStateMachine for procedure workflow
- [ ] Integrate SafeReversible for undo operations
- [ ] Implement SafeProvenance for receipts
- [ ] Add SafeMetric for system health
