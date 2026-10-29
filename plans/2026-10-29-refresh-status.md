# Plan: Make the rolling refresh PR current and readable

Date: 2026-10-29

## Goal

Make each refresh's result clear without reopening the PR or posting duplicate reports.

## Decisions made

- Keep one rolling `data-refresh` PR. Open it only for web changes against main. Close it when the latest build's web files match main.
- Separate three comparisons: latest build versus the existing proposal controls updates and notifications; proposal versus main describes merging; proposal versus the last release describes publishing.
- Put the last check time and workflow link, changes since the previous proposal, pending changes against main, and output coverage at the top. Put the check date in the title.
- Keep exactly one full report in the PR description. Replace older bot report comments with short superseded notices linking to the description. Preserve human comments and short notification history.
- Update the branch and full report for meaningful input, package, calculation code, or output changes, including changes below web rounding. Incorporate a newer main or published-release baseline before refreshing comparisons. Notify by a short comment only when web files change against the existing proposal.
- Ignore access dates alone when deciding whether to rewrite the branch. If the proposal and main are unchanged, retain the report for the committed files and update only the check status and title. Label the report's update time separately from the last check.
- This intentionally replaces the October 27 policy of retaining older inputs when web numbers match. The user's difficulty finding the current report and distinguishing it from historical comments is the new argument. Keeping the report and branch consistent also makes the proposal easier to review.
- Keep the R build read-only and the publish job free of R and package execution. Do not change calculations, fetch live data, run a release, or merge.

## Implementation phase

1. Extend PR maintenance with meaningful snapshot comparison, clear status, consistent files and report, short notifications, and migration of older bot reports.
2. Expand local Git and stub GitHub lifecycle fixtures for these decisions, dates-only checks, changed main, package and input changes without new web numbers, other output changes, comments, and repeated checks.
3. Update README and AGENTS.md. Run focused tests, workflow lint, and an offline rebuild. Verify committed data stays unchanged.
4. Commit self-contained changes. Resolve post-commit reviews and run the branch checkpoint panel. Push and open a PR, wait for checks, then ask the maintainer to merge.

## Risks

- Updating input or package files without changed web numbers can require another check approval. It does not get a notification comment. GitHub may independently notify subscribers of other PR activity.
- Access-only checks retain the report's earlier access dates and baselines. The status distinguishes the report update from the latest check. New main or release baselines cause a branch and report update even if web numbers match the proposal.
- Historical reports remain available in workflow run summaries and retained artifacts. The PR conversation keeps only short notices and notifications.

## Validation and results

- Implemented a trusted Python helper behind the existing shell entry point. Publishing still runs no R or artifact code. The artifact allowlist and workflow permissions are unchanged.
- The description has a prominent check time and run link, proposal-change status, pending changes against main, latest output quarter, and a single report with its own update time. The title includes the check date. Check-only runs preserve the report for the committed files.
- Meaningful file changes and new main or release baselines synchronize the branch and report. New comments are short notifications for changed web files only. Older full bot reports are replaced with superseded notices, preserving human and unrelated bot comments.
- All 18 local Git and stub GitHub lifecycle fixtures passed. They cover new, stale, unchanged, access-only, input-only, package-only, publication-date, spreadsheet, below-rounding, added and removed file, new main, code, release-baseline, and legacy-report cases. Repeating an input-only update is quiet and preserves the report and branch. The comment tests evaluate the actual jq selector, including human and unrelated bot comments.
- All 19 existing calendar and isolated writer tests passed. Workflow lint (actionlint 1.7.12), shell syntax, and git diff whitespace checks passed.
- The offline pipeline passed with 2 targets completed and 23 cached. Committed data_final and data_outputs files remain unchanged. The sandboxed R startup stalled; the check completed using the existing local renv cache outside the sandbox. No live data fetch ran.
- Plan review 656, implementation review 658, and documentation review 660 passed. Checkpoint 670 passed code, design, and security reviews with no findings. Its Claude reviewer could not authenticate because its OAuth session expired, so that fourth review is unavailable. No code findings needed fixes or accepted risks.
- The earlier checkpoint 665 was canceled because local main was behind origin/main. Updated the local reference and ran checkpoint 670 against the correct base, 7206a21.
- Delivery and GitHub check results are recorded on the implementation PR. The live refresh PR is left for the next refresh after merge. No release or merge ran.
