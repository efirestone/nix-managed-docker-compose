{ pkgs, writeTextFile }:

writeTextFile {
  name = "docker-compose-update";
  executable = true;
  destination = "/bin/docker-compose-update.sh";
  text = ''
    #!${pkgs.runtimeShell}
  '' + builtins.readFile ./docker-compose-update.sh;
}
