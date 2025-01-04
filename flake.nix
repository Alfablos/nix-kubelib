{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };
  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      # inherit (pkgs) lib;
      kubelib = pkgs.callPackage ./lib { };
    in
    {
      packages.default = self.packages.x86_64-linux.lib;
      packages.x86_64-linux.lib = kubelib;
    };
}
