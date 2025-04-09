#!/usr/bin/env python3
import argparse
import json
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

    substituter = Substituter(file_system=file_system, output_dir=Path(args.output_dir))
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

    for compose_file in current_compose_files:
        print(f"Loading: {compose_file}")
        docker_utils.compose_up(path=compose_file)

if __name__ == "__main__":
    main()
