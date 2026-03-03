# Changelog

## [0.4.0] - 2026-03-03
0944a1a Add Composer CLI with orchestrate, dry-run, and validate commands
7bd1bca Add JSON codec for Composer ProcedurePlan and Receipt
f29948e fix: emergency-room license AGPL→PMPL, update umbrella STATE.scm
0423170 feat: scaffold Composer Gleam orchestration engine (22 tests passing)
4d5a63d docs: update observatory and emergency-room STATE.scm from stubs to actual completion
72d3af2 test: add integration round-trip conversion tests (72 tests)
cce1673 test: add security manager tests (83 tests)
f564661 test: add comprehensive web layer and mix task tests (112 tests)
70fb900 test: add Phoenix router integration tests and test config
3c94383 Update STATE.scm: test coverage 15% → 55%, 625 tests passing
56fca83 Add 8 test files: CircuitBreaker, K9Contract, InputValidator, CycleDetector, A2ML, Parser/Transformer dispatch, RoutingDecision
b18064b Update HAR STATE.scm: record K9Contract init fix
b541e65 Fix K9Contract ETS table initialization in HAR
f440a51 Add K9-SVC and a2ml deployment narrative docs
50988f2 feat(har): add K9-SVC service contracts for backend routing governance
8772b7a feat(har): ETS-backed circuit breaker FSM for backend routing protection
bc8767d feat(har): a2ml attestation, backend manifests, input validation, cycle detection
1970452 feat(har): regex cache, real health checks, consistency validation
d388eb8 feat: absorb playbooks repo into ambientops
4ee27a6 Auto-commit: Sync changes [2026-02-24]
