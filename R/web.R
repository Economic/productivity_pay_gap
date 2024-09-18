create_web_data_csv <- function(data, file) {
  
  output = data |> 
    filter(frequency == "quarterly") |> 
    select(-frequency) |> 
    filter(name %in% c(
      "comp_private_real_index_1948",
      "productivity_real_index_1948"
    )) |> 
    # here is a good place to do web friendly formatting
    pivot_wider(id_cols = c(year, quarter)) |> 
    mutate(date = paste0(year, "q", quarter)) |> 
    arrange(year, quarter) |> 
    select(date, comp_private_real_index_1948, productivity_real_index_1948)
  
  write_csv(output, file)
  
  file
}

create_web_stats_csv <- function(data, file) {
  
  data = data |> 
    filter(frequency == "quarterly") |> 
    filter(name %in% c(
      "comp_private_real_index_1948",
      "productivity_real_index_1948"
    )) |> 
    mutate(quarter_date = yq(paste(year, quarter)))
  
  max_quarter_date = data |> 
    distinct(quarter_date) |> 
    filter(quarter_date == max(quarter_date)) |> 
    mutate(quarter_date = paste0(year(quarter_date), "q", quarter(quarter_date))) |> 
    pull(quarter_date)
  
  pct_growth_1979q4_present = data |> 
    filter(quarter_date == yq("1979q4") | quarter_date == yq(max_quarter_date)) |> 
    arrange(quarter_date) |> 
    mutate(value = value / lag(value) - 1, .by = name) |> 
    filter(!is.na(value)) |> 
    mutate(name = case_match(
      name,
      "comp_private_real_index_1948" ~ "Productivity, 1979q4–",
      "productivity_real_index_1948" ~ "Hourly pay, 1979q4–"
    )) |> 
    mutate(name = paste0(name, max_quarter_date, ", percent growth"))
  
  ratio = pct_growth_1979q4_present |> 
    summarize(value = max(value) / min(value)) |> 
    mutate(
      value = label_number(accuracy = 0.1)(value),
      value = paste0(value, "x"),
      name = "Productivity has grown by __ as much as pay"
    ) |> 
    select(name, value)
  
  pct_growth_1979q4_present = pct_growth_1979q4_present |> 
    mutate(value = label_percent(accuracy = 0.1)(value)) |> 
    select(name, value)
  
  output = bind_rows(
    pct_growth_1979q4_present,
    ratio
  ) |> 
    select(name, value)
  
  write_csv(output, file)
  file
}