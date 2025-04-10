{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.managedDockerCompose;

  managedDockerCompose = pkgs.callPackage ./script.nix {};

  backendStr = if cfg.backend == "podman" then "podman"
    else if cfg.backend == "docker" then "docker"
    else if cfg.backend == "" then config.virtualisation.oci-containers.backend
    else throw "Invalid docker compose backend: ${cfg.backend}";

  envSysPackages = if backendStr == "podman" then [
    pkgs.python3
    pkgs.podman
    pkgs.podman-compose
  ] else [
    pkgs.python3
    pkgs.docker
    pkgs.docker-compose
  ];

  resolvedComposeFilesDirectory = "/run/nix-docker-compose";

  # Write the config options out to a JSON file, which will then be read by the Python script.
  configFile = pkgs.writeTextFile {
    name = "managed-docker-compose-config.json";
    text = (builtins.toJSON cfg);
  };
in {
  options.services.managedDockerCompose = rec {
    enable = mkEnableOption "Enable automatic docker compose file management.";
    backend = lib.mkOption {
      type = types.str;
      default = config.virtualisation.oci-containers.backend;
      description = ''
        The virtualisation backend to use (either \"docker\" or \"podman\"). Defaults to virtualisation.oci-containers.backend.
      '';
    };

    projects = mkOption {
      type = types.attrsOf (types.submodule ({
        options = {
          composeFile = mkOption {
            type = types.path;
            description = "Path to the Docker Compose file.";
          };

          substitutions = mkOption {
            type = types.attrsOf types.str;
            default = {};
            description = "Attribute set of variable substitutions to apply to Docker Compose files. For example, ${projectName} in compose.yaml will be replaced by substitutions.projectName.";
            example = {
              projectName = "my-app";
              imageName = "my-image";
              dbUser = "admin";
            };
          };

          secrets = mkOption {
            type = types.attrsOf types.path;
            default = {};
            description = "Attribute set of variable substitutions to apply to Docker Compose files. For example, ${dbPassword} in compose.yaml will be replaced by the contents of the file specified by secrets.dbPassword.";
            example = {
              dbPassword = "/etc/db_password";
            };
          };
        };
      }));
      default = {};
      description = "Set of managed Docker Compose projects.";
    };
  };

  config = mkIf cfg.enable {
    # Give system the right packages, including our own
    environment.systemPackages = [ managedDockerCompose ] ++ envSysPackages;

    # Enable the container service if we're running Docker. Podman doesn't need it.
    virtualisation.containers.enable = mkIf (backendStr == "docker") true;

    # Do some file system setup. This must be done in an activation script when we have
    # root access and can still modify certain things.
    system.activationScripts."managed-docker-compose" = {
      text = ''
        # Delete the old compose files, which may contain secrets.
        # We'll recreate them if they're still valid.
        rm -rf "${resolvedComposeFilesDirectory}/*"

        mkdir -p "${resolvedComposeFilesDirectory}"
        chmod 0751 "${resolvedComposeFilesDirectory}"

        # Create a RAM disk to ensure the secrets don't survive a reboot and aren't
        # available to someone sniffing the hard drive.
        # If this package is still included then we'll recreate them.
        grep -q "${resolvedComposeFilesDirectory} ramfs" /proc/mounts ||
          mount -t ramfs none "${resolvedComposeFilesDirectory}" -o nodev,nosuid,mode=0751
      '';
    };

    # Run the docker-compose-update.py script each time we activate/deploy.
    systemd.services.managed-docker-compose = {
      description = "Update Docker Compose files as part of nix config";
      wantedBy = [ "multi-user.target" ];
      path = envSysPackages;
      serviceConfig = let
        composeFileArgs = (map (file: "-f \"${lib.escapeShellArg file}\"") composeFiles);
        combinedArgs = concatStringsSep " " composeFileArgs;
      in {
        Type = "simple";
        ExecStart = "${managedDockerCompose}/bin/managed-docker-compose -c ${configFile} -o ${resolvedComposeFilesDirectory}";
        TimeoutSec = 90;
      };
    };
  };
}
