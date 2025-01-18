{
  description = "A nix service that runs docker-compose.yaml files included in your nix config repo.";

  inputs.nixpkgs.url = "nixpkgs/nixos-24.11-small";

  outputs = { self, nixpkgs }:
  let
    forEachSystem = nixpkgs.lib.genAttrs [ 
      # "aarch64-darwin"
      "aarch64-linux"
      # "x86_64-darwin"
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
      default = self.nixosConfiguration.${system}.hello-world;

      # the following line is necessary to make nix flake check happy
      config.system.build.toplevel = self.nixosConfigurations.${system}.hello-world.config.system.build.toplevel;

      # the following line with // will concat the attrs
    }) // { hello-world = self.nixosConfigurations.x86_64-linux.hello-world; };

    checks = forEachSystem (system: {
      moduleTest = nixpkgs.legacyPackages.${system}.testers.runNixOSTest {
        name = "moduleTest";
        nodes.machine1 = {
          imports = [ self.outputs.nixosModules.managed-docker-compose ];

          # enable our custom module
          services.managed-docker-compose.enable = true;

          # our module requires these things (maybe it should enable them itself too?)
          virtualisation.docker.enable = true;
          environment.systemPackages = with nixpkgs.legacyPackages.${system}; [ 
            docker
            docker-compose
          ];

          # A default user able to use sudo
          users.users.guest = {
            isNormalUser = true;
            home = "/home/guest";
            extraGroups = [ "wheel" "docker" ];
            initialPassword = "guest";
          };

          security.sudo.wheelNeedsPassword = false;

          # got a small docker compose from here:
          #  https://stackoverflow.com/questions/71719908/what-is-the-smallest-image-that-can-be-used-to-leave-docker-compose-running-inde
          environment.etc."docker-compose/hello/docker-compose.yaml".text = 
            ''
            version: '3.9'
            services:
              myservice:
                image: registry.hub.docker.com/alpine:latest
                command: tail -f /dev/null
            '';
        };
        # TODO: need to make this into a non-trivial test!
        #       see: https://vtimofeenko.com/posts/practical-nix-flake-anatomy-a-guided-tour-of-flake.nix/#checks
        testScript = ''
          machine.wait_for_unit("default.target")
          assert "hello" == "hello"
        '';
      };
    });
  };
}
