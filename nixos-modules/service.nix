{
  config,
  pkgs,
  lib ? pkgs.lib,
  ...
}:

with lib;

let
  cfg = config.services.managed-docker-compose;

  managed-docker-compose = pkgs.callPackage ../package.nix {};

  backendStr = if cfg.backend == "podman" then "podman"
    else if cfg.backend == "docker" then "docker"
    else if cfg.backend == "" then config.virtualisation.oci-containers.backend
    else throw "Invalid docker compose backend: ${cfg.backend}";


  resolveSubstitutions = import ../resolve-substitutions.nix;

  composeFiles = lib.mapAttrsToList (name: appCfg:
    if lib.isAttrs appCfg.substitutions && appCfg.substitutions == {} then
      appCfg.compose_file
    else if builtins.isString appCfg.compose_file then
      throw ''
        Error in application "${name}": 
        Substitutions are not supported if `compose_file` is a path already on the remote
        system, as indicated by using a quoted string and not a path.
        You provided: ${toString appCfg.compose_file}
        Hint: use a Nix path like ./path/to/file instead of a string like "/etc/compose.yml"
      ''
    else let 
      content = builtins.readFile appCfg.compose_file;
      resolved = resolveSubstitutions content appCfg.substitutions;
    in
      pkgs.writeText "compose.yml" resolved
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
  options = {
    services.managed-docker-compose = rec {
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
            compose_file = mkOption {
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
  };

  config = mkIf cfg.enable {
    
    # Give system the right packages, including our own
    environment.systemPackages = [ managed-docker-compose ] ++ envSysPackages;

    # Setup the right virtualisation modules depending on backend.
    virtualisation.docker.enable = mkIf (backendStr == "docker") true;
    virtualisation.containers.enable = mkIf (backendStr == "docker") true;
    virtualisation.podman.enable = mkIf (backendStr == "podman") true;

    # Run the docker-compose-update.py script each time we activate/deploy.
    systemd.services.managed-docker-compose = {
      description = "Update Docker Compose files as part of nix config";
      wantedBy = [ "multi-user.target" ];
      path = envSysPackages;
      serviceConfig = {
        Type = "simple";
        ExecStart = "${managed-docker-compose}/bin/docker-compose-update.sh -b ${backendStr} ${concatStringsSep " " (map (file: "-f \"${file}\"") composeFiles)}";
        TimeoutSec = 90;
      };
    };
  };
}
