# AGENTS.md

Guidance for coding agents working in this repository.

## Working here

- **Overview:** README's "How updates work" describes the release-day refresh, merge and release cycle, and "Maintainer setup" lists the GitHub settings it depends on, such as secrets, notification email, and the `main` ruleset.
- **Plans:** the newest dated file in `plans/` is the current plan, with next steps. Its "Decisions made" and "Resolved questions" sections are settled: don't reopen them without a new argument. New plans go in `plans/YEAR-MM-DD-short-description.md`.
- **Changes:** make each change on a branch and open a pull request. `main` is protected, so direct pushes are rejected. The maintainer merges, with merge commits only (`gh pr merge N --merge`). Ask them when a PR is ready.
- **CI check:** `.github/workflows/check.yml` runs on every PR and every push to `main`. It rebuilds offline and fails if anything in `data_final/` or `data_outputs/` differs from the committed files. So when code changes the outputs, rebuild offline (`TAR_PROJECT=offline`) and commit the result in the same PR. It also posts the change report as a PR comment, except on refresh PRs, which carry the refresh workflow's report. PR and refresh reports compare with both `main` and the last published release, including when the PR introduces no data changes. Post-merge checks compare with the commit before the push.
- **Releases:** `.github/workflows/release.yml` is a manual button, run by the maintainer; never run it without being asked. It publishes the final files of the commit it starts from as a dated GitHub release (`vYYYY.M.D`), after the offline check passes on that commit, with the change report against the previous release as notes. It refuses a release when nothing but access dates changed, and a second release the same day unless it's marked as a correction with a reason. A dry run checks everything and creates nothing. Logic: `.github/scripts/release-plan.sh` and `publish-release.sh`.
- **Data refresh:** `.github/workflows/calendar-refresh.yml` saves BLS and BEA release dates on the separate `calendar` branch every Monday at 5:17 a.m. Eastern. `.github/workflows/scheduled-data-update.yml` reads them daily at 2:27 p.m. Eastern and calls `.github/workflows/refresh.yml` on release days and the following calendar day, including weekends. Overlaps produce one scheduled build per date. The five releases are Employment Situation, Productivity and Costs, Consumer Price Index, GDP, and Personal Income and Outlays. Calendar refresh retains yesterday for pending follow-ups. Failed calendar refreshes keep the previous schedule; missing, invalid, or exhausted schedules fail visibly. Bootstrap the calendar after merge as described in README. `refresh.yml` also runs on demand. It updates every package, fetches fresh data, and, if the web files changed, opens or updates the PR from the `data-refresh` branch, assigned to the maintainer. For an existing PR, meaningful input, package, calculation code, or output changes update the branch and report, even when web numbers match. New main or release baselines also refresh the proposal. Access dates alone update only the title and top check status, retaining the report for the committed files. The description starts with the latest check, changes since the previous proposal, pending changes against main, output coverage, and the next scheduled data update with its reasons. The next update also appears in the workflow run summary, including dry runs and builds with no web changes. It uses the saved calendar and Eastern time, joins overlapping reasons with “and”, and updates on each check even when the detailed report stays unchanged. An unavailable calendar is reported without blocking manual refreshes. Directly below the next update, Expected latest output quarter estimates combined coverage from the earliest required input quarter, projecting affected inputs through the previous completed quarter for saved releases due by that build under normal timing. Unchanged coverage says no new quarter expected. All estimates are subject to source availability. Missing coverage shows unavailable. The forecast never controls the build or schedule. It holds the only full report, with its own update time. Older bot report comments become short superseded notices. Only changed web files against the existing proposal get a new notification comment. No PR is opened for inputs alone when web files match main; an existing PR is closed when the latest build's web files match main. The entry point is `.github/scripts/update-refresh-pr.sh`; its trusted Python helper runs in the publish job. It never publishes a release. A manual run with `dry_run` builds and reports without touching the PR. GitHub holds the check on the bot's PR until a maintainer approves it. To merge, approve the held run, then merge once it passes. The build job runs package code with read-only access. The publish job can write but runs no R, and copies in only allowlisted files from the build's artifact (`.github/scripts/copy-refresh-files.sh`); keep it that way.
- **Commits:** commit early and often. Give each self-contained change its own commit; small commits get faster, more focused reviews.
- **Live data:** a live `tar_make()` calls the BLS and BEA APIs and changes the committed data (see "Running the Pipeline"). Don't run one without a reason.

## Reviews (roborev)

- A post-commit hook sends every commit to one code reviewer automatically. See the results with `roborev list` and `roborev show <job>`.
- At the end of each plan phase, run `roborev review --branch --base main --panel checkpoint_panel --wait`. That panel covers code, design and security.
- `.roborev.toml` tells reviewers what matters here: wrong published numbers, calculation changes nobody declared, and the security of the GitHub workflows. Fix real findings. For a finding that needs several unusual conditions at once, record it as an accepted risk in the current plan's "Risks" section rather than adding code. Then close the job with `roborev comment <job> "..."` and `roborev close <job>`.

## Style

- **Prose:** short sentences, and no em dashes.
- **R:** tidyverse style, the base pipe `|>`, and `=` for assignment.

## Project Overview

This repository produces data for the [EPI Productivity-Pay Gap](https://www.epi.org/productivity-pay-gap/) page, tracking the historical divergence between U.S. productivity growth and worker compensation (1948–present). Output is published to the EPI website and State of Working America Data Library.

### Key Files

- **`_targets.R`**: Defines the full pipeline DAG using `tar_assign()`, with live and offline versions of the fetch targets
- **`_targets.yaml`**: The `main` (live) and `offline` targets projects and their stores
- **`packages.R`**: All package loading with conflict resolution via `conflicted`
- **`R/bls.R`**: BLS API fetching (`bls_grab_all`), the hours spreadsheet download (`download_bls_hours`, `read_bls_hours_release_date`), and wage series construction (`clean_bls_pay`, `clean_hours_data`)
- **`R/bea.R`**: BEA NIPA API fetching (`bea_grab_all`, `bea_grab_series`)
- **`R/prices.R`**: Extracts Extended Chained CPI-U from the `realtalk` package
- **`R/combine.R`**: Merges all sources, calculates productivity and real compensation, creates 1948q1=100 indices
- **`R/web.R`**: Formats final outputs for web (`create_web_data_csv`, `create_web_counter_csv`, `create_web_stats_csv`)
- **`R/document_data.R`**: Generates `epi_productivity_pay_gap_sources.csv` tracking data provenance, and reads and writes the fetch log
- **`R/checks.R`**: Sanity checks on the final files and on installed packages; a failure stops the pipeline
- **`R/report_snapshot.R`**: Reads the committed files at a git ref or in the working tree, for the change report. Releases through v2026.9.14 use the pre-Phase 1 paths
- **`R/report_why.R`**: The exact split of each revision into input contributions, including the headline stats
- **`R/report.R`**: Builds `reports/change_report.md`

### Core Calculations (in `R/combine.R`)

- **Productivity** = NIPA NDP (table 1.7.5, line 30) / BLS total economy hours
- **Compensation ratio** = NIPA total compensation (table 2.1, line 2) / NIPA wages (table 2.1, line 3)
- **Private-sector compensation** = BLS production/nonsupervisory wages × compensation ratio
- **Real values**: deflated by Extended Chained CPI-U (from `realtalk` package)
- **Indices**: all series indexed to 1948q1 = 100
- **Counterfactual wage** = real compensation per unit of real productivity in 1979q4 (1979 for annual data) × real productivity / compensation ratio. It and the actual real wage start at that base

### Wage Series Construction (`R/bls.R`)

The BLS hourly wage series splices two sources:

- **Pre-1964**: Series EEU00500006 (historical production workers, annual, from `data_inputs/bls_EEU00500006.csv`)
- **1964–present**: Series CES0500000008 (seasonally adjusted, for quarterly data) and CEU0500000008 (not seasonally adjusted, for annual data), via BLS API

The early series is ratio-adjusted at the 1964 crossover. Pre-1964 annual values are assigned to Q3, and the missing quarters are interpolated with `zoo::na.approx()`.

## Output Files

| File | Description |
|------|-------------|
| `data_final/epi_productivity_pay_gap.csv` | All series, long format, annual + quarterly |
| `data_final/epi_productivity_pay_gap_web.csv` | Quarterly only, wide format, rounded to 1 decimal |
| `data_final/epi_productivity_pay_gap_web_stats.csv` | Key statistics for website display |
| `data_final/epi_productivity_pay_counter_web.csv` | Quarterly real actual wage and counterfactual wage (grown with productivity since 1979q4), from 1979q4, rounded to 2 decimals |
| `data_final/epi_productivity_pay_gap_sources.csv` | Data provenance documentation |

On `main`, `data_final/` can be ahead of the latest GitHub release. Intermediate files (cleaned hours, spliced wages, prices) are written to `data_outputs/`. Everything in `data_raw/`, `data_outputs/` and `data_final/` is committed to git. The targets stores (`_targets/`, `_targets_offline/`) are not.

## Data Inputs

Files in `data_inputs/`, which change only by hand:

- `bls_EEU00500006.csv`: historical production worker wages (pre-1964). Static; no updates needed
- `bls_series_codes.csv` / `bea_series_codes.csv`: API series configurations

Files in `data_raw/`, fetched from outside by the live pipeline:

- `bls_api_output.csv` / `bea_api_output.csv`: BLS and BEA API results
- `total-economy-hours-employment.xlsx`: BLS total economy hours. Its release date is read from the ReadMe sheet
- `fetch_log.csv`: when each source was last fetched, and the status of the last attempt. A failed fetch keeps the date of the last successful one. If you ever commit the hours spreadsheet by hand, update its `date_accessed` here too.

## Running the Pipeline

- **Live (default):** `tar_make()` fetches the BLS and BEA API data and downloads the hours spreadsheet whenever they are more than a day old. That changes the committed data. It needs `BLS_API_KEY` and `BEA_API_KEY` (read by `epidatatools`) and `BLS_DOWNLOAD_EMAIL` (sent to BLS in the `User-Agent` header). If the hours download fails, the committed spreadsheet is kept and the fetch log records why.
- **Offline:** `TAR_PROJECT=offline` with `tar_make()` rebuilds everything from the committed files in `data_raw/`, in its own store, with no network access or credentials. Use it to check that the committed outputs are reproducible: afterward, `git diff -- data_final data_outputs` should be empty. In R: `Sys.setenv(TAR_PROJECT = "offline"); targets::tar_make()`.
- The sanity checks (`output_checks`, `package_check`) run in both modes. `package_check` is an error offline and a warning in live mode.
- **Change report:** every `tar_make()` ends by writing `reports/change_report.md` (git ignores `reports/`). It compares the working tree with `origin/main`, so run `git fetch` first; set `PPG_BASELINE` to compare with another ref. It explains each revision exactly by input. If the inputs don't explain a revision, it says the calculation itself changed. Baselines must be v2026.3.11 or later; older releases store the BLS API results in a format the report doesn't read.
- **Two report baselines:** data refreshes and PR checks also set `PPG_RELEASE_BASELINE` to the last published GitHub release tag. That adds an overview and a separate full comparison with the release. The R pipeline never queries GitHub. Release notes and local defaults keep a single comparison.
- **Changing a calculation on purpose:** `index_terms` in `R/report_why.R` encodes how `R/combine.R` builds the indexes from their inputs. If you change that on purpose, update `index_terms` in the same PR, or later reports will keep flagging a method change. Changes to `R/bls.R`, `R/bea.R`, `R/prices.R`, `R/web.R` and the series code files aren't measured: the report names them in a warning.

## Packages

Key non-standard packages:

- `epidatatools`: EPI's wrapper for BLS and BEA APIs (`get_bls()`, `get_bea_nipa()`)
- `epitargets`: EPI's targets helpers: `create_csv()` (writes a data frame, returns the file path), `tar_age_date()` and `tar_target_date()` (add a `<name>_date` target recording the build date), and `tar_csv_read()`
- `realtalk`: EPI's package providing Extended Chained CPI-U; see https://economic.github.io/realtalk/
- `tarchetypes`: Provides `tar_file()`, `tar_age()` and `tar_assign()`

Package versions are locked via `renv`. Run `renv::restore()` to install from `renv.lock`. `.Rprofile` sets repos to economic.r-universe.dev and Posit Package Manager.
