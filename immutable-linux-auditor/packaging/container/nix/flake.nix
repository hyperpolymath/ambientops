{
  description = "Immutable Auditor build environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            cmake
            ninja
            gcc
            pkg-config
            git
            rustc
            cargo
            qt6.qtbase
            qt6.qtdeclarative
            qt6.qtquickcontrols2
          ];
        };
      });
}
