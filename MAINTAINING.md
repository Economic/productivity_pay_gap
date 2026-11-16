# Maintaining the Productivity-Pay Gap data

## How updates work

1. Open the automatic `data-refresh` PR. If needed, create one with **Actions → refresh**.
2. Click **Approve and run workflows** if GitHub asks. Wait for `check` to pass.
3. Read the change report. Check data coverage, headline numbers, and unexpected revisions.
4. If the changes are correct, merge the PR with a merge commit.
5. To publish, run **Actions → release**. It publishes the final files and change report. Wait for it to finish.

For manual workflows, select `main`, then **Run workflow**. Keep the default settings. Select `dry_run` for a preview. Merging alone publishes nothing.

See [README.md](README.md) for downloads and [Reference](#reference) for setup and technical details.

## Troubleshooting

| Problem | Action |
|---|---|
| Expected data is still missing | Read the source coverage and failure details in the PR or workflow run. Rerun `refresh` once inputs are available. See [refresh details](#refresh-details). |
| Saved calendar is unavailable or outdated | Run **Actions → Calendar refresh → Run workflow** on `main`, using the defaults. Manual `refresh` still works without the calendar. See [calendar setup](#start-the-release-calendar). |
| BLS hours download failed | Check the error and retry `refresh`. If needed, follow the [manual replacement procedure](#hours-download-failures). |

## Reference

- [Refresh details](#refresh-details) and [release details](#release-details)
- [Maintainer setup](#maintainer-setup): secrets, notifications, protection rules, and calendar initialization
- [Reproduce the data](#reproduce-the-data): packages, live and offline runs, [reports](#the-change-report), and [code changes](#making-changes)
- [Repository files](#repository-files) and [workflow implementation](#workflow-implementation)

## Refresh details

### Schedule

All times use Eastern time, with daylight saving changes.

| Workflow | Time | Action |
|---|---|---|
| `Calendar refresh` | Monday, 5:17 a.m. | Save BLS and BEA release dates in `schedule.json` on the `calendar` branch. |
| `Scheduled data update` | Daily, 2:27 p.m. | Run `refresh` if a release or its next-day check is due. |

The five releases are Employment Situation, Productivity and Costs, Consumer Price Index, GDP, and Personal Income and Outlays. The calendar keeps yesterday's dates for next-day checks. Failed downloads keep the old schedule.

Builds include weekends and holidays. Overlapping dates cause one build. If none is due, the daily check passes without a refresh.

Each refresh updates all R packages, downloads data, rebuilds outputs, and reports changes from `main` and the last release. Even successful builds can use old API or `realtalk` data. The next-day build always runs. After that, run `refresh` manually for late data. Manual runs need no calendar.

Run `Calendar refresh` if dates change after Monday. Also run it if a missing, invalid, or expired schedule fails the daily check. GitHub can delay or skip scheduled runs.

If the hours download fails, the build uses the saved spreadsheet and updates the PR. The run then reports failure. GitHub sends a failure notice.

### Proposal updates and notifications

| Change | Result |
|---|---|
| Web files differ from `main` | Open the assigned `data-refresh` PR. |
| Web files match `main` | Close the refresh PR, if open. Input changes alone do not open a PR. |
| Inputs, packages, calculation code, or outputs change | Update an open PR's files and report, even if web numbers stay the same. |
| `main` or the last release changes | Update the open PR to use the new comparison commits. |
| Only access dates change | Update the title and check status. Keep the saved files and report. |

The description starts with the latest check and run link. It lists changes from the previous proposal and `main`, output coverage, and the next update. The title shows the check date.

The full report stays in the description with its own date and run link. Old bot reports become short notices.

Only web changes from the existing proposal cause a notification comment. GitHub can send other PR notifications.

### Next update and coverage forecast

The PR and run summary show the next build time and reasons from the saved calendar. Multiple reasons use “and”. Every check updates this line, including dry runs and builds with no web changes. The report can stay unchanged.

A missing, invalid, or expired calendar gives a `Calendar refresh` prompt. Manual refreshes still work.

**Expected latest output quarter**, below the next update, estimates coverage after that build:

1. Start with each input's latest complete quarter.
2. For inputs with a saved release due by the build, assume data through the previous completed quarter.
3. Keep the observed quarter for other inputs.
4. Use the earliest input quarter as the combined estimate.

Unchanged coverage says “no new quarter expected”. Missing calendar or coverage data gives no estimate.

Estimates are subject to source availability, including agency delays, changed dates, and `realtalk` publication. They never control builds, calculations, or schedules.

## Release details

Run releases manually. The starting commit must pass the offline check. The workflow publishes that commit's final files. Tags use today's date, for example `v2026.11.6`. Notes show changes from the last release.

Access-date changes alone cannot be released. A second same-day release needs `correction` and a reason. Use `dry_run` to check and preview without publishing. See [workflow implementation](#workflow-implementation).

## Maintainer setup

Set these GitHub options:

| Setting | Value |
|---|---|
| Repository secrets | `BLS_API_KEY`, `BEA_API_KEY`, and `BLS_DOWNLOAD_EMAIL`. See [Setup](#setup). |
| Refresh PR assignee | `benzipperer`, set in `.github/scripts/update-refresh-pr.py`. Change this for a new maintainer. |
| `protect main` ruleset | Require PRs and the `check` status. Allow merge commits only. Keep the bypass list empty. |

In the assignee's [notification settings](https://github.com/settings/notifications):

- Enable **Email** under **Participating, @mentions and custom** to receive assigned PR notices.
- Enable failed-workflow emails under **Actions**. Scheduled failure notices go to whoever last changed the schedule.
- Use **Custom routing** if Economic emails must use a specific address.

Notification settings are outside the repository.

### Start the release calendar

1. Run **Actions → Calendar refresh → Run workflow** on `main` with `dry_run` checked.
2. Check the five release types and dates in the run summary.
3. Run it again with `dry_run` unchecked. This creates the `calendar` branch.

Keep that branch for daily checks. Failed downloads leave it intact. Downloads use `BLS_DOWNLOAD_EMAIL`.

Calendar dry runs check dates without saving. Scheduled data dry runs build only when due and leave PRs unchanged. Both workflows require `main` for real runs. Branch dry runs use that branch's code. A `refresh` dry run builds on any date without changing the PR.

## Reproduce the data

### Setup

Install the versions in `renv.lock` with [renv](https://rstudio.github.io/renv/). Run this from the project directory:

```r
renv::restore()
```

`.Rprofile` starts renv and sets the repositories to economic.r-universe.dev and Posit Package Manager.

Key packages:

- [`epidatatools`](https://github.com/Economic/epidatatools): BLS and BEA API tools
- `epitargets`: pipeline helpers
- [`realtalk`](https://economic.github.io/realtalk/): price indices

For live downloads, set these environment variables, for example in `~/.Renviron`:

- `BLS_API_KEY`: [register for a key](https://data.bls.gov/registrationEngine/)
- `BEA_API_KEY`: [register for a key](https://apps.bea.gov/API/signup/)
- `BLS_DOWNLOAD_EMAIL`: contact email, required in the hours download's `User-Agent` header

### Generate the data

Run `targets::tar_make()` to download API data and the hours spreadsheet. It writes downloads to `data_raw/`, intermediate files to `data_outputs/`, and final files to `data_final/`.

Downloads stay cached for one day. Failed hours downloads keep the saved spreadsheet and record the error in `data_raw/fetch_log.csv`.

Both modes run `output_checks` and `package_check`. Package mismatches stop offline runs but only warn in live runs.

To update packages, including `realtalk` price data, run these before `tar_make()`:

```r
renv::update()
renv::snapshot()
```

### The change report

Each run writes `reports/change_report.md`, comparing local files with `origin/main`. Run `git fetch` first. Set `PPG_BASELINE` for another Git ref. The report cannot read the BLS format in releases before v2026.3.11.

Refreshes and PR checks show two comparisons:

| Comparison | Purpose |
|---|---|
| Proposed data against `main` | Show what merging changes. |
| Proposed data against the last release | Show what publishing changes, including changes already merged. |

The overview shows summaries and headline numbers for the release, `main`, and proposed data. Wages retain each version's last quarter. Missing wage files show “Not available”. Expand comparisons for inputs, outputs, and revisions.

Both comparison commits are recorded. PR checks compare the proposed merge result with the base commit. Checks after merging compare with the commit before the push. Release notes use the previous release only.

For both local views, also set `PPG_RELEASE_BASELINE` to the published tag. R never looks up GitHub releases.

Comparisons list added or removed files, periods, and series, revised values, and changed headline numbers. Added files can leave existing values unchanged. Both sections show the same differences. Differences do not prove a download or release occurred.

The Why section splits revisions by input. Unexplained revisions are flagged as calculation changes.

- Productivity and pay tables use index points: effects on the latest common quarter and average signed effects across revised quarters.
- Three headline-growth tables show effects in percentage points. They include rounding and added or removed quarters when needed.
- Zero effects stay visible. A dash means the input is outside the formula.
- The productivity-to-pay growth multiple shows previous → revised values without splitting the change by input.

### Offline mode

Rebuild from saved data without downloads or API keys:

```r
Sys.setenv(TAR_PROJECT = "offline")
targets::tar_make()
```

CI uses this mode. A matching rebuild leaves `git diff -- data_final data_outputs` empty. The `_targets_offline/` cache leaves `_targets/` unchanged. No network access is needed.

### Making changes

Create a branch and PR. Commit each complete change separately. The maintainer uses `gh pr merge N --merge`.

If code changes outputs, rebuild offline and commit them in the same PR. Otherwise, `check` fails.

If you change the index formula in `R/combine.R`, update `index_terms` in `R/report_why.R` in the same PR. Otherwise, later reports flag a calculation change.

The report warns about changes to `R/bls.R`, `R/bea.R`, `R/prices.R`, `R/web.R`, and series code files. It cannot measure their effects.

#### Hours download failures

If BLS blocks the download:

1. Download the [total economy hours file](https://www.bls.gov/productivity/tables/total-economy-hours-employment.xlsx) manually.
2. Save it as `data_raw/total-economy-hours-employment.xlsx`.
3. Set its `date_accessed` in `data_raw/fetch_log.csv` to the download date.

## Repository files

See [README.md](README.md#final-files-data_final) for the five final files.

Commit downloaded, intermediate, and final files to Git. Ignore the caches (`_targets/` and `_targets_offline/`) and generated reports (`reports/`).

### Fetched files (`data_raw/`)

| File | Contents |
|---|---|
| `bea_api_output.csv` | BEA API results |
| `bls_api_output.csv` | BLS API results |
| `total-economy-hours-employment.xlsx` | BLS hours spreadsheet |
| `fetch_log.csv` | Last successful download date and last attempt's status for each source. Failures keep the successful date. |

### Intermediate files (`data_outputs/`)

| File | Contents |
|---|---|
| `bls_hours.csv` | BLS total economy hours |
| `bls_pay.csv` | Early and current BLS wages, combined |
| `prices.csv` | Price index |

### Hand-maintained inputs (`data_inputs/`)

| File | Contents |
|---|---|
| `bls_EEU00500006.csv` | Wages before 1964. This file needs no updates. |
| `bls_series_codes.csv`, `bea_series_codes.csv` | API series settings |

## Workflow implementation

The [check workflow](.github/workflows/check.yml) rebuilds offline on every PR and push to `main`. The check fails if rebuilt files in `data_final/` or `data_outputs/` differ from the committed files.

Reports go in PR comments, except refresh PRs use the description. Reports after merging compare with the commit before the push. Approve the held check on workflow-created PRs.

[update-refresh-pr.sh](.github/scripts/update-refresh-pr.sh) calls [update-refresh-pr.py](.github/scripts/update-refresh-pr.py) to manage the refresh PR. Keep these security rules:

- Run R and package code only in the build job, with read-only repository access.
- Give write access to the publish job. Run no R or package code there.
- Copy only files on the allowlist with [copy-refresh-files.sh](.github/scripts/copy-refresh-files.sh).
- Keep only data on the calendar branch. Never run code from it.

[release-plan.sh](.github/scripts/release-plan.sh) selects the tag and checks release rules. [publish-release.sh](.github/scripts/publish-release.sh) publishes the checked commit's final files.
