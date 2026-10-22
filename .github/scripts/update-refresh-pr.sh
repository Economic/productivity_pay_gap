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
)
report="reports/change_report.md"

pr=$(gh pr list --head "$branch" --state open --json number --jq '.[0].number // empty')

# What I last saw: the open refresh PR, or main if none is open
if [ -n "$pr" ]; then
  last_seen="origin/$branch"
else
  last_seen="origin/main"
fi

# Notify only when the web files changed since then
if git diff --quiet "$last_seen" -- "${web_files[@]}"; then
  echo "The web files match $last_seen, so there is nothing new to report."
  if [ -n "$pr" ] && git diff --quiet origin/main -- "${web_files[@]}"; then
    gh pr close "$pr" --delete-branch --comment "\`main\` already has these numbers."
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

body=$(mktemp)
{
  echo "Weekly data refresh, $(date -u +%Y-%m-%d). Merging it updates the numbers on \`main\`; it doesn't publish a release."
  echo
  cat "$report"
} > "$body"

# Creating the PR assigned to me emails me; after that, each update's comment does
if [ -z "$pr" ]; then
  gh pr create --draft --base main --head "$branch" --title "$title" \
    --body-file "$body" --assignee benzipperer
else
  gh pr edit "$pr" --title "$title" --body-file "$body"
  gh pr comment "$pr" --body-file "$report"
fi

# A push made with the built-in token doesn't start other workflows, but a
# manual trigger does, so start the required check here
gh workflow run check.yml --ref "$branch"
