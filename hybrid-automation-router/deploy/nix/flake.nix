# SPDX-License-Identifier: MPL-2.0
# HAR (Hybrid Automation Router) Nix Flake
#
# Usage:
#   nix develop       # Enter development shell
#   nix build         # Build the package
#   nix run           # Run HAR
#   nix flake check   # Run tests

{
  description = "HAR - BGP for infrastructure automation";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Elixir/Erlang versions
        erlang = pkgs.erlang_26;
        elixir = pkgs.elixir_1_16;

        # Build inputs
        buildInputs = with pkgs; [
          erlang
          elixir
          git
          gnumake
          gcc
        ];

      in {
        # Development shell
        devShells.default = pkgs.mkShell {
          inherit buildInputs;

          shellHook = ''
            export MIX_HOME=$PWD/.nix-mix
            export HEX_HOME=$PWD/.nix-hex
            export PATH=$MIX_HOME/bin:$HEX_HOME/bin:$PATH
            export LANG=en_US.UTF-8

            # Initialize mix/hex if needed
            if [ ! -d "$MIX_HOME" ]; then
              mix local.hex --force --if-missing
              mix local.rebar --force --if-missing
            fi

            echo "HAR Development Shell"
            echo "Elixir: $(elixir --version | head -1)"
            echo "Erlang: $(erl -eval 'io:format(\"~s~n\", [erlang:system_info(otp_release)]), halt().' -noshell)"
          '';
        };

        # Package
        packages.default = pkgs.beamPackages.mixRelease {
          pname = "har";
          version = "1.0.0-rc1";

          src = ../..;

          mixEnv = "prod";

          nativeBuildInputs = [ pkgs.git ];

          # Get dependencies from mix.lock
          mixFodDeps = pkgs.beamPackages.fetchMixDeps {
            pname = "har-deps";
            version = "1.0.0-rc1";
            src = ../..;
            sha256 = pkgs.lib.fakeSha256;
          };

          meta = with pkgs.lib; {
            description = "BGP for infrastructure automation";
            homepage = "https://github.com/hyperpolymath/hybrid-automation-router";
            license = licenses.mpl20;
            maintainers = [ ];
            platforms = platforms.unix;
          };
        };

        # Container image
        packages.container = pkgs.dockerTools.buildLayeredImage {
          name = "har";
          tag = "latest";

          contents = [
            self.packages.${system}.default
            pkgs.busybox
            pkgs.cacert
            pkgs.curl
          ];

          config = {
            Cmd = [ "bin/har" "start" ];
            Env = [
              "RELEASE_COOKIE=har_cluster_cookie"
              "PHX_SERVER=true"
              "PORT=4000"
            ];
            ExposedPorts = {
              "4000/tcp" = {};
              "4369/tcp" = {};
            };
            User = "1000:1000";
          };
        };

        # Apps
        apps.default = flake-utils.lib.mkApp {
          drv = self.packages.${system}.default;
          exePath = "/bin/har";
        };

        # Checks
        checks = {
          format = pkgs.runCommand "check-format" {
            buildInputs = [ elixir ];
          } ''
            cd ${../..}
            mix format --check-formatted
            touch $out
          '';

          test = pkgs.runCommand "check-tests" {
            buildInputs = buildInputs;
          } ''
            cd ${../..}
            export MIX_ENV=test
            mix deps.get
            mix test
            touch $out
          '';
        };
      }
    );
}
