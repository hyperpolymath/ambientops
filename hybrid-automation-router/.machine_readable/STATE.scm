;; SPDX-License-Identifier: PMPL-1.0-or-later
;; STATE.scm - Project state for hybrid-automation-router
;; Media-Type: application/vnd.state+scm

(state
  (metadata
    (version "1.0.0-rc1")
    (schema-version "1.0")
    (created "2026-01-03")
    (updated "2026-02-28T4")
    (project "hybrid-automation-router")
    (repo "github.com/hyperpolymath/hybrid-automation-router"))

  (project-context
    (name "hybrid-automation-router")
    (tagline "BGP for infrastructure automation")
    (tech-stack ("elixir" "otp" "phoenix-liveview" "libgraph" "ipfs")))

  (current-position
    (phase "poc")
    (overall-completion 50)
    (components
      (("semantic-graph" . 95)
       ("parsers" . 60)
       ("transformers" . 60)
       ("control-plane" . 95)
       ("circuit-breaker" . 100)
       ("k9-contracts" . 100)
       ("attestation" . 80)
       ("input-validation" . 70)
       ("web-ui" . 75)
       ("ipfs" . 10)
       ("security" . 20)
       ("testing" . 55)))
    (working-features
      ("semantic-graph-ir"
       "ansible-parser"
       "salt-parser"
       "terraform-parser"
       "puppet-parser-stub"
       "chef-parser-stub"
       "kubernetes-parser-stub"
       "cloudformation-parser-stub"
       "docker-compose-parser-stub"
       "pulumi-parser-stub"
       "ansible-transformer"
       "salt-transformer"
       "terraform-transformer"
       "routing-engine"
       "routing-table"
       "policy-engine"
       "health-checker"
       "phoenix-liveview-dashboard"
       "otp-clustering"
       "telemetry-metrics"
       "convert-pipeline"
       "a2ml-routing-attestation"
       "backend-manifests"
       "input-validation"
       "cycle-detection"
       "circuit-breaker-fsm"
       "k9-svc-contracts")))

  (route-to-mvp
    (milestones
      (("m1-compliance" . "License, SCM, .well-known — COMPLETE")
       ("m2-testing" . "Test coverage for all parsers/transformers — IN PROGRESS")
       ("m3-features" . "IPFS real integration, security manager, router consistency")
       ("m4-production" . "Containerfile, selur-compose, CLI escript")
       ("m5-polish" . "SCM documentation updates"))))

  (blockers-and-issues
    (critical)
    (high
      ("test-coverage" . "36 test files covering control plane, data plane, contracts, attestation — web layer and mix tasks still untested"))
    (medium
      ("ipfs-stub" . "IPFS node returns mock CIDs, not real content addressing")
      ("security-stub" . "Security manager auth/authz not implemented"))
    (low
      ("ansible-notify" . "Ansible parser doesn't extract notify/handler dependencies")
      ("regex-cache-benchmark" . "Benchmark wildcard regex caching vs compilation")))

  (critical-next-actions
    (immediate
      ("add-web-tests" . "Test Phoenix controllers, LiveViews, and router")
      ("add-mix-task-tests" . "Tests for har.convert, har.parse, har.transform CLI tasks"))
    (this-week
      ("add-security-tests" . "Test Security.Manager auth/authz/audit")
      ("integration-tests" . "More round-trip conversion tests (Chef→Puppet, K8s→DockerCompose)")
      ("implement-ipfs" . "Real ex_ipfs integration"))
    (this-month
      ("containerfile" . "Production container image")
      ("cli-escript" . "Command-line interface")
      ("security-impl" . "X.509 auth, policy-based authz")))

  (session-history
    (("2026-02-28-f" . "Test suite expansion: 8 new test files (2,373 lines). CircuitBreaker FSM (25 tests), K9Contract (33 tests), InputValidator (27 tests), CycleDetector (15 tests), A2ML attestation (17 tests), Parser dispatch (10 tests), Transformer dispatch (12 tests), RoutingDecision struct (4 tests). Total: 625 tests, 0 failures. Fixed timing races in CB tests, parser dispatch fixtures, sigil delimiters.")
     ("2026-02-28-e" . "Completeness audit fix: K9Contract.init() was never called — ETS table :har_k9_contracts was never created, so contracts were silently skipped. Added init call to Application.start/2 before supervision tree. Also added K9-SVC-EXPLAINED.adoc and A2ML-EXPLAINED.adoc narrative docs.")
     ("2026-02-28-d" . "K9-SVC service contracts: ETS-backed contract storage with SHA-256 IDs, timed_enforce wrapper for routing pipeline, breach policies (log/alert/circuit_break/degrade), backend degradation markers, glob-style pattern matching, wired into Router.route/2")
     ("2026-02-28-c" . "Circuit breaker FSM: ETS-backed three-state circuit breaker (closed/open/half-open), wired into routing pipeline and health checker, Process.send_after half-open transitions, telemetry events")
     ("2026-02-28-b" . "Attestation + hardening: a2ml routing attestations, backend manifests, input validation, semantic graph cycle detection")
     ("2026-02-28" . "Performance + reliability: regex cache, real health checks, consistency validation")
     ("2026-02-13" . "Full sweep: compliance fixes, testing foundation, feature completion"))))
