from command_runner import CommandRunner

class FakeCommandRunner:
    def __init__(self, responses: list[CommandRunner.RunResult]):
        self.responses = responses
        self.index = 0
        self.commands = []

    def run(self, *args) -> str:
        self.commands.append(args)
        self.index += 1
        return self.responses[self.index - 1]
