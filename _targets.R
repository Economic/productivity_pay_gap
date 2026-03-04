## Load packages
source("./packages.R")

## Load R sources
lapply(list.files("./R", full.names = TRUE), source)

tar_option_set(imports = "realtalk")

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
    source_dates = source_dates,
    output_file = "release/epi_productivity_pay_gap_sources.csv"
  ) |>
    tar_file()

  #######################
  # INTERMEDIATE OUTPUS #
  #######################
  bls_api_output = bls_series_csv |>
    bls_grab_all() |>
    create_csv("data_outputs/bls_api_output.csv") |>
    tar_age_date(format = "file")

  bls_pay = clean_bls_pay(bls_early_wages_csv, bls_api_output) |>
    create_csv("data_outputs/bls_pay.csv") |>
    tar_file()

  bls_hours = clean_hours_data(bls_hours_xlsx) |>
    create_csv("data_outputs/bls_hours.csv") |>
    tar_file()

  bea_api_output = bea_series_csv |>
    bea_grab_all() |>
    create_csv("data_outputs/bea_api_output.csv") |>
    tar_age_date(format = "file")

  prices = make_prices() |>
    create_csv("data_outputs/prices.csv") |>
    tar_target_date(format = "file")

  source_dates = collect_target_date(
    bls_api_output_date,
    bea_api_output_date,
    prices_date
  ) |>
    tar_target()

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
