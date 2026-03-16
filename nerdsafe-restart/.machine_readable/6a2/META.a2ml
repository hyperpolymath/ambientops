;; SPDX-License-Identifier: MPL-2.0-or-later
;; META.scm - Meta-level information for nerdsafe-restart
;; Media-Type: application/meta+scm

(meta
 (architecture-decisions
  (adr-001
   (status accepted)
   (date "2026-01-04")
   (title "Container-based simulation over VM")
   (context "Need to simulate shell startup without actual reboot")
   (decision "Use nerdctl/podman containers instead of QEMU VMs")
   (consequences
    (positive "Faster startup, lower resource usage, simpler setup")
    (negative "Cannot emulate kernel boot, systemd, or hardware")))

  (adr-002
   (status accepted)
   (date "2026-01-04")
   (title "93% fidelity is sufficient")
   (context "Cannot achieve 100% emulation without actual hardware reboot")
   (decision "Accept 93% fidelity for shell startup validation")
   (consequences
    (positive "Fast validation, catches most config errors")
    (negative "May miss tool init failures, race conditions")))

  (adr-003
   (status accepted)
   (date "2026-01-04")
   (title "Fedora Kinoite 43 as base image")
   (context "User runs Kinoite, need matching environment")
   (decision "Use Fedora 43 base with rpm-ostree-like package set")
   (consequences
    (positive "Matches user's actual OS closely")
    (negative "Container still differs from immutable ostree")))

  (adr-004
   (status proposed)
   (date "2026-01-04")
   (title "Ada for TUI implementation")
   (context "Need safe, reliable TUI for managing validation")
   (decision "Use Ada with ncurses bindings for TUI")
   (consequences
    (positive "Strong typing, safety guarantees, GNAT available")
    (negative "Smaller ecosystem than Rust/Go for TUI")))

  (adr-005
   (status proposed)
   (date "2026-01-04")
   (title "Guix for reproducibility")
   (context "Need reproducible validation environment")
   (decision "Provide Guix manifest alongside containers")
   (consequences
    (positive "Bit-for-bit reproducible, functional approach")
    (negative "Guix not as widely available as containers"))))

 (development-practices
  (code-style
   (shell "ShellCheck compliant, POSIX where possible")
   (ada "GNAT style guide")
   (documentation "AsciiDoc for all docs"))
  (security
   (containers "Read-only mounts, cap-drop=ALL, no-new-privileges")
   (validation "No network access during validation"))
  (testing
   (unit "Syntax validation via bash -n")
   (integration "Full container startup test")
   (acceptance "93% fidelity threshold"))
  (versioning "Semantic versioning (semver)")
  (documentation "README.adoc, ROADMAP.adoc, inline comments")
  (branching "main branch, feature branches for development"))

 (design-rationale
  (why-containers
   "Containers provide isolated environment without kernel overhead of VMs.
    For shell startup validation, we only need userspace emulation.")
  (why-guix
   "Guix provides reproducible environments with declarative manifests.
    Users can recreate exact validation environment on any system.")
  (why-ada
   "Ada provides safety guarantees important for system tools.
    Strong typing prevents classes of bugs common in shell scripts.")
  (why-93-percent
   "Higher fidelity requires VM boot or actual reboot.
    93% catches syntax errors, path issues, and module loading problems.")))
