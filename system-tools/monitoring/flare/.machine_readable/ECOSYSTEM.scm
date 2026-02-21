;; SPDX-License-Identifier: PMPL-1.0-or-later
;; ECOSYSTEM.scm - Ecosystem position for system-flare
;; Media-Type: application/vnd.ecosystem+scm

(ecosystem
  (version "1.0")
  (name "system-flare")
  (type "system-resilience")
  (purpose "Rapid system halt with state preservation - emergency stop that saves work-in-progress")

  (position-in-ecosystem
    (category "system-resilience")
    (subcategory "emergency-halt")
    (unique-value
      ("Panic button for graceful emergency shutdown")
      ("Saves work-in-progress before halt")
      ("Fast execution target: < 5 seconds")
      ("Multiple triggers: hotkey, hardware, API")))

  (related-projects
    (project "ambientops"
      (relationship "parent")
      (description "Umbrella platform for ambient computing operations")
      (integration "system-flare is a resilience satellite"))

    (project "system-freeze-ejector"
      (relationship "sibling")
      (description "Off-machine kernel dump on freeze")
      (integration "Ejector for crashes, Flare for intentional emergency halt"))

    (project "system-emergency-room"
      (relationship "sibling")
      (description "Triage and stabilization")
      (integration "Emergency room handles post-flare recovery"))

    (project "cicd-hyper-a"
      (relationship "cousin")
      (description "CI/CD automation engine")
      (integration "Flare saves CI/CD session state before halt")))

  (what-this-is
    ("Emergency shutdown mechanism")
    ("Work-in-progress saver")
    ("Service notifier before halt")
    ("Fast, graceful stop"))

  (what-this-is-not
    ("Not for regular shutdown - use normal shutdown")
    ("Not a crash handler - that's system-freeze-ejector")
    ("Not a backup system - saves session state only")))
