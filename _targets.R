## Load your packages, e.g. library(targets).
source("./packages.R")

bea_key = Sys.getenv("BEA_API_KEY")
download_date = ymd("2024 June 26")

## Load your R files
lapply(list.files("./R", full.names = TRUE), source)

bea_grab_options = tribble(
  ~name, ~table_id, ~table_number, ~line_numbers, ~frequency,
  "nipa_ndp", "T10705", "1.7.5", 30, "quarterly",
  "nipa_ndp", "T10705", "1.7.5", 30, "annual",
  "nipa_comp", "T20100", "2.1", 2, "annual",
  "nipa_comp", "T20100", "2.1", 2, "quarterly",
  "nipa_wage", "T20100", "2.1", 3, "annual",
  "nipa_wage", "T20100", "2.1", 3, "quarterly",
) |> 
  mutate(download_date = download_date)

## tar_plan supports drake-style targets and also tar_target()
tar_plan(

# target = function_to_make(arg), ## drake style

# tar_target(target2, function_to_make2(arg)) ## targets style

  output = pmap(bea_grab_options, bea_grab)
)
