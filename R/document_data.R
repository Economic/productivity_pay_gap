document_data = function(
  bls_hours,
  bls_early_wages,
  bls_current_wages,
  bea_data,
  output_file
) {
  bls_hours_doc = tibble(
    name = "BLS total economy hours",
    date_accessed = ymd("2025 May 15"),
    date_published = ymd("2025 May 8"),
    source = "BLS Office of Productivity and Technology",
    source_url = "https://www.bls.gov/productivity/tables/home.htm",
    source_url_2 = "https://www.bls.gov/productivity/tables/total-economy-hours-employment.xlsx",
    data_location = bls_hours
  )

  bls_current_wages_doc = tibble(
    name = "CES production and nonsupervisory average hourly earnings, private-sector",
    source = "BLS Current Employment Statistics",
    source_url = "https://www.bls.gov/developers/home.htm"
  ) |>
    mutate(date_accessed = api_download_date)

  bind_rows(
    bls_hours_doc,
    bls_current_wages_doc,
  ) |>
    create_csv(output_file)
}

# bls_hours_doc = document_bls_hours(bls_hours_xlsx) |>
#     tar_target()
#   bls_wages_doc = document_bls_wages(
#     early = bls_early_wages_csv,
#     current = bls_series_csv
#   ) |>
#     tar_target()
#   bea_data_doc = document_bea_data(bea_series_csv) |>
#     tar_target()

# document_bls_hours = function(bls_hours_xlsx) {

# }

# document_bls_wages = function(early, current) {
#   # BLS early production workers wages: series EEU00500006
#   # downloaded via https://data.bls.gov/series-report
#   # bls_early_wages_csv = tar_file("data_inputs/bls_EEU00500006.csv")
#   # # BLS series inputs for API call
#   # bls_series_csv = tar_file("data_inputs/bls_series_codes.csv")
# }

# document_bea_data = function(bea_series_csv) {
#   # # BEA series inputs for API call
#   # bea_series_csv = tar_file("data_inputs/bea_series_codes.csv")
# }
