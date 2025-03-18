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

    checks = forEachSystem (system: {
      # To run the tests: nix flake check --all-systems
      # You may also want the -L and --verbose flags for additional debugging.
      # dockerTest = nixpkgs.legacyPackages.${system}.testers.runNixOSTest {
      #   name = "dockerTest";
      #   nodes.machine = {
      #     imports = [ self.outputs.nixosModules.managed-docker-compose ];

      #     # enable our custom module
      #     services.managed-docker-compose.enable = true;

      #     services.managed-docker-compose.applications.test_app = {
      #       compose_file = "/etc/docker-compose/test/compose.yaml";
      #     };

      #     virtualisation.oci-containers.backend = "docker";

      #     # Run a very lightweight image, but also one that doesn't immediately exit.
      #     environment.etc."docker-compose/test/compose.yaml".text = 
      #       ''
      #       services:
      #         myservice:
      #           image: testimg
      #           command: /bin/tail -f /dev/null
      #           network_mode: none
      #           volumes:
      #             # Map the bin from the current system in so that we can execute `tail`
      #             - /nix/store:/nix/store
      #             - /run/current-system/sw/bin:/bin
      #       '';
      #   };
      #   testScript = ''
      #     machine.wait_for_unit("managed-docker-compose.service")
          
      #     # Create a fake image to run
      #     machine.succeed("tar cv --files-from /dev/null | docker import - testimg")
      #     machine.wait_until_succeeds("docker ps --format='{{ .Image }}' | grep 'testimg'")
      #   '';
      # };

      # podmanTest = nixpkgs.legacyPackages.${system}.testers.runNixOSTest {
      #   name = "podmanTest";
      #   nodes.machine = {
      #     imports = [ self.outputs.nixosModules.managed-docker-compose ];

      #     # enable our custom module
      #     services.managed-docker-compose.enable = true;

      #     services.managed-docker-compose.applications.test_app = {
      #       compose_file = "/etc/docker-compose/test/compose.yaml";
      #     };

      #     # Run a very lightweight image, but also one that doesn't immediately exit.
      #     environment.etc."docker-compose/test/compose.yaml".text = 
      #       ''
      #       services:
      #         myservice:
      #           image: testimg
      #           command: /bin/tail -f /dev/null
      #           network_mode: none
      #           volumes:
      #             # Map the bin from the current system in so that we can execute `tail`
      #             - /nix/store:/nix/store
      #             - /run/current-system/sw/bin:/bin
      #       '';
      #   };
      #   testScript = ''
      #     machine.wait_for_unit("managed-docker-compose.service")
          
      #     # Create a fake image to run
      #     machine.succeed("tar cv --files-from /dev/null | podman import - testimg")
      #     machine.wait_until_succeeds("podman ps --format='{{ .Image }}' | grep 'testimg'")
      #   '';
      # };

      deactivateTest = nixpkgs.legacyPackages.${system}.testers.runNixOSTest {
        name = "deactivateOldComposeFilesTest";
        nodes.machine = {
          imports = [ self.outputs.nixosModules.managed-docker-compose ];

          # enable our custom module
          services.managed-docker-compose.enable = true;

          # Use docker and not podman for this test
          virtualisation.oci-containers.backend = "docker";

          services.managed-docker-compose.applications.test_app = {
            compose_file = "/etc/docker-compose/current_app/compose.yaml";
          };

          # Run a very lightweight image, but also one that doesn't immediately exit.
          environment.etc."docker-compose/current_app/compose.yaml".text = 
            ''
            services:
              current_app:
                image: testimg
                command: /bin/tail -f /dev/null
                network_mode: none
                volumes:
                  # Map the bin from the current system in so that we can execute `tail`
                  - /nix/store:/nix/store
                  - /run/current-system/sw/bin:/bin
            '';

          # This compose file isn't in the list of current files passed to the systemd service,
          # so it should be spun down.
          #
          # In the future we should only spin do applications that have a specific label (which we add)
          # so that it's still possible for other services to use Docker Compose, but for now we'll
          # assume that only managed-docker-compose is running Docker Compose.
          environment.etc."docker-compose/old_app/compose.yaml".text = 
            ''
            services:
              old_app:
                image: testimg
                command: /bin/tail -f /dev/null
                network_mode: none
                volumes:
                  # Map the bin from the current system in so that we can execute `tail`
                  - /nix/store:/nix/store
                  - /run/current-system/sw/bin:/bin
            '';
        };
        testScript = ''
          # Create a fake image to run
          machine.succeed("tar cv --files-from /dev/null | docker import - testimg")

          print("EF: Waiting for default target")
          machine.wait_for_unit("default.target")

          print("EF: Starting the old app")

          # Start the old app, which should then be spun down by our systemd service.
          machine.succeed("docker compose --file /etc/docker-compose/old_app/compose.yaml up")

          print("EF: Waiting for service")

          machine.wait_for_unit("managed-docker-compose.service")

          print(machine.succeed("cat /etc/nixos/configuration.nix"))

          print(machine.succeed("nixos-rebuild switch"))

          print("EF: Waiting for new app")

          machine.wait_until_succeeds("docker ps --format='{{ .Names }}' | grep 'current_app'")

          print("EF: Waiting for old app to disappear")

          machine.wait_until_fails("docker ps --format='{{ .Names }}' | grep 'old_app'")
        '';
      };
    });
  };
}
