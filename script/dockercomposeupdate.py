import argparse
import os
import posixpath
import subprocess
from pathlib import Path
from typing import Protocol

### Command Runner

# Runs Terminal commands. Defined as a protocol so that it can be faked out for testing.
class CommandRunner(Protocol):
    class RunResult(object):
        def __init__(self, returncode, stdout, stderr=None):
            self.returncode = returncode
            self.stderr = stderr
            self.stdout = stdout

    def run(self, command) -> RunResult:
        """Run a shell command and return its output."""

class RealCommandRunner:
    def run(self, *args, check=True) -> str:
        result = subprocess.run(args, text=True, capture_output=True, check=check)
        return CommandRunner.RunResult(
            returncode=result.returncode,
            stderr=result.stderr.strip(),
            stdout=result.stdout.strip()
        )
    
class RunningContainerInfo:
    def __init__(self, compose_file_path, project_name):
        self.compose_file_path = compose_file_path
        self.project_name = project_name

### File System

# Interacts with the file system. Defined as a protocol so that it can be faked out for testing.
class FileSystem(Protocol):
    def exists(self, path) -> bool:
        """Checks if a file system item exists"""

class RealFileSystem:
    def exists(self, path) -> bool:
        return path.exists()

### Application

class Application:
    def info_for_container(self, container_id, docker_backend, command_runner, file_system) -> RunningContainerInfo:
        """Find the docker compose file associated with a running container."""
        if not container_id:
            raise ValueError("Usage: compose_file_for_container <container_id>")

        compose_dir = command_runner.run(
            docker_backend,
            "inspect",
            container_id,
            "--format={{ index .Config.Labels \"com.docker.compose.project.working_dir\" }}"
        ).stdout
        compose_file = command_runner.run(
            docker_backend,
            "inspect",
            container_id,
            "--format={{ index .Config.Labels \"com.docker.compose.project.config_files\" }}"
        ).stdout
        project_name = command_runner.run(
            docker_backend,
            "inspect",
            container_id,
            "--format={{ index .Config.Labels \"com.docker.compose.project\" }}"
        ).stdout

        if not compose_file.startswith(compose_dir):
            compose_file = os.path.join(compose_dir, compose_file)

        compose_file_path = str(Path(compose_file).resolve()) if file_system.exists(Path(compose_file)) else None
        if compose_file_path == None:
            return None

        # Return both the compose.yaml path as well as the project name. If only the compose file path is given
        # then `docker compose down` tries to derive the project from the containing directory name, but with the Nix store
        # that's likely not the correct project name.
        return RunningContainerInfo(compose_file_path=compose_file_path, project_name=project_name)            

    def collect_info_for_running_containers(self, docker_backend, command_runner, file_system) -> list[RunningContainerInfo]:
        """Find all compose files for currently running containers."""

        container_ids = command_runner.run(docker_backend, "ps", "-q").stdout.splitlines()
        container_infos = set()

        for container_id in container_ids:
            info = self.info_for_container(container_id, docker_backend, command_runner, file_system)
            if info:
                container_infos.add(info)

        return container_infos

def main():
    parser = argparse.ArgumentParser(description="Update running Docker containers to match the compose files in /etc/docker-compose.")
    parser.add_argument("-b", "--backend", help="The Docker command to use ('docker' or 'podman')")
    parser.add_argument("-f", "--compose_file", help="The path to a Docker Compose file", action='append')
    args = parser.parse_args()

    print(f"Running docker compose script using {args.backend}")

    app = Application()
    command_runner = RealCommandRunner()
    file_system = RealFileSystem()

    current_compose_files = set(args.compose_file)
    running_container_infos = app.collect_info_for_running_containers(args.backend, command_runner, file_system)

    # For debugging
    # print(f"Current files: {current_compose_files}")
    # print(f"Running files: {set(map(lambda i: i.compose_file_path, running_container_infos))}")
    
    stale_containers = filter(lambda i: i.compose_file_path not in current_compose_files, running_container_infos)

    for container_info in stale_containers:
        print(f"Unloading: {container_info.compose_file_path}")
        command_runner.run(args.backend, "compose", "-p", container_info.project_name, "--file", container_info.compose_file_path, "down")

    for compose_file in current_compose_files:
        print(f"Loading: {compose_file}")
        command_runner.run(args.backend, "compose", "--file", compose_file, "up", "--detach")

if __name__ == "__main__":
    main()
