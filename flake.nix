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

    checks = forEachSystem (system: 
    let 
      runTest = nixpkgs.legacyPackages.${system}.testers.runNixOSTest;
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      # To run the tests: nix flake check --all-systems
      # You may also want the -L and --verbose flags for additional debugging.
      dockerTest = runTest {
        name = "dockerTest";
        nodes.machine = {
          imports = [ self.outputs.nixosModules.managed-docker-compose ];

          # enable our custom module
          services.managed-docker-compose.enable = true;

          services.managed-docker-compose.applications.test_app = {
            compose_file = "/etc/docker-compose/test/compose.yaml";
          };

          # Create a fake Docker image that we can "run"
          systemd.services.create-fake-docker-image = {
            description = "Create fake Docker image";
            before = [ "managed-docker-compose.service" ];
            requiredBy = [ "managed-docker-compose.service" ];
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "/bin/sh -c '${pkgs.gnutar}/bin/tar cv --files-from /dev/null | ${pkgs.docker}/bin/docker import - testimg'";
              TimeoutSec = 90;
            };
          };

          virtualisation.oci-containers.backend = "docker";

          # Run a very lightweight image, but also one that doesn't immediately exit.
          environment.etc."docker-compose/test/compose.yaml".text =
            ''
            services:
              myservice:
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
          machine.wait_until_succeeds("docker ps --format='{{ .Image }}' | grep 'testimg'")
        '';
      };

      podmanTest = runTest {
        name = "podmanTest";
        nodes.machine = {
          imports = [ self.outputs.nixosModules.managed-docker-compose ];

          # enable our custom module
          services.managed-docker-compose.enable = true;

          services.managed-docker-compose.applications.test_app = {
            compose_file = "/etc/docker-compose/test/compose.yaml";
          };

          # Create a fake Docker image that we can "run"
          systemd.services.create-fake-docker-image = {
            description = "Create fake Docker image";
            before = [ "managed-docker-compose.service" ];
            requiredBy = [ "managed-docker-compose.service" ];
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "/bin/sh -c '${pkgs.gnutar}/bin/tar cv --files-from /dev/null | ${pkgs.podman}/bin/podman import - testimg'";
              TimeoutSec = 90;
            };
          };

          # Run a very lightweight image, but also one that doesn't immediately exit.
          environment.etc."docker-compose/test/compose.yaml".text =
            ''
            services:
              myservice:
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
          machine.wait_until_succeeds("podman ps --format='{{ .Image }}' | grep 'testimg'")
        '';
      };

      deactivateTest = runTest {
        name = "deactivateOldComposeFilesTest";
        nodes.machine = {
          imports = [ self.outputs.nixosModules.managed-docker-compose ];

          # enable our custom module
          services.managed-docker-compose.enable = true;

          # Use docker and not podman for this test
          virtualisation.oci-containers.backend = "docker";

          environment.systemPackages = with pkgs; [
            docker
            gnutar
          ];

          services.managed-docker-compose.applications.test_app = {
            compose_file = "/etc/docker-compose/current_app/compose.yaml";
          };

          # Create a fake Docker image that we can "run"
          systemd.services.create-fake-docker-image = {
            description = "Create fake Docker image";
            before = [ "managed-docker-compose.service" ];
            requiredBy = [ "managed-docker-compose.service" ];
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "/bin/sh -c '${pkgs.gnutar}/bin/tar cv --files-from /dev/null | ${pkgs.docker}/bin/docker import - testimg'";
              TimeoutSec = 90;
            };
          };

          # Start an existing service. The managed-docker-compose service should spin this one down.
          systemd.services.start-existing-docker-container = {
            description = "Start existing Docker container";
            after = [ "create-fake-docker-image.service" ];
            before = [ "managed-docker-compose.service" ];
            requires = [ "create-fake-docker-image.service" ];
            requiredBy = [ "managed-docker-compose.service" ];
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${pkgs.docker}/bin/docker compose --file /etc/docker-compose/old_app/compose.yaml up --detach --wait";
              TimeoutSec = 90;
            };
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
          # Make sure the new application spins up
          machine.wait_until_succeeds("docker ps --format='{{ .Names }}' | grep 'current_app'")

          # Make sure the old application spins down
          machine.wait_until_fails("docker ps --format='{{ .Names }}' | grep 'old_app'")
        '';
      };

      substitutionTest = runTest {
          name = "substitutionTest";
          nodes.machine = {
            imports = [ self.outputs.nixosModules.managed-docker-compose ];

            # enable our custom module
            services.managed-docker-compose.enable = true;

            virtualisation.oci-containers.backend = "docker";

            services.managed-docker-compose.applications.test_app = let
              composeFile = pkgs.writeText "compose.yml"
                ''
                services:
                  myservice:
                    image: @image_name@
                    command: /bin/tail -f /dev/null
                    network_mode: none
                    volumes:
                      # Map the bin from the current system in so that we can execute `tail`
                      - /nix/store:/nix/store
                      - /run/current-system/sw/bin:/bin
                '';
            in {
              compose_file = composeFile;
              substitutions = {
                image_name = "testimg";
              };
            };

            # Create a fake Docker image that we can "run"
            systemd.services.create-fake-docker-image = {
              description = "Create fake Docker image";
              before = [ "managed-docker-compose.service" ];
              requiredBy = [ "managed-docker-compose.service" ];
              serviceConfig = {
                Type = "oneshot";
                ExecStart = "/bin/sh -c '${pkgs.gnutar}/bin/tar cv --files-from /dev/null | ${pkgs.docker}/bin/docker import - testimg'";
                TimeoutSec = 90;
              };
            };
          };
          testScript = ''
            machine.wait_until_succeeds("docker ps --format='{{ .Image }}' | grep 'testimg'")
          '';
      };
    });
  };
}
