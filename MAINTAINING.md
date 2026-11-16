# Maintaining the Productivity-Pay Gap data

Use the checklist below for routine updates. [Reference](#reference) covers setup, local development, and automation details. See [README.md](README.md) for downloads, final files, methodology, and sources.

## How updates work

1. **Wait for an update PR, or request one.** Refreshes run automatically on agency release days and the following day. To fetch data manually, run **Actions → refresh → Run workflow** on `main`, using the defaults. It opens or updates the `data-refresh` PR when web files differ from `main`.
2. **Review the PR description.** Check the latest output quarter, headline numbers, and explanations of revisions. The comparison with `main` shows what merging changes. The comparison with the last release shows what publishing changes. The opening status also shows the next scheduled update and expected coverage.
3. **Merge the update.** If prompted, click **Approve and run workflows**. Wait for `check` to pass, then merge using a merge commit. This updates `main`. Publishing is a separate step.
4. **Publish when ready.** Run **Actions → release → Run workflow** on `main`, leaving the defaults unchanged. It publishes the checked commit's five final files and a change report as a dated GitHub release. Select `dry_run` for a preview. A same-day correction requires `correction` and a reason. See [release details](#release-details) for the safeguards.

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

`Calendar refresh` runs every Monday at 5:17 a.m. Eastern. It saves BLS and BEA dates for Employment Situation, Productivity and Costs, Consumer Price Index, GDP, and Personal Income and Outlays in `schedule.json` on the separate `calendar` branch. It retains yesterday's releases for next-day follow-ups. Failed downloads keep the previous schedule.

`Scheduled data update` checks the saved dates every day at 2:27 p.m. Eastern. It calls `refresh` on release days and the following calendar day, including weekends and holidays. Overlaps produce one build per day. A successful daily check can mean no refresh was due. Times follow Eastern daylight saving changes.

Each refresh updates every R package, fetches the latest BLS and BEA data, rebuilds, and writes a report against `main` and the last published release. The next-day build runs even after a successful release-day build because agency APIs or the published `realtalk` package can still contain old data. There are no further automatic retries. Manual `refresh` can run on any date without a calendar.

A missing, invalid, or exhausted schedule fails the daily check. Run `Calendar refresh` to repair it, or to pick up changes announced after Monday. GitHub can delay or drop scheduled runs. If the hours download fails, the refresh builds with the committed spreadsheet and updates the PR as usual, then marks the run as failed so GitHub sends a failure notification.

### Proposal updates and notifications

The assigned `data-refresh` PR opens when web files differ from `main`. It closes when they match. Inputs alone do not open a PR. For an existing proposal, meaningful input, package, calculation code, or output changes update its files and report, even when web numbers match. New `main` or release baselines also update the proposal.

The title and opening status record the latest check. The description starts with the check time and run link, changes since the previous proposal, pending changes against `main`, output coverage, and the next update. Access dates alone update the title and opening status, leaving the committed files and report intact. The single full report stays in the description with its own update time and run link. Older bot report comments become superseded notices.

A short notification comment is posted only when web files change against the existing proposal. Changes limited to inputs, packages, or release baselines do not trigger that comment. GitHub can still notify subscribers of other PR activity.

### Next update and coverage forecast

The PR's opening status and workflow run summary show the next scheduled build at 2:27 p.m. Eastern and its release or follow-up reasons. Overlapping reasons are joined with “and”. This line uses the saved calendar and updates on every check, including dry runs and builds with no web changes, even when the detailed report stays unchanged. An unavailable calendar produces a message asking for `Calendar refresh` without blocking manual refreshes.

**Expected latest output quarter**, directly below the next update, estimates combined coverage after that build. It starts from each input's latest complete quarter. Inputs affected by saved releases due by the build are projected through the previous completed quarter; other inputs keep their observed coverage. The earliest input quarter sets the estimate. An unchanged estimate says “no new quarter expected”. Missing calendar or input coverage makes the estimate unavailable.

Estimates are subject to source availability, including rescheduled releases, agency delays, and publication of `realtalk`. The forecast never controls the build, calculations, or schedule.

## Release details

Publishing is manual. A release uses the final files of the commit the workflow starts from, after the offline check passes on that commit. Its tag uses the day's date, such as `v2026.11.6`. The change report against the previous release becomes the release notes.

The workflow refuses a release when only access dates changed. A second release on the same day requires `correction` and a reason. A `dry_run` runs the checks and previews the tag and notes without creating anything. See [workflow implementation](#workflow-implementation) for the scripts.

## Maintainer setup

The refresh emails depend on GitHub settings that aren't stored in the repository.

* **Repository secrets:** `BLS_API_KEY`, `BEA_API_KEY`, and `BLS_DOWNLOAD_EMAIL` (see [Setup](#setup)).
* **The assignee:** refresh pull requests are assigned to `benzipperer`, set in `.github/scripts/update-refresh-pr.py`. A new maintainer changes that name.
* **Email notifications,** in the assignee's [notification settings](https://github.com/settings/notifications):
  * **"Participating, @mentions and custom"**: tick **Email**. Being assigned counts as participating, so this covers the refresh emails.
  * **"Actions"**: tick **Email** for failed workflows. GitHub sends scheduled run failures to whoever last changed the workflow's schedule.
  * **"Custom routing"**: if the account has several email addresses, route the Economic organization to the one the maintainer reads.
* **The "protect main" ruleset,** in the repository settings: pull requests required, the `check` status check required, merge commits only, no bypass list.

### Start the release calendar

To initialize the saved calendar, run **Actions → Calendar refresh → Run workflow** on `main` with `dry_run` checked. Inspect the five release types and their dates in the run summary. Then run it without `dry_run` to create the `calendar` branch. Keep that branch: the daily job reads its saved schedule even if a later calendar download fails. The calendar download uses the existing `BLS_DOWNLOAD_EMAIL` secret.

Both calendar workflows have a dry-run option. A calendar dry run downloads and validates without saving. A scheduled data dry run follows the saved dates and, if due, builds and reports without changing the refresh PR. Real calendar and scheduled updates run only from `main`. Branch dry runs use the branch's code. The `refresh` dry run can build on any date without changing the PR.

## Reproduce the data

### Setup

Package versions are locked with [renv](https://rstudio.github.io/renv/). To install them, run this from the project directory:

```r
renv::restore()
```

`.Rprofile` activates renv and sets the repositories to economic.r-universe.dev and Posit Package Manager.

Along with CRAN packages, this installs three EPI packages:

* [`epidatatools`](https://github.com/Economic/epidatatools): BLS and BEA API wrappers
* `epitargets`: helpers for the `targets` pipeline
* [`realtalk`](https://economic.github.io/realtalk/): price indices

Set these environment variables, for example in `~/.Renviron`:

* `BLS_API_KEY` ([register](https://data.bls.gov/registrationEngine/))
* `BEA_API_KEY` ([register](https://apps.bea.gov/API/signup/))
* `BLS_DOWNLOAD_EMAIL`: your email address, sent in the `User-Agent` header. BLS refuses downloads of the hours spreadsheet unless the request includes a contact email.

### Generate the data

Run `targets::tar_make()`. It fetches the BLS and BEA data from their APIs, downloads the BLS hours spreadsheet, and writes the fetched files to `data_raw/`, intermediate files to `data_outputs/`, and the final files to `data_final/`.

Fetched data is cached for one day. If you run `tar_make()` again within a day, it reuses the cached data; after that, it fetches the data again. If the hours download fails, the pipeline keeps the committed spreadsheet, and `data_raw/fetch_log.csv` records why.

The `output_checks` and `package_check` sanity checks run in both modes. A package mismatch is an error offline and a warning in live mode.

To use newer package versions, such as the latest price indices in `realtalk`, run `renv::update()` and then `renv::snapshot()` before `tar_make()`.

### The change report

Each run writes `reports/change_report.md`, comparing the working tree with `origin/main`. Run `git fetch` first, or set `PPG_BASELINE` to another ref. Baselines must be v2026.3.11 or later because earlier releases use an unsupported BLS API format.

Refreshes and PR checks include two comparisons: proposed data against `main` for merging, and against the last published release for publishing. The overview shows both summaries and headline stats for the release, `main`, and proposal. Last-quarter typical and counterfactual wages retain each snapshot's dollar amounts and quarter; missing wage files show “Not available”. Expand either comparison for its inputs, outputs, and revision explanations. Release differences include changes already merged into `main`.

Both baselines are recorded by commit. PR checks compare the proposed merge result with the PR's base commit. Post-merge checks compare with the commit before the push. Release notes compare only with the previous release. To generate both views locally, set `PPG_RELEASE_BASELINE` to the published tag alongside `PPG_BASELINE`. The R pipeline never looks up releases on GitHub.

Each comparison lists added or removed files, periods, and series, revisions to existing values, and changed headline statistics. Concurrent changes appear together. A new counterfactual wage file can leave existing productivity, pay, and headline values unchanged. The overview and details describe the same snapshot differences; they do not indicate that data was fetched or published.

The Why section splits revisions exactly by input. Unexplained revisions are flagged as calculation changes. Paired productivity and pay tables show contributions to the latest common quarter's index revision and average signed contributions across revised quarters, in index points. Three headline-growth tables use percentage points, including rounding and added or removed quarters when applicable. Zero effects stay visible; a dash marks an input outside the formula. The productivity-to-pay growth multiple shows previous → revised without a decomposition.

### Offline mode

To rebuild everything from the committed files without fetching anything:

```r
Sys.setenv(TAR_PROJECT = "offline")
targets::tar_make()
```

This is what the `check` workflow runs. If the committed outputs are reproducible, `git diff -- data_final data_outputs` is then empty.

Offline mode uses its own targets store, `_targets_offline/`, so it does not disturb the live cache in `_targets/`. It needs no network access or API credentials.

### Making changes

Make each change on a branch and open a pull request. Commit each self-contained change separately. The maintainer merges with merge commits only (`gh pr merge N --merge`). If a change to the code changes the outputs, rebuild in offline mode and commit the new outputs in the same pull request, or the `check` workflow fails.

When intentionally changing how the indexes are calculated in `R/combine.R`, update `index_terms` in `R/report_why.R` in the same PR. Otherwise later reports will flag a calculation change. Changes to `R/bls.R`, `R/bea.R`, `R/prices.R`, `R/web.R`, and the series code files are not measured by the report; it names them in a warning.

#### Hours download failures

If BLS refuses the hours download, download the [total economy hours file](https://www.bls.gov/productivity/tables/total-economy-hours-employment.xlsx) by hand, save it as `data_raw/total-economy-hours-employment.xlsx`, and set its `date_accessed` in `data_raw/fetch_log.csv` to the day you downloaded it.

## Repository files

The five final files are documented in [README.md](README.md#final-files-data_final). Fetched files, intermediate files, and final files are committed to git. The targets stores (`_targets/` and `_targets_offline/`) and generated reports (`reports/`) are ignored.

### Fetched files (`data_raw/`)

* `bea_api_output.csv`: BEA API results
* `bls_api_output.csv`: BLS API results
* `total-economy-hours-employment.xlsx`: BLS total economy hours spreadsheet
* `fetch_log.csv`: when each source was last fetched, and the status of the last attempt. A failed fetch keeps the date of the last successful one.

### Intermediate files (`data_outputs/`)

* `bls_hours.csv`: BLS total economy hours
* `bls_pay.csv`: early and current BLS wage series, combined
* `prices.csv`: price index

### Hand-maintained inputs (`data_inputs/`)

* `bls_EEU00500006.csv`: historical production worker wages before 1964. This is static and needs no updates.
* `bls_series_codes.csv` and `bea_series_codes.csv`: API series configurations.

## Workflow implementation

The [check workflow](.github/workflows/check.yml) runs on every PR and every push to `main`. It rebuilds offline and fails if `data_final/` or `data_outputs/` differs from the committed files. It posts the change report as a PR comment except on refresh PRs, which keep their authoritative report in the description. Post-merge reports compare with the commit before the push. GitHub holds the required check on PRs opened by a workflow until a maintainer approves the run.

The refresh entry point is [update-refresh-pr.sh](.github/scripts/update-refresh-pr.sh), which calls [update-refresh-pr.py](.github/scripts/update-refresh-pr.py). The build job runs R and package code with read-only repository access. The publish job can write but runs no R or package code. It copies only allowlisted files from the build artifact using [copy-refresh-files.sh](.github/scripts/copy-refresh-files.sh). Keep that split. The calendar branch contains data only; never execute code from it.

The release workflow uses [release-plan.sh](.github/scripts/release-plan.sh) to choose the tag and apply release guards and [publish-release.sh](.github/scripts/publish-release.sh) to attach the final files from the checked commit and publish the release.
