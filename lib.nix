{ pkgs, config }:

pkgs.stdenv.mkDerivation {
  name = "managedDockerCompose";
  src = pkgs.writeText "greeting.txt" config.greeting;

  installPhase = ''
    mkdir -p $out
    cp $src $out/greeting.txt
  '';
}
