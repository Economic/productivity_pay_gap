# Plan: Refresh data on agency release days

Date: 2026-10-28

## Goal

Prepare the rolling data refresh PR when an input is released, with one next-day follow-up to catch delayed inputs.

## Decisions made

- Replace Monday's full data refresh with release-day builds. Keep the manual refresh button.
- Follow Employment Situation, Productivity and Costs, Consumer Price Index, Gross Domestic Product, and Personal Income and Outlays. Include preliminary and revised Productivity and Costs releases.
- Run the daily calendar check at 2:27 p.m. in `America/New_York`, following daylight saving time. Build on each release date and on the following calendar day, including weekends and holidays. Combine overlapping dates into one scheduled build per day.
- The next-day build is unconditional. A successful first build does not prove all upstream data was available. Do not add source freshness checks or further automatic retries.
- Refresh the saved agency calendars every Monday at 5:17 a.m. Eastern, matching realtalk. Keep a manual button and a dry run for both new workflows.
- Adapt realtalk's Python calendar reader, isolated calendar writer, and two calendar workflows. Reference implementation: Economic/realtalk at `577c812073f10b31d5380ac0fc7719befaee93f0`.
- Store `schedule.json` on a separate `calendar` branch. Download and parse with read-only permissions. Save only the validated JSON in a separate job with write permission. Never execute code from the calendar branch.
- Retain yesterday's events when refreshing the calendar, so refreshing between a release and its follow-up does not erase that follow-up. Compare Eastern calendar dates, not elapsed 24-hour intervals.
- The daily job reads the saved calendar without downloading agency feeds. Missing, invalid, or exhausted schedules fail visibly. A failed weekly refresh preserves the previous calendar. Use GitHub's existing workflow failure email notifications rather than adding issue notification machinery.
- Call the existing `refresh.yml` as a reusable workflow. Keep its read-only R build, allowlisted artifact copy, R-free publish job, rolling PR behavior, and manual release process.
- Use the latest published realtalk package available from r-universe. Nothing in this change publishes realtalk, merges a data PR, or publishes a data release.
- Work on a branch and open an implementation PR. The maintainer decides when to merge. Do not initialize the remote calendar or run live data refreshes before merge.

## Implementation phase

1. Adapt the calendar parser and writer. Generalize the BLS parser beyond CPI. Preserve agency timestamps, validate all five release types, and support release-day and next-day decisions across month, year, and daylight saving boundaries.
2. Add weekly calendar refresh and daily scheduled data update workflows. Remove the full build's Monday cron and expose it through `workflow_call`, including its existing dry-run input. Keep permissions scoped to each job and real scheduled updates restricted to main.
3. Add focused offline fixtures for calendar parsing, due dates, failed downloads preserving the saved file, and writing only the schedule to an isolated calendar branch. Run these checks in PR CI. Keep tests independent of agency availability and credentials.
4. Update README and AGENTS.md with the new schedule, retry policy, failure handling, and bootstrap steps. After merge, the maintainer first runs Calendar refresh as a dry run, inspects dates, then runs it normally to create the saved calendar.
5. Independently inspect the subagents' changes. Run focused checks, workflow lint, existing PR maintenance tests, and a full offline rebuild. Confirm committed data outputs are unchanged.
6. Commit self-contained changes and wait for post-commit roborev reviews. Run `roborev review --branch --base main --panel checkpoint_panel --wait` at the phase checkpoint. Fix normal-use findings. Record low-risk findings as accepted risks when a fix would add disproportionate complexity, then comment on and close those jobs.
7. Open a PR, wait for its checks, and report the result to the maintainer. Stop and ask if a major design question arises.

## Risks

- A release rescheduled after the Monday calendar refresh can be missed until the next refresh. Manual calendar refresh and manual data refresh remain available.
- APIs or realtalk publication can lag beyond the next-day build. The follow-up improves coverage but is not a guarantee. The maintainer can run refresh again.
- GitHub can delay or drop scheduled runs. There is no persistent catch-up queue or global daily deduplication across manually triggered runs. Normal scheduled overlaps produce one build per date.
- Unconditional follow-ups can do no useful data work. The user accepted this cost, roughly 6 to 8 full builds per month under the currently published calendar pattern.
- Existing refresh and report risks still apply. No calculation or data changes are intended.

## Validation and results

- Implemented the generalized calendar reader, isolated writer, weekly calendar workflow, and daily reusable refresh call. Updated maintainer instructions and removed the obsolete weekly PR wording.
- All 19 new offline tests passed: 13 calendar cases and 6 writer cases. They cover all five releases, preliminary and revised Productivity and Costs dates, timezone and calendar-day boundaries, overlapping releases, saved-file preservation, branch isolation, and symlink replacement. All 5 existing refresh PR lifecycle cases passed.
- Independently exercised the daily workflow's actual shell step with local Git fixtures. Due and non-due schedules emit the correct output. A missing calendar fails before calling refresh.
- actionlint 1.7.12 passed every workflow. Bash syntax checks and `git diff --check` passed.
- A forced offline rebuild completed all 25 targets with none skipped. All committed files in `data_final/` and `data_outputs/` stayed unchanged.
- A calendar-only live download validated 36 events across all five release types. The resulting schedule has 7 build dates in November 2026 and 8 in December 2026, including next-day runs and overlapping dates. No live data pipeline or remote calendar initialization was run.
- Plan commit review 600, script commit review 602, and workflow commit review 604 passed. Phase checkpoint 609 passed all four reviewers with no findings. No additional risks needed to be accepted.
- Delivery and final GitHub check results are recorded on the implementation PR. The remote calendar bootstrap remains a maintainer step after merge.
