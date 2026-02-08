# proven Integration Plan

This document outlines the recommended [proven](https://github.com/hyperpolymath/proven) modules for NAFA (Neurodiverse App for Adventurers).

## Recommended Modules

| Module | Purpose | Priority |
|--------|---------|----------|
| SafeGraph | Directed graphs with cycle detection proofs for adventure/quest tracking | High |
| SafeOrdering | Temporal ordering with causality proofs for event sequencing | High |
| SafePath | Safe filesystem access for user data and save files | Medium |

## Integration Notes

NAFA as a neurodiverse-focused adventure app benefits from proven's guarantees:

- **SafeGraph** is ideal for representing quest dependencies, location maps, and progression trees. The DAG type ensures no circular dependencies in quest chains, and topological sorting provides correct task ordering.

- **SafeOrdering** handles the sequencing of user actions and events. For users who may need to review their progress or understand cause-and-effect relationships, verified causal ordering is valuable.

- **SafePath** ensures user save data and configuration files are accessed safely without risk of path traversal vulnerabilities.

These modules support NAFA's goal of providing a trustworthy, predictable experience for neurodiverse users who benefit from clear structure and reliable behavior.

## Related

- [proven library](https://github.com/hyperpolymath/proven)
- [Idris 2 documentation](https://idris2.readthedocs.io/)
