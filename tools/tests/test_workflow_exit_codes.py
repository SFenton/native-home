"""Workflow steps run under `bash -e`: an exit code read as `cmd; rc=$?` is never read, because the failing command ends
the step first. Steps read it as `rc=0; cmd || rc=$?`."""

import re
import subprocess
import unittest
from pathlib import Path

WORKFLOWS = Path(__file__).resolve().parents[2] / ".github" / "workflows"


class WorkflowExitCodeTests(unittest.TestCase):
    def test_no_step_reads_an_exit_code_after_a_semicolon(self):
        offenders = []
        for path in sorted(WORKFLOWS.glob("*.yml")):
            for number, line in enumerate(path.read_text().splitlines(), 1):
                if re.search(r";\s*\w+=\$\?", line):
                    offenders.append(f"{path.name}:{number}: {line.strip()}")
        self.assertEqual(offenders, [], "use `rc=0; cmd || rc=$?` under bash -e")

    def test_no_step_reads_an_exit_code_on_the_line_after_a_command(self):
        # `cmd` then `code=$?` on the next line ends the step at `cmd` under bash -e just the same.
        offenders = []
        for path in sorted(WORKFLOWS.glob("*.yml")):
            lines = path.read_text().splitlines()
            for number, line in enumerate(lines, 1):
                if not re.match(r"\s*\w+=\$\?\s*$", line) or number < 2:
                    continue
                before = lines[number - 2].strip()
                if before and not before.startswith("#") and not before.endswith(("|", "&&", "\\", "|-")) \
                        and not re.match(r"(-\s*)?run:|set \+e", before):
                    offenders.append(f"{path.name}:{number}: {before} / {line.strip()}")
        self.assertEqual(offenders, [], "use `code=0; cmd || code=$?` under bash -e")

    def test_the_or_form_reads_the_code_under_bash_e(self):
        script = 'rc=0\nfilters="$(exit 3)" || rc=$?\necho "$rc"\n'
        out = subprocess.run(["bash", "-e", "-o", "pipefail", "-c", script], capture_output=True, text=True)
        self.assertEqual((out.returncode, out.stdout.strip()), (0, "3"))


if __name__ == "__main__":
    unittest.main()
