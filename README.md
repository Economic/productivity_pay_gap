# README

This repository produces the data for the [EPI Productivity-Pay Gap](<https://www.epi.org/productivity-pay-gap/>) page, which also explains the methodology and provides a link to download the data.

The productivity-pay gap data is also available on the [State of Working America Data Library](<https://data.epi.org>).

You can use this repository to reproduce the data from scratch.

## Development environment

### Packages

You will need R and all of the packages in `packages.R`
- Some package versions must match the versions specified in `_targets.R`
- In particular you should use the latest price indices in the [`realtalk`](https://economic.github.io/realtalk/) package.

### Environment variables

- `BLS_DOWNLOAD_EMAIL` email valid for BLS downloads
- BLS and BEA API keys set, respectively, in `BLS_API_KEY`and `BEA_API_KEY`.

## Reproducing and deploying the data

- Set the `api_download_date` variable to the current date.

- `tar_make()`: will produce all of the data in 3 .csv files
    - `epi_productivity_pay_gap.csv` : all series, long format
    - `epi_productivity_pay_gap_web.csv` : web ready, pay and productivity series indexed to 1948q1
    - `epi_productivity_pay_gap_web_stats.csv` : relevant statistics for website

## Output

### Intermediate

- `bea_api_output.csv`: API results from BEA
- `bls_api_output.csv`: API results from BLS
- `bls_hours.csv`: CSV version of BLS total economy hours
- `bls_pay.csv`: combined BLS early and later wage series
- `prices.csv`: price indices

### Release

- `epi_productivity_pay_gap.csv`: all annual and quarterly data in long format
- `epi_productivity_pay_gap_web.csv`: EPI Productivity-Pay Gap web page ready data in wide format, rounded to one decimal place
- `epi_productivity_pay_gap_web_stats.csv`: miscellanous stats based on web-ready data

## Sources

### Productivity

- Total hours ([BLS](https://www.bls.gov/productivity/tables/home.htm))
- Net domestic product (Bureau of Economic Analysis, NIPA table 1.7.5, via BEA API)

### Pay

- Average hourly wages for production/nonsupervisory workers (Bureau of Labor Statistics, Current Employment Statistics, series CES0500000008, CES0500000008, via BLS API)
- Average hourly wages for production workers (Bureau of Labor Statistics Current Employment Statistics, series EEU00500006, via BLS API)
- Total compensation (Bureau of Economic Analysis, NIPA table 2.1, line 2, via BEA API)
- Wages (Bureau of Economic Analysis, NIPA table 2.1, line 3, via BEA API)
     
