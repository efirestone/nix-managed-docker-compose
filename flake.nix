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
      #
      # TO run the tests interactively:
      # `nix run .#checks.x86_64-linux.dockerTest.driver -- --interactive`
      # then after being dropped into python shell:
      # >>> machine.wait_for_unit("default.target")
      # >>> machine.shell_interact()
      #
      # see: https://blog.thalheim.io/2023/01/08/how-to-execute-nixos-tests-interactively-for-debugging/
      dockerTest = nixpkgs.legacyPackages.${system}.testers.runNixOSTest {
        name = "dockerTest";
        nodes.machine = {
          imports = [ self.outputs.nixosModules.managed-docker-compose ];

          environment.systemPackages = with nixpkgs.legacyPackages.${system}; [ 
            docker
            docker-compose
          ];

          # enable our custom module
          services.managed-docker-compose.enable = true;

          # our module requires these things (maybe it should enable them itself too?)
          virtualisation.oci-containers.backend = "docker";
          virtualisation.containers.enable = true;
          virtualisation.docker.enable = true;

          # Run a very lightweight image, but also one that doesn't immediately exit.
          environment.etc."docker-compose/test/docker-compose.yaml".text = 
            ''
            services:
              myservice:
                image: testimg
                command: /bin/tail -f /dev/null
                volumes:
                  # Map the bin from the current system in so that we can execute `tail`
                  - /nix/store:/nix/store
                  - /run/current-system/sw/bin:/bin
            '';
        };
        testScript = ''
          machine.wait_for_unit("managed-docker-compose.service")
          
          # Create a fake image to run
          machine.succeed("tar cv --files-from /dev/null | docker import - testimg")
          machine.wait_until_succeeds("docker ps --format='{{ .Image }}' | grep 'testimg'")
        '';
      };

      podmanTest = nixpkgs.legacyPackages.${system}.testers.runNixOSTest {
        name = "podmanTest";
        nodes.machine = {
          imports = [ self.outputs.nixosModules.managed-docker-compose ];

          environment.systemPackages = with nixpkgs.legacyPackages.${system}; [ 
            podman
            podman-compose
          ];

          # enable our custom module
          services.managed-docker-compose.enable = true;

          # our module requires these things (maybe it should enable them itself too?)
          virtualisation.oci-containers.backend = "podman";
          virtualisation.podman.enable = true;

          # Run a very lightweight image, but also one that doesn't immediately exit.
          environment.etc."docker-compose/test/docker-compose.yaml".text = 
            ''
            services:
              myservice:
                image: testimg
                command: /bin/tail -f /dev/null
                volumes:
                  # Map the bin from the current system in so that we can execute `tail`
                  - /nix/store:/nix/store
                  - /run/current-system/sw/bin:/bin
            '';
        };
        testScript = ''
          machine.wait_for_unit("managed-docker-compose.service")
          
          # Create a fake image to run
          machine.succeed("tar cv --files-from /dev/null | podman import - testimg")
          machine.wait_until_succeeds("podman ps --format='{{ .Image }}' | grep 'testimg'")
        '';
      };
    });
  };
}
