import unittest
from command_runner import CommandRunner
from docker_utils import DockerUtils
from fake_command_runner import FakeCommandRunner
from fake_file_system import FakeFileSystem
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
            existing_paths=[Path("/the/containing/dir/compose.yaml")]
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

        self.assertEqual(info.compose_file_path, "/the/containing/dir/compose.yaml")
        self.assertEqual(info.project_name, "the_project")

    # Test fetching the compose yaml path for a running docker service.
    # This variant tests when docker returns an absolute path for the
    # com.docker.compose.project.config_files attribute.
    def test_info_for_container_with_absolute_config_file(self):
        command_runner = FakeCommandRunner(
            responses=[
                CommandRunner.RunResult(returncode=0, stdout="/the/containing/dir"),
                # Sometimes the config file is returned as an absolute path
                CommandRunner.RunResult(returncode=0, stdout="/the/containing/dir/compose.yaml"),
                CommandRunner.RunResult(returncode=0, stdout="the_project"),
            ]
        )
        file_system = FakeFileSystem(
            existing_paths=[Path("/the/containing/dir/compose.yaml")]
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

        self.assertEqual(info.compose_file_path, "/the/containing/dir/compose.yaml")
        self.assertEqual(info.project_name, "the_project")

if __name__ == '__main__':
    unittest.main()
