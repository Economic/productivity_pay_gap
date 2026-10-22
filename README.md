# EPI Productivity-Pay Gap data

This repository produces the data for the [EPI Productivity-Pay Gap](https://www.epi.org/productivity-pay-gap/) page, which also explains the methodology.

## Download the latest data

You can download the data from

* the [EPI Productivity-Pay Gap](https://www.epi.org/productivity-pay-gap/) page
* the [State of Working America Data Library](https://data.epi.org/productivity/productivity_growth/line/year/national/real_index_1948/productivity_pay)
* the [latest release files](https://github.com/Economic/productivity_pay_gap/releases/latest) from this repository

## Reproduce the data

### Setup

Package versions are locked with [renv](https://rstudio.github.io/renv/). To install them, run this from the project directory:

```r
renv::restore()
```

Along with CRAN packages, this installs three EPI packages:

* [`epidatatools`](https://github.com/Economic/epidatatools): BLS and BEA API wrappers
* `epitargets`: helpers for the `targets` pipeline
* [`realtalk`](https://economic.github.io/realtalk/): price indices

Set these environment variables, for example in `~/.Renviron`:

* `BLS_API_KEY` ([register](https://data.bls.gov/registrationEngine/))
* `BEA_API_KEY` ([register](https://apps.bea.gov/API/signup/))
* `BLS_DOWNLOAD_EMAIL`: your email address. BLS refuses downloads of the hours spreadsheet unless the request includes a contact email.

### Generate the data

Run `targets::tar_make()`. It fetches the BLS and BEA data from their APIs, downloads the BLS hours spreadsheet, and writes the fetched files to `data_raw/`, intermediate files to `data_outputs/`, and the final files to `data_final/`.

Fetched data is cached for one day. If you run `tar_make()` again within a day, it reuses the cached data; after that, it fetches the data again. If the hours download fails, the pipeline keeps the committed spreadsheet, and `data_raw/fetch_log.csv` records why.

To rebuild everything from the committed files without fetching anything, use offline mode:

```r
Sys.setenv(TAR_PROJECT = "offline")
targets::tar_make()
```

If the committed outputs are reproducible, `git diff -- data_final data_outputs` is then empty.

### Update the data for a new release

1. Update `realtalk` to get the latest price indices, and record the new version in `renv.lock`:

   ```r
   renv::update("realtalk")
   renv::snapshot()
   ```

2. Run `targets::tar_make()`.

If BLS refuses the hours download, download the [total economy hours file](https://www.bls.gov/productivity/tables/total-economy-hours-employment.xlsx) by hand, save it as `data_raw/total-economy-hours-employment.xlsx`, and set its `date_accessed` in `data_raw/fetch_log.csv` to the day you downloaded it.

Official data comes from the [GitHub releases](https://github.com/Economic/productivity_pay_gap/releases). The files on `main` may include updates that haven't been released yet.

## Output

### Final files (`data_final/`)

* `epi_productivity_pay_gap.csv`: all series, annual and quarterly, in long format
* `epi_productivity_pay_gap_web.csv`: quarterly real pay and productivity indexed to 1948q1 = 100, in wide format and rounded to one decimal place, for the web page
* `epi_productivity_pay_gap_web_stats.csv`: summary statistics for the web page
* `epi_productivity_pay_gap_sources.csv`: underlying data sources, with access and publication dates

### Fetched files (`data_raw/`)

* `bea_api_output.csv`: BEA API results
* `bls_api_output.csv`: BLS API results
* `total-economy-hours-employment.xlsx`: BLS total economy hours spreadsheet
* `fetch_log.csv`: when each source was last fetched, and the status of the last attempt

### Intermediate files (`data_outputs/`)

* `bls_hours.csv`: BLS total economy hours
* `bls_pay.csv`: early and current BLS wage series, combined
* `prices.csv`: price index

## Methodology

* **Productivity** is net domestic product divided by total economy hours worked.
* **Pay** is the average hourly compensation of private-sector production and nonsupervisory workers. It equals their average hourly wages multiplied by the economy-wide ratio of total compensation to wages.
* Both series are deflated by the Extended Chained CPI-U and indexed to 1948q1 = 100.

## Underlying data sources

### Productivity

* Net domestic product: BEA, NIPA table 1.7.5, line 30 (BEA API)
* Total economy hours worked: [BLS Office of Productivity and Technology](https://www.bls.gov/productivity/tables/home.htm) (downloaded to `data_raw/total-economy-hours-employment.xlsx`)

### Pay

* Average hourly earnings of production and nonsupervisory employees, private sector, 1964 to present: BLS Current Employment Statistics, series CES0500000008 (seasonally adjusted, used for quarterly data) and CEU0500000008 (not seasonally adjusted, used for annual data) (BLS API)
* Average hourly earnings of production workers, private sector, before 1964: BLS Current Employment Statistics, series EEU00500006 (static file `data_inputs/bls_EEU00500006.csv`). This annual series is rescaled to match the current series in 1964, and quarterly values before 1964 are interpolated.
* Compensation of employees: BEA, NIPA table 2.1, line 2 (BEA API)
* Wages and salaries: BEA, NIPA table 2.1, line 3 (BEA API)

### Prices

* Extended Chained CPI-U: [`realtalk`](https://economic.github.io/realtalk/) package
