# Maintaining the Productivity-Pay Gap data

This guide covers setup, automated and manual data updates, change reports, development, and releases. See [README.md](README.md) for downloads, final files, methodology, and data sources.

## How updates work

1. **Every Monday at 5:17 a.m. Eastern**, `Calendar refresh` downloads the BLS and BEA release calendars. It saves dates for Employment Situation, Productivity and Costs, Consumer Price Index, GDP, and Personal Income and Outlays in `schedule.json` on the separate `calendar` branch. A failed refresh keeps the previous schedule. Calendar refresh retains yesterday’s releases so their next-day follow-ups remain scheduled.
2. **Every day at 2:27 p.m. Eastern**, `Scheduled data update` reads the saved calendar. On a release day and the following calendar day, including weekends and holidays, it runs `refresh`. Overlapping dates produce one scheduled build per day. Each refresh:
   * updates every R package and fetches the latest BLS and BEA data
   * rebuilds the numbers and writes a change report against both `main` and the last published release; its headline table includes the last quarter's typical and counterfactual wages for each snapshot, with dollar amounts and quarters, or “Not available” for snapshots without the wage file
   * opens an assigned pull request from `data-refresh` when the web files differ from `main`; closes an existing refresh PR when the latest build's web files match `main`
   * updates the proposal's files and report when inputs, packages, calculation code, or outputs change, even if the web numbers stay the same; refreshes them when the comparison baselines change too
   * puts the last check time and run link, changes since the previous proposal, pending changes against `main`, latest output quarter, and next scheduled update with its reasons first in the description; includes the check date in the title
   * posts a short notification comment only when the web files change against the existing proposal; the description holds the single current report, and earlier bot report comments become short superseded notices
3. **When the maintainer wants the new numbers in `main`,** they open that pull request, click "Approve and run workflows" (GitHub holds the required check on pull requests opened by a workflow), and merge once the check passes. This changes `main` but publishes nothing.
4. **When the maintainer wants to publish,** they run the `release` workflow from the Actions tab, on `main`, with every box unticked. It publishes `main`'s final files as a release named for the day (for example `v2026.10.22`), with a change report covering everything since the previous release as notes. Ticking `dry_run` previews the tag and notes without creating anything. The offline check must pass on the commit being released. The workflow refuses a release when only access dates changed. A second release on the same day requires `correction` and a reason.

Times follow Eastern daylight saving changes. The next-day build runs even if the release-day build succeeded: agency APIs or the published `realtalk` package can still have old data when a build succeeds. If only access dates change, the branch and its report stay unchanged. The title and top status record the latest check. The report has its own update time and run link, so its dates describe the committed files. Input or package changes without changed web numbers update the branch and report without a notification comment. GitHub can still notify subscribers of other PR activity. There are no further automatic retries. If inputs are still late, run `refresh` manually from Actions once they are available. Manual refresh does not depend on the calendar.

The refresh PR's opening status and workflow run summary show the next scheduled data update at 2:27 p.m. Eastern, including the release or next-day follow-up reasons. Overlapping reasons are joined with “and”. The line uses the saved calendar at the time of the check and updates even when the detailed report stays unchanged. Dry runs and builds with no web changes include it in the run summary too. If the saved calendar is missing, invalid, or exhausted, the line says the next update is unavailable and asks you to run Calendar refresh. This does not block a manual data refresh.

Directly below it, **Expected latest output quarter** estimates the latest quarter of the combined final output after that build. It starts with each input's latest complete quarter and projects inputs affected by saved releases due by that build through the previous completed quarter, following normal release timing. Inputs without a release keep their observed coverage. The earliest input quarter sets the estimate. An unchanged estimate says “no new quarter expected”. Every estimate is qualified with “subject to source availability”: rescheduled releases, agency delays, and publication of the realtalk package can affect actual coverage. Missing calendars or input coverage produce an unavailable estimate and leave manual refreshes working. The forecast never controls the build, calculations, or schedule.

Every pull request into `main` must pass the `check` workflow, which rebuilds everything from the committed raw data and fails if the result differs from the committed files. `main` accepts changes only through pull requests, merged with merge commits.

If the BLS hours download fails, the refresh still finishes with the committed spreadsheet, then fails, so GitHub emails a failure notice. A missing, invalid, or exhausted saved calendar fails the daily check. Run `Calendar refresh` to repair it. Calendar changes announced after Monday can be missed until the next calendar refresh; run it manually when needed. GitHub can delay or drop scheduled runs.

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

Each run ends by writing `reports/change_report.md`. It describes what changed compared with `origin/main`, and why: each input source, packages and code, and the final files. It splits every revision exactly into contributions from each input. If the inputs do not explain a revision, it says the calculation itself changed. Run `git fetch` first so `origin/main` is current, or set `PPG_BASELINE` to compare with another ref, such as a release tag from v2026.3.11 on.

Baselines must be v2026.3.11 or later. Older releases store the BLS API results in a format the report does not read.

A refresh compares the latest build with the existing proposal to decide whether to update the branch or post a notification. The report's comparisons serve different purposes: proposed data versus `main` describes merging, and proposed data versus the last published GitHub release describes publishing. Release differences do not trigger repeated notifications. Data refreshes and PR checks retain both report comparisons. The overview shows both summaries and the headline stats for the release, `main`, and the proposed data. Expand each comparison for its inputs, outputs, and revision explanations. The `main` comparison shows what merging changes. The release comparison includes changes already merged into `main`. Both baselines are recorded by commit. PR checks use the proposed merge result and the PR's base commit as `main`.

To generate both views locally, set `PPG_RELEASE_BASELINE` to the published release tag as well as setting `PPG_BASELINE` for `main`. No release lookup happens inside the R pipeline. Post-merge checks keep their comparison with the commit before the push. Release notes keep their single comparison with the previous release.

Each comparison describes output changes explicitly: files added or removed, revisions to existing values, periods or series added or removed, and changed headline statistics. Simultaneous changes appear together. Adding a counterfactual wage file can leave existing productivity, pay, and headline values unchanged. The overview and detailed comparisons use the same description. These descriptions compare snapshots; they do not indicate that fresh data was fetched or a release was published.

The report's Why section uses paired productivity and pay tables. It shows input contributions to the latest common quarter's index revision and average signed contributions across revised quarters, in index points. Three headline-growth tables use percentage points and include rounding and added or removed quarters when applicable. Zero effects stay visible; a dash marks an input outside an index's formula. The productivity-to-pay growth multiple is shown as previous → revised without a decomposition.

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

The [check workflow](.github/workflows/check.yml) runs on every PR and every push to `main`. It rebuilds offline and fails if `data_final/` or `data_outputs/` differs from the committed files. It posts the change report as a PR comment except on refresh PRs, which keep their authoritative report in the description. Post-merge reports compare with the commit before the push.

The refresh entry point is [update-refresh-pr.sh](.github/scripts/update-refresh-pr.sh), which calls [update-refresh-pr.py](.github/scripts/update-refresh-pr.py). The build job runs R and package code with read-only repository access. The publish job can write but runs no R or package code. It copies only allowlisted files from the build artifact using [copy-refresh-files.sh](.github/scripts/copy-refresh-files.sh). Keep that split. The calendar branch contains data only; never execute code from it.

The release workflow uses [release-plan.sh](.github/scripts/release-plan.sh) to choose the tag and apply release guards and [publish-release.sh](.github/scripts/publish-release.sh) to attach the final files from the checked commit and publish the release.
