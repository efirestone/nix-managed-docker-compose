from pathlib import Path
from typing import Dict

class FakeFileSystem:
    class FileInfo:
        def __init__(self, mode: int = 0o775, text: str = None):
            self.mode = mode
            self.text = text
    class DirInfo:
        def __init__(self, mode: int = 0o775):
            self.mode = mode

    def __init__(self, content=dict()):
        self.content = content

    def chmod(self, path, mode):
        if not self.exists(path):
            print(f"Cannot change mode for non-existent file: {path}")
            raise FileNotFoundError

        self.content[path].mode = mode

    def exists(self, path) -> bool:
        return path in self.content

    def mkdir(self, path: Path, mode: int = 0o777, parents: bool = False, exist_ok: bool = False):
        if not exist_ok:
            if self.exists(path):
                raise FileExistsError

        self.content[path] = FakeFileSystem.DirInfo(mode=mode)

    def read_text(self, path: Path) -> str:
        if not self.exists(path):
            print(f"Cannot read text from non-existent file: {path}")
            raise FileNotFoundError
        return self.content[path].text

    def write_text(self, path: Path, text: str):
        self.content[path] = FakeFileSystem.FileInfo(text=text)
