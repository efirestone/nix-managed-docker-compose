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
        file_system.write_text(Path("/tmp/secret"), "secret_pass")

        template_path = Path("/tmp/compose.yml")
        file_system.write_text(
            template_path,
            '''
              DB_USER: ${user}
              DB_PASSWD: "${secr}"
            '''
        )

        substituter = Substituter(file_system=file_system, output_dir=Path("/tmp/"))

        new_path = substituter.substitute(
            path=template_path,
            project_name="proj",
            substitutions={ "user": "dbuser" },
            secrets={ "secr": "/tmp/secret" }
        )

        resolved_content = file_system.read_text(new_path)

        self.assertEqual(
            resolved_content,
            '''
              DB_USER: dbuser
              DB_PASSWD: "secret_pass"
            '''
        )

if __name__ == '__main__':
    unittest.main()
