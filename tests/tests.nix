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
        composeFile = ./docker_compose.yml;
      };

      # Create a fake Docker image that we can "run"
      systemd.services.create-fake-docker-image = {
        description = "Create fake Docker image";
        before = [ "managed-docker-compose.service" ];
        requiredBy = [ "managed-docker-compose.service" ];
        path = with pkgs; [ docker gnutar ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "/bin/sh -c 'tar cv --files-from /dev/null | docker import - testimg'";
          TimeoutSec = 90;
        };
      };

      virtualisation.oci-containers.backend = "docker";
    };
    testScript = ''
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
        composeFile = ./docker_compose.yml;
      };

      # Create a fake Docker image that we can "run"
      systemd.services.create-fake-docker-image = {
        description = "Create fake Docker image";
        before = [ "managed-docker-compose.service" ];
        requiredBy = [ "managed-docker-compose.service" ];
        path = with pkgs; [ gnutar podman ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "/bin/sh -c 'tar cv --files-from /dev/null | podman import - testimg'";
          TimeoutSec = 90;
        };
      };
    };
    testScript = ''
      machine.wait_until_succeeds("podman ps --format='{{ .Image }}' | grep 'testimg'")
    '';
  };

  deactivateWithoutSubstitutionsTest = runTest {
    name = "deactivateOldComposeFilesWithoutSubstitutionsTest";
    nodes.machine = {
      imports = [ module ];

      # enable our custom module
      services.managedDockerCompose.enable = true;

      # Use docker and not podman for this test
      virtualisation.oci-containers.backend = "docker";

      services.managedDockerCompose.projects.testApp = {
        composeFile = ./current_app_compose.yml;
      };

      # Start an existing service. The managed-docker-compose service should spin this one down.
      systemd.services.start-existing-docker-container = {
        description = "Start existing Docker container";
        before = [ "managed-docker-compose.service" ];
        requiredBy = [ "managed-docker-compose.service" ];
        serviceConfig = {
          Type = "oneshot";
          # Create a fake Docker image that we can "run"
          ExecStartPre = ''
            /bin/sh -ec 'echo "Creating fake image..."; \
              ${pkgs.gnutar}/bin/tar cv --files-from /dev/null | ${pkgs.docker}/bin/docker import - testimg; \
              ${pkgs.docker}/bin/docker image inspect testimg > /dev/null'
          '';

          # Start the "old" docker container that we will spin down.
          ExecStart = [ "${pkgs.docker-compose}/bin/docker-compose --file /etc/docker-compose/old_app/compose.yaml up --detach --wait" ];
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
      # Make sure the new project spins up
      machine.wait_until_succeeds("docker ps --format='{{ .Names }}' | grep 'current_app'")

      # Make sure the old project spins down
      machine.wait_until_fails("docker ps --format='{{ .Names }}' | grep 'old_app'")
    '';
  };

  deactivateWithSubstitutionsTest = let
    oldComposeFile = pkgs.writeTextFile {
      name = "old_compose.yml";
      text = ''
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
    oldComposeFilePath = "/run/nix-docker-compose/old_app/compose.yml";
  in runTest {
    name = "deactivateOldComposeFilesWithSubstitutionsTest";
    nodes.machine = {
      imports = [ module ];

      # enable our custom module
      services.managedDockerCompose.enable = true;

      # Use docker and not podman for this test
      virtualisation.oci-containers.backend = "docker";

      services.managedDockerCompose.projects.testApp = {
        composeFile = ./current_app_compose.yml;
      };

      system.activationScripts.createOldDockerComposeYML.text = ''
        mkdir -p /run/nix-docker-compose/old_app
        cp "${oldComposeFile}" "${oldComposeFilePath}"
        chmod 751 "/run/nix-docker-compose"
        chmod 551 "/run/nix-docker-compose/old_app"
        chmod 440 "${oldComposeFilePath}"
      '';

      # Start an existing service. The managed-docker-compose service should spin this one down,
      # and because the compose.yml is in the secrets directory, it should try to delete it.
      systemd.services.start-existing-docker-container = {
        description = "Start existing Docker container";
        before = [ "managed-docker-compose.service" ];
        requiredBy = [ "managed-docker-compose.service" ];
        serviceConfig = {
          Type = "oneshot";
          # Create a fake Docker image that we can "run"
          ExecStartPre = ''
            /bin/sh -ec 'echo "Creating fake image..."; \
              ${pkgs.gnutar}/bin/tar cv --files-from /dev/null | ${pkgs.docker}/bin/docker import - testimg; \
              ${pkgs.docker}/bin/docker image inspect testimg > /dev/null'
          '';

          # Start the "old" docker container that we will spin down.
          ExecStart = [ "${pkgs.docker-compose}/bin/docker-compose --file ${oldComposeFilePath} up --detach --wait" ];
          TimeoutSec = 90;
        };
      };
    };
    testScript = ''
      # Make sure the new project spins up
      machine.wait_until_succeeds("docker ps --format='{{ .Names }}' | grep 'current_app'")

      # Make sure the old project spins down
      machine.wait_until_fails("docker ps --format='{{ .Names }}' | grep 'old_app'")

      # Make sure the old secrets-containing compose file is deleted.
      machine.succeed("[ ! -e \"${oldComposeFilePath}\" ]")
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
          composeFile = ./substitute_compose.yml;
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
          path = with pkgs; [ docker gnutar ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "/bin/sh -c 'tar cv --files-from /dev/null | docker import - test-image'";
            TimeoutSec = 90;
          };
        };
      };
      testScript = ''
        # The name of the image we loaded was defined using a substitution and a secret (combined),
        # so if it loaded, then both were subbed in correctly.
        machine.wait_until_succeeds("docker ps --format='{{ .Image }}' | grep 'test-image'")

        mode = machine.succeed("stat -c \"%a\" /run/nix-docker-compose").strip()
        assert mode == "751", "Expected compose files directory to have non-world-readable permissions."

        test_app_dir = "2kr6ayhpr3ndfzaqif6vvkyqalri7hxpfh3i183kb47jc85pamsh-testApp"
        mode = machine.succeed(f"stat -c \"%a\" /run/nix-docker-compose/{test_app_dir}").strip()
        assert mode == "551", "Expected project directory to have non-world-readable permissions."

        mode = machine.succeed(f"stat -c \"%a\" /run/nix-docker-compose/{test_app_dir}/compose.yml").strip()
        assert mode == "440", "Expected compose file with secrets to have non-world-readable permissions."
      '';
  };
}
