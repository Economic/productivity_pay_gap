# Plan: Add last-quarter wages to headline stats

Date: 2026-10-30

## Goal

Show the latest typical and counterfactual wages in the refresh report's three-column headline comparison.

## Decisions made

- Append “Typical wage, last quarter” and “Counterfactual wage, last quarter” to the Headline stats table with Last release, main, and Proposed columns.
- Read Actual wage, Counterfactual wage, and Year from the final row of each snapshot's counterfactual wage web file. Format every available cell as `$XX.XX (YYYYqZ)`. Each snapshot keeps its own quarter.
- Show “Not available” when a snapshot has no wage file. The user confirmed this for releases before that file was introduced, including v2026.9.14.
- This changes report presentation only. Keep calculations, final CSV files, snapshot reading, attribution, notification rules, and workflow permissions unchanged.

## Implementation phase

1. Add the two rows to the shared three-column report, used by refreshes and PR checks. Extend offline report fixtures with distinct values and quarters in all three snapshots and a missing wage file.
2. Run report comparison checks and an offline rebuild. Inspect the rendered rows and verify committed data stays unchanged. Commit and run the required branch checkpoint review.
3. Record validation, push, and open a PR. Wait for GitHub checks and ask the maintainer to merge.

## Risks

- Real wages use each snapshot's own latest-quarter dollar basis. The table preserves the saved values and dates rather than rebasing or reconstructing missing historical files.

## Validation and results

- Pending implementation.
