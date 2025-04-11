import os
import hashlib
from file_system import FileSystem
from pathlib import Path
from typing import Dict

class Substituter:
    def __init__(self, file_system: FileSystem, output_dir: Path):
        self.file_system = file_system
        self.output_dir = output_dir

    def substitute(self, path: Path, project_name: str, substitutions: Dict[str, str], secrets: Dict[str, str]) -> Path:
        if not path.exists():
            raise Exception(f"Compose file not found: {path}")

        # If we're not doing any substitutions, then don't write out a new file.
        if not substitutions and not secrets:
            return path

        template = path.read_text()

        # Apply substitutions
        for key, value in substitutions.items():
            template = template.replace(f"${{{key}}}", value)

        # Apply secrets
        for key, secret_path in secrets.items():
            secret_file = Path(secret_path)
            if not secret_file.exists():
                raise Exception(f"Secret file not found: {secret_path}")
            secret_content = secret_file.read_text()
            template = template.replace(f"${{{key}}}", secret_content)

        # Write to output file
        # Include a hash of the contents so that if we change a compose file, the old one is still
        # there to spin down even after the new one has been spun up.
        sha256 = hashlib.sha256(template.encode('utf-8')).digest()

        project_dir = self.output_dir / f"{sha256}-{project_name}"
        project_dir.mkdir()
        output_path = project_dir / "compose.yml"
        output_path.write_text(template)

        # Make the file not-world-readable since it may contain secrets
        os.chmod(project_dir, 0o551)
        os.chmod(output_path, 0o440)

        return output_path
