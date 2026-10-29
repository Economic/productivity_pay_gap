# Plan: Make the rolling refresh PR current and readable

Date: 2026-10-29

## Goal

Make each refresh's result clear without reopening the PR or posting duplicate reports.

## Decisions made

- Keep one rolling `data-refresh` PR. Open it only for web changes against main. Close it when the latest build's web files match main.
- Separate three comparisons: latest build versus the existing proposal controls updates and notifications; proposal versus main describes merging; proposal versus the last release describes publishing.
- Put the last check time and workflow link, changes since the previous proposal, pending changes against main, and output coverage at the top. Put the check date in the title.
- Keep exactly one full report in the PR description. Replace older bot report comments with short superseded notices linking to the description. Preserve human comments and short notification history.
- Update the branch and full report for meaningful input, package, calculation code, or output changes, including changes below web rounding. Incorporate a newer main before refreshing comparisons. Notify by a short comment only when web files change against the existing proposal.
- Ignore access dates alone when deciding whether to rewrite the branch. If the proposal and main are unchanged, retain the report for the committed files and update only the check status and title. Label the report's build time separately from the last check.
- This intentionally replaces the October 27 policy of retaining older inputs when web numbers match. The user's difficulty finding the current report and distinguishing it from historical comments is the new argument. Keeping the report and branch consistent also makes the proposal easier to review.
- Keep the R build read-only and the publish job free of R and package execution. Do not change calculations, fetch live data, run a release, or merge.

## Implementation phase

1. Extend PR maintenance with meaningful snapshot comparison, clear status, consistent files and report, short notifications, and migration of older bot reports.
2. Expand local Git and stub GitHub lifecycle fixtures for these decisions, dates-only checks, changed main, package and input changes without new web numbers, other output changes, comments, and repeated checks.
3. Update README and AGENTS.md. Run focused tests, workflow lint, and an offline rebuild. Verify committed data stays unchanged.
4. Commit self-contained changes. Resolve post-commit reviews and run the branch checkpoint panel. Push and open a PR, wait for checks, then ask the maintainer to merge.

## Risks

- Updating input or package files without changed web numbers can require another check approval. It does not get a notification comment. GitHub may independently notify subscribers of other PR activity.
- Access-only checks retain the report's earlier access dates and baselines. The status distinguishes the report build from the latest check. A newer main causes a branch and report update even if web numbers match the proposal.
- Historical reports remain available in workflow run summaries and retained artifacts. The PR conversation keeps only short notices and notifications.

## Validation and results

- Pending implementation.
