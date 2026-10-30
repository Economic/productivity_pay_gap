# EPI Productivity-Pay Gap data

This repository produces the data for the [EPI Productivity-Pay Gap](https://www.epi.org/productivity-pay-gap/) page, which also explains the methodology.

## Download the data

You can download the data from

* the [EPI Productivity-Pay Gap](https://www.epi.org/productivity-pay-gap/) page
* the [State of Working America Data Library](https://data.epi.org/productivity/productivity_growth/line/year/national/real_index_1948/productivity_pay)
* the [latest release](https://github.com/Economic/productivity_pay_gap/releases/latest) of this repository

Official data comes from the [GitHub releases](https://github.com/Economic/productivity_pay_gap/releases). Each release has the five final files and a change report explaining what changed since the previous release, and why. The files on `main` may include updates that haven't been released yet.

## Output

### Final files (`data_final/`)

* `epi_productivity_pay_gap.csv`: all series, annual and quarterly, in long format
* `epi_productivity_pay_gap_web.csv`: quarterly real pay and productivity indexed to 1948q1 = 100, in wide format and rounded to one decimal place, for the web page
* `epi_productivity_pay_gap_web_stats.csv`: summary statistics for the web page
* `epi_productivity_pay_counter_web.csv`: quarterly real actual wage and the wage had it grown with productivity since 1979q4, from 1979q4, rounded to two decimal places, for the web page
* `epi_productivity_pay_gap_sources.csv`: underlying data sources, with access and publication dates

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

## Maintenance

See [MAINTAINING.md](MAINTAINING.md) for setup, offline reproduction, live data refreshes, change reports, development, and releases.
