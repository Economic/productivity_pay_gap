# Quarterly series in wide format, one column per series, rounded. `series`
# maps each column name to its series name in `data`.
create_web_quarterly_csv = function(data, series, digits, file) {
  output = data |>
    filter(frequency == "quarterly", name %in% series) |>
    pivot_wider(id_cols = c(year, quarter)) |>
    arrange(year, quarter) |>
    mutate(Year = paste0(year, "q", quarter)) |>
    select(Year, all_of(series)) |>
    mutate(across(-Year, ~ round(.x, digits)))

  write_csv(output, file)

  file
}

create_web_data_csv <- function(data, file) {
  create_web_quarterly_csv(
    data,
    series = c(
      Productivity = "productivity_real_index_1948",
      Pay = "comp_private_real_index_1948"
    ),
    digits = 1,
    file = file
  )
}

# The wages start in 1979q4, the base of the counterfactual
create_web_counter_csv = function(data, file) {
  create_web_quarterly_csv(
    data,
    series = c(
      `Actual wage` = "wage_actual_real",
      `Counterfactual wage` = "wage_counter_real"
    ),
    digits = 2,
    file = file
  )
}

create_web_stats_csv <- function(web_data, file) {
  data = web_data |>
    clean_names() |>
    mutate(quarter_date = yq(year)) |>
    select(quarter_date, pay, productivity) |>
    pivot_longer(-quarter_date)

  max_quarter_date = data |>
    distinct(quarter_date) |>
    filter(quarter_date == max(quarter_date)) |>
    mutate(
      quarter_date = paste0(year(quarter_date), "q", quarter(quarter_date))
    ) |>
    pull(quarter_date)

  max_year = year(yq(max_quarter_date))

  total_growth_1979q4_present = data |>
    filter(
      quarter_date == yq("1979q4") | quarter_date == yq(max_quarter_date)
    ) |>
    arrange(quarter_date) |>
    mutate(value = value / lag(value) - 1, .by = name) |>
    filter(!is.na(value)) |>
    mutate(
      name = recode_values(
        name,
        "productivity" ~ "Productivity, 1979q4–",
        "pay" ~ "Hourly pay, 1979q4–"
      )
    ) |>
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
      total_years = (time - lag(time)) / 4,
      .by = name
    ) |>
    filter(!is.na(total_growth)) |>
    mutate(
      value = (total_growth + 1)^(1 / total_years) - 1,
      value = label_percent(accuracy = 0.1)(value)
    ) |>
    mutate(
      name = recode_values(
        name,
        "productivity" ~ "Productivity, 1948–1979, average annual growth",
        "pay" ~ "Compensation, 1948–1979, average annual growth"
      )
    ) |>
    select(name, value)

  avg_growth_1979_present = data |>
    arrange(name, quarter_date) |>
    mutate(time = row_number(), .by = name) |>
    filter(quarter_date %in% yq(c("1979q4", max_quarter_date))) |>
    mutate(
      total_growth = value / lag(value) - 1,
      total_years = (time - lag(time)) / 4,
      .by = name
    ) |>
    filter(!is.na(total_growth)) |>
    mutate(
      value = (total_growth + 1)^(1 / total_years) - 1,
      value = label_percent(accuracy = 0.1)(value)
    ) |>
    mutate(
      name = recode_values(
        name,
        "productivity" ~ "Productivity, 1979–",
        "pay" ~ "Compensation, 1979–"
      )
    ) |>
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
