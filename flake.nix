# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
#
# Nix flake development environment for ambientops.
# Usage: nix develop
{
  description = "AmbientOps — ambient operations and system management toolkit";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let pkgs = nixpkgs.legacyPackages.${system};
      in {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Rust — core tools and CLI
            rustc
            cargo
            clippy
            rustfmt

            # Elixir/Erlang — distributed services
            elixir
            erlang

            # zig — protocol implementations
            vlang

            # Deno — scripting and automation
            deno

            # Build tooling
            pkg-config
            gnumake
          ];

          shellHook = ''
            echo "ambientops dev shell — cargo + elixir + vlang + deno"
          '';
        };
      });
}
