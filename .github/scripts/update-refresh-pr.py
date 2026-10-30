"""Maintain one refresh proposal, one current report, and short notifications.

Runs in the R-free publish job, on the build's main commit with allowlisted
artifact files copied into the working tree. Only the web comparison with the
existing proposal controls notification comments. The report keeps its main
and published-release comparisons.
"""

import csv
from datetime import datetime
import io
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from zoneinfo import ZoneInfo


BRANCH = "data-refresh"
WEB_FILES = [
    "data_final/epi_productivity_pay_gap_web.csv",
    "data_final/epi_productivity_pay_gap_web_stats.csv",
    "data_final/epi_productivity_pay_counter_web.csv",
]
DATA_PATHS = ["data_raw", "data_outputs", "data_final", "renv.lock", "renv/activate.R"]
CODE_PATHS = ["R", "data_inputs", "_targets.R", "_targets.yaml", "packages.R", ".Rprofile"]
REPORT_START = "<!-- refresh-report-start -->"
REPORT_END = "<!-- refresh-report-end -->"


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def git(*args):
    return run("git", *args)


def contents(ref, path):
    if ref is None:
        file = Path(path)
        return file.read_bytes() if file.is_file() else None
    result = subprocess.run(["git", "show", f"{ref}:{path}"], capture_output=True)
    if result.returncode:
        # Missing optional files are legitimate. Other Git failures must not
        # silently look like unchanged data.
        if path not in git("ls-tree", "-r", "--name-only", ref, "--", path).splitlines():
            return None
        result.check_returncode()
    return result.stdout


def comparable(data, path):
    """Access dates alone do not require a new proposal or another check."""
    if data is not None and path in (
        "data_raw/fetch_log.csv", "data_final/epi_productivity_pay_gap_sources.csv"
    ):
        rows = list(csv.reader(io.StringIO(data.decode())))
        if rows and "date_accessed" in rows[0]:
            column = rows[0].index("date_accessed")
            return [row[:column] + row[column + 1:] for row in rows]
    return data


def changed_files(ref, paths):
    names = set(git("ls-tree", "-r", "--name-only", ref, "--", *paths).splitlines())
    names.update(git("ls-files", "--cached", "--others", "--exclude-standard", "--", *paths).splitlines())
    return {
        path for path in names
        if comparable(contents(ref, path), path) != comparable(contents(None, path), path)
    }


def report_section(body):
    if REPORT_START in body and REPORT_END in body:
        return body.split(REPORT_START, 1)[1].split(REPORT_END, 1)[0].strip()
    return None


def report_label(report):
    return re.search(r"^\*\*(.+)\*\*$", report, re.MULTILINE).group(1)


def retire_reports(pr, url, temp):
    """Replace only earlier full reports authored by the Actions bot."""
    reports = run(
        "gh", "api", "--paginate", f"repos/{{owner}}/{{repo}}/issues/{pr}/comments",
        "--jq", '.[] | select(.user.login == "github-actions[bot]" and '
        '(.body | startswith("# Change report\\n"))) | [.id, .created_at] | @tsv',
    )
    for row in reports.splitlines():
        comment_id, created_at = row.split("\t")
        notice = (
            f"Report from {created_at} superseded. "
            f"See the [current report in the PR description]({url}). "
            "Historical reports are available in the refresh workflow run summaries."
        )
        payload = temp / "superseded.json"
        payload.write_text(json.dumps({"body": notice}))
        run("gh", "api", "--method", "PATCH",
            f"repos/{{owner}}/{{repo}}/issues/comments/{comment_id}", "--input", str(payload))


def summary(text):
    print(text)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as file:
            file.write(text + "\n")


def maintain(temp):
    now = datetime.now(ZoneInfo("America/New_York"))
    checked = now.strftime("%Y-%m-%d %I:%M %p %Z")
    date = now.strftime("%Y-%m-%d")
    run_url = (
        f"{os.environ['GITHUB_SERVER_URL']}/{os.environ['GITHUB_REPOSITORY']}"
        f"/actions/runs/{os.environ['GITHUB_RUN_ID']}"
    )
    next_update = run(sys.executable, str(Path(__file__).with_name("release-calendar.py")), "next", "--with-coverage")
    current = json.loads(run(
        "gh", "pr", "list", "--head", BRANCH, "--base", "main", "--state", "open",
        "--json", "number,body,url",
    ))
    proposal = current[0] if current else None
    main_web_changed = any(contents("origin/main", p) != contents(None, p) for p in WEB_FILES)
    if not main_web_changed:
        if proposal:
            run("gh", "pr", "close", str(proposal["number"]), "--delete-branch",
                "--comment", "`main` already has the latest build's web numbers.")
        summary(f"Last checked: [{checked}]({run_url}). No web changes against main.")
        summary(next_update)
        return

    old_ref = f"origin/{BRANCH}"
    old_commit = subprocess.run(
        ["git", "rev-parse", "--verify", old_ref], text=True, capture_output=True,
    )
    expected = old_commit.stdout.strip() if old_commit.returncode == 0 else ""
    if proposal and not expected:
        raise RuntimeError("The open refresh PR's branch was not fetched.")
    changed = changed_files(old_ref, DATA_PATHS + CODE_PATHS) if proposal else set()
    web_changed = not proposal or any(contents(old_ref, p) != contents(None, p) for p in WEB_FILES)
    inputs_changed = any(not path.startswith("data_final/") for path in changed)
    outputs_changed = any(path.startswith("data_final/") for path in changed)
    # A new main also needs a new proposal and report, so the main comparison
    # cannot remain frozen at a baseline that no longer describes merging.
    main_changed = proposal and subprocess.run(
        ["git", "merge-base", "--is-ancestor", "HEAD", old_ref],
    ).returncode != 0
    previous_report = report_section(proposal["body"]) if proposal else None
    fresh_report = Path("reports/change_report.md").read_text().strip()
    def baselines(text):
        return re.findall(r"^Baselines:.*$", text or "", re.MULTILINE)
    baselines_changed = bool(previous_report) and baselines(previous_report) != baselines(fresh_report)
    update_branch = not proposal or bool(changed) or main_changed or baselines_changed or not previous_report

    if not proposal:
        result = "First proposal. Web numbers differ from main."
    elif web_changed:
        result = "Proposed web numbers changed."
    else:
        updates = []
        if inputs_changed:
            updates.append("Inputs, packages, or calculation code updated")
        if outputs_changed:
            updates.append("Other output files updated")
        if main_changed or baselines_changed:
            updates.append("Comparison baselines updated")
        if not previous_report:
            updates.append("Report moved to the current format")
        result = "; ".join(updates) + "; web numbers unchanged." if updates else (
            "Inputs, packages, calculation code, and outputs unchanged (ignoring access dates)."
        )

    if update_branch:
        report = fresh_report
        section = f"**Report updated:** [{checked}]({run_url})\n\n{report}"
    else:
        # Keep the report for the committed files, including their access dates.
        # A check-only run must not claim its fresh access dates are in the PR.
        section = previous_report
        report = section.split("# Change report", 1)[1]
    label = report_label(report)
    title = f"Data refresh: checked {date}; {label}"[:256]
    latest = list(csv.DictReader(io.StringIO(contents(None, WEB_FILES[0]).decode())))[-1]["Year"]
    body = temp / "body.md"
    body.write_text(
        f"**Last checked:** [{checked}]({run_url})\n\n"
        f"**Since the previous proposal:** {result}\n\n"
        f"**Pending against main:** {label}\n\n"
        f"**Latest output:** {latest}. Input coverage is shown in the report below.\n\n"
        "Merging this PR updates `main`; publishing remains a separate manual step.\n\n"
        'To merge: approve the held check run ("Approve and run workflows"), then merge once it passes.\n\n'
        f"{next_update}\n\n"
        "## Latest refresh report\n\n"
        "This report describes the files in this PR. Its main comparison describes merging; "
        "its release comparison describes publishing. The report update time can precede "
        "the last check when only access dates changed.\n\n"
        f"{REPORT_START}\n{section}\n{REPORT_END}\n"
    )

    if update_branch:
        git("switch", "--quiet", "-C", BRANCH)
        git("add", "-A", "--", *DATA_PATHS)
        git("-c", "user.name=github-actions[bot]", "-c",
            "user.email=41898282+github-actions[bot]@users.noreply.github.com",
            "commit", "--quiet", "-m", f"Data refresh: {label}")
        run("gh", "auth", "setup-git")
        git("push", "--quiet", f"--force-with-lease=refs/heads/{BRANCH}:{expected}", "origin", BRANCH)

    if proposal:
        pr = str(proposal["number"])
        run("gh", "pr", "edit", pr, "--title", title, "--body-file", str(body))
        retire_reports(pr, proposal["url"], temp)
        if web_changed:
            comment = temp / "notification.md"
            comment.write_text(
                f"Proposed web numbers updated in the [{checked} refresh]({run_url}).\n\n"
                f"Pending against main: {label}\n\n"
                f"See the [current report in the PR description]({proposal['url']}).\n"
            )
            run("gh", "pr", "comment", pr, "--body-file", str(comment))
    else:
        run("gh", "pr", "create", "--base", "main", "--head", BRANCH,
            "--title", title, "--body-file", str(body), "--assignee", "benzipperer")
    summary(f"Last checked: [{checked}]({run_url}). {result}")
    summary(next_update)


if __name__ == "__main__":
    with tempfile.TemporaryDirectory(prefix="refresh-pr-") as directory:
        maintain(Path(directory))
