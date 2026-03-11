document_data = function(
  bls_hours,
  bls_early_wages,
  bls_current_wages,
  bea_data,
  source_dates,
  output_file
) {
  get_date = function(target_name) {
    source_dates |>
      filter(name == target_name) |>
      pull(time) |>
      as_date()
  }

  realtalk_version = as.character(packageVersion("realtalk"))

  realtalk_doc = tibble(
    name = "Extended Chained CPI-U",
    date_accessed = get_date("prices"),
    date_published = ymd(str_replace_all(realtalk_version, "\\.", "-")),
    source = paste("realtalk, version", realtalk_version),
    source_url = "https://economic.github.io/realtalk/",
    access_method = "R package",
    data_location = "realtalk"
  )

  bls_hours_doc = tibble(
    name = "BLS total economy hours",
    date_accessed = ymd("2026 March 11"),
    date_published = ymd("2026 March 5"),
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
      name = recode_values(
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
      date_accessed = get_date("bls_api_output")
    )

  bea_data_doc = bea_data |>
    read_csv(show_col_types = F) |>
    filter(frequency == "annual") |>
    mutate(
      name = recode_values(
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
      date_accessed = get_date("bea_api_output")
    )

  bind_rows(
    bls_hours_doc,
    bls_current_wages_doc,
    bls_early_wages_doc,
    bea_data_doc,
    realtalk_doc
  ) |>
    arrange(name) |>
    create_csv(output_file)
}
