# Plan: Forecast output coverage after the next update

Date: 2026-10-30

## Goal

Show the anticipated latest quarter of the combined final output directly under Next scheduled update in the refresh PR and workflow summary.

## Decisions made

- The user chose the combined output quarter, rather than the newest quarter from an individual source.
- Use “Expected latest output quarter: YYYYqZ (subject to source availability).” If coverage is unchanged, add “no new quarter expected” in the parentheses.
- Start with the latest complete quarter in each required input: wages, hours, prices, NDP, compensation, and NIPA wages. For saved releases due by the next build, project their affected inputs through the previous completed quarter under normal release timing. Never reduce already observed coverage. The earliest projected input quarter determines expected combined coverage.
- Treat Productivity and Costs as affecting hours, Employment Situation as affecting wages, CPI as affecting realtalk prices, GDP as affecting NDP, and Personal Income and Outlays as affecting compensation and NIPA wages.
- This is an estimate, not a promise of publication. Preserve current source coverage for inputs without an intervening release. Do not assume a new quarter merely because a build runs or a calendar quarter ends.
- Missing calendars or input coverage yield an unavailable forecast without blocking manual refreshes. Recompute alongside Next scheduled update on every check, preserving retained reports and notification rules.
- The wage headline rows are completed separately in [PR #34](https://github.com/Economic/productivity_pay_gap/pull/34). Keep that reviewed implementation separate from this forecast.
- Read existing CSVs as data only. Keep the publish job free of R and package or artifact code. Do not change calculations, CSV outputs, schedules, permissions, or releases.

## Implementation phase

1. Share the next scheduled build's timestamp with the coverage estimate and read the required input quarters from existing allowlisted CSVs.
2. Show the estimate directly below Next scheduled update in the PR status and both workflow summaries. Extend offline calendar and PR fixtures for advancing and unchanged coverage, limiting sources, follow-ups, year boundaries, and unavailable inputs.
3. Update documentation. Run focused checks and workflow lint, commit, and complete the required branch checkpoint. Push and open a PR, wait for GitHub's offline check, and ask the maintainer to merge.

## Risks

- Normal release timing projects the previous completed quarter. Rescheduled releases, incomplete agency releases, delayed spreadsheet/API updates, and realtalk publication can leave actual coverage behind that estimate. The displayed qualification and documentation make this explicit. The estimate never controls pipeline calculations or scheduling.
- Saved calendars retain recent events and future releases, not a complete publication history. Older missing data with no retained release stays at its observed coverage, making the estimate conservative until a later build observes it.

## Validation and results

- Added the shared next-build timestamp and an optional coverage estimate to the trusted calendar helper. The build and publish jobs use it to show the forecast immediately below Next scheduled update, including dry runs, builds without a PR, and retained reports.
- All 55 offline checks passed: 27 calendar cases, 22 PR lifecycle fixtures, and 6 calendar writer cases. Added coverage includes source-specific projection, a different source remaining limiting, complete monthly quarters, delayed follow-ups, year boundaries, preserving observed coverage, both NIPA income series, and missing coverage without losing the next scheduled date.
- The lifecycle fixtures execute the actual workflow summary step. A calendar-only change updates both scheduled time and forecast quarter without rewriting the proposal or retained report or sending a notification.
- A read-only preview using the latest saved data-refresh input files and calendar produces November 5, 2026, 2:27 PM EST for Productivity and Costs and an expected combined quarter of 2026q3, subject to source availability. No live data fetch ran.
- Workflow lint and whitespace checks passed. All committed data_raw, data_outputs, and data_final files remain unchanged. No permissions or artifact allowlist changes were needed.
- Plan review 696 and implementation review 698 passed. Branch checkpoint 703 passed all four reviewers, including code, design, and security, with no findings. No additional accepted risks were needed.
- Delivery and GitHub offline check results are recorded on [PR #35](https://github.com/Economic/productivity_pay_gap/pull/35). The maintainer merges after checks pass. PR #34 remains the separate completed wage headline change. No merge or release ran.
