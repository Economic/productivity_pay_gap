combine_data <- function(bls_pay_data, bls_hours_data, bea_data, prices) {
  clean_bea = bea_data |> 
    select(name, year, quarter, frequency, value) |> 
    pivot_wider(id_cols = c(year, quarter, frequency)) 
  
  bea_ratios = clean_bea |> 
    mutate(nipa_comp_wage_ratio = nipa_comp / nipa_wage) |> 
    select(year, quarter, frequency, nipa_comp, nipa_wage, nipa_comp_wage_ratio)
  
  productivity = clean_bea |> 
    select(year, quarter, frequency, nipa_ndp) |> 
    full_join(bls_hours_data, by = c("year", "quarter", "frequency")) |> 
    rename(bls_hours_millions = hours_millions) |> 
    mutate(productivity = nipa_ndp / bls_hours_millions)
  
  bls_pay = bls_pay_data |> 
    pivot_wider(id_cols = c(frequency, year, quarter)) |> 
    select(
      frequency, 
      year, 
      quarter,
      bls_wage_goods = wage_goods_prod, 
      bls_wage_private = wage_private_prod
    )
  
  bls_wage_base = bls_pay |>
    filter(year == 1964) |>
    select(
      frequency, 
      quarter, 
      bls_goods_base = bls_wage_goods, 
      bls_private_base = bls_wage_private
    )
  
  cpi_u_rs_base = prices |> 
    filter(year == 2023, frequency == "annual") |> 
    pull(cpi_u_rs) 
  
  c_cpi_u_base = prices |> 
    filter(year == 2023, frequency == "annual") |> 
    pull(c_cpi_u) 

  output = bls_pay |>
    inner_join(bls_wage_base, by = c("frequency", "quarter")) |> 
    mutate(bls_goods_base_ratio = if_else(
      year <= 1964, 
      bls_wage_goods / bls_goods_base,
      NA
    )) |> 
    mutate(bls_wage_private_extended = if_else(
      year <= 1964,
      bls_goods_base_ratio * bls_private_base,
      bls_wage_private
    )) |> 
    inner_join(bea_ratios, by = c("year", "quarter", "frequency")) |> 
    mutate(
      bls_comp_private = bls_wage_private_extended * nipa_comp_wage_ratio
    ) |> 
    inner_join(productivity, by = c("year", "quarter", "frequency")) |> 
    inner_join(prices, by = c("year", "quarter", "frequency")) |> 
    mutate(
      bls_comp_private_cpi_u_rs = bls_comp_private * cpi_u_rs_base / cpi_u_rs,
      bls_comp_private_c_cpi_u = bls_comp_private * c_cpi_u_base / c_cpi_u,
      productivity_cpi_u_rs = productivity * cpi_u_rs_base / cpi_u_rs,
      productivity_c_cpi_u = productivity * c_cpi_u_base / c_cpi_u
    ) |> 
    select(
      frequency, 
      year, 
      quarter, 
      bls_wage_goods, 
      bls_wage_private, 
      bls_wage_private_extended,
      nipa_comp,
      nipa_wage,
      nipa_comp_wage_ratio,
      bls_comp_private,
      bls_hours_millions,
      nipa_ndp,
      productivity,
      bls_comp_private_cpi_u_rs,
      productivity_cpi_u_rs,
      bls_comp_private_c_cpi_u,
      productivity_c_cpi_u
    )
  
  comp_cpi_u_rs_base = output |> 
    filter(year == 1979, frequency == "annual") |> 
    pull(bls_comp_private_cpi_u_rs)
  
  comp_c_cpi_u_base = output |> 
    filter(year == 1979, frequency == "annual") |> 
    pull(bls_comp_private_c_cpi_u)
  
  pdy_cpi_u_rs_base = output |> 
    filter(year == 1979, frequency == "annual") |> 
    pull(productivity_cpi_u_rs)
  
  pdy_c_cpi_u_base = output |> 
    filter(year == 1979, frequency == "annual") |> 
    pull(productivity_c_cpi_u)
  
  output |> 
    mutate(
      bls_comp_private_cpi_u_rs_index = 
        bls_comp_private_cpi_u_rs / comp_cpi_u_rs_base,
      bls_comp_private_c_cpi_u_index = 
        bls_comp_private_c_cpi_u / comp_c_cpi_u_base,
      productivity_cpi_u_rs_index = 
        productivity_cpi_u_rs / pdy_cpi_u_rs_base,
      productivity_c_cpi_u_index = 
        productivity_c_cpi_u / pdy_c_cpi_u_base
    )
  
}

create_final_csvs <- function(data, directory, file_prefix) {
  quarterly = data |> 
    filter(frequency == "quarterly") |> 
    select(-frequency)
  
  annual = data |> 
    filter(frequency == "annual") |> 
    select(-c(frequency, quarter))
  
  file_name_quarterly = file.path(
    directory, 
    paste0(file_prefix, "_quarterly", ".csv")
  )
  
  file_name_annual = file.path(
    directory, 
    paste0(file_prefix, "_annual", ".csv")
  )
  
  write_csv(quarterly, file_name_quarterly)
  write_csv(annual, file_name_annual)
  
  c(file_name_quarterly, file_name_annual)
}

