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
    environment.systemPackages = [ managed-docker-compose ];

    # Run the docker-compose-update.sh script each time we activate/deploy.
    systemd.services.managed-docker-compose = let 
      backend = if cfg.backend == "podman" then "podman"
        else if cfg.backend == "docker" then "docker"
        else if cfg.backend == "" then config.virtualisation.oci-containers.backend
        else throw "Invalid docker compose backend: ${cfg.backend}";
    in {
      description = "Update Docker Compose files as part of nix config";
      wantedBy = [ "multi-user.target" ];
      startAt = "post-activation";
      environment = {
        DOCKER_BACKEND = backend;
      };
      path = if backend == "podman" then [
        pkgs.podman
        pkgs.podman-compose
      ] else [
        pkgs.docker
        pkgs.docker-compose
      ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${managed-docker-compose}/bin/docker-compose-update.sh";
        TimeoutSec = 90;
      };
    };
  };
}
