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
  in {
    # A Nixpkgs overlay that provides a 'managed-docker-compose' package.
    overlays.default = final: prev: { managed-docker-compose = final.callPackage ./package.nix {}; };

    packages = forEachSystem (system: {
      managed-docker-compose = nixpkgs.legacyPackages.${system}.callPackage ./package.nix {};
      default = self.packages.${system}.managed-docker-compose;
    });

    nixosModules = import ./nixos-modules { overlays = overlayList; };

    nixosConfigurations = forEachSystem (system: {

      # should be able to build this by running:
      # `nix build .nixosConfigurations.x86_64-linux.hello-world.config.system.build.toplevel`
      # but the above will probably fail since no bootloader or file systems have been added to the config
      # so instead we can build it as a vm:
      # `nix build .#nixosConfigurations.x86_64-linux.hello-world.config.system.build.vm`
      # run it with:
      # `./result/bin/run-nixos-vm`
      hello-world = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          
          # include our module
          self.outputs.nixosModules.managed-docker-compose

          ./examples/hello-world-configuration.nix
        ];
      };

    });
  };
}
