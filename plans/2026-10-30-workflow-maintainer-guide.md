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

- Pending implementation.
