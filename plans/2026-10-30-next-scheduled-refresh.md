# Plan: Show the next scheduled data update

Date: 2026-10-30

## Goal

Show when the next scheduled data build is expected and why, in the refresh PR and workflow run summary.

## Decisions made

- Put one line at the end of the PR's opening status section, before Latest refresh report. Include it before Change report in the build run summary too, including dry runs and builds with no web changes.
- Use Eastern time with EST or EDT. Read the saved calendar used by the scheduler. Include release-day builds and unconditional next-day follow-ups, joining overlapping reasons with “and”.
- Recompute the line on each check, even when the branch and detailed report stay unchanged. It describes the calendar at the time of the check.
- If the calendar is missing, invalid, or exhausted, show “Next scheduled update: unavailable. Run Calendar refresh.” Keep manual refreshes working.
- Keep the build read-only and the publish job free of R and artifact code. Do not change calculations, data, schedules, release behavior, or notification rules.

## Implementation phase

1. Extend the trusted calendar helper to identify and format the next future scheduled build, sharing validation with the scheduler.
2. Add the line to the refresh PR status and workflow summaries. Cover overlaps, timezone boundaries, missing calendars, and check-only PR updates with offline fixtures.
3. Update documentation, run focused checks and workflow lint, commit, and complete the branch checkpoint review. Push and open a PR. Ask the maintainer to merge after checks pass.

## Risks

- This is a forecast from the saved calendar. Later calendar changes and delayed or dropped GitHub scheduled runs can change the actual time. A long build can finish after another scheduled time has passed; each job shows the next future time when it writes its status.
- The display's daily time must stay in sync with the scheduler workflow. A focused check will enforce that relationship.

## Validation and results

- Pending implementation.
