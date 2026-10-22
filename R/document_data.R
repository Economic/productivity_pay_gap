# Live mode records when each source was last fetched in data_raw/fetch_log.csv,
# so the offline rebuild can reproduce the sources CSV from committed files.
read_fetch_log = function(file) {
  read_csv(file, col_types = "cDc")
}

write_fetch_log = function(
  bls_api_date,
  bea_api_date,
  prices_date,
  bls_hours_fetch,
  file
) {
  previous_dates = read_fetch_log(file) |>
    select(source, previous_date = date_accessed)

  tibble(
    source = c("bls_api_output", "bea_api_output", "prices"),
    date_accessed = c(bls_api_date, bea_api_date, prices_date),
    status = "ok"
  ) |>
    bind_rows(bls_hours_fetch) |>
    left_join(previous_dates, by = "source") |>
    # a failed fetch keeps the date of the last successful one, because
    # that fetch is where the data came from
    mutate(
      date_accessed = if_else(status == "ok", date_accessed, previous_date)
    ) |>
    select(source, date_accessed, status) |>
    arrange(source) |>
    create_csv(file)
}

document_data = function(
  bls_hours,
  bls_early_wages,
  bls_current_wages,
  bea_data,
  fetch_log,
  output_file
) {
  fetch_dates = read_fetch_log(fetch_log)

  get_date = function(source_name) {
    fetch_dates |>
      filter(source == source_name) |>
      pull(date_accessed)
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

  hours_release_date = read_bls_hours_release_date(bls_hours)
  if (is.na(hours_release_date)) {
    stop("No 'Data released' line in the ReadMe sheet of ", bls_hours)
  }

  bls_hours_doc = tibble(
    name = "BLS total economy hours",
    date_accessed = get_date("bls_hours"),
    date_published = hours_release_date,
    source = "BLS Office of Productivity and Technology",
    source_url = "https://www.bls.gov/productivity/tables/home.htm",
    source_url_2 = "https://www.bls.gov/productivity/tables/total-economy-hours-employment.xlsx",
    access_method = "download",
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
