;; SPDX-License-Identifier: PMPL-1.0-or-later
(meta
  (metadata
    (version "0.1.0")
    (last-updated "2026-02-08"))
  (project-info
    (type standalone)
    (languages (rust))
    (license "PMPL-1.0-or-later")
    (author "Jonathan D.A. Jewell <jonathan.jewell@open.ac.uk>"))
  (architecture-decisions
    (adr "sysfs-only-scanning"
      (status accepted)
      (rationale "No external dependencies like lspci. Direct sysfs reads are faster, more portable, and work in containers."))
    (adr "dry-run-default"
      (status accepted)
      (rationale "Hardware remediation is inherently risky. DRY RUN by default ensures human oversight."))
    (adr "receipt-based-undo"
      (status accepted)
      (rationale "Every applied change generates a receipt JSON for rollback. No change without undo path."))
    (adr "fedora-atomic-first"
      (status accepted)
      (rationale "Origin system is Fedora Atomic. rpm-ostree kargs is primary, grubby/systemd-boot follow."))
    (adr "hospital-model"
      (status accepted)
      (rationale "Part of AmbientOps hospital model. Crash Team sits in Operating Room for planned procedures."))))
