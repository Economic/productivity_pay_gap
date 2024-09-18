make_prices <- function(realtalk_version) {
  c_cpi_u_quarterly = c_cpi_u_extended_quarterly_sa |> 
    select(year, quarter, c_cpi_u = c_cpi_u_extended) |> 
    mutate(frequency = "quarterly") 
  
  c_cpi_u_annual = c_cpi_u_extended_annual |> 
    select(year, c_cpi_u = c_cpi_u_extended) |> 
    mutate(frequency = "annual")
  
  c_cpi_u_annual |> 
    bind_rows(c_cpi_u_quarterly)
}