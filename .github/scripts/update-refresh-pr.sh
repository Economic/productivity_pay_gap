#!/usr/bin/env bash
# Opens or updates the rolling data refresh PR. Run by the publish job of
# .github/workflows/refresh.yml, in a checkout of main with the build job's
# fresh files on top. See "Weekly refresh flow" in
# plans/2026-10-21-ci-data-release-workflow.md.
set -euo pipefail

branch="data-refresh"
web_files=(
  data_final/epi_productivity_pay_gap_web.csv
  data_final/epi_productivity_pay_gap_web_stats.csv
  data_final/epi_productivity_pay_counter_web.csv
)
report="reports/change_report.md"

pr=$(gh pr list --head "$branch" --state open --json number --jq '.[0].number // empty')

# A refresh PR is stale once main has the same numbers, for example after a
# local data PR was merged
if [ -n "$pr" ] && git diff --quiet origin/main -- "${web_files[@]}"; then
  gh pr close "$pr" --delete-branch --comment "\`main\` already has these numbers."
  exit 0
fi

body=$(mktemp)
trap 'rm -f "$body"' EXIT
{
  echo "Data refresh, $(date -u +%Y-%m-%d). Merging it updates the numbers on \`main\`; it doesn't publish a release."
  echo
  echo "To merge: approve the held check run (\"Approve and run workflows\"), then merge once it passes."
  echo
  echo "The report below describes the latest refresh build. When its web numbers match this PR, only this description is updated; the branch keeps its existing files."
  echo
  cat "$report"
} > "$body"

# Notify only when the web files changed since I last saw them: in the open
# refresh PR, or in main if none is open
if [ -n "$pr" ]; then
  last_seen="origin/$branch"
else
  last_seen="origin/main"
fi
if git diff --quiet "$last_seen" -- "${web_files[@]}"; then
  if [ -n "$pr" ]; then
    gh pr edit "$pr" --body-file "$body"
    echo "The web files match $last_seen. Updated the PR description without rewriting the branch or posting a comment."
  else
    echo "The web files match $last_seen, so there is nothing new to report."
  fi
  exit 0
fi

# The change label is the report's first bold line
label=$(sed -n 's/^\*\*\(.*\)\*\*$/\1/p' "$report" | head -n 1)
title="Data refresh: $label"

# A fresh branch from main, with every changed data and package file
git switch --quiet -C "$branch"
git add -A data_raw data_outputs data_final renv.lock renv/activate.R
git -c user.name="github-actions[bot]" \
  -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
  commit --quiet -m "$title"
gh auth setup-git
git push --quiet --force origin "$branch"

# Creating the PR assigned to me emails me; after that, each update's comment does
if [ -z "$pr" ]; then
  # Not a draft: the held check already keeps it from being merged by accident
  gh pr create --base main --head "$branch" --title "$title" \
    --body-file "$body" --assignee benzipperer
else
  gh pr edit "$pr" --title "$title" --body-file "$body"
  gh pr comment "$pr" --body-file "$report"
fi

# GitHub runs the check on this PR, but holds the run until a maintainer
# approves it, because the bot opened the PR. That approval is a deliberate
# gate: the PR's files come from a job that ran freshly updated package code.
