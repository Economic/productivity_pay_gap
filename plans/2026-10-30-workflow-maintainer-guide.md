# Plan: Consolidate maintainer documentation

Date: 2026-10-30

## Goal

Move maintenance instructions into a root MAINTAINING.md guide, following the dedicated-guide pattern in Economic/realtalk.

## Decisions made

- Keep the README focused on downloading the data, final output files, methodology, and underlying sources. Link to MAINTAINING.md for setup, reproduction, refreshes, reports, development, and releases.
- Move the existing operational sections and fetched and intermediate file documentation into the guide. Preserve the settled refresh and release behavior, including report retention, forecast assumptions, and manual publishing.
- Replace duplicated operational detail in AGENTS.md with links to the guide. Keep agent-specific branch, commit, review, live-data, release, and workflow-security constraints explicit.
- Correct links and stale implementation paths while moving the text. Update the reviewer documentation reference. Keep historical plans as records of their original work.
- This is documentation only. Do not change calculations, data, workflow configuration, or automation behavior, and do not run live refreshes or releases.

## Implementation phase

1. Create the guide from the existing README and agent guidance. Update the README, agent pointers, and reviewer reference.
2. Check that operational details survive the move, validate local Markdown links and anchors, inspect the documentation diff, and run the required checkpoint review. No new tests or local data rebuild are needed for a prose-only move.
3. Commit, push, and open a PR. Wait for the existing GitHub check and ask the maintainer to merge.

## Risks

- Duplicated instructions can drift. The guide is the full maintenance reference; AGENTS.md retains only the operational constraints agents must follow and links for the details.

## Validation and results

- Created the root MAINTAINING.md guide from the existing README maintenance sections and operational details in AGENTS.md. The README retains downloads, final files, methodology, and sources with one link to the guide. AGENTS.md retains explicit agent rules and links to the full procedures. Updated the reviewer documentation reference.
- Preserved scheduling, PR and report behavior, forecast assumptions, release guards, manual spreadsheet provenance, package and offline setup, calculation-change instructions, and the read-only build / R-free publish boundary. Corrected the assignee setting's path to update-refresh-pr.py and removed obsolete “new workflows” wording.
- Compared the moved README sections with the guide and inspected the five lines edited for current wording or paths. All 23 local Markdown links and anchors, reviewer TOML syntax, and whitespace checks passed. Historical plans are unchanged.
- Only documentation and reviewer guidance changed. Calculation code, workflow files, and committed data are unchanged. No new tests, local R rebuild, live fetch, merge, or release ran.
- Plan review 707 and implementation review 709 passed. Checkpoint 714 passed all four reviewers, including code, design, and security, with no findings. No additional accepted risks were needed.
- Delivery and the existing GitHub offline check results are recorded on [PR #36](https://github.com/Economic/productivity_pay_gap/pull/36). The maintainer merges after checks pass.
