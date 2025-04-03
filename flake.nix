{
  description = "A nix service that runs docker-compose.yaml files included in your nix config repo.";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-24.11-small";

    substitute-vars = {
      url = "github:efirestone/nix-substitute-vars/0.1.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, substitute-vars }@args:
  let
    forEachSystem = nixpkgs.lib.genAttrs [
      "aarch64-linux"
      "x86_64-linux"
    ];

    overlayList = [ self.overlays.default ];

    substituteVars = substitute-vars.lib.substituteVars;
  in {
    # A Nixpkgs overlay that provides a 'managed-docker-compose' package.
    overlays.default = final: prev: { managed-docker-compose = final.callPackage ./package.nix {}; };

    packages = forEachSystem (system: {
      managed-docker-compose = nixpkgs.legacyPackages.${system}.callPackage ./package.nix {};
      default = self.packages.${system}.managed-docker-compose;
    });

    nixosModules = import ./nixos-modules (args // { inherit substituteVars; overlays = overlayList; });

    checks = forEachSystem (system:
    let
      module = self.outputs.nixosModules.managed-docker-compose;
      tests = import ./tests/tests.nix {
        inherit module nixpkgs system;
      };
    in
      tests
    );
  };
}
