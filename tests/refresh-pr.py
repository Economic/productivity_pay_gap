"""Exercise refresh PR decisions with real local Git repos and a stub GitHub CLI."""

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
URL = "https://github.com/Economic/productivity_pay_gap/pull/21"
OLD_RUN = "https://github.com/Economic/productivity_pay_gap/actions/runs/100"
NEW_RUN = "https://github.com/Economic/productivity_pay_gap/actions/runs/200"


def run(args, cwd, env=None):
    result = subprocess.run(args, cwd=cwd, env=env, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(f"{args}:\n{result.stdout}\n{result.stderr}")
    return result.stdout.strip()


def report(name, main, release="v2026.9.14"):
    return (
        "# Change report\n\n"
        f"Baselines: `main` at `{main}`; last published release `{release}`.\n\n"
        "**Fixture revisions pending**\n\n"
        f"Report fixture: {name}\n"
    )


def check_case(root, name, *, open_pr=True, fresh_value=2, mutations=None,
               update=False, notify=False, advance_main=False, legacy=False,
               release="v2026.9.14", repeat=False):
    case = root / name
    case.mkdir()
    remote = case / "origin.git"
    repo = case / "checkout"
    repo.mkdir()
    run(["git", "init", "--bare", "--quiet", str(remote)], case)
    run(["git", "init", "--quiet", "--initial-branch=main"], repo)

    def git(*args):
        return run(["git", *args], repo)

    def write(path, text):
        (repo / path).write_text(text)

    def write_web(value):
        for filename in WEB_FILES:
            write("data_final/" + filename, f"Year,Value\n2026q2,{value}\n")

    git("config", "user.name", "Refresh fixture")
    git("config", "user.email", "fixture@example.com")
    git("config", "core.hooksPath", "/dev/null")
    git("config", "commit.gpgsign", "false")
    for folder in ("data_raw", "data_outputs", "data_final", "data_inputs", "renv", "reports", "R"):
        (repo / folder).mkdir()
    write("data_raw/input.csv", "value\n1\n")
    write("data_raw/fetch_log.csv", "source,date_accessed,status\nbls_hours,2026-10-27,ok\n")
    write("data_raw/hours.xlsx", "fixture spreadsheet\n")
    write("data_outputs/output.csv", "value\n1\n")
    write("data_final/epi_productivity_pay_gap.csv", "value\n1.0001\n")
    write("data_final/epi_productivity_pay_gap_sources.csv",
          "source,date_accessed,date_published\nBLS,2026-10-27,2026-09-03\n")
    write("renv.lock", '{"Packages": {"fixture": {"Version": "1"}}}\n')
    write("renv/activate.R", "# fixture\n")
    write("R/combine.R", "# fixture\n")
    write("data_inputs/series.csv", "series\n1\n")
    write_web(1)
    git("add", ".")
    git("commit", "--quiet", "-m", "main fixture")
    git("remote", "add", "origin", str(remote))
    git("push", "--quiet", "-u", "origin", "main")
    initial_main = git("rev-parse", "HEAD")
    old_report = report("earlier proposal", initial_main)
    old_section = f"**Report updated:** [earlier build]({OLD_RUN})\n\n{old_report.strip()}"
    old_body = ("Earlier status\n\n<!-- refresh-report-start -->\n" + old_section
                + "\n<!-- refresh-report-end -->\n")
    if legacy:
        old_body = "Old introduction\n\n" + old_report
    original_branch = None
    if open_pr:
        git("switch", "--quiet", "-c", "data-refresh")
        write_web(2)
        git("commit", "--quiet", "-am", "earlier refresh")
        git("push", "--quiet", "origin", "data-refresh")
        original_branch = git("rev-parse", "origin/data-refresh")
        git("switch", "--quiet", "main")
    if advance_main:
        write("README.md", "New main\n")
        # Calculation code comes from main, never from the build artifact.
        for path, text in (mutations or {}).items():
            if path.startswith("R/"):
                write(path, text)
        git("add", "README.md", "R")
        git("commit", "--quiet", "-m", "advance main")
        git("push", "--quiet", "origin", "main")
    main_commit = git("rev-parse", "HEAD")
    write_web(fresh_value)
    for path, text in (mutations or {}).items():
        if text is None:
            (repo / path).unlink()
        else:
            write(path, text)
    fresh_report = report(name, main_commit, release)
    write("reports/change_report.md", fresh_report)
    capture = case / "capture"
    capture.mkdir()
    state = {"prs": [{"number": 21, "url": URL, "body": old_body}] if open_pr else [],
             "comments": [
                 {"id": 11, "created_at": "2026-10-27T19:34:06Z",
                  "user": {"login": "github-actions[bot]"}, "body": old_report},
                 {"id": 12, "created_at": "2026-10-27T19:35:06Z",
                  "user": {"login": "maintainer"}, "body": old_report},
                 {"id": 13, "created_at": "2026-10-27T19:36:06Z",
                  "user": {"login": "github-actions[bot]"}, "body": "An unrelated bot comment"},
                 {"id": 14, "created_at": "2026-10-27T19:37:06Z",
                  "user": {"login": "github-actions[bot]"}, "body": old_report},
             ]}
    state_file = capture / "state.json"
    state_file.write_text(json.dumps(state))
    env = dict(os.environ, PATH=f"{root / 'bin'}:{os.environ['PATH']}",
               TEST_CAPTURE=str(capture), GITHUB_SERVER_URL="https://github.com",
               GITHUB_REPOSITORY="Economic/productivity_pay_gap", GITHUB_RUN_ID="200",
               GITHUB_STEP_SUMMARY=str(capture / "summary.md"))
    run(["bash", str(SCRIPT)], repo, env)
    calls = [json.loads(line) for line in (capture / "calls.jsonl").read_text().splitlines()]
    actions = [call[:2] for call in calls]
    final = json.loads(state_file.read_text())
    if fresh_value == 1:
        expected_actions = [["pr", "list"], ["pr", "close"]] if open_pr else [["pr", "list"]]
        assert actions == expected_actions
        assert git("rev-parse", "HEAD") == main_commit
        assert not (capture / "edit.md").exists()
        assert NEW_RUN in (capture / "summary.md").read_text()
        print(f"Passed: {name}")
        return

    body = (capture / ("edit.md" if open_pr else "create.md")).read_text()
    assert body.startswith("**Last checked:**")
    assert NEW_RUN in body.split("## Latest refresh report")[0]
    assert "**Pending against main:** Fixture revisions pending" in body
    assert "**Latest output:** 2026q2" in body
    assert body.count("# Change report") == 1
    title_call = next(call for call in calls if call[:2] in (["pr", "edit"], ["pr", "create"]))
    title = title_call[title_call.index("--title") + 1]
    assert title.startswith("Data refresh: checked ")
    assert title.endswith("Fixture revisions pending")
    if update:
        assert ["auth", "setup-git"] in actions
        assert git("rev-parse", "origin/data-refresh") != original_branch
        assert git("rev-parse", "origin/data-refresh^") == main_commit
        assert fresh_report.strip() in body
        # The entire published snapshot must match the report's build files.
        for folder in ("data_raw", "data_outputs", "data_final", "renv"):
            assert not git("diff", "origin/data-refresh", "--", folder)
        assert not git("diff", "origin/data-refresh", "--", "renv.lock")
        for path, text in (mutations or {}).items():
            if text is None:
                assert not git("ls-tree", "--name-only", "origin/data-refresh", "--", path)
            else:
                assert git("show", f"origin/data-refresh:{path}") == text.strip()
    else:
        assert ["auth", "setup-git"] not in actions
        assert git("rev-parse", "HEAD") == main_commit
        assert git("rev-parse", "origin/data-refresh") == original_branch
        assert old_section in body
        assert fresh_report.strip() not in body
        assert "outputs unchanged" in body
        assert OLD_RUN in body
    assert (["pr", "comment"] in actions) == notify
    if notify:
        notification = (capture / "comment.md").read_text()
        assert NEW_RUN in notification and URL in notification
        assert "# Change report" not in notification
        assert "Fixture revisions pending" in notification
    if open_pr:
        # jq is executed by the stub, so this exercises the real author/body
        # selector as well as pagination and targeted comment updates.
        assert "--paginate" in next(call for call in calls if call[:2] == ["api", "--paginate"])
        assert "superseded" in final["comments"][0]["body"]
        assert URL in final["comments"][0]["body"]
        assert final["comments"][1]["body"] == old_report
        assert final["comments"][2]["body"] == "An unrelated bot comment"
        assert "superseded" in final["comments"][3]["body"]
    else:
        assert "--assignee" in title_call
        assert ["pr", "comment"] not in actions
    if repeat:
        first_commit = git("rev-parse", "origin/data-refresh")
        first_body = body
        git("switch", "--quiet", "main")
        # A repeated build only changes access dates. Reuse the fresh report
        # baselines but let its access-date text differ from the saved report.
        write("data_raw/fetch_log.csv", "source,date_accessed,status\nbls_hours,2026-10-30,ok\n")
        write("data_final/epi_productivity_pay_gap_sources.csv",
              "source,date_accessed,date_published\nBLS,2026-10-30,2026-09-03\n")
        write("reports/change_report.md", fresh_report + "Accessed again on October 30\n")
        # Restore changed snapshot files from the proposal before the next build.
        for path, text in (mutations or {}).items():
            if text is not None:
                write(path, text)
        write_web(fresh_value)
        env["GITHUB_RUN_ID"] = "201"
        (capture / "calls.jsonl").write_text("")
        run(["bash", str(SCRIPT)], repo, env)
        again = [json.loads(line) for line in (capture / "calls.jsonl").read_text().splitlines()]
        assert not any(call[:2] in (["auth", "setup-git"], ["pr", "comment"], ["api", "--method"]) for call in again)
        assert git("rev-parse", "origin/data-refresh") == first_commit
        second_body = (capture / "edit.md").read_text()
        assert "actions/runs/201" in second_body
        assert first_body.split("<!-- refresh-report-start -->")[1] == second_body.split("<!-- refresh-report-start -->")[1]
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
import subprocess
import sys

args = sys.argv[1:]
capture = Path(os.environ["TEST_CAPTURE"])
state_file = capture / "state.json"
state = json.loads(state_file.read_text())
with (capture / "calls.jsonl").open("a") as log:
    log.write(json.dumps(args) + "\\n")
if args[:2] == ["pr", "list"]:
    print(json.dumps(state["prs"]))
elif args[:2] in (["pr", "edit"], ["pr", "create"], ["pr", "comment"]):
    body = Path(args[args.index("--body-file") + 1])
    shutil.copyfile(body, capture / (args[1] + ".md"))
    if args[1] == "edit":
        state["prs"][0]["body"] = body.read_text()
    elif args[1] == "create":
        state["prs"] = [{"number": 21, "url": "https://github.com/Economic/productivity_pay_gap/pull/21", "body": body.read_text()}]
elif args[:2] == ["api", "--paginate"]:
    subprocess.run(["jq", "-r", args[args.index("--jq") + 1]],
                   input=json.dumps(state["comments"]), text=True, check=True)
elif args[:2] == ["api", "--method"]:
    assert args[2] == "PATCH"
    comment_id = int(args[3].rsplit("/", 1)[1])
    body = json.loads(Path(args[args.index("--input") + 1]).read_text())["body"]
    next(comment for comment in state["comments"] if comment["id"] == comment_id)["body"] = body
elif args[:2] not in (["pr", "close"], ["auth", "setup-git"]):
    raise SystemExit("Unexpected gh call: " + repr(args))
state_file.write_text(json.dumps(state))
''')
    gh.chmod(0o755)
    cases = [
        ("unchanged", {}),
        ("access_dates_only", {"mutations": {
            "data_raw/fetch_log.csv": "source,date_accessed,status\nbls_hours,2026-10-29,ok\n",
            "data_final/epi_productivity_pay_gap_sources.csv":
                "source,date_accessed,date_published\nBLS,2026-10-29,2026-09-03\n"}}),
        ("stale", {"fresh_value": 1}),
        ("no_changes_no_pr", {"open_pr": False, "fresh_value": 1}),
        ("no_web_changes_no_pr", {"open_pr": False, "fresh_value": 1,
                                   "mutations": {"data_raw/input.csv": "value\n2\n"}}),
        ("changed_web", {"fresh_value": 3, "update": True, "notify": True}),
        ("new_pr", {"open_pr": False, "update": True}),
        ("inputs_only", {"mutations": {"data_raw/input.csv": "value\n2\n"}, "update": True, "repeat": True}),
        ("packages_only", {"mutations": {"renv.lock": '{"Packages": {"fixture": {"Version": "2"}}}\n'}, "update": True}),
        ("spreadsheet_only", {"mutations": {"data_raw/hours.xlsx": "new spreadsheet\n"}, "update": True}),
        ("source_publication", {"mutations": {"data_final/epi_productivity_pay_gap_sources.csv":
            "source,date_accessed,date_published\nBLS,2026-10-29,2026-11-05\n"}, "update": True}),
        ("below_web_rounding", {"mutations": {"data_final/epi_productivity_pay_gap.csv": "value\n1.0002\n"}, "update": True}),
        ("added_file", {"mutations": {"data_outputs/new.csv": "value\n2\n"}, "update": True}),
        ("removed_file", {"mutations": {"data_outputs/output.csv": None}, "update": True}),
        ("new_main", {"advance_main": True, "update": True}),
        ("code_changed", {"advance_main": True, "mutations": {"R/combine.R": "# new calculation\n"}, "update": True}),
        ("new_release", {"release": "v2026.10.29", "update": True}),
        ("legacy_report", {"legacy": True, "update": True}),
    ]
    for name, options in cases:
        check_case(root, name, **options)

print("Refresh PR lifecycle checks passed.")
