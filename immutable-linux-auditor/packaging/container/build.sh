#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work_dir="$root_dir"
build_dir="$root_dir/build"
container_dir="$root_dir/packaging/container"
image_name="${IMAGE_NAME:-immutable-auditor-build}"

use_guix() {
  if command -v guix >/dev/null 2>&1; then
    guix time-machine -C "$container_dir/guix/channels.scm" \
      -- shell -m "$container_dir/guix/manifest.scm" -- \
      bash -lc "cmake -S \"$work_dir\" -B \"$build_dir\" && cmake --build \"$build_dir\""
    return 0
  fi
  return 1
}

use_nix() {
  if command -v nix >/dev/null 2>&1; then
    nix develop "$container_dir/nix" -c \
      bash -lc "cmake -S \"$work_dir\" -B \"$build_dir\" && cmake --build \"$build_dir\""
    return 0
  fi
  return 1
}

if use_guix; then
  echo "Built with Guix."
elif use_nix; then
  echo "Built with Nix."
else
  echo "Neither guix nor nix found. Install one or build manually."
  exit 1
fi

  echo "Building Chainguard-based build container..."
  podman build -f "$container_dir/Containerfile" -t "$image_name" "$work_dir"

if command -v ct >/dev/null 2>&1; then
  echo "Cerro Torre detected. Packing container image (ct)..."
  ct pack "$image_name" -o "$build_dir/${image_name}.ctp"
else
  echo "Cerro Torre not found. Trying ct container (ct:latest)..."
  podman run --rm -v "$build_dir:/workspace" ghcr.io/hyperpolymath/ct:latest \
    pack "$image_name" -o "/workspace/${image_name}.ctp"
fi

if command -v vordr >/dev/null 2>&1; then
  echo "Vordr detected. Verifying container image..."
  vordr verify --static --image "$image_name"
elif [ -d "/var/mnt/eclipse/repos/vordr" ]; then
  echo "Vordr repo detected. Attempting to build..."
  if command -v cargo >/dev/null 2>&1; then
    (cd /var/mnt/eclipse/repos/vordr && cargo build --release)
    if [ -x "/var/mnt/eclipse/repos/vordr/target/release/vordr" ]; then
      /var/mnt/eclipse/repos/vordr/target/release/vordr verify --static --image "$image_name"
    else
      echo "Vordr build completed but binary not found."
      exit 1
    fi
  else
    echo "Cargo not found; cannot build vordr."
    exit 1
  fi
else
  echo "Vordr not found. Verification required."
  exit 1
fi

if command -v svalinn-compose >/dev/null 2>&1; then
  echo "Svalinn detected. Compose integration is available for runtime deployments."
fi

if command -v selur-svct >/dev/null 2>&1; then
  echo "Selur detected. Verified container pipeline is available."
fi
