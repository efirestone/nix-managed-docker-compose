#!/usr/bin/env python3
import argparse
import json
import shutil
import sys
from command_runner import RealCommandRunner
from docker_utils import DockerUtils
from file_system import RealFileSystem
from pathlib import Path
from substituter import Substituter

def main():
    parser = argparse.ArgumentParser(description="Update running Docker containers using Docker Compose")
    parser.add_argument("-c", "--config", help="The configuration JSON file")
    parser.add_argument("-o", "--output_dir", help="Output file path", default="/run/nix-docker-compose")
    args = parser.parse_args()

    command_runner = RealCommandRunner()
    file_system = RealFileSystem()

    try:
        with open(args.config) as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        sys.exit(f"Failed to parse JSON input: {e}")

    backend = data.get("backend")
    projects = dict(data.get("projects"))

    output_dir = Path(args.output_dir)
    substituter = Substituter(file_system=file_system, output_dir=output_dir)
    current_compose_files = set()
    for name, app_config in projects.items():
        resolved_path = substituter.substitute(
            path=Path(app_config.get("composeFile")),
            project_name=name,
            substitutions=app_config.get("substitutions"),
            secrets=app_config.get("secrets")
        )
        current_compose_files.add(resolved_path)

    docker_utils = DockerUtils(
        docker_backend=backend,
        command_runner=command_runner,
        file_system=file_system
    )

    running_container_infos = docker_utils.collect_info_for_running_containers()

    # For debugging
    # print(f"Current files: {current_compose_files}")
    # print(f"Running files: {set(map(lambda i: i.compose_file_path, running_container_infos))}")

    stale_containers = filter(lambda i: i.compose_file_path not in current_compose_files, running_container_infos)

    for container_info in stale_containers:
        print(f"Unloading: {container_info.compose_file_path}")
        docker_utils.compose_down(info=container_info)

        # Delete the old compose file as it contained secrets and we don't want to leave it around.
        clean_up_compose_file(container_info.compose_file_path, output_dir)

    for compose_file in current_compose_files:
        print(f"Loading: {compose_file}")
        docker_utils.compose_up(path=compose_file)

def clean_up_compose_file(compose_file_path: Path, output_dir: Path):
    try:
        compose_file_path.resolve().relative_to(output_dir.resolve())
    except ValueError:
        # The compose file is not within the secrets directory, so don't try to delete it.
        # Compose files that didn't include substitutions are kept in the Nix store, which we can't
        # (and shouldn't) modify.
        return

    try:
        shutil.rmtree(str(compose_file_path.parent))
    except Exception as e:
        print(f"❌ Failed to delete {compose_file_path.parent}: {e}")

if __name__ == "__main__":
    main()
