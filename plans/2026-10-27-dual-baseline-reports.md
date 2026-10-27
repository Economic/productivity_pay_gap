# Plan: Compare refreshes and PRs with main and the last release

Date: 2026-10-27

## Goal

Show what merging a PR changes and what publishing its data would change for readers.

## Decisions made

- Weekly refreshes and PR checks show two independent comparisons: proposed data against main, then against the last published GitHub release.
- An overview shows both change summaries. A shared headline table shows release, main, and proposed values. Each comparison has expandable inputs, outputs, and revision explanations.
- Resolve both baseline refs to commits. PR checks compare the proposed merge result against the PR event's base commit. Refreshes compare fresh files against the checked-out main commit.
- Select the published release through GitHub, consistent with the release workflow. A reachable tag alone is not the release baseline.
- When both baselines are the same commit, share their comparison details.
- Keep both views when a PR introduces no data changes. Main can still have unreleased changes.
- Refresh titles still describe changes against main. Notification decisions still compare with the last seen web files.
- Local defaults, post-merge comparisons, release notes, and all data calculations stay as they are.
- The user authorized merging the implementation after checks pass, then updating PR #26 to trigger the new reports. Do not merge PR #26 as part of this work.

## Implementation phase

1. Separate comparison calculation from report rendering and add the combined report.
2. Wire refresh and PR workflows to supply fixed baselines without adding network access to the offline R pipeline.
3. Update documentation and verify unchanged data outputs, independent attribution, identical baselines, unreleased main changes, and added periods. Run the checkpoint review and fix real findings.
4. Open the implementation PR, wait for CI, merge with a merge commit, then merge main into PR #26's branch and push to trigger its new check.

## Risks

- The report remains informational. The accepted report risks in the 2026-10-21 plan still apply. The offline rebuild and manual release process remain the checks on published data.
- Baselines describe the snapshots recorded in a run. A later merge or release requires another run to update them.

## Validation and results

- A forced offline rebuild completed all 23 targets, including the combined report. Every committed file in data_final/ and data_outputs/ stayed byte for byte unchanged.
- The regression script passed: separate NDP attribution against both baselines, no new data with unreleased changes, access dates, different commits with identical outputs, shared details for one commit, added quarters, and a missing release baseline.
- Single-baseline reports against main and v2026.9.14 match the original renderer byte for byte.
- actionlint passed for all workflows. The generated combined report was inspected locally.
- GitHub CI passed for the implementation and posted both comparisons on PR #27. The published report identifies main a01dc84 and release v2026.9.14 at 60a1503.
- Commit review 488 passed. Checkpoint review 493 found one low-severity issue: regression tests shared the report step, so their failure could suppress reports. The tests now run in a separate informational PR-only step. Release and post-merge report generation do not run fixture tests. Final review and CI for this adjustment are pending.
