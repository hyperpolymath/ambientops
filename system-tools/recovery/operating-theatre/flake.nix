# SPDX-License-Identifier: AGPL-3.0-or-later
# flake.nix - Nix flake for System Operating Theatre
{
  description = "Plan-first system management tool";

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
        packages = {
          default = pkgs.stdenv.mkDerivation {
            pname = "operating-theatre";
            version = "0.1.0";

            src = ./.;

            nativeBuildInputs = with pkgs; [
              ldc
              dub
            ];

            buildPhase = ''
              dub build --build=release
            '';

            installPhase = ''
              mkdir -p $out/bin
              cp sor $out/bin/
            '';

            meta = with pkgs.lib; {
              description = "Plan-first system management tool";
              homepage = "https://github.com/hyperpolymath/system-operating-theatre";
              license = licenses.agpl3Plus;
              maintainers = [ ];
              platforms = platforms.linux;
            };
          };

          sor = self.packages.${system}.default;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            ldc
            dub
            just
            nickel
          ];

          shellHook = ''
            echo "System Operating Theatre development environment"
            echo "Run 'dub build' to compile"
          '';
        };

        apps.default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/sor";
        };
      }
    );
}
