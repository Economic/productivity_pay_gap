document_data = function(
  bls_hours,
  bls_early_wages,
  bls_current_wages,
  bea_data,
  output_file
) {
  bls_hours_doc = tibble(
    name = "BLS total economy hours",
    date_accessed = ymd("2025 August 20"),
    date_published = ymd("2025 August 7"),
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

  bls_current_wages_doc = bls_current_wages |>
    read_csv(show_col_types = F) |>
    mutate(
      name = case_match(
        name,
        "wage_private_prod_sa" ~ "seasonally adjusted",
        "wage_private_prod_nsa" ~ "not seasonally adjusted"
      )
    ) |>
    mutate(
      name = paste(
        "CES production and nonsupervisory average hourly earnings, private-sector,",
        name
      )
    ) |>
    mutate(
      source = paste("BLS Current Employment Statistics, series", table_id)
    ) |>
    select(name, source) |>
    mutate(
      source_url = "https://www.bls.gov/developers/home.htm",
      access_method = "BLS API",
      data_location = bls_current_wages,
      date_accessed = api_download_date
    )

  bea_data_doc = bea_data |>
    read_csv(show_col_types = F) |>
    filter(frequency == "annual") |>
    mutate(
      name = case_match(
        name,
        "nipa_ndp" ~ "BEA Net domestic product",
        "nipa_comp" ~ "BEA Compensation of employees",
        "nipa_wage" ~ "BEA Wages and salaries"
      )
    ) |>
    mutate(
      source = paste0(
        "BEA National Income and Product Accounts,",
        "Table ",
        table_number,
        ", Line Number ",
        line_numbers
      )
    ) |>
    select(name, source) |>
    mutate(
      source_url = "https://apps.bea.gov/API/",
      access_method = "BEA API",
      data_location = bea_data,
      date_accessed = api_download_date
    )

  bind_rows(
    bls_hours_doc,
    bls_current_wages_doc,
    bls_early_wages_doc,
    bea_data_doc
  ) |>
    arrange(name) |>
    create_csv(output_file)
}
