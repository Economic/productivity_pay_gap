# Plan: Describe output changes explicitly

Date: 2026-10-28

## Goal

Explain each comparison with concrete output changes. A new output file must not look like a revision to existing productivity or pay values.

## Decisions made

- Replace the dual-baseline overview's summary and web-visible yes/no columns with one generated result description.
- Derive the description from comparison facts: added or removed output files, revised existing values, added or removed periods or series, and changed published headline statistics.
- Combine applicable changes. Adding a counterfactual wage file must not hide revisions elsewhere.
- Use the same description in the detailed comparison and the single-baseline report. Retain the existing short change label for the first bold line and refresh PR titles.
- Preserve both baselines, exact attribution, calculation warnings, notification rules, and all published data calculations.
- Scope this change to the output descriptions discussed with the user. Keep the existing run-context wording and zero-contribution tables.
- Commit and complete roborev reviews before pushing and opening a PR. Do not merge or run a live refresh.

## Implementation phase

1. Add output comparison facts and a deterministic description builder. Reuse the existing value comparisons and floating-point tolerance where appropriate.
2. Render the description in the overview and each detailed comparison. Update the README.
3. Extend in-memory report fixtures for unchanged data, added files, revisions, changed stats, periods or series added or removed, and simultaneous changes. Inspect the actual main-versus-release report.
4. Run the regression checks and an offline rebuild. Confirm committed outputs stay unchanged.
5. Commit, wait for post-commit reviews, and run the checkpoint panel. Fix real findings. Record low-risk findings as accepted risks if a fix would add disproportionate complexity. Once reviews pass, push, open a PR, and wait for CI.

## Risks

- The description summarizes data differences. It does not establish whether new data was fetched or whether the website has published a release.
- Existing accepted attribution and informational-report risks still apply.

## Validation and results

- Pending implementation.
