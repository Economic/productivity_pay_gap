## Load packages
source("./packages.R")

## Load R sources
lapply(list.files("./R", full.names = TRUE), source)

tar_option_set(imports = "realtalk")

# TAR_PROJECT=offline (see _targets.yaml) rebuilds everything from the
# committed files in data_raw/ without network access. The default live mode
# fetches them again once they are more than a day old.
offline = Sys.getenv("TAR_PROJECT") == "offline"

##################
# FETCHED FILES  #
##################
fetched_files = if (offline) {
  tar_assign({
    bls_api_output = tar_file("data_raw/bls_api_output.csv")
    bea_api_output = tar_file("data_raw/bea_api_output.csv")
    bls_hours_xlsx = tar_file("data_raw/total-economy-hours-employment.xlsx")
    fetch_log = tar_file("data_raw/fetch_log.csv")
  })
} else {
  tar_assign({
    bls_api_output = bls_series_csv |>
      bls_grab_all() |>
      create_csv("data_raw/bls_api_output.csv") |>
      tar_age_date(format = "file")

    bea_api_output = bea_series_csv |>
      bea_grab_all() |>
      create_csv("data_raw/bea_api_output.csv") |>
      tar_age_date(format = "file")

    bls_hours_download = download_bls_hours(
      "data_raw/total-economy-hours-employment.xlsx"
    ) |>
      tar_age(age = as.difftime(1, units = "days"))

    bls_hours_xlsx = {
      bls_hours_download
      "data_raw/total-economy-hours-employment.xlsx"
    } |>
      tar_file()

    fetch_log = write_fetch_log(
      bls_api_date = bls_api_output_date,
      bea_api_date = bea_api_output_date,
      prices_date = prices_date,
      bls_hours_fetch = bls_hours_download,
      file = "data_raw/fetch_log.csv"
    ) |>
      tar_file()
  })
}

pipeline = tar_assign({
  ###############
  # INPUT FILES #
  ###############
  bls_early_wages_csv = tar_file("data_inputs/bls_EEU00500006.csv")
  bls_series_csv = tar_file("data_inputs/bls_series_codes.csv")
  bea_series_csv = tar_file("data_inputs/bea_series_codes.csv")
  renv_lock = tar_file("renv.lock")

  data_documentation = document_data(
    bls_hours = bls_hours_xlsx,
    bls_early_wages = bls_early_wages_csv,
    bls_current_wages = bls_series_csv,
    bea_data = bea_series_csv,
    fetch_log = fetch_log,
    output_file = "data_final/epi_productivity_pay_gap_sources.csv"
  ) |>
    tar_file()

  ########################
  # INTERMEDIATE OUTPUTS #
  ########################
  bls_pay = clean_bls_pay(bls_early_wages_csv, bls_api_output) |>
    create_csv("data_outputs/bls_pay.csv") |>
    tar_file()

  bls_hours = clean_hours_data(bls_hours_xlsx) |>
    create_csv("data_outputs/bls_hours.csv") |>
    tar_file()

  prices = make_prices() |>
    create_csv("data_outputs/prices.csv") |>
    tar_target_date(format = "file")

  ###############
  # FINAL FILES #
  ###############
  output = combine_data(
    bls_pay_csv = bls_pay,
    bls_hours_csv = bls_hours,
    bea_csv = bea_api_output,
    prices_csv = prices
  ) |>
    tar_target()

  output_data_csv = create_csv(
    output,
    "data_final/epi_productivity_pay_gap.csv"
  ) |>
    tar_csv_read()

  output_web_data_csv = create_web_data_csv(
    output,
    "data_final/epi_productivity_pay_gap_web.csv"
  ) |>
    tar_csv_read()

  output_web_stats_csv = create_web_stats_csv(
    output_web_data_csv,
    "data_final/epi_productivity_pay_gap_web_stats.csv"
  ) |>
    tar_csv_read()

  output_web_counter_csv = create_web_counter_csv(
    output,
    "data_final/epi_productivity_pay_counter_web.csv"
  ) |>
    tar_csv_read()
  ##########
  # CHECKS #
  ##########
  output_checks = check_outputs(
    data = output,
    web_data = output_web_data_csv,
    web_stats = output_web_stats_csv,
    sources_csv = data_documentation
  ) |>
    tar_target()

  # installed packages can change without any tracked file changing
  package_check = check_packages(renv_lock, strict = offline) |>
    tar_target(cue = tar_cue(mode = "always"))

  #################
  # CHANGE REPORT #
  #################
  # Compares the files in the working tree with a git ref: origin/main, or
  # PPG_BASELINE. Always rerun, since the ref can move. The unnamed arguments
  # only make it run after the final files and the checks.
  change_report = write_change_report(
    baseline = Sys.getenv("PPG_BASELINE", "origin/main"),
    packages_ok = package_check,
    file = "reports/change_report.md",
    output_checks,
    output_data_csv_file,
    output_web_data_csv_file,
    output_web_stats_csv_file,
    data_documentation,
    bls_pay,
    bls_hours,
    prices,
    fetch_log
  ) |>
    tar_file(cue = tar_cue(mode = "always"))
})

c(fetched_files, pipeline)
