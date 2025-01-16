# not sure this file is strictly necessary, but leaving it here for now
{pkgs ? import <nixpkgs> {}}: {
  managed-docker-compose = pkgs.callPackage ./package.nix {};
}