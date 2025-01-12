{pkgs ? import <nixpkgs> {}}: {
  agenix = pkgs.callPackage ./package.nix {};
}