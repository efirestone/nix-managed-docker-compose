# Nix Native Docker Compose Service

A nix service that runs docker-compose.yaml files included in your nix config repo. The service takes care of spinning down services from docker compose files that are no longer part of your config, and spins up 

# Usage

## With Flakes

If you use flakes, add the following lines to your flake.nix:

```
{
  inputs {
    managed-docker-compose.url = "github:efirestone/nix-managed-docker-compose/main";
    nixpkgs.url = "nixpkgs/nixos-24.11";
  };

  outputs = { self, nixpkgs, managed-docker-compose }: let
    system = "x86_64-linux";
  in {
    nixosConfigurations.myHost = nixpkgs.lib.nixosSystem {
      system = system;
      modules = [
        ./configuration.nix
        managed-docker-compose.nixOSModules.default
      ];
    };
  };
}
```

## Without Flakes

??

# Development

To test out any changes, run this at the repo root:

```
nix flake check -L --all-systems
```
