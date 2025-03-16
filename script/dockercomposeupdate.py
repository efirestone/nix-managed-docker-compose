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
    def compose_file_for_container(self, container_id, docker_backend, command_runner, file_system):
        """Find the docker compose file associated with a running container."""
        if not container_id:
            raise ValueError("Usage: compose_file_for_container <container_id>")

        compose_dir = command_runner.run(
            docker_backend,
            "inspect",
            container_id,
            "--format='{{ index .Config.Labels \"com.docker.compose.project.working_dir\" }}'"
        ).stdout
        compose_file = command_runner.run(
            docker_backend,
            "inspect",
            container_id,
            "--format='{{ index .Config.Labels \"com.docker.compose.project.config_files\" }}'"
        ).stdout

        if not compose_file.startswith(compose_dir):
            compose_file = os.path.join(compose_dir, compose_file)

        return str(Path(compose_file).resolve()) if file_system.exists(Path(compose_file)) else None

    def collect_compose_files_for_running_containers(self, docker_backend, command_runner, file_system):
        """Find all compose files for currently running containers."""

        container_ids = command_runner.run(docker_backend, "ps", "-q").stdout.splitlines()
        compose_files = set()

        for container_id in container_ids:
            compose_file = self.compose_file_for_container(container_id, docker_backend, command_runner, file_system)
            if compose_file:
                compose_files.add(compose_file)

        return sorted(compose_files)

    def collect_current_compose_files(self, directory: str):
        """Finds all docker-compose files in a directory, recursively.

        Args:
            directory (str): The directory to search within.

        Returns:
            list[Path]: A list of matching file paths.
        """

        dir = Path(directory)
        if not dir.is_dir():
            raise ValueError(f"Provided path '{directory}' is not a valid directory.")

        matches = []
        patterns = {
            "compose.yml",
            "compose.yaml",
            "container-compose.yml",
            "container-compose.yaml",
            "docker-compose.yml",
            "docker-compose.yaml",
        }

        for path in dir.walk():
            for file in path[2]:
                if file in patterns:
                    full_path = posixpath.join(path[0], file)
                    matches.append(str(full_path))

        return sorted(matches)

def main():
    parser = argparse.ArgumentParser(description="Update running Docker containers to match the compose files in /etc/docker-compose.")
    parser.add_argument("docker_backend", help="The Docker command to use ('docker' or 'podman')")
    args = parser.parse_args()

    ETC_DIR = "/etc/docker-compose"
    print(f"Running docker compose script using {args.docker_backend}")

    app = Application()
    command_runner = RealCommandRunner()
    file_system = RealFileSystem()

    current_compose_files = app.collect_current_compose_files(ETC_DIR)
    running_compose_files = app.collect_compose_files_for_running_containers(args.docker_backend, command_runner, file_system)

    stale_compose_files = sorted(set(running_compose_files) - set(current_compose_files))

    for compose_file in stale_compose_files:
        print(f"Unloading: {compose_file}")
        command_runner.run(args.docker_backend, "compose", "--file", compose_file, "down")

    for compose_file in current_compose_files:
        print(f"Loading: {compose_file}")
        command_runner.run(args.docker_backend, "compose", "--file", compose_file, "up", "--detach")

if __name__ == "__main__":
    main()
