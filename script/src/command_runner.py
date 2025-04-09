import subprocess
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
        result = subprocess.run(args, text=True, capture_output=True, check=False)
        if check and result.returncode != 0:
            raise Exception(f"""
                Command \"{args}\" returned non-zero exit status {result.returncode}
                stderr: {result.stderr}
                stdout: {result.stdout}
                """
            )

        return CommandRunner.RunResult(
            returncode=result.returncode,
            stderr=result.stderr.strip(),
            stdout=result.stdout.strip()
        )
