#!/usr/bin/env bash
# Save the validated calendar artifact in an isolated checkout of calendar.
# Never check out calendar over the scripts/code running this workflow.
# Adapted from Economic/realtalk at 577c812073f10b31d5380ac0fc7719befaee93f0.
# Copyright (c) 2023 realtalk authors
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
set -euo pipefail

schedule=$(realpath "${1:?Usage: update-calendar.sh schedule.json}")
[ -f "$schedule" ] && [ ! -L "$1" ] || { echo "Expected a regular schedule.json file" >&2; exit 1; }
remote=$(git remote get-url origin)
calendar_repo=$(mktemp -d)
trap 'rm -rf "$calendar_repo"' EXIT

gh auth setup-git
git init --quiet "$calendar_repo"
git -C "$calendar_repo" remote add origin "$remote"

if git -C "$calendar_repo" ls-remote --exit-code --heads origin refs/heads/calendar > /dev/null; then
  git -C "$calendar_repo" fetch --quiet --depth=1 origin calendar
  git -C "$calendar_repo" checkout --quiet -b calendar FETCH_HEAD
else
  status=$?
  [ "$status" = 2 ] || exit "$status"
  git -C "$calendar_repo" checkout --quiet --orphan calendar
fi

# Do not follow a schedule.json symlink left on the calendar branch.
cp --remove-destination "$schedule" "$calendar_repo/schedule.json"
git -C "$calendar_repo" add schedule.json
if git -C "$calendar_repo" diff --cached --quiet; then
  echo "The saved calendar is unchanged."
  exit 0
fi

GIT_AUTHOR_NAME='github-actions[bot]' \
GIT_AUTHOR_EMAIL='41898282+github-actions[bot]@users.noreply.github.com' \
GIT_COMMITTER_NAME='github-actions[bot]' \
GIT_COMMITTER_EMAIL='41898282+github-actions[bot]@users.noreply.github.com' \
  git -C "$calendar_repo" commit --quiet -m "Refresh BLS and BEA release calendar"
git -C "$calendar_repo" push --quiet origin HEAD:refs/heads/calendar
echo "Saved the release schedule on calendar."
