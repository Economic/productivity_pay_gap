library(targets)
library(tarchetypes)

# conflicts and other options
library(conflicted)
conflict_prefer("filter", "dplyr", quiet = TRUE)
conflict_prefer("lag", "dplyr", quiet = TRUE)
conflict_prefer("zip", "zip", quiet = TRUE)
conflict_prefer("year", "lubridate", quiet = TRUE)
conflict_prefer("quarter", "lubridate", quiet = TRUE)
conflict_prefer("month", "lubridate", quiet = TRUE)


options(usethis.quiet = TRUE)

# packages for this analysis
suppressPackageStartupMessages({
  library(tidyverse)
  library(bea.R)
  library(readxl)
  library(janitor)
  library(blsR)
  library(realtalk)
  library(assertr)
  library(zoo)
  library(scales)
})