import base64
import hashlib
from file_system import FileSystem
from pathlib import Path
from typing import Dict

class Substituter:
    def __init__(self, file_system: FileSystem, output_dir: Path):
        self.file_system = file_system
        self.output_dir = output_dir

    def substitute(self, path: Path, project_name: str, substitutions: Dict[str, str], secrets: Dict[str, str]) -> Path:
        if not self.file_system.exists(path):
            raise Exception(f"Compose file not found: {path}")

        # If we're not doing any substitutions, then don't write out a new file.
        if not substitutions and not secrets:
            return path

        template = self.file_system.read_text(path)

        # Apply substitutions
        for key, value in substitutions.items():
            template = template.replace(f"${{{key}}}", value)

        # Apply secrets
        for key, secret_path in secrets.items():
            secret_file = Path(secret_path)
            if not self.file_system.exists(secret_file):
                raise Exception(f"Secret file not found: {secret_path}")
            # self.file_system.write_text(Path("/tmp/some_secret"), "7dd02d9password")
            # secret_content = self.file_system.read_text(Path("/tmp/some_secret")) #secret_file)
            secret_content = self.file_system.read_text(secret_file).rstrip('\r')
            print(f"secret content: {secret_content}!!")
            template = template.replace(f"${{{key}}}", secret_content)

        # Write to output file
        # Include a hash of the contents so that if we change a compose file, the old one is still
        # there to spin down even after the new one has been spun up.
        sha256 = Substituter._nix_sha256_base32(template)

        project_dir = self.output_dir / f"{sha256}-{project_name}"
        self.file_system.mkdir(project_dir, parents=False, exist_ok=True)
        # project_dir.mkdir(parents=False, exist_ok=True)
        output_path = project_dir / "compose.yml"
        self.file_system.write_text(output_path, template)

        # Make the file not-world-readable since it may contain secrets
        self.file_system.chmod(project_dir, 0o551)
        self.file_system.chmod(output_path, 0o440)

        return output_path

    @staticmethod
    def _nix_base32_encode(data: bytes) -> str:
        # Nix uses its own base32 alphabet:
        nix_alphabet = '0123456789abcdfghijklmnpqrsvwxyz'
        std_alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'
        b32 = base64.b32encode(data).decode('utf-8').lower().strip('=')

        trans = str.maketrans(std_alphabet.lower(), nix_alphabet)
        return b32.translate(trans)

    @staticmethod
    def _nix_sha256_base32(s: str) -> str:
        sha256 = hashlib.sha256(s.encode('utf-8')).digest()
        return Substituter._nix_base32_encode(sha256)
