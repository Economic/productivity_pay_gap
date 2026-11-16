# Plan: Simplify maintainer instructions

Date: 2026-11-16

## Goal

Put routine maintenance in a short checklist, with troubleshooting immediately below it and the technical reference later in MAINTAINING.md.

## Decisions made

- Keep MAINTAINING.md as the full maintenance reference and keep README focused on data users.
- Lead with short actions for opening a refresh PR, running checks, reviewing, merging, and publishing. The maintainer requested realtalk-style steps in the opening checklist phase.
- Put common failures in a small troubleshooting table. Link to the detailed procedures.
- Move scheduling, proposal updates, notification behavior, report interpretation, and release safeguards into reference sections. Compress repeated explanations while preserving their meaning.
- Preserve existing heading anchors used by AGENTS.md. Keep setup, offline reproduction, development, repository files, and workflow security guidance available.
- This is documentation only. Do not change workflows, calculations, packages, or data. Do not run live refreshes or releases.
- Use a separate checkout based on current remote main. Leave the original checkout's uncommitted renv changes untouched.

## Implementation phase

1. Rewrite the guide and inspect it against the previous version for lost operational requirements.
2. Validate local Markdown links and anchors, whitespace, and the documentation-only diff. Run the required branch checkpoint review and resolve real findings. No local R rebuild is needed for this prose-only change.
3. Record results, push the branch, and open a PR. Wait for the GitHub check and ask the maintainer to merge.

## Reference rewrite phase

The maintainer asked for simpler technical English in all text from “Refresh details” onward. Update the existing PR #37.

1. Keep the opening checklist, troubleshooting table, and reference links unchanged.
2. Rewrite the remaining sections with short sentences, direct instructions, and common words. Use tables for parallel rules. Remove repeated explanations. Keep technical names, commands, links, and operating rules accurate.
3. Check all links and existing anchors. Compare the rewrite with the previous text for lost requirements. Run the branch checkpoint review, push to PR #37, and wait for CI.

## Opening checklist phase

The maintainer asked for an opening checklist like realtalk's maintainer guide. Update PR #37.

1. Follow the short action steps in Economic/realtalk's `.github/MAINTAINING.md`, including its open shortening PR #59.
2. Keep merge and release as separate actions. This project's release workflow does not merge the update PR.
3. State shared manual-workflow settings once. Keep all text from Troubleshooting onward unchanged.
4. Check links, anchors, and the diff. Run the checkpoint review, push, and wait for CI.

## Risks

- A shorter opening can hide uncommon procedures. Keep the full reference in the same file and link to it from the checklist and troubleshooting table.

## Validation and results

- Added the four-step checklist and troubleshooting table, about 300 words combined. Moved scheduling, proposal updates, forecasts, and release safeguards into linked reference sections. Compressed report explanations and added a direct link to the manual hours replacement procedure.
- All 37 local Markdown links and all 15 pre-existing guide anchors passed validation. Whitespace checks passed. Inspected the diff against the prior guide to confirm release guards, report semantics, provenance, local reproduction, and workflow security guidance remain available.
- Only MAINTAINING.md and this plan changed. No R rebuild, live fetch, workflow change, data change, merge, or release ran. The original checkout and its uncommitted renv changes remain untouched.
- Automatic plan review 726 and implementation review 728 passed. Branch checkpoint 738 passed all four reviewers, including code, design, and security, with no findings. No additional accepted risks were needed.
- The initial version passed GitHub check 43909147233 on [PR #37](https://github.com/Economic/productivity_pay_gap/pull/37). The maintainer requested a further reference rewrite before merging.

## Reference rewrite validation

- Rewrote every section from Refresh details onward with short sentences and direct instructions. Used tables for schedules, PR update rules, settings, comparisons, and file lists. Kept the opening text unchanged.
- Kept operating rules, release checks, report units, download provenance, and the read-only build / R-free publish split. No code, workflow, package, or data changes.
- All 37 local Markdown links and all existing anchors passed. The opening text is unchanged. Whitespace checks passed. Checkpoint 747 passed with no findings. Final follow-up reviews and CI results are recorded on PR #37.

## Opening checklist validation

- Replaced the long checklist with five short actions. Put shared manual-workflow settings below the list. Kept the release separate from merging.
- The source style is [realtalk's guide](https://github.com/Economic/realtalk/blob/main/.github/MAINTAINING.md) and its [shortening PR #59](https://github.com/Economic/realtalk/pull/59).
- Local checks, branch review, and CI results are recorded on PR #37.
