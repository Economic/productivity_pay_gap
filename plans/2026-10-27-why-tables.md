# Plan: Explain revisions with paired tables

Date: 2026-10-27

## Goal

Make the Why section show the signed contribution of every applicable input to productivity and pay revisions.

## Decisions made

- Keep the existing exact decomposition. Only report presentation and aggregation across revised quarters change.
- Show the latest common quarter in one paired table: previous index, revised index, every input contribution, and net revision. Use index points.
- Remove the standalone base-period subsection. Continue accounting for base-period revisions in the decomposition.
- Replace absolute contribution shares across revised quarters with average signed contributions in a paired table. Count revised quarters separately for each index and show their date ranges. Average over revised quarters only.
- Keep every applicable input, including zero contributions. Use a dash for an input outside an index's formula. If an index has no revised quarters, its averages are unavailable, not zero.
- Show three paired headline tables: total growth since 1979q4, average annual growth through 1979q4, and average annual growth since 1979q4. Use percentage points for contributions. Keep rounding and applicable added/removed-quarter effects.
- Show the productivity-to-pay growth multiple on one line with both values and an arrow, even if unchanged. No decomposition or parenthetical comment.
- Retain material calculation-change rows and existing warnings. NIPA compensation and wages are the two components of the benefits adjustment.
- Do not change published data calculations, report baselines, workflow permissions, or refresh notification rules.
- The user authorized creating a PR, waiting for checks, merging with a merge commit, and then running the refresh workflow. Do not merge the data refresh PR or publish a release.

## Implementation phase

1. Add paired revision tables and remove superseded prose.
2. Verify actual refresh data, zero contributions, offsetting contributions, no revised quarters, calculation-change warnings, and added/removed quarters. Rebuild offline and confirm committed outputs stay unchanged.
3. Run the checkpoint review. Fix normal-use problems. Record remote edge cases as accepted risks when defensive code would add disproportionate complexity.
4. Open the PR, wait for checks and review, merge, and run refresh from main. Check that the refresh builds the updated report.

## Risks

- Average signed contributions can conceal offsetting effects across quarters. Counts and ranges identify the population, and the latest-quarter table shows its own effects separately. This tradeoff is accepted in preference to complex summaries.
- Displayed values are rounded independently. Totals are computed before rounding, so displayed contributions can differ slightly from the displayed total.
- Existing accepted report risks in the 2026-10-21 plan still apply, including attribution of upstream cleaning changes and the rounding row's inclusion of changes in R/web.R.

## Validation

Implementation and checks will be recorded below and in the implementation PR.
