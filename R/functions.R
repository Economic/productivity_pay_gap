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


bea_grab = function(
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
# 
# bea_supp = bea_grab("T70800") %>% 
#   filter(LineNumber == 1) %>% 
#   mutate(
#     year = as.numeric(TimePeriod), 
#     value = DataValue,
#     source = paste0(
#       "NIPA Table 7.8, Line ", 
#       LineNumber,
#       ", ",
#       LineDescription
#     ),
#     unit = "millions"
#   ) |> 
#   select(year, value, source) 
# 
# bea_ndp_annual = bea_grab("T10705") |> 
#   filter(LineNumber == 30) %>% 
#   mutate(
#     year = as.numeric(TimePeriod), 
#     value = DataValue,
#     source = paste0(
#       "NIPA Table 1.7.5, Line ", 
#       LineNumber,
#       ", ",
#       LineDescription
#     ),
#     unit = "millions"
#   ) |> 
#   select(year, value, source) 
# 
# bea_ndp_quarter = bea_grab("T10705", frequency = 'Q') |> 
#   filter(LineNumber == 30) %>% 
#   mutate(
#     quarter_date = yq(TimePeriod), 
#     year = year(quarter_date),
#     quarter = quarter(quarter_date),
#     value = DataValue,
#     source = paste0(
#       "NIPA Table 1.7.5, Line ", 
#       LineNumber,
#       ", ",
#       LineDescription
#     ),
#     unit = "millions"
#   ) |> 
#   select(year, quarter, value, source) 
# 
# bea_pi_annual = bea_grab("T20100", frequency = 'A') |> 
#   filter(LineNumber %in% c(2, 3)) |> 
#   mutate(
#     year = as.numeric(TimePeriod), 
#     value = DataValue,
#     source = paste0(
#       "NIPA Table 1.7.5, Line ", 
#       LineNumber,
#       ", ",
#       LineDescription
#     ),
#     unit = "millions"
#   ) |> 
#   select(year, value, source) 
# 
