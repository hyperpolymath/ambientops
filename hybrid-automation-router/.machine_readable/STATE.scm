;; SPDX-License-Identifier: PMPL-1.0-or-later
;; STATE.scm - Project state for hybrid-automation-router
;; Media-Type: application/vnd.state+scm

(state
  (metadata
    (version "1.0.0-rc1")
    (schema-version "1.0")
    (created "2026-01-03")
    (updated "2026-02-13")
    (project "hybrid-automation-router")
    (repo "github.com/hyperpolymath/hybrid-automation-router"))

  (project-context
    (name "hybrid-automation-router")
    (tagline "BGP for infrastructure automation")
    (tech-stack ("elixir" "otp" "phoenix-liveview" "libgraph" "ipfs")))

  (current-position
    (phase "poc")
    (overall-completion 45)
    (components
      (("semantic-graph" . 95)
       ("parsers" . 60)
       ("transformers" . 60)
       ("control-plane" . 85)
       ("web-ui" . 75)
       ("ipfs" . 10)
       ("security" . 15)
       ("testing" . 15)))
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
       "convert-pipeline")))

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
      ("test-coverage" . "Only 5 test files for 34 source modules"))
    (medium
      ("ipfs-stub" . "IPFS node returns mock CIDs, not real content addressing")
      ("security-stub" . "Security manager auth/authz not implemented"))
    (low
      ("ansible-notify" . "Ansible parser doesn't extract notify/handler dependencies")
      ("router-consistency" . "validate_consistency/1 is a TODO")))

  (critical-next-actions
    (immediate
      ("add-core-tests" . "Test HAR API, Salt parser, Router, RoutingTable")
      ("add-parser-tests" . "Tests for all 9 parser modules"))
    (this-week
      ("add-transformer-tests" . "Tests for all 9 transformer modules")
      ("integration-tests" . "Round-trip conversion tests")
      ("implement-ipfs" . "Real ex_ipfs integration"))
    (this-month
      ("containerfile" . "Production container image")
      ("cli-escript" . "Command-line interface")
      ("security-impl" . "X.509 auth, policy-based authz")))

  (session-history
    (("2026-02-13" . "Full sweep: compliance fixes, testing foundation, feature completion"))))
