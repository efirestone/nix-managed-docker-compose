{
  description = "A nix service that runs docker-compose.yaml files included in your nix config repo.";

  inputs.nixpkgs.url = "nixpkgs/nixos-24.11-small";

  outputs = { self, nixpkgs }:
  let
    forEachSystem = nixpkgs.lib.genAttrs [ 
      "aarch64-linux"
      "x86_64-linux"
    ];

    overlayList = [ self.overlays.default ];
  in rec {
    # A Nixpkgs overlay that provides a 'managed-docker-compose' package.
    overlays.default = final: prev: { managed-docker-compose = final.callPackage ./package.nix {}; };

    packages = forEachSystem (system: {
      managed-docker-compose = nixpkgs.legacyPackages.${system}.callPackage ./package.nix {};
      default = self.packages.${system}.managed-docker-compose;
    });

    nixosModules = import ./nixos-modules { overlays = overlayList; };
  };
}
