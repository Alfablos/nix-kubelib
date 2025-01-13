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
      packages.${system}.default = self.packages.lib;
      packages.lib = kubelib;
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = with pkgs; [ yq-go ];
      };
    };
}
