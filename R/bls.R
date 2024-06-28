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

bls_grab_all <- function(data_csv, date) {
  data = read_csv(data_csv, show_col_types = FALSE)
  
  series_list = data |> 
    pull(table_id) |> 
    as.list()
  
  series_names = data |> 
    pull(name) |> 
    as.list()
  
  names(series_list) = series_names
  
  bls_data = get_series_tables(series_list, start_year = 1947, end_year = 2024) |>
    suppressMessages()
  
  bls_data |> 
    list_rbind(names_to = "name") |> 
    mutate(
      seasonal = str_extract(name, "_sa$|_nsa$"), 
      seasonal = str_remove(seasonal, "_"), 
      name = str_remove(name, "_sa$|_nsa$")
    )
}

clean_bls_pay = function(data) {
  # check that there is no M13 value
  m13_length = data |> 
    filter(seasonal == "nsa", period == "M13") |> 
    select(period) |> 
    pull(period) |> 
    length()
  
  stopifnot(m13_length == 0)
  
  data_monthly = data |> 
    mutate(
      month = as.numeric(str_sub(period, 2, 3)),
      quarter = quarter(ym(paste(year, month))) 
    ) |> 
    select(name, year, month, quarter, value, seasonal) 
  
  valid_dates_annual = data_monthly |> 
    filter(seasonal == "nsa") |> 
    mutate(
      month_count = n(), 
      row_number = row_number(), 
      .by = c(name, year)
    ) |> 
    filter(month_count == 12, row_number == 12) |> 
    select(name, year)
  
  valid_dates_quarterly = data_monthly |> 
    filter(seasonal == "sa") |> 
    mutate(
      month_count = n(), 
      row_number = row_number(),
      .by = c(name, year, quarter)
    ) |> 
    filter(month_count == 3, row_number == 3) |> 
    select(name, year, quarter) 
    
  data_quarterly = data_monthly |> 
    filter(seasonal == "sa") |> 
    summarize(value = mean(value), .by = c(name, year, quarter)) |> 
    inner_join(valid_dates_quarterly, by = c("name", "year", "quarter")) |> 
    mutate(frequency = "quarterly") |> 
    arrange(name, year, quarter)
  
  data_annual = data_monthly |> 
    filter(seasonal == "nsa") |> 
    summarize(value = mean(value), .by = c(name, year)) |> 
    inner_join(valid_dates_annual, by = c("name", "year")) |> 
    mutate(frequency = "annual") |> 
    arrange(name, year)
  
  data_quarterly |> 
    bind_rows(data_annual) |> 
    select(name, frequency, year, quarter, value) 
}