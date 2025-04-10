import os
from command_runner import CommandRunner
from file_system import FileSystem
from pathlib import Path

class RunningContainerInfo:
    def __init__(self, compose_file_path, project_name):
        self.compose_file_path = compose_file_path
        self.project_name = project_name

class DockerUtils:
    def __init__(self, docker_backend: str, command_runner: CommandRunner, file_system: FileSystem):
        self.docker_backend = docker_backend
        self.command_runner = command_runner
        self.file_system = file_system

    def info_for_container(self, container_id) -> RunningContainerInfo:
        """Find the docker compose file associated with a running container."""
        if not container_id:
            raise ValueError("Usage: compose_file_for_container <container_id>")

        compose_dir = self.command_runner.run(
            self.docker_backend,
            "inspect",
            container_id,
            "--format={{ index .Config.Labels \"com.docker.compose.project.working_dir\" }}"
        ).stdout
        compose_file = self.command_runner.run(
            self.docker_backend,
            "inspect",
            container_id,
            "--format={{ index .Config.Labels \"com.docker.compose.project.config_files\" }}"
        ).stdout
        project_name = self.command_runner.run(
            self.docker_backend,
            "inspect",
            container_id,
            "--format={{ index .Config.Labels \"com.docker.compose.project\" }}"
        ).stdout

        if not compose_file.startswith(compose_dir):
            compose_file = os.path.join(compose_dir, compose_file)

        compose_file_path = str(Path(compose_file).resolve()) if self.file_system.exists(Path(compose_file)) else None
        if compose_file_path == None:
            return None

        # Return both the compose.yaml path as well as the project name. If only the compose file path is given
        # then `docker compose down` tries to derive the project from the containing directory name, but with the Nix store
        # that's likely not the correct project name.
        return RunningContainerInfo(compose_file_path=compose_file_path, project_name=project_name)            

    def collect_info_for_running_containers(self) -> list[RunningContainerInfo]:
        """Find all compose files for currently running containers."""

        container_ids = self.command_runner.run(self.docker_backend, "ps", "-q").stdout.splitlines()
        container_infos = set()

        for container_id in container_ids:
            info = self.info_for_container(container_id)
            if info:
                container_infos.add(info)

        return container_infos
    
    def compose_down(self, info: RunningContainerInfo):
        self.command_runner.run(self.docker_backend, "compose", "-p", info.project_name, "--file", info.compose_file_path, "down")

    def compose_up(self, path: str):
        self.command_runner.run(self.docker_backend, "compose", "--file", path, "up", "--detach")
