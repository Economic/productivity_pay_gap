create_web_data_csv <- function(data, file) {
  
  output = data |> 
    filter(frequency == "quarterly") |> 
    select(-frequency) |> 
    filter(name %in% c(
      "comp_private_real_index_1948",
      "productivity_real_index_1948"
    )) |> 
    pivot_wider(id_cols = c(year, quarter)) |> 
    mutate(date = paste0(year, "q", quarter)) |> 
    arrange(year, quarter) |> 
    select(date, comp_private_real_index_1948, productivity_real_index_1948) |>
    #rename columns and round to nearest 2 decimal places
    rename(Year = date,
           Pay = comp_private_real_index_1948,
           Productivity = productivity_real_index_1948) |>
    mutate(Pay = round(Pay, 2),
           Productivity = round(Productivity, 2))
  
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
  
  max_year = year(yq(max_quarter_date))
  
  total_growth_1979q4_present = data |> 
    filter(quarter_date == yq("1979q4") | quarter_date == yq(max_quarter_date)) |> 
    arrange(quarter_date) |> 
    mutate(value = value / lag(value) - 1, .by = name) |> 
    filter(!is.na(value)) |> 
    mutate(name = case_match(
      name,
      "comp_private_real_index_1948" ~ "Productivity, 1979q4–",
      "productivity_real_index_1948" ~ "Hourly pay, 1979q4–"
    )) |> 
    mutate(name = paste0(name, max_quarter_date, ", total percent growth"))
  
  ratio = total_growth_1979q4_present |> 
    summarize(value = max(value) / min(value)) |> 
    mutate(
      value = label_number(accuracy = 0.1)(value),
      value = paste0(value, "x"),
      name = "Productivity has grown by __ as much as pay"
    ) |> 
    select(name, value)
  
  total_growth_1979q4_present = total_growth_1979q4_present |> 
    mutate(value = label_percent(accuracy = 0.1)(value)) |> 
    select(name, value)
  
  avg_growth_1948_1979 = data |> 
    arrange(name, quarter_date) |> 
    mutate(time = row_number(), .by = name) |> 
    filter(quarter_date %in% yq(c("1948q1", "1979q4"))) |>
    mutate(
      total_growth = value / lag(value) - 1,
      total_years = (time - lag(time) + 1) / 4,
      .by = name
    ) |> 
    filter(!is.na(total_growth)) |> 
    mutate(
      value = (total_growth + 1)^(1/total_years) - 1,
      value = label_percent(accuracy = 0.1)(value)
    ) |> 
    mutate(name = case_match(
      name,
      "comp_private_real_index_1948" ~ "Productivity, 1948–1979, average annual growth",
      "productivity_real_index_1948" ~ "Compensation, 1948–1979, average annual growth"
    )) |> 
    select(name, value)
  
  avg_growth_1979_present = data |> 
    arrange(name, quarter_date) |> 
    mutate(time = row_number(), .by = name) |> 
    filter(quarter_date %in% yq(c("1979q4", max_quarter_date))) |>
    mutate(
      total_growth = value / lag(value) - 1,
      total_years = (time - lag(time) + 1) / 4,
      .by = name
    ) |> 
    filter(!is.na(total_growth)) |> 
    mutate(
      value = (total_growth + 1)^(1/total_years) - 1,
      value = label_percent(accuracy = 0.1)(value)
    ) |> 
    mutate(name = case_match(
      name,
      "comp_private_real_index_1948" ~ "Productivity, 1979–",
      "productivity_real_index_1948" ~ "Compensation, 1979–"
    )) |> 
    mutate(name = paste0(name, max_year, ", average annual growth")) |> 
    select(name, value)
  
  output = bind_rows(
    total_growth_1979q4_present,
    ratio,
    avg_growth_1948_1979,
    avg_growth_1979_present
  ) |> 
    select(name, value)
  
  write_csv(output, file)
  file
}