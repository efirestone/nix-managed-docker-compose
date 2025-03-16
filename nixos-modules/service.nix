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
      startAt = "post-activation";
      path = envSysPackages;
      serviceConfig = {
        Type = "simple";
        ExecStart = "${managed-docker-compose}/bin/docker-compose-update.sh ${backendStr}";
        TimeoutSec = 90;
      };
    };
  };
}
