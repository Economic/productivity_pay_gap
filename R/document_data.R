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
    access_method = "manual download",
    data_location = bls_hours
  )

  bls_early_wages_doc = tibble(
    name = "CES production average hourly earnings, private-sector, not seasonally adjusted",
    date_accessed = ymd("2025 May 15"),
    source = "BLS Current Employment Statistics, series EEU00500006",
    source_url = "https://data.bls.gov/series-report",
    access_method = "manual_download",
    data_location = bls_early_wages
  )

  bls_current_sa = tibble(
    name = "CES production and nonsupervisory average hourly earnings, private-sector, seasonally adjusted",
    source = "BLS Current Employment Statistics, series CES0500000008"
  )

  bls_current_nsa = tibble(
    name = "CES production and nonsupervisory average hourly earnings, private-sector, not seasonally adjusted",
    source = "BLS Current Employment Statistics, series CEU0500000008"
  )

  bls_current_wages_doc = bls_current_sa |>
    bind_rows(bls_current_nsa) |>
    mutate(
      source_url = "https://www.bls.gov/developers/home.htm",
      access_method = "BLS API",
      data_location = bls_current_wages,
      date_accessed = api_download_date
    )

  bind_rows(
    bls_hours_doc,
    bls_current_wages_doc,
    bls_early_wages_doc
  ) |>
    create_csv(output_file)
}

# document_bea_data = function(bea_series_csv) {
#   # # BEA series inputs for API call
#   # bea_series_csv = tar_file("data_inputs/bea_series_codes.csv")
# }
