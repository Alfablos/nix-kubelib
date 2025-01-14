{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        system = "x86_64-linux";
        pkgs = import nixpkgs { inherit system; };
        # inherit (pkgs) lib;
        kubelib = pkgs.callPackage ./lib { };
      in
      {
        packages.default = self.packages.lib;
        packages.lib = kubelib;
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [ yq-go ];
        };
      }

    );
}
