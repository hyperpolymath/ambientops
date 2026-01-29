;; SPDX-License-Identifier: PMPL-1.0-or-later
;; ECOSYSTEM.scm - Ecosystem positioning

(ecosystem
  ((version . "1.0.0")
   (name . "ambientops")
   (type . "umbrella-application")
   (purpose . "Cross-platform system tools ecosystem for everyday users")
   (position-in-ecosystem . "coordinator")
   (related-projects
     ((ops-glance . "Ward UI - tray/ambient system weather")
      (emergency-button . "Emergency Room - panic-safe intake")
      (operating-room . "Operating Room - planned procedures engine")
      (network-ambulance . "Network diagnostics and repair (OR procedure pack, v1.0)")
      (disk-ambulance . "Disk health and filesystem repair (OR procedure pack, v0.5)")
      (performance-ambulance . "System performance diagnostics (OR procedure pack, v0.5)")
      (security-ambulance . "Security posture assessment (OR procedure pack, v0.5)")
      (traffic-conditioner . "Continuous network optimization (v0.1 planning)")
      (network-orchestrator . "Enterprise network management (v0.1 planning)")
      (ambientops-composer . "Visual macro/script builder (v0.1 planning)")
      (juliadashboard . "Observability dashboard")
      (personal-sysadmin . "Clinician workflows")
      (hybrid-automation-router . "Policy-gated execution")
      (feedback-a-tron . "Referrals/discharge notes")
      (system-tools-contracts . "Shared schemas and contracts")
      (palimpsest-license . "License framework")))
   (what-this-is
     ("Umbrella repository for AmbientOps ecosystem")
     ("Documentation and UX model (hospital metaphor)")
     ("Ecosystem manifest and coordination")
     ("Packaging glue for installers"))
   (what-this-is-not
     ("Not the implementation of Ward/ER/OR - those live in satellite repos")
     ("Not a monolithic application")
     ("Not fearware or nagware"))))
