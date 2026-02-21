# Immutable Auditor Roadmap (v0.1 -> v12)

This roadmap outlines a pragmatic path from the current prototype to a mature
v12 release. Version numbers are semantic milestones, not dates.

## v0.1 (current)
- Standalone Qt/QML app
- Tree view with root, Flatpak, containers, toolboxes
- Details panel with raw command output
- Settings: icons, status chips, color-blind palette, preserve expanded state

## v0.2
- Make errors actionable (missing command, host bridge hint)
- Add last refresh time + manual refresh hotkey
- Improve list parsing (robust column parsing for toolbox/distrobox)

## v0.3
- Cached data snapshot + “last known good” state
- Graceful handling of slow commands (per-section timeouts)
- Basic search/filter for nodes

## v0.4
- Context-sensitive help coverage for all nodes
- Node-specific quick actions (copy details, open logs)

## v0.5
- UI polish pass (spacing, typography, icon set alignment)
- Accessibility audit (contrast, keyboard navigation, screen reader labels)

## v0.6
- Device/host metadata header (host name, OS, booted deployment hash)
- Support rpm-ostree rollback/booted/default indicators

## v0.7
- Flatpak details: runtime info, update availability
- Containers: running vs stopped counts, image source

## v0.8
- Toolboxes: version, base image, running state
- Distrobox: base image and status

## v0.9
- Export report (JSON + plain text)
- “Copy tree” to clipboard

## v1.0
- Stable data model + UI contract
- Packaging: Flatpak + RPM
- Documentation: full user guide + troubleshooting

## v2.0
- Split backend into a service/daemon for reuse
- Local cache + delta refresh for faster startup

## v3.0
- Policy-based warnings (e.g., layered packages on production systems)
- Optional policy profiles (dev, workstation, production)

## v4.0
- Plugin system for new sources (e.g., nix, brew, custom scripts)

## v5.0
- Discover/GNOME Software integration (entry point + embedded view)

## v6.0
- Fleet reporting: merge multiple host reports
- Signed snapshots

## v7.0
- Timeline view of changes (deployments, packages, containers)

## v8.0
- Remote collection (SSH) with read-only mode

## v9.0
- Compliance profiles and exportable evidence bundles

## v10.0
- Localization (major locales) and theming system

## v11.0
- Pluggable UI skins (KDE, GNOME, neutral)

## v12.0
- Long-term support branch
- Stable plugin API + compatibility guarantees
- Formal spec for data model and report formats
