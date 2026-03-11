# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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
- **`R/helpers.R`**: `create_csv()` utility (writes a data frame, returns the file path for targets tracking)

### Core Calculations (in `R/combine.R`)

- **Productivity** = NIPA NDP (table 1.7.5, line 30) / BLS total economy hours
- **Compensation ratio** = NIPA total compensation (table 2.1, line 2) / NIPA wages (table 2.1, line 3)
- **Private-sector compensation** = BLS production/nonsupervisory wages × compensation ratio
- **Real values**: deflated by Extended Chained CPI-U (from `realtalk` package)
- **Indices**: all series indexed to 1948q1 = 100

### Wage Series Construction (`R/bls.R`)

The BLS hourly wage series splices two sources:
- **Pre-1964**: Series EEU00500006 (historical production workers, from `data_inputs/bls_EEU00500006.csv`)
- **1964–present**: Series CES0500000008 / CEU0500000008 (via BLS API)

The early series is ratio-adjusted at the 1964 crossover. Missing quarterly values are interpolated with `zoo::na.approx()`.

## Output Files

| File | Description |
|------|-------------|
| `release/epi_productivity_pay_gap.csv` | All series, long format, annual + quarterly |
| `release/epi_productivity_pay_gap_web.csv` | Quarterly only, wide format, rounded to 1 decimal |
| `release/epi_productivity_pay_gap_web_stats.csv` | Key statistics for website display |
| `release/epi_productivity_pay_gap_sources.csv` | Data provenance documentation |

## Data Inputs

Static files in `data_inputs/` that must be manually updated when new data is released:
- `total-economy-hours-employment.xlsx`: BLS total economy hours (from BLS productivity tables)
- `bls_EEU00500006.csv`: Historical production worker wages (pre-1964)
- `bls_series_codes.csv` / `bea_series_codes.csv`: API series configurations

## Packages

Key non-standard packages:
- `epidatatools`: EPI's internal wrapper for BLS and BEA APIs
- `realtalk`: EPI's package providing Extended Chained CPI-U; install from https://economic.github.io/realtalk/
- `tarchetypes`: Provides `tar_age()`, `tar_file()`, `tar_assign()`

Package versions are locked via `renv`. Run `renv::restore()` to install from `renv.lock`.
