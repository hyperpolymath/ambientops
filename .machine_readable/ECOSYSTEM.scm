;; SPDX-License-Identifier: PMPL-1.0-or-later
;; ECOSYSTEM.scm - Ecosystem position for ambientops
;; Media-Type: application/vnd.ecosystem+scm

(ecosystem
  (version "2.0")
  (name "ambientops")
  (type "hybrid-monorepo")
  (purpose "Hospital-model operations framework - trustworthy system help without fearware")

  (position-in-ecosystem
    (category "platform-infrastructure")
    (subcategory "system-operations")
    (unique-value
      ("Hospital Model: Ward → ER → Operating Room → Records")
      ("Contract-driven data flow: EvidenceEnvelope → ProcedurePlan → Receipt → SystemWeather")
      ("Human oversight mandatory: DRY RUN by default, receipts for undo")
      ("Hybrid monorepo: core departments in-repo, tools as satellites")))

  ;; Internal components (in this monorepo)
  (internal-components
    (component "clinician"
      (department "Operating Room")
      (language "Rust")
      (loc 4400)
      (description "AI-assisted system administration with learning capabilities")
      (origin "personal-sysadmin")
      (integration "Consumes EvidenceEnvelopes from ER, applies diagnostic reasoning"))

    (component "emergency-room"
      (department "Emergency Room")
      (language "V")
      (loc 1800)
      (description "Panic-safe intake with one-click stabilization")
      (origin "emergency-button")
      (produces ("evidence-envelope" "receipt"))
      (consumes ())
      (integration "Captures incidents, produces EvidenceEnvelope via --envelope flag"))

    (component "hardware-crash-team"
      (department "Operating Room")
      (language "Rust")
      (loc 700)
      (description "PCI zombie detection, crash analysis, remediation plans")
      (produces ("evidence-envelope" "procedure-plan" "receipt"))
      (consumes ())
      (integration "Produces EvidenceEnvelopes and ProcedurePlans via --envelope/--procedure flags"))

    (component "observatory"
      (department "Ward")
      (language "Elixir")
      (loc 600)
      (description "System metrics, bundle ingestion, weather generation")
      (produces ("system-weather"))
      (consumes ("evidence-envelope" "receipt" "run-bundle"))
      (integration "Ingests EvidenceEnvelopes via CLI, generates SystemWeather"))

    (component "contracts"
      (department "Data Backbone")
      (language "JSON+Deno")
      (description "8 JSON schemas with cross-validation (4 wired, 4 future)")
      (origin "system-tools/contracts")
      (schemas
        (wired "evidence-envelope" "procedure-plan" "receipt" "system-weather")
        (future "message-intent" "pack-manifest" "ambient-payload" "run-bundle"))
      (integration "Schema definitions for all inter-component data; see contracts/WIRING.md"))

    (component "contracts-rust"
      (department "Data Backbone")
      (language "Rust")
      (description "Serde types matching JSON schemas with From conversions")
      (integration "Shared crate for Rust components to emit schema-conformant output"))

    (component "records/referrals"
      (department "Records")
      (language "Elixir")
      (loc 400)
      (description "Automated multi-platform bug reporting MCP server")
      (origin "feedback-o-tron")
      (produces ())
      (consumes ("evidence-envelope"))
      (integration "Submits findings from EvidenceEnvelopes to GitHub/GitLab/Bugzilla/Codeberg"))

    (component "composer"
      (department "Operating Room")
      (description "Orchestration engine (stubs)")
      (integration "Planned: visual macro/script builder for procedures")))

  ;; External satellites (separate repos)
  (related-projects
    (project "nafa-app"
      (relationship "satellite")
      (category "ward-ui")
      (description "Mobile journey planner UI (ReScript/Deno)")
      (status "active")
      (consumes ("system-weather" "ambient-payload"))
      (integration "Displays SystemWeather via GET /api/weather, provides ambient UI"))

    (project "panic-attacker"
      (relationship "satellite")
      (category "diagnostics-lab")
      (description "Software health scanner - security posture assessment")
      (status "active")
      (integration "Feeds scan results to verisimdb via JSON output"))

    (project "verisimdb"
      (relationship "satellite")
      (category "data-pipeline")
      (description "Multimodal database for scan results and drift detection")
      (status "active")
      (integration "Stores hexads from panic-attack, queryable via VQL"))

    (project "verisimdb-data"
      (relationship "satellite")
      (category "data-pipeline")
      (description "Git-backed flat-file store for scan snapshots")
      (status "active")
      (integration "Ingest pipeline: scan → JSON → git commit → indexed"))

    (project "hypatia"
      (relationship "satellite")
      (category "ci-cd")
      (description "Neurosymbolic CI/CD intelligence and pattern detection")
      (status "active")
      (integration "Reads verisimdb hexads, dispatches to gitbot-fleet"))

    (project "gitbot-fleet"
      (relationship "satellite")
      (category "automation")
      (description "Bot orchestration: rhodibot, echidnabot, sustainabot, glambot, seambot, finishbot")
      (status "active")
      (integration "Executes automated fixes with confidence thresholds"))

    (project "echidna"
      (relationship "satellite")
      (category "verification")
      (description "Neurosymbolic theorem proving with 30 prover backends")
      (status "active")
      (integration "Trust-hardening verification pipeline for proofs"))

    (project "network-orchestrator"
      (relationship "satellite")
      (category "network")
      (description "Enterprise network infrastructure management")
      (status "planning")
      (integration "BGP, SNMP, DHCP routing and remote diagnostics"))

    (project "traffic-conditioner"
      (relationship "satellite")
      (category "network")
      (description "Continuous network optimization and QoS")
      (status "planning")
      (integration "Bufferbloat mitigation, VPN and WiFi optimization"))

    (project "system-tools"
      (relationship "upstream-source")
      (category "canonical-contracts")
      (description "Original location of contract schemas (now absorbed)")
      (status "active")
      (integration "Canonical copies in ambientops/contracts/, originals preserved")))

  (what-this-is
    ("Hybrid monorepo for hospital-model system operations")
    ("Contract-driven data flow between Ward, ER, OR, and Records")
    ("Human-first operations: DRY RUN default, receipts, undo tokens")
    ("Rust workspace (clinician + hardware-crash-team + contracts-rust)")
    ("Elixir OTP apps (observatory + referrals) as separate processes"))

  (what-this-is-not
    ("Not a single monolithic application - hybrid architecture")
    ("Not an observability platform - observatory is advisory only")
    ("Not a cloud provider - manages local/on-prem systems")
    ("Not automated-first - human oversight mandatory for all mutations")))
