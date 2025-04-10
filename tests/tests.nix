{ module, pkgs, system }:

let 
  runTest = pkgs.nixosTest;
in {
  # To run the tests: nix flake check --all-systems
  # You may also want the -L and --verbose flags for additional debugging.
  dockerTest = runTest {
    name = "dockerTest";
    nodes.machine = {
      imports = [ module ];

      # enable our custom module
      services.managedDockerCompose.enable = true;

      services.managedDockerCompose.projects.testApp = {
        composeFile = "/tmp/compose.yml";
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
    };
    testScript = ''
      machine.copy_from_host("${./docker_compose.yml}", "/tmp/compose.yml")
      machine.wait_until_succeeds("docker ps --format='{{ .Image }}' | grep 'testimg'")
    '';
  };

  podmanTest = runTest {
    name = "podmanTest";
    nodes.machine = {
      imports = [ module ];

      # enable our custom module
      services.managedDockerCompose.enable = true;

      services.managedDockerCompose.projects.testApp = {
        composeFile = "/tmp/compose.yml";
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
    };
    testScript = ''
      machine.copy_from_host("${./docker_compose.yml}", "/tmp/compose.yml")
      machine.wait_until_succeeds("podman ps --format='{{ .Image }}' | grep 'testimg'")
    '';
  };

  deactivateTest = runTest {
    name = "deactivateOldComposeFilesTest";
    nodes.machine = {
      imports = [ module ];

      # enable our custom module
      services.managedDockerCompose.enable = true;

      # Use docker and not podman for this test
      virtualisation.oci-containers.backend = "docker";

      environment.systemPackages = with pkgs; [
        docker
        gnutar
      ];

      services.managedDockerCompose.projects.testApp = {
        composeFile = "/tmp/compose.yml";
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

      # This compose file isn't in the list of current files passed to the systemd service,
      # so it should be spun down.
      #
      # In the future we should only spin down projects that have a specific label (which we add)
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
      machine.copy_from_host("${./current_app_compose.yml}", "/tmp/compose.yml")

      # Make sure the new project spins up
      machine.wait_until_succeeds("docker ps --format='{{ .Names }}' | grep 'current_app'")

      # Make sure the old project spins down
      machine.wait_until_fails("docker ps --format='{{ .Names }}' | grep 'old_app'")
    '';
  };

  substitutionTest = runTest {
      name = "substitutionTest";
      nodes.machine = {
        imports = [ module ];

        # enable our custom module
        services.managedDockerCompose.enable = true;

        virtualisation.oci-containers.backend = "docker";

        environment.etc.secretpassword.text = "image";

        services.managedDockerCompose.projects.testApp = {
          composeFile = "/tmp/compose.yml";
          substitutions = {
            subbed = "test";
          };
          secrets = {
            secret = "/etc/secretpassword";
          };
        };

        # Create a fake Docker image that we can "run"
        systemd.services.create-fake-docker-image = {
          description = "Create fake Docker image";
          before = [ "managed-docker-compose.service" ];
          requiredBy = [ "managed-docker-compose.service" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "/bin/sh -c '${pkgs.gnutar}/bin/tar cv --files-from /dev/null | ${pkgs.docker}/bin/docker import - test-image'";
            TimeoutSec = 90;
          };
        };
      };
      testScript = ''
        machine.copy_from_host("${./substitute_compose.yml}", "/tmp/compose.yml")

        # The name of the image we loaded was defined using a substitution and a secret (combined),
        # so if it loaded, then both were subbed in correctly.
        machine.wait_until_succeeds("docker ps --format='{{ .Image }}' | grep 'test-image'")

        mode = machine.succeed("stat -c \"%a\" /run/nix-docker-compose").strip()
        assert mode == "751", "Expected compose files directory to have non-world-readable permissions."

        mode = machine.succeed("stat -c \"%a\" /run/nix-docker-compose/testApp").strip()
        assert mode == "551", "Expected project directory to have non-world-readable permissions."

        mode = machine.succeed("stat -c \"%a\" /run/nix-docker-compose/testApp/compose.yml").strip()
        assert mode == "440", "Expected compose file with secrets to have non-world-readable permissions."
      '';
  };
}
