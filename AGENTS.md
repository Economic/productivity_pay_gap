# AGENTS.md

Guidance for coding agents working in this repository.

## Working here

- **Overview:** [README.md](README.md) documents downloads, output files, methodology, and sources. [MAINTAINING.md](MAINTAINING.md) is the full maintenance reference. Read the relevant sections before changing pipeline or automation behavior.
- **Plans:** the newest dated file in `plans/` is the current plan, with next steps. Its "Decisions made" and "Resolved questions" sections are settled: don't reopen them without a new argument. New plans go in `plans/YEAR-MM-DD-short-description.md`.
- **Changes:** make each change on a branch and open a pull request. `main` is protected, so direct pushes are rejected. The maintainer merges, with merge commits only (`gh pr merge N --merge`). Ask them when a PR is ready.
- **CI check:** follow [Making changes](MAINTAINING.md#making-changes). If code changes outputs, rebuild offline (`TAR_PROJECT=offline`) and commit the changed `data_final/` and `data_outputs/` files in the same PR. CI checks reproducibility.
- **Releases:** publishing is a manual maintainer action. Never run the release workflow without being asked. See [How updates work](MAINTAINING.md#how-updates-work) and [Workflow implementation](MAINTAINING.md#workflow-implementation).
- **Data refresh:** see [How updates work](MAINTAINING.md#how-updates-work), [Maintainer setup](MAINTAINING.md#maintainer-setup), and [The change report](MAINTAINING.md#the-change-report). Keep package execution in the read-only build job and the publish job free of R and package code. Copy only allowlisted artifact files. Never execute code from the calendar branch.
- **Commits:** commit early and often. Give each self-contained change its own commit; small commits get faster, more focused reviews.
- **Live data:** a live `tar_make()` calls the BLS and BEA APIs and changes committed data. Do not run one without a reason. Use [Offline mode](MAINTAINING.md#offline-mode) for reproducibility checks.

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
- `fetch_log.csv`: when each source was last fetched, and the status of the last attempt. A failed fetch keeps the date of the last successful one. See [Making changes](MAINTAINING.md#making-changes) for a manual spreadsheet replacement.

## Running the pipeline

See [Reproduce the data](MAINTAINING.md#reproduce-the-data) for setup, live and offline runs, and change report baselines. For intentional calculation changes, follow [Making changes](MAINTAINING.md#making-changes), including updating the report’s `index_terms` when the index formula changes.

## Packages

Key non-standard packages:

- `epidatatools`: EPI's wrapper for BLS and BEA APIs (`get_bls()`, `get_bea_nipa()`)
- `epitargets`: EPI's targets helpers: `create_csv()` (writes a data frame, returns the file path), `tar_age_date()` and `tar_target_date()` (add a `<name>_date` target recording the build date), and `tar_csv_read()`
- `realtalk`: EPI's package providing Extended Chained CPI-U; see https://economic.github.io/realtalk/
- `tarchetypes`: Provides `tar_file()`, `tar_age()` and `tar_assign()`

See [Setup](MAINTAINING.md#setup) for the locked package environment.
