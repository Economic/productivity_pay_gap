make_prices <- function(realtalk_version, cpi_u_rs_monthly, cpi_u_rs_annual) {
  cpi_u_rs_annual = cpi_u_rs_annual |>
    read_csv(show_col_types = FALSE) |> 
    select(year, cpi_u_rs = cpi_u_rs_extended) |> 
    mutate(frequency = "annual")
  
  cpi_u_rs_quarterly = cpi_u_rs_monthly |> 
    read_csv(show_col_types = FALSE) |> 
    mutate(quarter = quarter(ym(paste(year, month)))) |> 
    summarize(cpi_u_rs = mean(cpi_u_rs_extended), .by = c(year, quarter)) |> 
    mutate(frequency = "quarterly")
  
  c_cpi_u_quarterly = c_cpi_u_extended_quarterly_sa |> 
    select(year, quarter, c_cpi_u = c_cpi_u_extended) |> 
    mutate(frequency = "quarterly") 
  
  c_cpi_u_annual = c_cpi_u_extended_annual |> 
    select(year, c_cpi_u = c_cpi_u_extended) |> 
    mutate(frequency = "annual")
  
  annual_data = cpi_u_rs_annual |> 
    inner_join(c_cpi_u_annual, by = c("year", "frequency"))
  
  quarterly_data = cpi_u_rs_quarterly |> 
    inner_join(c_cpi_u_quarterly, by = c("year", "quarter", "frequency"))
  
  annual_data |> 
    bind_rows(quarterly_data)
}