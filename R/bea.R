bea_grab_all <- function(bea_series_csv) {
  data = read_csv(bea_series_csv, show_col_types = FALSE)

  pmap(data, bea_grab_series) |>
    list_rbind()
}

bea_grab_series = function(
  name,
  table_id,
  table_number,
  line_numbers,
  frequency
) {
  if (frequency == "annual") {
    frequency_abb = "year"
  } else if (frequency == "quarterly") {
    frequency_abb = "quarter"
  } else {
    stop("invalid frequency: must be 'annual' or 'quarterly'")
  }

  get_bea_nipa(table_id, years = "ALL", frequency = frequency_abb) %>%
    filter(line_number %in% c(line_numbers)) |>
    mutate(
      source = paste0(
        "NIPA, ",
        table_description,
        ", Line ",
        line_number,
        ", ",
        line_description
      ),
      name = name,
      frequency = frequency
    ) |>
    select(name, any_of(c("year", "quarter")), frequency, value, source)
}
