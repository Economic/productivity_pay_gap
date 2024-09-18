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

bls_grab_all <- function(data_csv, end_year, download_date) {
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
      name = str_remove(name, "_sa$|_nsa$"),
      download_date = api_download_date
    )
}

clean_bls_pay = function(early_wages_csv, api_data) {
  
  # make annual wages 
  wage_late_annual = api_data |> 
    filter(name == "wage_private_prod", seasonal == "nsa") |> 
    # this should be only monthly data
    verify(period != "M13") |> 
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
    mutate(value = if_else(
      year >= 1964, 
      late_value, 
      early_value * adj_factor)
    ) |> 
    select(year, value) |> 
    mutate(frequency = "annual")
  
  # make quarterly wages
  wages_late_quarterly = api_data |> 
    filter(name == "wage_private_prod", seasonal == "sa") |> 
    # this should be only monthly data
    verify(period != "M13") |> 
    mutate(
      month = str_sub(period, 2, 3),
      month_date = ym(paste(year, month)),
      quarter = quarter(month_date)
    ) |> 
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