import unittest
from command_runner import CommandRunner
from docker_utils import DockerUtils
from fake_command_runner import FakeCommandRunner
from fake_file_system import FakeFileSystem
from substituter import Substituter
from pathlib import Path

# To run this, run "PYTHONPATH=script/src python3 -m unittest discover -s script/tests"
class TestDockerComposeUpdate(unittest.TestCase):
    # Test fetching the compose yaml path for a running docker service.
    # This variant tests when docker returns a relative path for the
    # com.docker.compose.project.config_files attribute.
    def test_info_for_container_with_relative_config_file(self):
        command_runner = FakeCommandRunner(
            responses=[
                CommandRunner.RunResult(returncode=0, stdout="/the/containing/dir"),
                # Sometimes the config file is returned relative to the working directory
                CommandRunner.RunResult(returncode=0, stdout="compose.yaml"),
                CommandRunner.RunResult(returncode=0, stdout="the_project"),
            ]
        )
        file_system = FakeFileSystem(
            content={ Path("/the/containing/dir/compose.yaml"): "" }
        )

        docker_utils = DockerUtils(docker_backend="docker", command_runner=command_runner, file_system=file_system)
        info = docker_utils.info_for_container("container_id")

        self.assertEqual(
            command_runner.commands,
            [
                ("docker", "inspect", "container_id", "--format={{ index .Config.Labels \"com.docker.compose.project.working_dir\" }}"),
                ("docker", "inspect", "container_id", "--format={{ index .Config.Labels \"com.docker.compose.project.config_files\" }}"),
                ("docker", "inspect", "container_id", "--format={{ index .Config.Labels \"com.docker.compose.project\" }}"),
            ]
        )

        self.assertEqual(info.compose_file_path, Path("/the/containing/dir/compose.yaml"))
        self.assertEqual(info.project_name, "the_project")

    # Test fetching the compose yaml path for a running docker service.
    # This variant tests when docker returns an absolute path for the
    # com.docker.compose.project.config_files attribute.
    def test_info_for_container_with_absolute_config_file(self):
        compose_file_path = Path("/the/containing/dir/compose.yml")
        command_runner = FakeCommandRunner(
            responses=[
                CommandRunner.RunResult(returncode=0, stdout="/the/containing/dir"),
                # Sometimes the config file is returned as an absolute path
                CommandRunner.RunResult(returncode=0, stdout=str(compose_file_path)),
                CommandRunner.RunResult(returncode=0, stdout="the_project"),
            ]
        )
        file_system = FakeFileSystem(
            content={ compose_file_path: "" }
        )

        docker_utils = DockerUtils(docker_backend="docker", command_runner=command_runner, file_system=file_system)
        info = docker_utils.info_for_container("container_id")

        self.assertEqual(
            command_runner.commands,
            [
                ("docker", "inspect", "container_id", "--format={{ index .Config.Labels \"com.docker.compose.project.working_dir\" }}"),
                ("docker", "inspect", "container_id", "--format={{ index .Config.Labels \"com.docker.compose.project.config_files\" }}"),
                ("docker", "inspect", "container_id", "--format={{ index .Config.Labels \"com.docker.compose.project\" }}"),
            ]
        )

        self.assertEqual(info.compose_file_path, compose_file_path)
        self.assertEqual(info.project_name, "the_project")

class TestSubstituter(unittest.TestCase):
    def test_substitute(self):
        file_system = FakeFileSystem()
        file_system.write_text(Path("/tmp/secret"), "N@^ahX@@M8Vwz1ER4sZ@3P@F")

        template_path = Path("/tmp/compose.yml")
        file_system.write_text(
            template_path,
            '''
services:
  # https://forgejo.org/docs/next/admin/installation-docker/
  forgejo:
    # Use [digest pinning](https://docs.renovatebot.com/docker/#digest-pinning) and rely on renovatebot
    image: codeberg.org/forgejo/forgejo:10-rootless@sha256:5658d26e908b9acb533f86616000dd3d9619085e6979aa394d89142ed69f19b2
    restart: unless-stopped
    container_name: forgejo
    environment:
      FORGEJO__database__DB_TYPE: mysql
      FORGEJO__database__HOST: db:3306
      FORGEJO__database__NAME: forgejo
      FORGEJO__database__USER: forgejo
      FORGEJO__database__PASSWD: "${mysqlPassword}"
    networks:
      forgejo:
      macvlan:
        ipv4_address: 10.1.10.120
        # mac_address: 02:42:0a:01:0a:fc
    user: ${uid}:${gid}
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - /etc/timezone:/etc/timezone:ro
      - /services/forgejo/config:/etc/gitea
      - /services/forgejo/data:/var/lib/gitea
    depends_on:
      - db

  db:
    image: mysql:8.0.41@sha256:0c28992fc27c2f6e253e3e8900318cc26ebc59b724036d41b626134a29e80268
    restart: unless-stopped
    container_name: forgejo-mysql
    environment:
      MYSQL_ROOT_PASSWORD_FILE: /run/secrets/mysql_root_password
      MYSQL_USER: forgejo
      MYSQL_PASSWORD_FILE: /run/secrets/mysql_password
      MYSQL_DATABASE: forgejo
    networks:
      forgejo:
    volumes:
      - /services/forgejo/mysql:/var/lib/mysql
    secrets:
      - mysql_password
      - mysql_root_password

networks:
  forgejo:
    external: false
  macvlan:
    external: true

secrets:
   mysql_password:
     file: ${mysqlPasswordFile}
   mysql_root_password:
     file: ${mysqlRootPasswordFile}
            '''
        )

        substituter = Substituter(file_system=file_system, output_dir=Path("/tmp/"))

        new_path = substituter.substitute(
            path=template_path,
            project_name="proj",
            substitutions={
                "uid": "777",
                "gid": "743",
                "mysqlPasswordFile": "/tmp/secret",
                "mysqlRootPasswordFile": "/tmp/secret",
            },
            secrets={ "mysqlPassword": "/tmp/secret" }
        )

        resolved_content = file_system.read_text(new_path)

        print(f"Resolved content:\n{resolved_content}")

        self.assertEqual(
            resolved_content,
            '''
              DB_USER: dbuser
              DB_PASSWD: "secret_pass"
            '''
        )

if __name__ == '__main__':
    unittest.main()
