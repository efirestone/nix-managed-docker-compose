class FakeFileSystem:
    def __init__(self, existing_paths):
        self.existing_paths = existing_paths

    def exists(self, path) -> bool:
        return path in self.existing_paths
