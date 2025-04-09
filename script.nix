{ pkgs }:

let
  pythonEnv = pkgs.python3.withPackages (ps: with ps; [ ]);
in
  pkgs.stdenv.mkDerivation {
    pname = "managed-docker-compose";
    version = "0.1";

    src = ./script;

    nativeBuildInputs = [ pkgs.makeWrapper ];

    buildInputs = [ pythonEnv ];

    installPhase = ''
      mkdir -p $out/lib/managed-docker-compose
      cp -r . $out/lib/managed-docker-compose

      mkdir -p $out/bin
      makeWrapper ${pythonEnv}/bin/python3 $out/bin/managed-docker-compose \
        --add-flags "$out/lib/managed-docker-compose/src/main.py"
    '';
  }
