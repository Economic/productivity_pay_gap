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

- **`_targets.R`**: Defines the full pipeline DAG using `tar_assign()`
- **`packages.R`**: All package loading with conflict resolution via `conflicted`
- **`R/bls.R`**: BLS API fetching (`bls_grab_all`) and wage series construction (`clean_bls_pay`, `clean_hours_data`)
- **`R/bea.R`**: BEA NIPA API fetching (`bea_grab_all`, `bea_grab_series`)
- **`R/prices.R`**: Extracts Extended Chained CPI-U from the `realtalk` package
- **`R/combine.R`**: Merges all sources, calculates productivity and real compensation, creates 1948q1=100 indices
- **`R/web.R`**: Formats final outputs for web (`create_web_data_csv`, `create_web_stats_csv`)
- **`R/document_data.R`**: Generates `epi_productivity_pay_gap_sources.csv` tracking data provenance

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
| `release/epi_productivity_pay_gap.csv` | All series, long format, annual + quarterly |
| `release/epi_productivity_pay_gap_web.csv` | Quarterly only, wide format, rounded to 1 decimal |
| `release/epi_productivity_pay_gap_web_stats.csv` | Key statistics for website display |
| `release/epi_productivity_pay_gap_sources.csv` | Data provenance documentation |

Intermediate files (API results, cleaned hours, spliced wages, prices) are written to `data_outputs/`. Both `release/` and `data_outputs/` are committed to git, as is `_targets/meta/meta`.

## Data Inputs

Files in `data_inputs/`:

- `total-economy-hours-employment.xlsx`: BLS total economy hours. Download manually from BLS for each release
- `bls_hours_dates.csv`: access and publication dates for the hours file, used in the sources CSV. Update whenever the hours file changes
- `bls_EEU00500006.csv`: historical production worker wages (pre-1964). Static; no updates needed
- `bls_series_codes.csv` / `bea_series_codes.csv`: API series configurations

## Running the Pipeline

- `BLS_API_KEY` and `BEA_API_KEY` must be set; `epidatatools` reads them.
- `bls_api_output` and `bea_api_output` use `tar_age_date()` with a 1-day age, so `tar_make()` downloads new API data whenever the cached pulls are more than a day old. That changes the release numbers.
- To rebuild a single target without refreshing the API data, use `tar_make(names = c(...), shortcut = TRUE)`.

## Packages

Key non-standard packages:

- `epidatatools`: EPI's wrapper for BLS and BEA APIs (`get_bls()`, `get_bea_nipa()`)
- `epitargets`: EPI's targets helpers: `create_csv()` (writes a data frame, returns the file path), `tar_age_date()`, `tar_target_date()`, `collect_target_date()`, `tar_csv_read()`
- `realtalk`: EPI's package providing Extended Chained CPI-U; see https://economic.github.io/realtalk/
- `tarchetypes`: Provides `tar_file()` and `tar_assign()`

Package versions are locked via `renv`. Run `renv::restore()` to install from `renv.lock`. `.Rprofile` sets repos to economic.r-universe.dev and Posit Package Manager.
