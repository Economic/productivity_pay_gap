combine_data <- function(bls_pay_csv, bls_hours_csv, bea_csv, prices_csv) {
  clean_bea = bea_csv |>
    read_csv(show_col_types = FALSE) |>
    select(name, year, quarter, frequency, value) |>
    pivot_wider(id_cols = c(year, quarter, frequency))

  bea_ratios = clean_bea |>
    mutate(nipa_comp_wage_ratio = nipa_comp / nipa_wage) |>
    select(year, quarter, frequency, nipa_comp_wage_ratio)

  bls_hours_data = read_csv(bls_hours_csv, show_col_types = FALSE)

  productivity = clean_bea |>
    select(year, quarter, frequency, nipa_ndp) |>
    full_join(bls_hours_data, by = c("year", "quarter", "frequency")) |>
    mutate(productivity_nominal = nipa_ndp / hours_millions) |>
    select(year, quarter, frequency, productivity_nominal)

  bls_pay = bls_pay_csv |>
    read_csv(show_col_types = FALSE) |>
    rename(bls_prod_wage_nominal = value) |>
    select(year, quarter, frequency, bls_prod_wage_nominal)

  prices = prices_csv |>
    read_csv(show_col_types = FALSE) |>
    select(year, quarter, frequency, cpi = c_cpi_u)

  combined_data = bls_pay |>
    inner_join(bea_ratios, by = c("year", "quarter", "frequency")) |>
    mutate(
      comp_private_nominal = bls_prod_wage_nominal * nipa_comp_wage_ratio
    ) |>
    inner_join(productivity, by = c("year", "quarter", "frequency")) |>
    inner_join(prices, by = c("year", "quarter", "frequency")) |>
    # only look at dates when key series are available
    filter(
      !is.na(comp_private_nominal),
      !is.na(productivity_nominal),
      !is.na(cpi)
    )

  cpi_bases = combined_data |>
    arrange(frequency, year, quarter) |>
    filter(row_number() == n(), .by = frequency) |>
    select(frequency, cpi_base = cpi)

  real_data = combined_data |>
    inner_join(cpi_bases, by = "frequency") |>
    mutate(
      comp_private_real = comp_private_nominal * cpi_base / cpi,
      productivity_real = productivity_nominal * cpi_base / cpi
    )

  # compensation per unit of productivity in 1979q4 (1979 for annual data), the
  # base of the counterfactual wage
  counter_bases = real_data |>
    filter(year == 1979, quarter == 4 | is.na(quarter)) |>
    transmute(frequency, comp_per_productivity = comp_private_real / productivity_real)
  if (!identical(sort(counter_bases$frequency), c("annual", "quarterly"))) {
    stop("The data needs exactly one row for 1979q4 and one for 1979.")
  }

  output = real_data |>
    inner_join(counter_bases, by = "frequency") |>
    mutate(
      since_base = year > 1979 | (year == 1979 & (quarter == 4 | is.na(quarter))),
      wage_actual_real = if_else(
        since_base,
        bls_prod_wage_nominal * cpi_base / cpi,
        NA
      ),
      # pay if it had grown with productivity since the base, converted from
      # compensation to wages
      wage_counter_real = if_else(
        since_base,
        comp_per_productivity * productivity_real / nipa_comp_wage_ratio,
        NA
      )
    ) |>
    select(
      frequency,
      year,
      quarter,
      bls_prod_wage_nominal,
      comp_private_nominal,
      productivity_nominal,
      comp_private_real,
      productivity_real,
      comp_wage_ratio = nipa_comp_wage_ratio,
      wage_actual_real,
      wage_counter_real
    ) |>
    pivot_longer(-c(frequency, year, quarter)) |>
    # the wages start at the base
    filter(!(name %in% c("wage_actual_real", "wage_counter_real") & is.na(value)))

  bases_1948 = output |>
    filter(name %in% c("comp_private_real", "productivity_real")) |>
    filter(year == 1948 & (quarter == 1 | is.na(quarter))) |>
    select(frequency, name, value_base = value)

  index_1948 = output |>
    inner_join(bases_1948, by = c("frequency", "name")) |>
    mutate(value = value / value_base * 100) |>
    mutate(name = paste0(name, "_index_1948")) |>
    select(-value_base)

  output |>
    bind_rows(index_1948) |>
    arrange(frequency, year, quarter, name)
}
