"""Exercise refresh PR maintenance with local Git repos and a stub GitHub CLI."""

import json
import os
from pathlib import Path
import subprocess
import tempfile


SCRIPT = Path(__file__).resolve().parents[1] / ".github/scripts/update-refresh-pr.sh"
WEB_FILES = [
    "epi_productivity_pay_gap_web.csv",
    "epi_productivity_pay_gap_web_stats.csv",
    "epi_productivity_pay_counter_web.csv",
]


def run(args, cwd, env=None):
    result = subprocess.run(args, cwd=cwd, env=env, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(f"{args}:\n{result.stdout}\n{result.stderr}")
    return result.stdout.strip()


def check_case(root, name, open_pr, fresh_value):
    case = root / name
    case.mkdir()
    remote = case / "origin.git"
    repo = case / "checkout"
    repo.mkdir()
    run(["git", "init", "--bare", "--quiet", str(remote)], case)
    run(["git", "init", "--quiet", "--initial-branch=main"], repo)

    def git(*args):
        return run(["git", *args], repo)

    git("config", "user.name", "Refresh fixture")
    git("config", "user.email", "fixture@example.com")
    git("config", "core.hooksPath", "/dev/null")
    git("config", "commit.gpgsign", "false")
    for folder in ("data_raw", "data_outputs", "data_final", "renv", "reports"):
        (repo / folder).mkdir()
    (repo / "data_raw/input.csv").write_text("fixture\n")
    (repo / "data_outputs/output.csv").write_text("fixture\n")
    (repo / "renv.lock").write_text("{}\n")
    (repo / "renv/activate.R").write_text("# fixture\n")

    def write_web(value):
        for filename in WEB_FILES:
            (repo / "data_final" / filename).write_text(f"fixture\n{value}\n")

    write_web(1)
    git("add", ".")
    git("commit", "--quiet", "-m", "main fixture")
    git("remote", "add", "origin", str(remote))
    git("push", "--quiet", "-u", "origin", "main")
    original_branch = None
    if open_pr:
        git("switch", "--quiet", "-c", "data-refresh")
        write_web(2)
        git("commit", "--quiet", "-am", "earlier refresh")
        git("push", "--quiet", "origin", "data-refresh")
        original_branch = git("rev-parse", "origin/data-refresh")
        git("switch", "--quiet", "main")
    main_commit = git("rev-parse", "HEAD")
    write_web(fresh_value)
    report = f"# Change report\n\n**Fixture revision**\n\nLatest report: {name}\n"
    (repo / "reports/change_report.md").write_text(report)
    capture = case / "capture"
    capture.mkdir()
    env = dict(os.environ, PATH=f"{root / 'bin'}:{os.environ['PATH']}",
               TEST_OPEN_PR="21" if open_pr else "", TEST_CAPTURE=str(capture))
    run(["bash", str(SCRIPT)], repo, env)
    calls = [json.loads(line) for line in (capture / "calls.jsonl").read_text().splitlines()]
    actions = [call[:2] for call in calls]

    if name == "unchanged":
        assert actions == [["pr", "list"], ["pr", "edit"]]
        assert "--title" not in calls[-1]
        assert git("rev-parse", "HEAD") == main_commit
        assert git("rev-parse", "origin/data-refresh") == original_branch
        assert report in (capture / "edit.md").read_text()
        assert "latest refresh build" in (capture / "edit.md").read_text()
    elif name == "stale":
        assert actions == [["pr", "list"], ["pr", "close"]]
        assert "--delete-branch" in calls[-1]
        assert git("rev-parse", "HEAD") == main_commit
    elif name == "no_changes_no_pr":
        assert actions == [["pr", "list"]]
        assert git("rev-parse", "HEAD") == main_commit
    elif name == "changed":
        assert actions == [["pr", "list"], ["auth", "setup-git"], ["pr", "edit"], ["pr", "comment"]]
        assert "--title" in calls[-2]
        assert git("rev-parse", "origin/data-refresh") != original_branch
        assert (capture / "comment.md").read_text() == report
        assert report in (capture / "edit.md").read_text()
    elif name == "new_pr":
        assert actions == [["pr", "list"], ["auth", "setup-git"], ["pr", "create"]]
        assert "--assignee" in calls[-1]
        assert git("rev-parse", "HEAD") == git("rev-parse", "origin/data-refresh")
        assert report in (capture / "create.md").read_text()
    print(f"Passed: {name}")


with tempfile.TemporaryDirectory(prefix="ppg-refresh-tests-") as directory:
    root = Path(directory)
    (root / "bin").mkdir()
    gh = root / "bin/gh"
    gh.write_text('''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import shutil
import sys

args = sys.argv[1:]
capture = Path(os.environ["TEST_CAPTURE"])
with (capture / "calls.jsonl").open("a") as log:
    log.write(json.dumps(args) + "\\n")
if args[:2] == ["pr", "list"]:
    print(os.environ["TEST_OPEN_PR"])
elif args[:2] in (["pr", "edit"], ["pr", "create"], ["pr", "comment"]):
    body = args[args.index("--body-file") + 1]
    shutil.copyfile(body, capture / (args[1] + ".md"))
elif args[:2] not in (["pr", "close"], ["auth", "setup-git"]):
    raise SystemExit("Unexpected gh call: " + repr(args))
''')
    gh.chmod(0o755)
    for name, open_pr, value in [
        ("unchanged", True, 2),
        ("stale", True, 1),
        ("no_changes_no_pr", False, 1),
        ("changed", True, 3),
        ("new_pr", False, 2),
    ]:
        check_case(root, name, open_pr, value)

print("Refresh PR lifecycle checks passed.")
