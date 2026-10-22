# AGENTS.md

Guidance for coding agents working in this repository.

## Working here

- **Plans:** the newest dated file in `plans/` is the current plan, with next steps. Its "Decisions made" and "Resolved questions" sections are settled: don't reopen them without a new argument. New plans go in `plans/YEAR-MM-DD-short-description.md`.
- **Changes:** make each change on a branch and open a pull request. `main` is protected, so direct pushes are rejected. The maintainer merges, with merge commits only (`gh pr merge N --merge`). Ask them when a PR is ready.
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
- **`R/web.R`**: Formats final outputs for web (`create_web_data_csv`, `create_web_stats_csv`)
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
- **Changing a calculation on purpose:** the report's expectations of how the indexes, web data and web stats are computed are in `R/report_why.R` (`index_terms`, `expected_published_stat()`, `expected_published_ratio()`, `web_data_mismatches()`). If you change `R/combine.R`, `R/prices.R` or `R/web.R` on purpose, update them in the same PR, or later reports will keep flagging a method change.

## Packages

Key non-standard packages:

- `epidatatools`: EPI's wrapper for BLS and BEA APIs (`get_bls()`, `get_bea_nipa()`)
- `epitargets`: EPI's targets helpers: `create_csv()` (writes a data frame, returns the file path), `tar_age_date()` and `tar_target_date()` (add a `<name>_date` target recording the build date), and `tar_csv_read()`
- `realtalk`: EPI's package providing Extended Chained CPI-U; see https://economic.github.io/realtalk/
- `tarchetypes`: Provides `tar_file()`, `tar_age()` and `tar_assign()`

Package versions are locked via `renv`. Run `renv::restore()` to install from `renv.lock`. `.Rprofile` sets repos to economic.r-universe.dev and Posit Package Manager.
