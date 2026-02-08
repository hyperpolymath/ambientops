;; SPDX-License-Identifier: PMPL-1.0-or-later
(state
  (metadata
    (version "0.1.0")
    (last-updated "2026-02-08")
    (status active))
  (project-context
    (name "hardware-crash-team")
    (purpose "Diagnose and remediate hardware-induced system crashes")
    (completion-percentage 35))
  (components
    (component "scanner"
      (status working)
      (description "PCI device enumeration, zombie detection, partial binding detection")
      (remaining "BAR enumeration, lspci enrichment, interrupt checking"))
    (component "analyzer"
      (status stub)
      (description "Crash log analyzer - correlate crashes with hardware")
      (remaining "journalctl parsing, boot history, correlation scoring"))
    (component "remediation"
      (status working)
      (description "Plan/Apply/Undo workflow with receipt generation")
      (remaining "rpm-ostree integration, grubby, systemd-boot, multi-device plans"))
    (component "tui"
      (status planned)
      (description "ATS2 TUI for interactive diagnostics"))
    (component "integration"
      (status planned)
      (description "verisimdb, hypatia, MCP server, SARIF output")))
  (blockers-and-issues
    (issue "IOMMU group count reads 0 despite IOMMU being active - sysfs path issue")
    (issue "lspci-based description enrichment not yet implemented")
    (issue "Crash analyzer is stub only"))
  (critical-next-actions
    (action "Implement BAR memory region enumeration in scanner")
    (action "Add lspci description enrichment")
    (action "Implement journalctl parser for crash analyzer")
    (action "Add multi-device remediation plans (GPU + audio codec together)")
    (action "Test rpm-ostree kargs integration on Fedora Atomic")))
