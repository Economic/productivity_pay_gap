## Load your packages, e.g. library(targets).
source("./packages.R")

bea_key = Sys.getenv("BEA_API_KEY")
bls_key = Sys.getenv("BLS_API_KEY")
download_date = ymd("2024 June 28")

realtalk_version = packageVersion("realtalk")

## Load your R files
lapply(list.files("./R", full.names = TRUE), source)

tar_plan(
  
  # INPUT FILES
  # BLS total economy hours
  tar_file(bls_hours_xlsx, "data_inputs/total-economy-hours-employment.xlsx"),
  # BLS series inputs
  tar_file(bls_series_csv, "data_inputs/bls_series.csv"),
  # BEA series inputs
  tar_file(bea_series_csv, "data_inputs/bea_series.csv"),
  # old CPI-U-RS extended series
  tar_file(cpi_u_rs_monthly, "data_inputs/cpi_u_rs_extended_monthly_sa.csv"),
  tar_file(cpi_u_rs_annual, "data_inputs/cpi_u_rs_extended_annual.csv"),
  
  # INTERMEDIATE OUTPUS
  prices = make_prices(realtalk_version, cpi_u_rs_monthly, cpi_u_rs_annual),
  bls_api_output = bls_grab_all(bls_series_csv, download_date),
  bls_hours = clean_hours_data(bls_hours_xlsx),
  bea_api_output = bea_grab_all(bea_series_csv, download_date),
  bls_pay = clean_bls_pay(bls_api_output),
  
  # FINAL OUTPUTS
  output = combine_data(bls_pay, bls_hours, bea_api_output, prices),
  tar_file(
    output_csv, 
    create_final_csvs(output, "data_outputs", "epi_productivity_pay")
  )
  
)

# Sources
# BLS total economy hours:
# https://www.bls.gov/productivity/tables/home.htm
# https://www.bls.gov/productivity/tables/total-economy-hours-employment.xlsx