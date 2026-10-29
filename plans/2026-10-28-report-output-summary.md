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

- Added comparison facts and one shared output-description builder. The dual-baseline overview now has Comparison and Result columns. Single-baseline and expanded comparisons render the same description.
- Kept the short labels and the web-file comparison boolean used by existing report and refresh behavior. No workflow, notification, or calculation changes were needed.
- Extended report regression checks passed for added and removed wage files and series, simultaneous file additions and revisions, simultaneous period changes and revisions, stats-only changes, full-data revisions below web rounding, access dates, source documentation, and reordered statistics. Existing attribution and baseline checks also passed.
- Inspected the actual main-versus-v2026.9.14 report. It identifies the added wage file, 468 values in the two new full-data series, and changed source documentation. It explicitly states that existing published productivity, pay, and headline values are unchanged. Against main, it says no output changes.
- A forced offline rebuild completed all 25 targets with none skipped. All committed files in `data_final/` and `data_outputs/` stayed unchanged. Workflow lint and `git diff --check` passed.
- Plan commit review 626 passed. Implementation reviews and delivery are pending.
