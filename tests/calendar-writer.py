"""Check calendar persistence using local git and a stand-in GitHub CLI.

Adapted from Economic/realtalk's calendar writer tests at 577c812073f10b31d5380ac0fc7719befaee93f0.
"""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


WRITER = Path(__file__).resolve().parents[1] / ".github/scripts/update-calendar.sh"


class CalendarWriterTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        bindir = self.directory / "bin"
        bindir.mkdir()
        gh = bindir / "gh"
        gh.write_text("#!/bin/sh\n[ \"$*\" = 'auth setup-git' ]\n")
        gh.chmod(0o755)
        self.env = {
            **os.environ,
            "PATH": f"{bindir}{os.pathsep}{os.environ['PATH']}",
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_CONFIG_NOSYSTEM": "1",
        }
        self.remote = self.directory / "remote.git"
        self.checkout = self.directory / "checkout"
        self.git("init", "--quiet", "--bare", str(self.remote))
        self.git("init", "--quiet", "--initial-branch=main", str(self.checkout))
        self.git("config", "user.name", "Fixture", cwd=self.checkout)
        self.git("config", "user.email", "fixture@example.invalid", cwd=self.checkout)
        self.git("config", "core.hooksPath", "/dev/null", cwd=self.checkout)
        self.git("config", "commit.gpgsign", "false", cwd=self.checkout)
        (self.checkout / "main-code").write_text("main stays unchanged\n")
        self.git("add", ".", cwd=self.checkout)
        self.git("commit", "--quiet", "-m", "main fixture", cwd=self.checkout)
        self.git("remote", "add", "origin", str(self.remote), cwd=self.checkout)
        self.git("push", "--quiet", "origin", "main", cwd=self.checkout)
        self.main = self.git("rev-parse", "main", cwd=self.checkout)
        self.schedule = self.directory / "schedule.json"
        self.schedule.write_text(json.dumps({"refreshed_at": "2026-10-28T12:00:00Z", "events": []}) + "\n")

    def git(self, *args, cwd=None):
        result = subprocess.run(["git", *args], cwd=cwd, env=self.env, check=True, capture_output=True, text=True)
        return result.stdout.strip()

    def write(self, schedule=None, check=True):
        return subprocess.run(
            ["bash", str(WRITER), str(schedule or self.schedule)],
            cwd=self.checkout, env=self.env, check=check, capture_output=True, text=True,
        )

    def remote_git(self, *args):
        return self.git("--git-dir", str(self.remote), *args)

    def assert_main_unchanged(self):
        self.assertEqual(self.remote_git("rev-parse", "main"), self.main)
        self.assertEqual(self.git("rev-parse", "HEAD", cwd=self.checkout), self.main)
        self.assertEqual(self.git("status", "--porcelain", cwd=self.checkout), "")

    def test_first_save_creates_only_schedule_and_preserves_main(self):
        self.write()
        self.assertEqual(self.remote_git("ls-tree", "--name-only", "calendar"), "schedule.json")
        self.assertEqual(self.remote_git("show", "calendar:schedule.json"), self.schedule.read_text().strip())
        self.assert_main_unchanged()

    def test_later_save_updates_calendar_and_identical_save_adds_no_commit(self):
        self.write()
        previous = self.remote_git("rev-parse", "calendar")
        self.write()
        self.assertEqual(self.remote_git("rev-parse", "calendar"), previous)
        self.schedule.write_text(json.dumps({"refreshed_at": "2026-11-02T10:17:00Z", "events": []}) + "\n")
        self.write()
        self.assertNotEqual(self.remote_git("rev-parse", "calendar"), previous)
        self.assertEqual(self.remote_git("rev-parse", "calendar^"), previous)
        self.assertEqual(self.remote_git("show", "calendar:schedule.json"), self.schedule.read_text().strip())
        self.assert_main_unchanged()

    def test_existing_calendar_code_is_not_checked_out_over_main_or_executed(self):
        self.write()
        self.git("fetch", "--quiet", "origin", "calendar", cwd=self.checkout)
        self.git("switch", "--quiet", "-c", "calendar", "FETCH_HEAD", cwd=self.checkout)
        marker = self.directory / "executed"
        code = self.checkout / ".github/scripts/update-calendar.sh"
        code.parent.mkdir(parents=True)
        code.write_text(f"#!/bin/sh\ntouch '{marker}'\nexit 1\n")
        code.chmod(0o755)
        self.git("add", ".github", cwd=self.checkout)
        self.git("commit", "--quiet", "-m", "calendar branch code fixture", cwd=self.checkout)
        self.git("push", "--quiet", "origin", "calendar", cwd=self.checkout)
        self.git("switch", "--quiet", "main", cwd=self.checkout)
        self.schedule.write_text("{\"updated\": true}\n")
        self.write()
        self.assertFalse(marker.exists())
        self.assert_main_unchanged()
        changed = self.remote_git("diff-tree", "--no-commit-id", "--name-only", "-r", "calendar")
        self.assertEqual(changed, "schedule.json")

    def test_missing_or_symlink_artifact_preserves_previous_calendar(self):
        self.write()
        previous = self.remote_git("rev-parse", "calendar")
        link = self.directory / "link.json"
        link.symlink_to(self.schedule)
        for path in (self.directory / "missing.json", link):
            with self.subTest(path=path):
                self.assertNotEqual(self.write(path, check=False).returncode, 0)
                self.assertEqual(self.remote_git("rev-parse", "calendar"), previous)

    def test_existing_calendar_symlink_is_replaced_without_writing_its_target(self):
        self.write()
        self.git("fetch", "--quiet", "origin", "calendar", cwd=self.checkout)
        self.git("switch", "--quiet", "-c", "calendar", "FETCH_HEAD", cwd=self.checkout)
        target = self.directory / "untouched"
        target.write_text("keep this file\n")
        schedule = self.checkout / "schedule.json"
        schedule.unlink()
        schedule.symlink_to(target)
        self.git("add", "schedule.json", cwd=self.checkout)
        self.git("commit", "--quiet", "-m", "calendar symlink fixture", cwd=self.checkout)
        self.git("push", "--quiet", "origin", "calendar", cwd=self.checkout)
        self.git("switch", "--quiet", "main", cwd=self.checkout)
        self.write()
        self.assertEqual(target.read_text(), "keep this file\n")
        self.assertTrue(self.remote_git("ls-tree", "calendar", "schedule.json").startswith("100644 blob "))
        self.assertEqual(self.remote_git("show", "calendar:schedule.json"), self.schedule.read_text().strip())
        self.assert_main_unchanged()

    def test_connection_failure_preserves_previous_calendar(self):
        self.write()
        previous = self.remote_git("rev-parse", "calendar")
        self.git("remote", "set-url", "origin", str(self.directory / "unavailable.git"), cwd=self.checkout)
        self.assertNotEqual(self.write(check=False).returncode, 0)
        self.assertEqual(self.remote_git("rev-parse", "calendar"), previous)


if __name__ == "__main__":
    unittest.main()
