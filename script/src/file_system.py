from typing import Protocol

### File System

# Interacts with the file system. Defined as a protocol so that it can be faked out for testing.
class FileSystem(Protocol):
    def exists(self, path) -> bool:
        """Checks if a file system item exists"""

class RealFileSystem:
    def exists(self, path) -> bool:
        return path.exists()
