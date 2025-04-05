{
  description = "A nix service that runs docker-compose.yaml files included in your nix config repo.";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-24.11-small";
    flake-utils.url = "github:numtide/flake-utils";

    substitute-vars = {
      url = "github:efirestone/nix-substitute-vars/0.2.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, substitute-vars, ... }@args:
  let
    lib = {
      makePackage = { pkgs, config }: import ./lib.nix { inherit pkgs config; };
    };
  in
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        substituteVars = substitute-vars.lib.${system}.substituteVars;

        module = { pkgs, ... }@args:
          import ./module.nix ({
            inherit pkgs substituteVars;
          } // args);

        tests = import ./tests/tests.nix {
          inherit module pkgs system;
        };
      in {
        nixosModules.default = module;

        lib = lib;

        checks = builtins.mapAttrs (_: v: v) tests;
      });
}
