#!/usr/bin/env bash
# Decides the release tag and applies the release guards. Run by the plan job
# of .github/workflows/release.yml, in a checkout of the commit to release,
# with full history and tags. See "Release flow" in
# plans/2026-10-21-ci-data-release-workflow.md.
#
# Environment: SHA, DRY_RUN and CORRECTION ("true" or "false"), REASON, and
# DATE_OVERRIDE (YYYY-MM-DD; the workflow passes it only for dry runs).
# Writes tag, previous_tag, title and latest_quarter to $GITHUB_OUTPUT.
set -euo pipefail

fail() {
  echo "::error::$1"
  exit 1
}

if [ "$DRY_RUN" != "true" ] && [ "${GITHUB_REF:-}" != "refs/heads/main" ]; then
  fail "Releases are made only from main. Run a dry run to test another branch."
fi
if [ "$CORRECTION" = "true" ] && [ -z "${REASON//[[:space:]]/}" ]; then
  fail "A correction needs a reason."
fi

# Tags are named for the day in Eastern time, without zero padding: v2026.9.14
day="${DATE_OVERRIDE:-$(TZ=America/New_York date +%Y-%m-%d)}"
[[ "$day" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || fail "The date must look like 2026-10-22."
base="v$(date -d "$day" +%Y.%-m.%-d)"
base_pattern="^${base//./\\.}(\\.[0-9]+)?$"

# Releases already published that day: base, then base.2, base.3, ...
same_day=$(gh release list --limit 200 --exclude-drafts --json tagName --jq '.[].tagName' |
  grep -E "$base_pattern" || true)
if [ -z "$same_day" ]; then
  if [ "$CORRECTION" = "true" ]; then
    fail "There is no release on $day to correct."
  fi
  tag="$base"
  previous=$(gh release view --json tagName --jq .tagName)
else
  if [ "$CORRECTION" != "true" ]; then
    fail "$base already exists. Tick 'correction' and give a reason to publish a corrected release."
  fi
  # the highest suffix so far; the plain tag counts as 1
  last=$(echo "$same_day" | sed -E 's/^v[0-9]+\.[0-9]+\.[0-9]+//; s/^\.//; s/^$/1/' | sort -n | tail -n 1)
  tag="$base.$((last + 1))"
  # a correction is compared with the release it corrects
  if [ "$last" -gt 1 ]; then
    previous="$base.$last"
  else
    previous="$base"
  fi
fi

# A tag with no release (pushed by hand, say) must not be reused
if git rev-parse --quiet --verify "refs/tags/$tag" >/dev/null; then
  fail "The tag $tag exists without a release. Delete the stray tag, then run this again."
fi

# The no-change guard: the final files must differ from the previous
# release, ignoring the access dates in the sources CSV, which change with
# every data pull. A file the previous release didn't have counts as changed.
python3 -I - "$previous" "$SHA" <<'PYTHON'
import csv, io, subprocess, sys

previous, sha = sys.argv[1], sys.argv[2]

# without the tag, every file would look new
tag_found = subprocess.run(["git", "rev-parse", "--verify", "--quiet", f"{previous}^{{commit}}"], capture_output=True)
if tag_found.returncode != 0:
    print(f"::error::{previous} is not in this checkout.")
    sys.exit(1)
files = [
    "epi_productivity_pay_gap.csv",
    "epi_productivity_pay_gap_web.csv",
    "epi_productivity_pay_gap_web_stats.csv",
    "epi_productivity_pay_gap_sources.csv",
    "epi_productivity_pay_counter_web.csv",
]

def rows(ref, name):
    # releases through v2026.9.14 kept the final files in release/
    for folder in ("data_final", "release"):
        shown = subprocess.run(["git", "show", f"{ref}:{folder}/{name}"], capture_output=True, text=True)
        if shown.returncode == 0:
            table = list(csv.reader(io.StringIO(shown.stdout)))
            if "date_accessed" in table[0]:
                i = table[0].index("date_accessed")
                table = [row[:i] + row[i + 1:] for row in table]
            return table
    return None

def current_rows(name):
    table = rows(sha, name)
    if table is None:
        # workflow commands are read from standard output
        print(f"::error::{name} is not in {sha}")
        sys.exit(1)
    return table

changed = [name for name in files if rows(previous, name) != current_rows(name)]
if not changed:
    print(f"::error::Nothing changed since {previous}, apart from access dates.")
    sys.exit(1)
print(f"Changed since {previous}: {', '.join(changed)}")
PYTHON

latest_quarter=$(git show "$SHA:data_final/epi_productivity_pay_gap_web.csv" | tail -n 1 | cut -d, -f1)

{
  echo "tag=$tag"
  echo "previous_tag=$previous"
  echo "title=Version ${tag#v}"
  echo "latest_quarter=$latest_quarter"
} >> "$GITHUB_OUTPUT"
echo "Tag: $tag (previous release: $previous; latest quarter: $latest_quarter)"
