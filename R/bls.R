clean_hours_data = function(data_xlsx) {
  quarterly_data = read_excel(data_xlsx, sheet = "MachineReadable") |>
    clean_names() |>
    filter(
      sector == "Total economy",
      basis == "All workers",
      component == "Total U.S. economy",
      measure == "Hours worked",
      year >= 1948
    ) |>
    mutate(value = as.numeric(value)) |>
    # convert to millions of hours to match NIPA table units (in millions $)
    mutate(value = value * 1000) |>
    select(year, quarter = qtr, hours_millions = value) |>
    mutate(frequency = "quarterly")

  year_max = quarterly_data |>
    summarize(num_quarters = n(), .by = year) |>
    filter(num_quarters == 4) |>
    filter(year == max(year)) |>
    pull(year)

  annual_data = quarterly_data |>
    filter(year <= year_max) |>
    summarize(hours_millions = mean(hours_millions), .by = c(year)) |>
    mutate(frequency = "annual")

  annual_data |>
    bind_rows(quarterly_data)
}

# Release date from the ReadMe sheet, which has a line like
# "Data released September 3, 2026; Bureau of Labor Statistics, ..."
read_bls_hours_release_date = function(data_xlsx) {
  readme_text = read_excel(
    data_xlsx,
    sheet = "ReadMe",
    col_names = FALSE,
    .name_repair = "minimal"
  ) |>
    unlist() |>
    str_subset("^Data released")

  if (length(readme_text) == 0) {
    return(as_date(NA))
  }

  readme_text[1] |>
    str_extract("(?<=^Data released )\\w+ \\d{1,2}, \\d{4}") |>
    mdy()
}

# Downloads the hours spreadsheet to `file`. If the download fails, `file`
# keeps the committed spreadsheet and the status says why.
download_bls_hours = function(
  file,
  url = "https://www.bls.gov/productivity/tables/total-economy-hours-employment.xlsx"
) {
  email = Sys.getenv("BLS_DOWNLOAD_EMAIL")
  temp_file = tempfile(fileext = ".xlsx")

  problem = if (email == "") {
    "BLS_DOWNLOAD_EMAIL is not set"
  } else {
    tryCatch(
      {
        # BLS refuses downloads without a contact email in the User-Agent.
        # download.file() follows the redirect BLS now sends for this URL.
        download.file(
          url,
          temp_file,
          mode = "wb",
          quiet = TRUE,
          headers = c("User-Agent" = email)
        )
        # a refused download can still look successful, so check the contents
        if (is.na(read_bls_hours_release_date(temp_file))) {
          "the response is not the hours spreadsheet"
        }
      },
      error = function(e) conditionMessage(e),
      warning = function(w) conditionMessage(w)
    )
  }

  if (is.null(problem)) {
    file.copy(temp_file, file, overwrite = TRUE)
    return(tibble(source = "bls_hours", date_accessed = today(), status = "ok"))
  }

  tibble(
    source = "bls_hours",
    date_accessed = as_date(NA),
    status = paste0(
      "download failed (",
      problem,
      "); kept file released ",
      read_bls_hours_release_date(file)
    )
  )
}

bls_grab_all <- function(bls_series_csv) {
  data = read_csv(bls_series_csv, show_col_types = FALSE) |>
    deframe() |>
    get_bls(start = 1947, end = year(today())) |>
    suppressMessages()

  data |>
    mutate(
      seasonal = str_extract(name, "_sa$|_nsa$"),
      seasonal = str_remove(seasonal, "_"),
      name = str_remove(name, "_sa$|_nsa$")
    )
}

clean_bls_pay = function(early_wages_csv, api_csv) {
  api_data = api_csv |>
    read_csv(show_col_types = FALSE)

  # make annual wages
  wage_late_annual = api_data |>
    filter(name == "wage_private_prod", seasonal == "nsa") |>
    # this should be only monthly data
    verify(date_frequency == "month") |>
    mutate(count_per_year = n(), .by = year) |>
    filter(count_per_year == 12) |>
    summarize(late_value = mean(value), .by = year)

  wage_early_annual = read_csv(early_wages_csv, show_col_types = FALSE) |>
    filter(year <= 1964, period == "M13") |>
    select(year, early_value = value)

  wages_combined_annual = wage_early_annual |>
    full_join(wage_late_annual, by = "year")

  adj_factor = wages_combined_annual |>
    filter(year == 1964) |>
    mutate(adj_factor = late_value / early_value) |>
    pull(adj_factor)

  wages_annual = wages_combined_annual |>
    mutate(
      value = if_else(
        year >= 1964,
        late_value,
        early_value * adj_factor
      )
    ) |>
    select(year, value) |>
    mutate(frequency = "annual")

  # make quarterly wages
  wages_late_quarterly = api_data |>
    filter(name == "wage_private_prod", seasonal == "sa") |>
    # this should be only monthly data
    verify(date_frequency == "month") |>
    mutate(quarter = quarter(date)) |>
    mutate(count_per_quarter = n(), .by = c(year, quarter)) |>
    filter(count_per_quarter == 3) |>
    summarize(value = mean(value), .by = c(year, quarter))

  wages_early_quarterly = wages_annual |>
    filter(year <= 1963) |>
    # assume annual data, which is all we have in early period, is quarter 3
    mutate(quarter = 3) |>
    select(year, quarter, value)

  wages_quarterly = wages_early_quarterly |>
    bind_rows(wages_late_quarterly) |>
    complete(year, quarter) |>
    arrange(year, quarter) |>
    mutate(value = na.approx(value, na.rm = FALSE)) |>
    filter(!is.na(value)) |>
    mutate(frequency = "quarterly")

  wages_annual |>
    bind_rows(wages_quarterly) |>
    select(year, quarter, frequency, value)
}
