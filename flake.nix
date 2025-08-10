{
  description = "A nix service that runs docker-compose.yaml files included in your nix config repo.";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-25.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
  flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = import nixpkgs { inherit system; };

      module = { pkgs, ... }@args: import ./module.nix ({ inherit pkgs; } // args);

      tests = import ./tests/tests.nix {
        inherit module pkgs system;
      };
    in {
      nixosModules.default = module;
      nixosModules.managedDockerCompose = module;

      checks = builtins.mapAttrs (_: v: v) tests;
    });
}
