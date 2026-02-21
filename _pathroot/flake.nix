# SPDX-License-Identifier: PMPL-1.0
# SPDX-FileCopyrightText: 2025 Jonathan D.A. Jewell
#
# RSR-template-repo - Nix Flake (fallback for Guix)
# Primary: guix.scm | Fallback: flake.nix
#
# Usage:
#   nix develop        # Enter dev shell
#   nix build          # Build package
#   nix flake check    # Validate flake
{
  description = "RSR Template Repository - Canonical template for RSR projects";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "rsr-template-repo";
          version = "0.1.0";

          src = ./.;

          meta = with pkgs.lib; {
            description = "Canonical template for RSR (Rhodium Standard Repository) projects";
            homepage = "https://github.com/hyperpolymath/RSR-template-repo";
            license = licenses.agpl3Plus;
            maintainers = [ ];
            platforms = platforms.all;
          };
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Core tools
            just
            git

            # Guile/Scheme (for SCM files)
            guile

            # Documentation
            asciidoctor

            # Security tools
            gitleaks
            trivy

            # Container tools
            nerdctl
          ];

          shellHook = ''
            echo "RSR Template Repository - Development Shell (Nix)"
            echo "Primary package manager: Guix (guix.scm)"
            echo "Fallback: Nix (flake.nix)"
            echo ""
            echo "Available commands:"
            echo "  just             - Show all recipes"
            echo "  just validate    - Run RSR validation"
            echo "  just info        - Show project info"
          '';
        };

        # Expose checks
        checks.default = self.packages.${system}.default;
      }
    );
}
