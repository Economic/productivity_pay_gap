bea_grab_all <- function(data_csv, date) {
  data = read_csv(data_csv, show_col_types = FALSE)
  
  pmap(data, bea_grab_series) |> 
    list_rbind() 
}

bea_grab_series = function(
    name, 
    table_id, 
    table_number, 
    line_numbers, 
    frequency, 
    download_date) {
  
  if (frequency == "annual") frequency_abb = "A"
  else if (frequency == "quarterly") frequency_abb = "Q"
  else stop("invalid frequency: must be 'annual' or 'quarterly'")

  data = bea_query(table_id, frequency = frequency_abb) %>% 
    filter(LineNumber %in% c(line_numbers)) |> 
    mutate(
      value = DataValue,
      source = paste0(
        "NIPA, Table ",
        table_number, 
        ", Line ", 
        LineNumber,
        ", ",
        LineDescription
      ),
      name = name,
      frequency = frequency
    )
  
  if (frequency == "annual") {
    data = data |> 
      mutate(year = as.numeric(TimePeriod)) |> 
      select(name, year, frequency, value, source)
  }
  if (frequency == "quarterly") {
    data = data |> 
      mutate(
        quarter_date = yq(TimePeriod), 
        year = year(quarter_date),
        quarter = quarter(quarter_date),
      ) |> 
      select(name, year, quarter, frequency, value, source)
  }

  data
}

bea_query <- function(tablename, frequency = 'A') {
  bea_specs <- list(
    'UserID' = bea_key,
    'Method' = 'GetData',
    'datasetname' = 'NIPA',
    'TableName' = tablename,
    'Frequency' = frequency,
    'Year' = 'X'
  )
  beaGet(bea_specs, asWide = FALSE) %>% 
    as_tibble() |> 
    suppressMessages()
}