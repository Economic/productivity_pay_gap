# Plan: Simplify maintainer instructions

Date: 2026-11-16

## Goal

Put routine maintenance in a short checklist, with troubleshooting immediately below it and the technical reference later in MAINTAINING.md.

## Decisions made

- Keep MAINTAINING.md as the full maintenance reference and keep README focused on data users.
- Lead with four actions: wait for or request a refresh, review the proposal, approve checks and merge, and publish manually.
- Put common failures in a small troubleshooting table. Link to the detailed procedures.
- Move scheduling, proposal updates, notification behavior, report interpretation, and release safeguards into reference sections. Compress repeated explanations while preserving their meaning.
- Preserve existing heading anchors used by AGENTS.md. Keep setup, offline reproduction, development, repository files, and workflow security guidance available.
- This is documentation only. Do not change workflows, calculations, packages, or data. Do not run live refreshes or releases.
- Use a separate checkout based on current remote main. Leave the original checkout's uncommitted renv changes untouched.

## Implementation phase

1. Rewrite the guide and inspect it against the previous version for lost operational requirements.
2. Validate local Markdown links and anchors, whitespace, and the documentation-only diff. Run the required branch checkpoint review and resolve real findings. No local R rebuild is needed for this prose-only change.
3. Record results, push the branch, and open a PR. Wait for the GitHub check and ask the maintainer to merge.

## Risks

- A shorter opening can hide uncommon procedures. Keep the full reference in the same file and link to it from the checklist and troubleshooting table.

## Validation and results

- Pending.
