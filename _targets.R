## Load your packages, e.g. library(targets).
source("./packages.R")

api_download_date = ymd("2025 Apr 5")
bea_key = Sys.getenv("BEA_API_KEY")
bls_key = Sys.getenv("BLS_API_KEY")
realtalk_version = "0.21.0"
bls_end_year = 2025

## Load your R files
lapply(list.files("./R", full.names = TRUE), source)

## PRELIMINARY TESTS
stopifnot(packageVersion("realtalk") == realtalk_version)

tar_assign({
  ###############
  # INPUT FILES #
  ###############
  # BLS total economy hours
  # https://www.bls.gov/productivity/tables/home.htm
  # https://www.bls.gov/productivity/tables/total-economy-hours-employment.xlsx
  bls_hours_xlsx = tar_file("data_inputs/total-economy-hours-employment.xlsx")

  # BLS early production workers wages: series EEU00500006
  # downloaded via https://data.bls.gov/series-report
  bls_early_wages_csv = tar_file("data_inputs/bls_EEU00500006.csv")

  # BLS series inputs for API call
  bls_series_csv = tar_file("data_inputs/bls_series_codes.csv")

  # BEA series inputs for API call
  bea_series_csv = tar_file("data_inputs/bea_series_codes.csv")

  #######################
  # INTERMEDIATE OUTPUS #
  #######################
  bls_api_output = bls_series_csv |>
    bls_grab_all(bls_end_year, api_download_date) |>
    create_csv("data_outputs/bls_api_output.csv") |>
    tar_file()

  bls_pay = clean_bls_pay(bls_early_wages_csv, bls_api_output) |>
    create_csv("data_outputs/bls_pay.csv") |>
    tar_file()

  bls_hours = clean_hours_data(bls_hours_xlsx) |>
    create_csv("data_outputs/bls_hours.csv") |>
    tar_file()

  bea_api_output = bea_series_csv |>
    bea_grab_all(api_download_date) |>
    create_csv("data_outputs/bea_api_output.csv") |>
    tar_file()

  prices = make_prices(realtalk_version) |>
    create_csv("data_outputs/prices.csv") |>
    tar_file()

  #################
  # FINAL RELEASE #
  #################
  output = combine_data(
    bls_pay_csv = bls_pay,
    bls_hours_csv = bls_hours,
    bea_csv = bea_api_output,
    prices_csv = prices
  ) |>
    tar_target()

  output_data_csv = create_csv(
    output,
    "release/epi_productivity_pay_gap.csv"
  ) |>
    tar_file()

  output_web_data_csv = create_web_data_csv(
    output,
    "release/epi_productivity_pay_gap_web.csv"
  ) |>
    tar_file()

  output_web_stats_csv = create_web_stats_csv(
    output_web_data_csv,
    "release/epi_productivity_pay_gap_web_stats.csv"
  ) |>
    tar_file()
})
