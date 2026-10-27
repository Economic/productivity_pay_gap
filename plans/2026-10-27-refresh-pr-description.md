# Plan: Keep the rolling refresh PR report current

Date: 2026-10-27

## Decisions made

- A refresh that matches the existing PR's web numbers updates that PR's description with the latest report.
- It does not rewrite the branch, post a new comment, or change the title in that case. New web numbers retain the existing branch-update and notification behavior.
- A refresh that matches main still closes a stale PR. With no open PR and no new web numbers, it still does nothing.
- The description identifies the report as the latest refresh build. The branch can retain earlier inputs or package versions when the published web numbers match.
- Keep the read-only build job, allowlisted artifact copy, and R-free publish job. No published calculations or data changes are needed.
- Follow the established branch, PR, checks, merge, and refresh workflow for this follow-up. Do not merge the data refresh PR or publish a release.

## Implementation phase

1. Share description generation between normal updates and unchanged-number updates.
2. Exercise the PR lifecycle with local fixtures and a stub GitHub CLI. Verify that unchanged numbers edit only the description, fresh numbers retain notifications, and stale/no-PR cases retain their behavior.
3. Run the offline build, required review, and GitHub checks. Fix real findings; accept remote edge cases when extra code would add disproportionate complexity.
4. Merge the implementation and run refresh. Confirm the existing PR gets the new report without a branch rewrite or new comment when its web numbers match.

## Risks

- Updating the description keeps the latest refresh report visible, while the branch remains the last refresh that changed web numbers. The description makes this distinction explicit. This is accepted rather than rebuilding branches for unchanged numbers.
- The repository's existing refresh and informational-report risks still apply.

## Validation

Results are recorded below and in the implementation PR.
