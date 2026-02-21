# Immutable Auditor Manual

## What It Does
Immutable Auditor provides a tree view of where software lives on immutable
Fedora variants (Silverblue, Kinoite, etc.). It aggregates information from:

- Root deployments (rpm-ostree)
- Flatpak apps (system and user scopes)
- Containers (Podman and Distrobox)
- Toolboxes

## Running

From the repo:

```
cmake -S . -B build
cmake --build build
./build/immutable-auditor
```

Inside a toolbox, the app will try to use a host bridge so it can query host
commands. If the data looks empty, check the "Missing or failed commands" panel.

## Navigation

- Expand/collapse rows with the triangle.
- Click a row to see raw command output in the Details panel.
- Use Settings for display preferences (icons, status chips, color-blind mode).

## Interpretation Guide

- **Root (rpm-ostree)**: the immutable OS images.
  - Current deployment: what you are booted into now.
  - Pending deployment: staged to apply on reboot.
  - Layered packages: RPMs layered on top of the immutable image.
  - Overrides: packages replaced or masked.
- **Flatpak**: app bundles installed in system/user scopes.
- **Containers**: Podman and Distrobox instances.
- **Toolboxes**: mutable developer environments.

## Color and Accessibility

- The default palette uses green for OK and gray for unavailable/unknown.
- Enable "Color-blind friendly palette" in Settings for a blue/yellow scheme.

## Troubleshooting

- If commands show as unavailable, you may be running inside a container without
  host command access.
- Check the Details panel for the actual command used and any stderr output.
