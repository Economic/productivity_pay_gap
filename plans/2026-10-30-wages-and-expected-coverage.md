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

- Pending implementation.
