## Load packages
source("./packages.R")

api_download_date = ymd("2025 September 3")
bea_key = Sys.getenv("BEA_API_KEY")
bls_key = Sys.getenv("BLS_API_KEY")
realtalk_version = "2025.8.12"
bls_end_year = 2025

## Load R sources
lapply(list.files("./R", full.names = TRUE), source)

## PRELIMINARY TESTS
stopifnot(packageVersion("realtalk") == realtalk_version)

tar_assign({
  ###############
  # INPUT FILES #
  ###############
  bls_hours_xlsx = tar_file("data_inputs/total-economy-hours-employment.xlsx")
  bls_early_wages_csv = tar_file("data_inputs/bls_EEU00500006.csv")
  bls_series_csv = tar_file("data_inputs/bls_series_codes.csv")
  bea_series_csv = tar_file("data_inputs/bea_series_codes.csv")

  data_documentation = document_data(
    bls_hours = bls_hours_xlsx,
    bls_early_wages = bls_early_wages_csv,
    bls_current_wages = bls_series_csv,
    bea_data = bea_series_csv,
    output_file = "release/epi_productivity_pay_gap_sources.csv"
  ) |>
    tar_file()

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
