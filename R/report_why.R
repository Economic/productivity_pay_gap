# The "why" in the change report: an exact split of each revision into
# contributions from the inputs. See "How the 'why' is computed" in
# plans/2026-10-21-ci-data-release-workflow.md.
#
# R/combine.R computes, relative to the base quarter 0 (1948q1):
#   productivity index = 100 * (NDP_t / NDP_0) * (H_0 / H_t) * (CPI_0 / CPI_t)
#   pay index = 100 * (W_t / W_0) * (COMP_t / COMP_0) * (WAGE_0 / WAGE_t) * (CPI_0 / CPI_t)
# So the log revision of index_t / index_b is the sum over inputs of
# sign * (log revision of input_t - log revision of input_b), for any base b.
# Whatever that sum doesn't explain is a change in the calculation itself.

index_names = c(
  productivity_real_index_1948 = "productivity",
  comp_private_real_index_1948 = "pay"
)

index_terms = tribble(
  ~index,         ~series,     ~sign, ~label,
  "productivity", "nipa_ndp",      1, "NDP (BEA)",
  "productivity", "hours",        -1, "Hours (BLS)",
  "productivity", "cpi",          -1, "CPI (realtalk)",
  "pay",          "ces_wage",      1, "CES wages (BLS)",
  "pay",          "nipa_comp",     1, "Compensation (BEA)",
  "pay",          "nipa_wage",    -1, "NIPA wages (BEA)",
  "pay",          "cpi",          -1, "CPI (realtalk)"
)

method_change_label = "Code or method change"
method_change_threshold = 1e-8

quarter_label = function(year, quarter) {
  paste0(year, "q", quarter)
}

quarter_count = function(period) {
  period[1] * 4 + period[2]
}

# (a - b) / (log a - log b), or a when a equals b. Multiplying log changes by
# it turns them into level changes that add up exactly.
log_mean = function(a, b) {
  if_else(abs(a - b) <= 1e-12 * abs(a), a, (a - b) / (log(a) - log(b)))
}

# Quarterly values of both indexes and of every input to them, in long form
index_inputs = function(snapshot) {
  bea = snapshot$bea_api |>
    filter(frequency == "quarterly") |>
    select(year, quarter, name, value) |>
    pivot_wider()
  hours = snapshot$bls_hours |>
    filter(frequency == "quarterly") |>
    select(year, quarter, hours = hours_millions)
  wages = snapshot$bls_pay |>
    filter(frequency == "quarterly") |>
    select(year, quarter, ces_wage = value)
  cpi = snapshot$prices |>
    filter(frequency == "quarterly") |>
    select(year, quarter, cpi = c_cpi_u)

  snapshot$data |>
    filter(frequency == "quarterly", name %in% names(index_names)) |>
    mutate(name = index_names[name]) |>
    select(year, quarter, name, value) |>
    pivot_wider() |>
    inner_join(bea, by = c("year", "quarter")) |>
    inner_join(hours, by = c("year", "quarter")) |>
    inner_join(wages, by = c("year", "quarter")) |>
    inner_join(cpi, by = c("year", "quarter")) |>
    pivot_longer(-c(year, quarter), names_to = "series")
}

# log(new) - log(old) for every series and quarter in both
log_revisions = function(old_inputs, new_inputs) {
  inner_join(
    old_inputs,
    new_inputs,
    by = c("year", "quarter", "series"),
    suffix = c("_old", "_new")
  ) |>
    mutate(log_revision = log(value_new) - log(value_old))
}

# Splits the log revision of index_t / index_base into input contributions,
# plus a "code or method change" remainder
split_log_revision = function(revisions, base) {
  base_revisions = revisions |>
    filter(year == base[1], quarter == base[2]) |>
    select(series, base_revision = log_revision)
  relative = revisions |>
    inner_join(base_revisions, by = "series") |>
    mutate(relative = log_revision - base_revision)
  # CPI enters both indexes, hence many-to-many
  contributions = relative |>
    inner_join(index_terms, by = "series", relationship = "many-to-many") |>
    transmute(year, quarter, index, label, log_contribution = sign * relative)

  remainder = contributions |>
    summarize(explained = sum(log_contribution), .by = c(year, quarter, index)) |>
    inner_join(
      relative |>
        filter(series %in% index_names) |>
        select(year, quarter, index = series, actual = relative),
      by = c("year", "quarter", "index")
    ) |>
    transmute(
      year,
      quarter,
      index,
      label = method_change_label,
      log_contribution = actual - explained
    )

  bind_rows(contributions, remainder)
}

# Revision of each index in every common quarter, split into contributions in
# index points
index_revisions = function(old_inputs, new_inputs) {
  revisions = log_revisions(old_inputs, new_inputs)
  levels = revisions |>
    filter(series %in% index_names) |>
    select(year, quarter, index = series, old = value_old, new = value_new)

  split_log_revision(revisions, base = c(1948, 1)) |>
    inner_join(levels, by = c("year", "quarter", "index")) |>
    mutate(points = log_mean(new, old) * log_contribution)
}

# Revisions to the 1948q1 inputs, which move every quarter of an index
base_period_revisions = function(old_inputs, new_inputs) {
  log_revisions(old_inputs, new_inputs) |>
    filter(
      year == 1948,
      quarter == 1,
      !series %in% index_names,
      log_revision != 0
    ) |>
    inner_join(distinct(index_terms, series, label), by = "series") |>
    transmute(label, percent = 100 * (exp(log_revision) - 1))
}

last_quarter = function(inputs) {
  last = inputs |>
    filter(series == "productivity") |>
    slice_max(year * 4 + quarter, n = 1)
  c(last$year, last$quarter)
}

# The web stats as published: total growth since 1979q4, average annual growth
# 1948q1 to 1979q4 and 1979q4 to the latest quarter, and the growth ratio
published_stats = function(web_stats) {
  web_stats |>
    mutate(
      stat = case_when(
        str_detect(name, "as much as") ~ "ratio",
        str_detect(name, "total percent growth") ~ "total_growth",
        str_detect(name, "1948–1979") ~ "growth_1948_1979",
        str_detect(name, "average annual growth") ~ "growth_1979_latest"
      ),
      index = case_when(
        stat == "ratio" ~ NA_character_,
        str_starts(name, "Productivity") ~ "productivity",
        .default = "pay"
      ),
      text = value,
      value = parse_number(value)
    ) |>
    select(stat, index, name, text, value)
}

# One growth stat for one index, from the unrounded indexes:
#   G = index_end / index_start, and the stat is G - 1, or G^(1 / years) - 1
#   when annualized. The revision at the earlier of the two end quarters is
#   split by input. If the end quarter moved, the move is "Added quarters" or
#   "Removed quarters".
split_growth_stat = function(
  revisions,
  old_inputs,
  new_inputs,
  index_name,
  start,
  end_old,
  end_new,
  annualized
) {
  index_at = function(inputs, period) {
    inputs |>
      filter(series == index_name, year == period[1], quarter == period[2]) |>
      pull(value)
  }
  growth = function(inputs, end) index_at(inputs, end) / index_at(inputs, start)
  power = function(end) {
    if (annualized) 4 / (quarter_count(end) - quarter_count(start)) else 1
  }

  # log(1 + stat) = power(end) * log(G(end)), from `inputs` up to `end`
  log_stat = function(inputs, end) power(end) * log(growth(inputs, end))
  end_common = if (quarter_count(end_new) < quarter_count(end_old)) end_new else end_old
  stat_old = exp(log_stat(old_inputs, end_old)) - 1
  stat_new = exp(log_stat(new_inputs, end_new)) - 1

  contributions = split_log_revision(revisions, start) |>
    filter(index == index_name, year == end_common[1], quarter == end_common[2]) |>
    transmute(label, log_contribution = log_contribution * power(end_common)) |>
    bind_rows(tibble(
      label = c("Added quarters", "Removed quarters"),
      log_contribution = c(
        log_stat(new_inputs, end_new) - log_stat(new_inputs, end_common),
        log_stat(old_inputs, end_common) - log_stat(old_inputs, end_old)
      )
    ))

  # percentage points of the stat
  scale = 100 * log_mean(1 + stat_new, 1 + stat_old)
  list(
    unrounded_old = 100 * stat_old,
    unrounded_new = 100 * stat_new,
    contributions = mutate(contributions, points = scale * log_contribution)
  )
}

# Every headline stat split into contributions, plus a "Rounding" line: the
# published stats come from indexes rounded to one decimal, then are rounded
# again for display, so their change differs slightly from the unrounded one.
# If R/web.R changed, this line also holds the effect of that change.
headline_stat_revisions = function(old, new, old_inputs, new_inputs) {
  revisions = log_revisions(old_inputs, new_inputs)
  end_old = last_quarter(old_inputs)
  end_new = last_quarter(new_inputs)
  specs = list(
    total_growth = list(start = c(1979, 4), end_old = end_old, end_new = end_new, annualized = FALSE),
    growth_1948_1979 = list(start = c(1948, 1), end_old = c(1979, 4), end_new = c(1979, 4), annualized = TRUE),
    growth_1979_latest = list(start = c(1979, 4), end_old = end_old, end_new = end_new, annualized = TRUE)
  )
  published = inner_join(
    published_stats(old$web_stats),
    published_stats(new$web_stats),
    by = c("stat", "index"),
    suffix = c("_old", "_new")
  )

  expand_grid(stat = names(specs), index = c("productivity", "pay")) |>
    pmap(\(stat, index) {
      spec = specs[[stat]]
      split = split_growth_stat(
        revisions,
        old_inputs,
        new_inputs,
        index,
        spec$start,
        spec$end_old,
        spec$end_new,
        spec$annualized
      )
      shown = published[published$stat == stat & published$index %in% index, ]
      rounding = (shown$value_new - shown$value_old) -
        (split$unrounded_new - split$unrounded_old)

      split$contributions |>
        bind_rows(tibble(label = "Rounding", points = rounding)) |>
        mutate(
          stat = stat,
          index = index,
          name = shown$name_new,
          text_old = shown$text_old,
          text_new = shown$text_new,
          unrounded_old = split$unrounded_old,
          unrounded_new = split$unrounded_new
        )
    }) |>
    list_rbind()
}
