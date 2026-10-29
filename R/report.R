# The "what changed and why" report, comparing the files in the working tree
# (or at a git ref) with a baseline ref. Written to reports/change_report.md.

epi_packages = c("realtalk", "epidatatools", "epitargets")

# Rows of the sources CSV that document each input
source_names = c(
  "CES wages, seasonally adjusted (BLS)" = "CES production and nonsupervisory average hourly earnings, private-sector, seasonally adjusted",
  "CES wages, not seasonally adjusted (BLS)" = "CES production and nonsupervisory average hourly earnings, private-sector, not seasonally adjusted",
  "NDP (BEA)" = "BEA Net domestic product",
  "Compensation (BEA)" = "BEA Compensation of employees",
  "NIPA wages (BEA)" = "BEA Wages and salaries",
  "Hours (BLS)" = "BLS total economy hours",
  "CPI (realtalk)" = "Extended Chained CPI-U"
)

md_table = function(data) {
  c(knitr::kable(data, format = "pipe"), "")
}

signed = function(x, digits = 3) {
  # so a tiny negative number prints as +0.000, not -0.000
  x = if_else(abs(x) < 0.5 * 10^-digits, 0, x)
  sprintf(paste0("%+.", digits, "f"), x)
}

# Whether a value was revised. Values computed in floating point can differ
# by about 1e-14 when nothing changed: the real series are rescaled to the
# latest quarter's CPI, which cancels out of the indexes only up to rounding.
revised = function(old, new) {
  abs(new - old) > 1e-9 * pmax(abs(old), abs(new))
}

# "old → new", or just the value when it didn't change
before_after = function(old, new) {
  old = coalesce(as.character(old), "none")
  new = coalesce(as.character(new), "none")
  if_else(old == new, old, paste(old, "→", new))
}

period_label = function(year, quarter, frequency) {
  case_when(
    frequency == "quarterly" ~ quarter_label(year, quarter),
    .default = as.character(year)
  )
}

# Every input value in long form: source, frequency, period, value
input_values = function(snapshot) {
  ces = snapshot$bls_api |>
    transmute(
      source = if_else(
        seasonal == "sa",
        "CES wages, seasonally adjusted (BLS)",
        "CES wages, not seasonally adjusted (BLS)"
      ),
      frequency = "monthly",
      period = format(date, "%Y-%m"),
      value
    )
  bea = snapshot$bea_api |>
    transmute(
      source = recode_values(
        name,
        "nipa_ndp" ~ "NDP (BEA)",
        "nipa_comp" ~ "Compensation (BEA)",
        "nipa_wage" ~ "NIPA wages (BEA)"
      ),
      frequency,
      period = period_label(year, quarter, frequency),
      value
    )
  hours = snapshot$bls_hours |>
    transmute(
      source = "Hours (BLS)",
      frequency,
      period = period_label(year, quarter, frequency),
      value = hours_millions
    )
  cpi = snapshot$prices |>
    transmute(
      source = "CPI (realtalk)",
      frequency,
      period = period_label(year, quarter, frequency),
      value = c_cpi_u
    )
  bind_rows(ces, bea, hours, cpi)
}

input_changes = function(old, new) {
  values = full_join(
    input_values(old),
    input_values(new),
    by = c("source", "frequency", "period"),
    suffix = c("_old", "_new")
  )
  # the latest monthly period for CES, quarterly for the rest
  latest = values |>
    filter(frequency %in% c("monthly", "quarterly")) |>
    summarize(
      latest_old = max(period[!is.na(value_old)]),
      latest_new = max(period[!is.na(value_new)]),
      .by = source
    )
  counts = values |>
    summarize(
      revised = sum(revised(value_old, value_new), na.rm = TRUE),
      added = sum(is.na(value_old)),
      removed = sum(is.na(value_new)),
      .by = source
    )
  # the sources CSV has its own `source` column, a description
  dates = function(snapshot) {
    tibble(input = names(source_names), name = source_names) |>
      inner_join(snapshot$sources, by = "name") |>
      select(source = input, date_accessed, date_published)
  }

  counts |>
    inner_join(latest, by = "source") |>
    inner_join(
      inner_join(dates(old), dates(new), by = "source", suffix = c("_old", "_new")),
      by = "source"
    ) |>
    transmute(
      Source = source,
      Accessed = before_after(date_accessed_old, date_accessed_new),
      Published = before_after(date_published_old, date_published_new),
      `Latest period` = before_after(latest_old, latest_new),
      `Revised values` = revised,
      `New values` = added,
      `Removed values` = removed
    )
}

package_changes = function(old, new) {
  full_join(old$packages, new$packages, by = "package", suffix = c("_old", "_new")) |>
    filter(is.na(version_old) | is.na(version_new) | version_old != version_new) |>
    arrange(!package %in% epi_packages, package != "R", package) |>
    transmute(Package = package, Version = before_after(version_old, version_new))
}

# Each index input's latest quarter. The latest quarter of the final files is
# the earliest of these.
latest_input_quarters = function(snapshot) {
  index_inputs_all = list(
    "CES wages (BLS)" = filter(snapshot$bls_pay, frequency == "quarterly"),
    "Hours (BLS)" = filter(snapshot$bls_hours, frequency == "quarterly"),
    "CPI (realtalk)" = filter(snapshot$prices, frequency == "quarterly"),
    "NDP (BEA)" = filter(snapshot$bea_api, frequency == "quarterly", name == "nipa_ndp"),
    "Compensation (BEA)" = filter(snapshot$bea_api, frequency == "quarterly", name == "nipa_comp"),
    "NIPA wages (BEA)" = filter(snapshot$bea_api, frequency == "quarterly", name == "nipa_wage")
  )
  index_inputs_all |>
    imap(\(data, source) {
      last = slice_max(data, year * 4 + quarter, n = 1, with_ties = FALSE)
      tibble(source = source, order = last$year * 4 + last$quarter, latest = quarter_label(last$year, last$quarter))
    }) |>
    list_rbind()
}

web_changes = function(old, new, file = "web") {
  longer = function(web) pivot_longer(web, -Year, names_to = "Series")
  inner_join(longer(old[[file]]), longer(new[[file]]), by = c("Year", "Series"), suffix = c("_old", "_new")) |>
    filter(value_old != value_new) |>
    mutate(change = value_new - value_old) |>
    arrange(desc(abs(change)), Year)
}

counter_web_lines = function(old, new) {
  if (is.null(new$counter_web)) {
    return(c(if (is.null(old$counter_web)) "No file in either snapshot." else "File removed.", ""))
  }
  if (is.null(old$counter_web)) {
    return(c(
      paste0("New file: ", first(new$counter_web$Year), " to ", last(new$counter_web$Year), "."),
      ""
    ))
  }
  revisions = web_changes(old, new, "counter_web")
  if (nrow(revisions) == 0) {
    return(c("No quarter changed after rounding.", ""))
  }
  c(
    paste0(n_distinct(revisions$Year), " quarters changed after rounding. Largest changes:"),
    "",
    md_table(
      revisions |>
        slice_head(n = 5) |>
        transmute(Quarter = Year, Series, Before = value_old, After = value_new, Change = signed(change, 2))
    )
  )
}

full_data_changes = function(old, new) {
  full_join(
    old$data,
    new$data,
    by = c("frequency", "year", "quarter", "name"),
    suffix = c("_old", "_new")
  ) |>
    mutate(is_revised = coalesce(revised(value_old, value_new), FALSE)) |>
    summarize(
      revised = sum(is_revised),
      added = sum(is.na(value_old)),
      removed = sum(is.na(value_new)),
      largest = max(c(0, abs(value_new - value_old)[is_revised])),
      .by = c(name, frequency)
    ) |>
    filter(revised > 0 | added > 0 | removed > 0) |>
    transmute(
      Series = name,
      Frequency = frequency,
      `Revised values` = revised,
      `New values` = added,
      `Removed values` = removed,
      `Largest revision` = as.character(signif(largest, 3))
    )
}

# Common input order and labels for all Why tables. Applicability comes from
# index_terms: an unused input gets a dash, while a zero effect stays visible.
why_input_labels = c(
  "NDP (BEA)" = "NDP (BEA)",
  "Hours (BLS)" = "Hours (BLS)",
  "CES wages (BLS)" = "Production/nonsupervisory wages (BLS)",
  "Compensation (BEA)" = "NIPA compensation",
  "NIPA wages (BEA)" = "NIPA wages",
  "CPI (realtalk)" = "CPI"
)

paired_why_table = function(rows) {
  rows |>
    mutate(index = str_to_sentence(index)) |>
    pivot_wider(names_from = index, values_from = text, values_fill = "\u2014") |>
    select(`Measure or contribution` = label, Productivity, Pay)
}

why_contribution_rows = function(rows, digits = 3, extra_labels = character()) {
  distinct(index_terms, index, label) |>
    bind_rows(expand_grid(index = c("productivity", "pay"), label = extra_labels)) |>
    left_join(select(rows, index, label, points), by = c("index", "label")) |>
    arrange(match(label, c(names(why_input_labels), extra_labels))) |>
    transmute(
      index,
      label = coalesce(unname(why_input_labels[label]), label),
      text = signed(coalesce(points, 0), digits)
    )
}

has_method_change = function(rows) {
  any(rows$label == method_change_label &
        abs(rows$log_contribution) > method_change_threshold, na.rm = TRUE)
}

why_index_table = function(revisions, average = FALSE) {
  rows = if (average) filter(revisions, revised(old, new)) else revisions
  levels = distinct(rows, index, year, quarter, old, new)
  contributions = rows |>
    summarize(points = mean(points), .by = c(index, label))
  extras = if (has_method_change(rows)) method_change_label else character()
  inputs = why_contribution_rows(contributions, extra_labels = extras)
  totals = levels |>
    summarize(points = mean(new - old), .by = index) |>
    transmute(index, label = "**Net revision**", text = paste0("**", signed(points), "**"))
  summary = if (!average) {
    levels |>
      select(index, old, new) |>
      pivot_longer(c(old, new), names_to = "label", values_to = "value") |>
      transmute(
        index,
        label = recode(label, old = "Previous index", new = "Revised index"),
        text = sprintf("%.3f", value)
      ) |>
      bind_rows(tibble(
        index = c("productivity", "pay"),
        label = "**Contributions, in index points**", text = ""
      ))
  }
  # Complete totals for an empty revised-quarter population, then label its
  # applicable cells n/a. An average over zero quarters is not a zero effect.
  totals = tibble(index = c("productivity", "pay")) |>
    left_join(totals, by = "index") |>
    mutate(label = "**Net revision**", text = coalesce(text, "n/a"))
  table = paired_why_table(bind_rows(summary, inputs, totals))
  if (average) {
    for (index_name in setdiff(c("productivity", "pay"), levels$index)) {
      column = str_to_sentence(index_name)
      table[[column]] = if_else(table[[column]] == "\u2014", "\u2014", "n/a")
    }
  }
  table
}

why_stat_table = function(rows, period_change = character()) {
  summary = distinct(rows, index, text_old, text_new) |>
    pivot_longer(c(text_old, text_new), names_to = "label", values_to = "text") |>
    mutate(label = recode(label,
      text_old = "Previous published growth", text_new = "Revised published growth"
    )) |>
    bind_rows(tibble(
      index = c("productivity", "pay"),
      label = "**Contributions, in percentage points**", text = ""
    ))
  extras = c(
    if (has_method_change(rows)) method_change_label,
    period_change,
    "Rounding"
  )
  totals = rows |>
    summarize(points = sum(points), .by = index) |>
    transmute(index, label = "**Net revision**", text = paste0("**", signed(points, 4), "**"))
  paired_why_table(bind_rows(
    summary, why_contribution_rows(rows, digits = 4, extra_labels = extras), totals
  ))
}

# The input contributing most to one index revision
main_source = function(revisions, index_name, period) {
  revisions |>
    filter(index == index_name, quarter_label(year, quarter) == period) |>
    slice_max(abs(points), n = 1, with_ties = FALSE) |>
    pull(label)
}

change_label = function(
  old,
  new,
  web_revisions,
  revisions,
  web_visible,
  final_files_differ
) {
  removed = setdiff(old$web$Year, new$web$Year)
  if (length(removed) > 0) {
    return(paste("Quarters removed:", paste(removed, collapse = ", ")))
  }
  added = setdiff(new$web$Year, old$web$Year)
  if (length(added) == 1) {
    return(paste("New quarter:", added))
  }
  if (length(added) > 1) {
    return(paste0("New quarters: ", first(added), " to ", last(added)))
  }
  if (nrow(web_revisions) > 0) {
    largest = web_revisions[1, ]
    index_name = if_else(largest$Series == "Productivity", "productivity", "pay")
    index_rows = revisions |>
      filter(index == index_name, quarter_label(year, quarter) == largest$Year)
    # a web value can change while its index doesn't, if R/web.R changed
    source = if (revised(index_rows$old[1], index_rows$new[1])) {
      # the short name: "CPI", not "CPI (realtalk)"
      str_remove(main_source(revisions, index_name, largest$Year), " \\([^)]*\\)")
    } else {
      "a change in R/web.R"
    }
    return(paste0(
      "Revisions only (largest: ",
      sprintf("%.1f", abs(largest$change)),
      " points, ",
      largest$Year,
      " ",
      tolower(largest$Series),
      ", from ",
      source,
      ")"
    ))
  }
  if (web_visible) {
    if (!same_contents(old$web_stats, new$web_stats)) {
      return("Web stats changed, web data unchanged")
    }
    if (is.null(old$counter_web)) {
      return("Counterfactual wage file added, web data unchanged")
    }
    return("Counterfactual wages changed, web data unchanged")
  }
  if (final_files_differ) "No web-visible changes" else "No changes"
}

# Keep file additions separate from revisions to values present in both files.
# These facts also retain simultaneous additions, removals, and revisions.
output_change_facts = function(old, new, web_revisions, data_changes, sources_differ) {
  quarterly = function(file, revisions) {
    before = old[[file]]
    after = new[[file]]
    list(
      file_added = is.null(before) && !is.null(after),
      file_removed = !is.null(before) && is.null(after),
      revised_quarters = n_distinct(revisions$Year),
      added_quarters = setdiff(after$Year, before$Year),
      removed_quarters = setdiff(before$Year, after$Year),
      added_series = setdiff(names(after), c("Year", names(before))),
      removed_series = setdiff(names(before), c("Year", names(after)))
    )
  }
  counter_revisions = if (!is.null(old$counter_web) && !is.null(new$counter_web)) {
    web_changes(old, new, "counter_web")
  } else {
    tibble(Year = character())
  }
  stats = function(snapshot) {
    published_stats(snapshot$web_stats) |>
      select(stat, index, name, text) |>
      arrange(stat, index)
  }
  list(
    web = quarterly("web", web_revisions),
    counter_web = quarterly("counter_web", counter_revisions),
    stats_changed = !same_contents(stats(old), stats(new)),
    data_revised = sum(data_changes$`Revised values`),
    data_added = sum(data_changes$`New values`),
    data_removed = sum(data_changes$`Removed values`),
    data_series_added = setdiff(unique(new$data$name), unique(old$data$name)),
    data_series_removed = setdiff(unique(old$data$name), unique(new$data$name)),
    sources_changed = sources_differ
  )
}

describe_output_changes = function(facts) {
  quarterly = function(change, name) {
    if (change$file_added) return(paste0(name, " file added."))
    if (change$file_removed) return(paste0(name, " file removed."))
    parts = c(
      if (change$revised_quarters > 0) {
        paste("existing values revised in", change$revised_quarters,
              ngettext(change$revised_quarters, "quarter", "quarters"))
      },
      if (length(change$added_quarters) > 0) {
        paste0("quarters added: ", paste(change$added_quarters, collapse = ", "))
      },
      if (length(change$removed_quarters) > 0) {
        paste0("quarters removed: ", paste(change$removed_quarters, collapse = ", "))
      },
      if (length(change$added_series) > 0) {
        paste0("series added: ", paste(change$added_series, collapse = ", "))
      },
      if (length(change$removed_series) > 0) {
        paste0("series removed: ", paste(change$removed_series, collapse = ", "))
      }
    )
    if (length(parts) > 0) paste0(name, ": ", paste(parts, collapse = "; "), ".")
  }
  counts = c(facts$data_revised, facts$data_added, facts$data_removed)
  changes = c(
    quarterly(facts$web, "Productivity and pay"),
    quarterly(facts$counter_web, "Actual and counterfactual wage"),
    if (facts$stats_changed) "Published headline statistics changed.",
    if (any(counts > 0)) {
      parts = c(
        paste(counts, c(
          ngettext(counts[1], "existing value revised", "existing values revised"),
          ngettext(counts[2], "value added", "values added"),
          ngettext(counts[3], "value removed", "values removed")
        ))[counts > 0],
        if (length(facts$data_series_added) > 0) {
          paste0("series added: ", paste(facts$data_series_added, collapse = ", "))
        },
        if (length(facts$data_series_removed) > 0) {
          paste0("series removed: ", paste(facts$data_series_removed, collapse = ", "))
        }
      )
      paste0("Full data: ", paste(parts, collapse = "; "), ".")
    },
    if (facts$sources_changed) "Source documentation changed."
  )
  if (length(changes) == 0) return("No output changes.")
  web = facts$web
  web_unchanged = !web$file_added && !web$file_removed && web$revised_quarters == 0 &&
    length(c(web$added_quarters, web$removed_quarters, web$added_series, web$removed_series)) == 0
  unchanged = if (web_unchanged) {
    if (facts$stats_changed) {
      "Existing published productivity and pay values unchanged."
    } else {
      "Existing published productivity, pay, and headline values unchanged."
    }
  } else if (!facts$stats_changed) {
    "Published headline values unchanged."
  }
  paste(c(changes, unchanged), collapse = " ")
}

# Calculate each comparison independently, including its revision attribution.
compare_snapshots = function(old, new) {
  old_inputs = index_inputs(old)
  new_inputs = index_inputs(new)
  code_files = changed_code_files(old$ref, new$ref)

  # Changed files that shape the published numbers in ways the report doesn't
  # measure: what is fetched or how it is cleaned, whose effect shows in the
  # inputs' contributions, and R/web.R, whose effect shows in the web data and
  # the rounding lines of the headline stats
  unmeasured_code = intersect(
    code_files,
    c(
      "R/bls.R",
      "R/bea.R",
      "R/prices.R",
      "R/web.R",
      "data_inputs/bea_series_codes.csv",
      "data_inputs/bls_series_codes.csv"
    )
  )

  revisions = index_revisions(old_inputs, new_inputs)
  stat_revisions = headline_stat_revisions(old, new, old_inputs, new_inputs)
  web_revisions = web_changes(old, new)
  data_changes = full_data_changes(old, new)
  sources_differ = !same_contents(
    select(old$sources, -date_accessed),
    select(new$sources, -date_accessed)
  )
  # the rule for notifying me: a web file changed
  web_visible = !same_contents(old$web, new$web) ||
    !same_contents(old$web_stats, new$web_stats) ||
    !same_contents(old$counter_web, new$counter_web)
  final_files_differ = web_visible || nrow(data_changes) > 0 || sources_differ
  label = change_label(
    old,
    new,
    web_revisions,
    revisions,
    web_visible,
    final_files_differ
  )
  output_facts = output_change_facts(old, new, web_revisions, data_changes, sources_differ)

  list(
    old_inputs = old_inputs,
    new_inputs = new_inputs,
    code_files = code_files,
    unmeasured_code = unmeasured_code,
    revisions = revisions,
    stat_revisions = stat_revisions,
    web_revisions = web_revisions,
    data_changes = data_changes,
    web_visible = web_visible,
    label = label,
    output_facts = output_facts,
    output_description = describe_output_changes(output_facts)
  )
}

# The report as a character vector of Markdown lines. `old` and `new` come from
# read_snapshot(); `baseline` names old's ref.
build_change_report = function(
  old, new, baseline, packages_ok = TRUE,
  comparison = compare_snapshots(old, new), show_unreleased = TRUE
) {
  old_inputs = comparison$old_inputs
  new_inputs = comparison$new_inputs
  code_files = comparison$code_files
  unmeasured_code = comparison$unmeasured_code
  revisions = comparison$revisions
  stat_revisions = comparison$stat_revisions
  web_revisions = comparison$web_revisions
  data_changes = comparison$data_changes
  label = comparison$label
  latest_old = last(old$web$Year)
  latest_new = last(new$web$Year)
  unreleased = if (show_unreleased && !is.null(old$ref)) unreleased_changes(old$ref)

  # ---- summary ----
  stats = inner_join(
    published_stats(old$web_stats),
    published_stats(new$web_stats),
    by = c("stat", "index"),
    suffix = c("_old", "_new")
  )
  summary_lines = c(
    "# Change report",
    "",
    paste0(
      "Compared with `", baseline, "` (commit ", substr(old$commit, 1, 7), ")",
      if (!is.null(new$ref)) paste0(", for `", new$ref, "`"), "."
    ),
    "",
    paste0("**", label, "**"),
    "",
    paste0("- Latest quarter: ", before_after(latest_old, latest_new)),
    paste0("- Output changes: ", comparison$output_description),
    if (length(unreleased$files) > 0) {
      paste0(
        "- `", baseline, "` has unreleased changes since ", unreleased$tag,
        " (ignoring access dates): ", paste(unreleased$files, collapse = ", ")
      )
    },
    "",
    "## Headline stats",
    "",
    md_table(transmute(stats, Stat = name_new, Before = text_old, After = text_new))
  )

  # ---- inputs ----
  # releases before Phase 1 have no fetch log
  fetch_problems = if (!is.null(new$fetch_log)) {
    new$fetch_log |>
      filter(status != "ok") |>
      transmute(line = paste0("- `", source, "`: ", status)) |>
      pull(line)
  }
  warnings = c(
    fetch_problems,
    if (!packages_ok) "- The installed packages don't match `renv.lock`; run `renv::status()`."
  )
  packages = package_changes(old, new)
  inputs = input_changes(old, new)
  input_lines = c(
    "## Inputs",
    "",
    "### Source coverage and changes",
    "",
    md_table(select(inputs, Source, `Latest period`, `Revised values`, `New values`, `Removed values`)),
    "### Source dates",
    "",
    md_table(select(inputs, Source, Accessed, Published)),
    "### Packages",
    "",
    if (nrow(packages) > 0) md_table(packages) else c("No package changes.", ""),
    "### Code and static inputs",
    "",
    if (length(code_files) > 0) c(paste0("- `", code_files, "`"), "") else c("No changes.", ""),
    "### Warnings",
    "",
    if (length(warnings) > 0) c(warnings, "") else c("None.", "")
  )

  # ---- outputs ----
  latest_inputs = full_join(
    latest_input_quarters(old),
    latest_input_quarters(new),
    by = "source",
    suffix = c("_old", "_new")
  )
  limiting = function(order, source) {
    sources = if (all(order == min(order))) "all inputs" else paste(source[order == min(order)], collapse = ", ")
    latest = (min(order) - 1) %/% 4
    paste0(sources, " (", quarter_label(latest, min(order) - latest * 4), ")")
  }
  output_lines = c(
    "## Outputs",
    "",
    "### Latest quarter by input",
    "",
    md_table(transmute(latest_inputs, Input = source, `Latest quarter` = before_after(latest_old, latest_new))),
    paste0(
      "The latest quarter of the final files is set by: ",
      before_after(
        limiting(latest_inputs$order_old, latest_inputs$source),
        limiting(latest_inputs$order_new, latest_inputs$source)
      ),
      "."
    ),
    "",
    "### Web data",
    "",
    if (nrow(web_revisions) > 0) {
      c(
        paste0(
          n_distinct(web_revisions$Year),
          " quarters changed after rounding. Largest changes:"
        ),
        "",
        md_table(
          web_revisions |>
            slice_head(n = 5) |>
            transmute(Quarter = Year, Series, Before = value_old, After = value_new, Change = signed(change, 1))
        )
      )
    } else {
      c("No quarter changed after rounding.", "")
    },
    "### Counterfactual wage data",
    "",
    counter_web_lines(old, new),
    "### Full data file",
    "",
    if (nrow(data_changes) > 0) md_table(data_changes) else c("No values changed.", "")
  )

  # ---- why ----
  common_last = revisions |> slice_max(year * 4 + quarter, n = 1)
  common_period = quarter_label(common_last$year[1], common_last$quarter[1])
  across_quarters = function(index_name) {
    revised_rows = revisions |> filter(index == index_name, revised(old, new))
    if (nrow(revised_rows) == 0) {
      return(paste0("- ", str_to_sentence(index_name), ": no quarter revised."))
    }
    periods = revised_rows |> distinct(year, quarter) |> arrange(year, quarter)
    paste0(
      "- ", str_to_sentence(index_name), ": ", nrow(periods), " quarters revised (",
      quarter_label(periods$year[1], periods$quarter[1]), " to ",
      quarter_label(last(periods$year), last(periods$quarter)),
      ")."
    )
  }
  ratio = filter(stats, stat == "ratio")
  method_changed = has_method_change(bind_rows(revisions, stat_revisions))
  period_change = sign(quarter_count(last_quarter(new_inputs)) - quarter_count(last_quarter(old_inputs)))
  period_effect = if (period_change > 0) {
    "Added quarters"
  } else if (period_change < 0) {
    "Removed quarters"
  } else {
    character()
  }
  stat_titles = c(
    total_growth = "Total growth, 1979q4 to latest quarter",
    growth_1948_1979 = "Average annual growth, 1948q1 to 1979q4",
    growth_1979_latest = "Average annual growth, 1979q4 to latest quarter"
  )
  stat_tables = map(names(stat_titles), \(stat_name) {
    rows = filter(stat_revisions, stat == stat_name)
    c(
      paste0("#### ", stat_titles[[stat_name]]), "",
      md_table(why_stat_table(
        rows,
        period_change = if (stat_name != "growth_1948_1979") period_effect else character()
      ))
    )
  }) |>
    unlist()
  why_lines = c(
    "## Why",
    "",
    paste0(
      "Contributions are signed. A dash means the input does not enter that index's formula. ",
      "NIPA compensation and NIPA wages are the two components of the benefits adjustment. ",
      "Totals are calculated before rounding, so displayed contributions may not add exactly to the displayed total."
    ),
    "",
    paste0("### Index revisions in ", common_period, ", the latest quarter in both"),
    "",
    md_table(why_index_table(common_last)),
    if (method_changed) {
      c(
        paste0(
          "**The inputs don't explain all of the changes: the calculation itself changed.** ",
          "See the \"", method_change_label, "\" rows, and the code changes under Inputs."
        ),
        ""
      )
    },
    if (length(unmeasured_code) > 0) {
      c(
        paste0(
          "**These changed files shape the published numbers, and the report doesn't measure ",
          "their effect separately: ", paste0("`", unmeasured_code, "`", collapse = ", "),
          ". The contributions of the inputs they shape, and for `R/web.R` the web data and ",
          "the rounding lines, may include a change in method.**"
        ),
        ""
      )
    },
    "### Across all revised quarters",
    "",
    across_quarters("productivity"),
    across_quarters("pay"),
    "",
    "Average contribution per revised quarter, in index points. n/a means no quarters were revised.",
    "",
    md_table(why_index_table(revisions, average = TRUE)),
    "### Headline stats",
    "",
    paste0(
      "Contributions are in percentage points, from the unrounded indexes. ",
      "\"Rounding\" reconciles these contributions with changes in the published stats, ",
      "which use indexes rounded to one decimal and are themselves rounded for display. ",
      "When the latest quarter changes, its effect is shown as added or removed quarters."
    ),
    "",
    stat_tables,
    paste0(
      "**", ratio$name_new, "**: ", ratio$text_old, " → ", ratio$text_new
    ),
    ""
  )

  check_lines = c(
    "## Checks",
    "",
    "- Sanity checks: passed.",
    paste0(
      "- Installed packages ",
      if_else(packages_ok, "match", "don't match"),
      " `renv.lock`."
    )
  )

  c(summary_lines, input_lines, output_lines, why_lines, check_lines)
}

build_dual_change_report = function(main, released, new, release_tag, packages_ok = TRUE) {
  against_main = compare_snapshots(main, new)
  same_baseline = identical(main$commit, released$commit)
  against_release = if (same_baseline) against_main else compare_snapshots(released, new)
  overview = tibble(
    Comparison = c("Proposed vs main", paste0("Proposed vs ", release_tag)),
    Result = c(against_main$output_description, against_release$output_description)
  )
  stats_column = function(snapshot, label) {
    published_stats(snapshot$web_stats) |>
      select(stat, index, all_of(setNames("text", label)))
  }
  stats = published_stats(new$web_stats) |>
    select(stat, index, Statistic = name, Proposed = text) |>
    full_join(stats_column(main, "main"), by = c("stat", "index")) |>
    full_join(stats_column(released, "Last release"), by = c("stat", "index")) |>
    select(Statistic, `Last release`, main, Proposed)
  quarters = tibble(
    Statistic = "Latest quarter",
    `Last release` = last(released$web$Year),
    main = last(main$web$Year),
    Proposed = last(new$web$Year)
  )
  details = function(old, baseline, comparison, title) {
    report = build_change_report(
      old, new, baseline, packages_ok,
      comparison = comparison, show_unreleased = FALSE
    )
    c(
      paste0("## ", title), "",
      "<details>", "<summary>Inputs, outputs, and revision explanations</summary>", "",
      # Drop the single-report title and move its headings down one level.
      sub("^(#+) ", "#\\1 ", report[-c(1, 2)]),
      "", "</details>", ""
    )
  }
  c(
    "# Change report", "",
    paste0("Proposed: working tree based on commit `", substr(git_commit("HEAD"), 1, 7), "`."),
    "PR checks use the proposed merge result; weekly refreshes use the freshly built files.",
    paste0("Baselines: `main` at `", substr(main$commit, 1, 7),
           "`; last published release `", release_tag, "` at `", substr(released$commit, 1, 7), "`."),
    "",
    # update-refresh-pr.sh uses the first bold line for the title against main.
    paste0("**", against_main$label, "**"), "",
    md_table(overview),
    if (against_main$label == "No changes") {
      c("No data changes introduced by this PR or refresh, ignoring access dates.", "")
    },
    "## Headline stats", "",
    md_table(bind_rows(quarters, stats)),
    details(main, "main", against_main, "Changes introduced by this PR or refresh"),
    if (same_baseline) {
      c("## Changes since the last release", "",
        "The release and main are the same commit. The comparison details above apply to both.", "")
    } else {
      details(released, release_tag, against_release, "Changes since the last release")
    }
  )
}

write_change_report = function(
  baseline, packages_ok, file, ...,
  release_baseline = Sys.getenv("PPG_RELEASE_BASELINE", "")
) {
  # `...` takes the final files only so the report runs after them
  # Resolve refs once so both views describe fixed snapshots throughout the run.
  baseline_commit = git_commit(baseline)
  release_commit = if (nzchar(release_baseline)) git_commit(release_baseline)
  old = read_snapshot(baseline_commit)
  new = read_snapshot()
  report = if (nzchar(release_baseline)) {
    released = read_snapshot(release_commit)
    build_dual_change_report(old, released, new, release_baseline, packages_ok)
  } else {
    build_change_report(old, new, baseline, packages_ok)
  }
  dir.create(dirname(file), showWarnings = FALSE, recursive = TRUE)
  writeLines(report, file)
  file
}
