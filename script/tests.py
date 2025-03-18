import unittest
from dockercomposeupdate import Application, CommandRunner
from pathlib import Path

class FakeCommandRunner:
    def __init__(self, responses: list[CommandRunner.RunResult]):
        self.responses = responses
        self.index = 0
        self.commands = []

    def run(self, *args) -> str:
        self.commands.append(args)
        self.index += 1
        return self.responses[self.index - 1]

class FakeFileSystem:
    def __init__(self, existing_paths):
        self.existing_paths = existing_paths

    def exists(self, path) -> bool:
        return path in self.existing_paths

# To run this, `cd` into `./script` and run `python -m unittest`
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

        app = Application()
        info = app.info_for_container("container_id", "docker", command_runner, file_system)

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

        app = Application()
        info = app.info_for_container("container_id", "docker", command_runner, file_system)

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
