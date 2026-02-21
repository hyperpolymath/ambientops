;; SPDX-License-Identifier: MPL-2.0-or-later
;; ECOSYSTEM.scm - Project ecosystem relationships
;; Media-Type: application/vnd.ecosystem+scm

(ecosystem
 (version "1.0")
 (name "nerdsafe-restart")
 (type "system-utility")
 (purpose "Pre-reboot shell configuration validation")

 (position-in-ecosystem
  (domain "system-administration")
  (niche "configuration-safety")
  (uniqueness "Only tool focused specifically on shell startup emulation"))

 (related-projects
  (parent-system
   (ambientops-observatory
    (relationship "satellite-of")
    (description "AmbientOps observability dashboard")
    (integration "nerdsafe-restart provides pre-boot validation for ops")
    (repo "hyperpolymath/ambientops-observatory")))

  (sibling-standard
   (modshells
    (relationship "validation-target")
    (description "Modular shell configuration framework")
    (integration "nerdsafe-restart validates modshells configurations")
    (repo "hyperpolymath/modshells")))

  (potential-consumer
   (git-hud
    (relationship "ci-integration")
    (description "Git repository management and automation")
    (integration "Could invoke nerdsafe-restart pre-commit")
    (repo "hyperpolymath/git-hud"))
   (robot-repo-bot
    (relationship "automation-hook")
    (description "Repository maintenance automation")
    (integration "Could validate shell configs before deployment")
    (repo "hyperpolymath/robot-repo-bot")))

  (inspiration
   (systemd-analyze
    (relationship "inspiration")
    (description "systemd boot analysis tool")
    (what-we-learned "Validation at boot layer is valuable"))
   (shellcheck
    (relationship "dependency")
    (description "Shell script static analysis")
    (what-we-learned "Static analysis catches many issues pre-execution"))
   (nixos-generators
    (relationship "inspiration")
    (description "NixOS image generation")
    (what-we-learned "Reproducible system configurations"))))

 (what-this-is
  "A pre-reboot safety check for shell configurations"
  "A containerized shell startup simulator"
  "A 93% fidelity emulator for bash startup sequence"
  "A tool for catching config errors before they brick systems")

 (what-this-is-not
  "A full system emulator (use QEMU for that)"
  "A bootloader tester (use systemd-boot-check)"
  "A kernel boot validator (different tooling entirely)"
  "A replacement for actual testing on hardware"
  "A 100% accurate simulation (fundamentally impossible)"))
