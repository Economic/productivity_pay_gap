## Load your packages, e.g. library(targets).
source("./packages.R")

bea_key = Sys.getenv("BEA_API_KEY")
bls_key = Sys.getenv("BLS_API_KEY")
download_date = ymd("2024 June 26")

## Load your R files
lapply(list.files("./R", full.names = TRUE), source)

tar_plan(
  
  # BLS total economy hours
  tar_file(bls_hours_xlsx, "data_inputs/total-economy-hours-employment.xlsx"),
  # BLS series inputs
  tar_file(bls_series_csv, "data_inputs/bls_series.csv"),
  # BEA series inputs
  tar_file(bea_series_csv, "data_inputs/bea_series.csv"),
  
  bls_api_output = bls_grab_all(bls_series_csv, download_date),
  bls_hours = clean_hours_data(bls_hours_xlsx),
  bea_api_output = bea_grab_all(bea_series_csv, download_date),
  bls_pay = clean_bls_pay(bls_api_output),
  
)

# Sources
# BLS total economy hours:
# https://www.bls.gov/productivity/tables/home.htm
# https://www.bls.gov/productivity/tables/total-economy-hours-employment.xlsx