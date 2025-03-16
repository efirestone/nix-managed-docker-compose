{ pkgs, writeTextFile }:

writeTextFile {
  name = "docker-compose-update";
  executable = true;
  destination = "/bin/docker-compose-update.sh";
  text = ''
    #!${pkgs.python3}/bin/python3
  '' + builtins.readFile ./script/dockercomposeupdate.py;
}
