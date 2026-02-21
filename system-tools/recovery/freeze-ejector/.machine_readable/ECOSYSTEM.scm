;; SPDX-License-Identifier: PMPL-1.0-or-later
;; ECOSYSTEM.scm - Ecosystem position for system-freeze-ejector
;; Media-Type: application/vnd.ecosystem+scm

(ecosystem
  (version "1.0")
  (name "system-freeze-ejector")
  (type "system-resilience")
  (purpose "Off-machine kernel dump for system recovery - preserves state during crashes")

  (position-in-ecosystem
    (category "system-resilience")
    (subcategory "crash-recovery")
    (unique-value
      ("Captures state when system becomes unresponsive")
      ("Ejects to off-machine storage before complete failure")
      ("Minimal kernel footprint - works when userspace frozen")
      ("Multiple targets: network, USB, serial")))

  (related-projects
    (project "ambientops"
      (relationship "parent")
      (description "Umbrella platform for ambient computing operations")
      (integration "system-freeze-ejector is a resilience satellite"))

    (project "system-flare"
      (relationship "sibling")
      (description "Rapid system halt with state preservation")
      (integration "Flare for graceful halt, Ejector for crash recovery"))

    (project "system-emergency-room"
      (relationship "sibling")
      (description "Triage and stabilization")
      (integration "Emergency room receives ejected state for analysis"))

    (project "cicd-hyper-a"
      (relationship "cousin")
      (description "CI/CD automation engine")
      (integration "Ejector can dump CI/CD session state on failure")))

  (what-this-is
    ("Watchdog-triggered state capture")
    ("Off-machine dump mechanism")
    ("Crash recovery enabler")
    ("Last-resort state preservation"))

  (what-this-is-not
    ("Not a backup system - emergency dump only")
    ("Not a monitoring tool - reactive only")
    ("Not a graceful shutdown - that's system-flare")))
