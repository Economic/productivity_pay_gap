# README
This repository produces the data for the EPI Productivity-Pay Gap page, currently served at <https://www.epi.org/productivity-pay-gap/>. For details on methodology or to download the data, go there!

The productivity-pay gap data is also available on our Data Library, currently served at <https://www.epi.org/data/>.

You can use this repository to reproduce the data from scratch.

## Development environment

-   R and all of the packages in `packages.R`
    -   Some package versions must match the versions specified in `_targets.R`
-   You will need the latest [EPI price indices](https://economic.github.io/realtalk/) downloaded using [`realtalk`](install.packages('realtalk', repos = c('https://economic.r-universe.dev', 'https://cloud.r-project.org')))
-   Environment variables:
    - `BLS_DOWNLOAD_EMAIL` email valid for BLS downloads
    - BLS and BEA API keys set, respectively, in `BLS_API_KEY`and `BEA_API_KEY`.

## Reproducing and deploying the data

- `tar_make()`: will produce all of the data in 3 .csv files
    - epi_productivity_pay_gap.csv : all series, long format
    - epi_productivity_pay_gap_web.csv : web ready, pay and productivity series indexed to 1948q1
    - epi_productivity_pay_gap_web_stats.csv : relevant statistics for website

## Sources

- Productivity
    - Total hours (unpublished BLS series)
    - Net domestic product (Bureau of Economic Analysis, NIPA table 1.7.5)

- Pay
    - Average hourly wages for production/nonsupervisory workers (Bureau of Labor Statistics, Current Employment Statistics, series CES0500000008)
    - Total compensation (Bureau of Economic Analysis, NIPA table 2.1, line 2)
    - Wages (Bureau of Economic Analysis, NIPA table 2.1, line 3)
     
