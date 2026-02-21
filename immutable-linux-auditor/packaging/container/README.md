# Build Container (Guix + Nix Fallback + Chainguard)

This directory defines a reproducible build container pipeline:

1. **Guix channels** as the primary build environment.
2. **Nix fallback** when Guix is unavailable.
3. **Chainguard base image** for containerized builds.
4. Optional hooks for **Cerro Torre**, **Vordr**, **Svalinn**, and **Selur**.

## Build (host)

```
./packaging/container/build.sh
```

This will:
- Build the app using Guix (or Nix if Guix is missing).
- Build a Chainguard-based container image tagged `immutable-auditor-build`.
- If available, run:
  - `ct pack` (Cerro Torre) to create a `.ctp` bundle
  - `vordr verify` to verify the image

Set a custom image name:

```
IMAGE_NAME=immutable-auditor-build-dev ./packaging/container/build.sh
```

## Files

- `Containerfile` – Chainguard build container base
- `guix/channels.scm` – Guix channels
- `guix/manifest.scm` – Guix build deps
- `nix/flake.nix` – Nix dev shell fallback
- `build.sh` – Orchestrated build pipeline
- `scripts/a2mla` – Wrapper that runs A2ML in attested (`A2MLa`) mode

## Notes

- The Chainguard base uses `apk` (Wolfi). Adjust package names if needed.
- For runtime containers, use Flatpak or RPM packaging instead.
