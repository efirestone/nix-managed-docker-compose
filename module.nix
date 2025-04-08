{ config, lib, pkgs, substituteVars, ... }:

with lib;

let
  cfg = config.services.managedDockerCompose;

  managedDockerCompose = pkgs.callPackage ./package.nix {};

  backendStr = if cfg.backend == "podman" then "podman"
    else if cfg.backend == "docker" then "docker"
    else if cfg.backend == "" then config.virtualisation.oci-containers.backend
    else throw "Invalid docker compose backend: ${cfg.backend}";

  composeFiles = lib.mapAttrsToList (name: appCfg:
    if lib.isAttrs appCfg.substitutions && appCfg.substitutions == {} then
      appCfg.composeFile
    else if builtins.isString appCfg.composeFile then
      throw ''
        Error in application "${name}": 
        Substitutions are not supported if `composeFile` is a path already on the remote
        system, as indicated by using a quoted string and not a path.
        You provided: ${toString appCfg.composeFile}
        Hint: use a Nix path like ./path/to/file instead of a string like "/etc/compose.yml"
      ''
    else
      substituteVars ({
        src = appCfg.composeFile;
        substitutions = appCfg.substitutions;
      })
  ) cfg.applications;

  envSysPackages = if backendStr == "podman" then [
    pkgs.python3
    pkgs.podman
    pkgs.podman-compose
  ] else [
    pkgs.python3
    pkgs.docker
    pkgs.docker-compose
  ];
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

    applications = mkOption {
      type = types.attrsOf (types.submodule ({
        options = {
          composeFile = mkOption {
            type = types.path;
            description = "Path to the Docker Compose file.";
          };

          substitutions = mkOption {
            type = types.attrsOf types.str;
            default = {};
            description = "Attribute set of variable substitutions to apply to Docker Compose files. For example, @projectName@ in compose.yaml will be replaced by substitutions.projectName.";
            example = {
              projectName = "my-app";
              imageName = "my-image";
              dbUser = "admin";
              dbPassword = "secret";
            };
          };
        };
      }));
      default = {};
      description = "Set of managed Docker Compose applications.";
    };
  };

  config = mkIf cfg.enable {
    # Give system the right packages, including our own
    environment.systemPackages = [ managedDockerCompose ] ++ envSysPackages;

    # Setup the right virtualisation modules depending on backend.
    virtualisation.docker.enable = mkIf (backendStr == "docker") true;
    virtualisation.containers.enable = mkIf (backendStr == "docker") true;
    virtualisation.podman.enable = mkIf (backendStr == "podman") true;

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
        ExecStart = "${managedDockerCompose}/bin/docker-compose-update.sh -b ${backendStr} ${combinedArgs}";
        TimeoutSec = 90;
      };
    };
  };
}
