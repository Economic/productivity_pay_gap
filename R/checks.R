# Sanity checks on the final files. Each failure stops the pipeline.
check_outputs = function(data, web_data, web_stats, counter_web, sources_csv) {
  quarters = yq(web_data$Year)
  expected_quarters = seq(yq("1948q1"), max(quarters), by = "quarter")
  if (!identical(as.numeric(quarters), as.numeric(expected_quarters))) {
    stop("The web data does not have every quarter from 1948q1 to its last quarter.")
  }

  if (anyNA(web_data)) {
    stop("The web data has missing values, so the two series end in different quarters.")
  }

  counter_quarters = yq(counter_web$Year)
  expected_counter_quarters = seq(yq("1979q4"), max(quarters), by = "quarter")
  if (!identical(as.numeric(counter_quarters), as.numeric(expected_counter_quarters))) {
    stop("The counterfactual wage data does not have every quarter from 1979q4 to the web data's last quarter.")
  }

  if (anyNA(counter_web)) {
    stop("The counterfactual wage data has missing values, so the two wages end in different quarters.")
  }

  base_wages = data |>
    filter(
      name %in% c("wage_actual_real", "wage_counter_real"),
      year == 1979,
      quarter == 4 | is.na(quarter)
    ) |>
    pivot_wider(id_cols = frequency)
  if (
    nrow(base_wages) != 2 ||
      any(abs(base_wages$wage_actual_real - base_wages$wage_counter_real) > 1e-9)
  ) {
    stop("The actual and counterfactual wages differ in 1979q4 or in 1979, their base.")
  }

  base_values = data |>
    filter(
      str_ends(name, "_index_1948"),
      year == 1948,
      quarter == 1 | is.na(quarter)
    ) |>
    pull(value)
  if (length(base_values) != 4 || any(abs(base_values - 100) > 1e-9)) {
    stop("The indexes do not equal 100 in 1948q1 and in 1948.")
  }

  last_complete_year = data |>
    filter(frequency == "quarterly", quarter == 4) |>
    pull(year) |>
    max()
  last_annual_year = data |>
    filter(frequency == "annual") |>
    pull(year) |>
    max()
  if (last_annual_year > last_complete_year) {
    stop("The annual data includes ", last_annual_year, ", which is not a complete year.")
  }

  stat_values = suppressWarnings(parse_number(web_stats$value))
  if (anyNA(stat_values) || !all(is.finite(stat_values))) {
    stop("A web stat is missing or not a number.")
  }

  sources = read_csv(sources_csv, show_col_types = FALSE)
  if (anyNA(sources$date_accessed)) {
    stop("A source in the sources CSV has no access date.")
  }
  if (any(sources$date_published > sources$date_accessed, na.rm = TRUE)) {
    stop(
      "A source in the sources CSV was published after it was accessed. ",
      "If the hours spreadsheet was committed by hand, update its date in data_raw/fetch_log.csv."
    )
  }

  invisible(TRUE)
}

# The installed packages must match renv.lock: offline that is an error,
# because the rebuild must use the locked versions; in live mode a warning.
check_packages = function(lockfile, strict) {
  status = NULL
  # renv::status() prints its report, so capture it; `<-` is needed here
  utils::capture.output(status <- renv::status(lockfile = lockfile))

  if (isTRUE(status$synchronized)) {
    return(invisible(TRUE))
  }

  problem = "The installed packages don't match renv.lock. Run renv::status() for details."
  if (strict) {
    stop(problem)
  }
  warning(problem)
  invisible(FALSE)
}
