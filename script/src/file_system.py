import os
from pathlib import Path
from typing import Protocol

### File System

# Interacts with the file system. Defined as a protocol so that it can be faked out for testing.
class FileSystem(Protocol):
    def exists(self, path) -> bool:
        """Checks if a file system item exists"""

    def chmod(self, path, mode):
        """Changes the permissions for a given path"""

    def mkdir(dir: Path, mode: int = 0o777, parents: bool = False, exist_ok: bool = False):
        """Creates a directory at a given path"""

    def read_text(self, path: Path) -> str:
        """Reads text from a file at a given path"""

    def write_text(self, path: Path, text: str):
        """Writes text to a file at a given path"""

class RealFileSystem:
    def chmod(self, path, mode):
        os.chmod(path, mode)

    def exists(self, path) -> bool:
        return path.exists()

    def mkdir(self, path: Path, mode: int = 0o777, parents: bool = False, exist_ok: bool = False):
        path.mkdir(mode=mode, parents=parents, exist_ok=exist_ok)

    def read_text(self, path: Path) -> str:
        return path.read_text()

    def write_text(self, path: Path, text: str):
        path.write_text(text)
