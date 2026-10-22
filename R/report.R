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

web_changes = function(old, new) {
  longer = function(web) pivot_longer(web, -Year, names_to = "Series")
  inner_join(longer(old$web), longer(new$web), by = c("Year", "Series"), suffix = c("_old", "_new")) |>
    filter(value_old != value_new) |>
    mutate(change = value_new - value_old) |>
    arrange(desc(abs(change)), Year)
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

# Lines describing the contributions, largest first, skipping tiny ones
contribution_text = function(contributions, digits = 3) {
  shown = contributions |>
    filter(
      abs(points) >= 0.5 * 10^-digits,
      !is_method_change(label) | abs(log_contribution) > method_change_threshold
    ) |>
    arrange(desc(abs(points)))
  if (nrow(shown) == 0) {
    return("no input changed it")
  }
  paste(paste(shown$label, signed(shown$points, digits)), collapse = ", ")
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
    return("Web stats changed, web data unchanged")
  }
  if (final_files_differ) "No web-visible changes" else "No changes"
}

# The report as a character vector of Markdown lines. `old` and `new` come from
# read_snapshot(); `baseline` names old's ref.
build_change_report = function(old, new, baseline, packages_ok = TRUE) {
  old_inputs = index_inputs(old)
  new_inputs = index_inputs(new)
  code_files = changed_code_files(old$ref, new$ref)

  # Code changes that alter an input are split from its data revisions by
  # processing the baseline's raw data with the current code. Only possible
  # for the working tree, where the loaded code is the current code; for CPI,
  # only when realtalk didn't change, since only the installed version exists.
  working_tree = is.null(new$ref)
  realtalk_version = function(snapshot) {
    snapshot$packages$version[snapshot$packages$package == "realtalk"]
  }
  same_realtalk = identical(realtalk_version(old), realtalk_version(new))
  # an old baseline's raw files can predate the current code's format
  recleaned_bls = if ("R/bls.R" %in% code_files && working_tree) {
    tryCatch(recleaned_bls_inputs(old$ref), error = \(e) NULL)
  }
  split_bls = !is.null(recleaned_bls)
  split_prices = "R/prices.R" %in% code_files && working_tree && same_realtalk
  recleaned = bind_rows(
    recleaned_bls,
    if (split_prices) recleaned_prices()
  )
  code_revisions = if (nrow(recleaned) > 0) {
    log_revisions(filter(old_inputs, series %in% recleaned$series), recleaned)
  }
  # changed files that shape what an input contains, whose effect can't be
  # separated from the data: they decide what is fetched, or couldn't be split
  unsplit_code = c(
    intersect(
      code_files,
      c("R/bea.R", "data_inputs/bea_series_codes.csv", "data_inputs/bls_series_codes.csv")
    ),
    if ("R/bls.R" %in% code_files && !split_bls) "R/bls.R",
    if ("R/prices.R" %in% code_files && !split_prices) "R/prices.R"
  )

  revisions = index_revisions(old_inputs, new_inputs, code_revisions)
  stat_revisions = headline_stat_revisions(old, new, old_inputs, new_inputs, code_revisions)
  web_revisions = web_changes(old, new)
  # web data that is, or stopped being, other than the indexes rounded to one
  # decimal. Compared with the baseline, so a rounding change is flagged once.
  old_mismatches = web_data_mismatches(old)
  new_mismatches = web_data_mismatches(new)
  web_mismatches = bind_rows(
    anti_join(new_mismatches, old_mismatches, by = c("Year", "Series")),
    anti_join(old_mismatches, new_mismatches, by = c("Year", "Series"))
  )
  data_changes = full_data_changes(old, new)
  sources_differ = !same_contents(
    select(old$sources, -date_accessed),
    select(new$sources, -date_accessed)
  )
  # the rule for notifying me: the web data or web stats file changed
  web_visible = !same_contents(old$web, new$web) ||
    !same_contents(old$web_stats, new$web_stats)
  final_files_differ = web_visible || nrow(data_changes) > 0 || sources_differ
  label = change_label(
    old,
    new,
    web_revisions,
    revisions,
    web_visible,
    final_files_differ
  )

  latest_old = last(old$web$Year)
  latest_new = last(new$web$Year)
  unreleased = if (!is.null(old$ref)) unreleased_changes(old$ref)

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
    paste0("- Web-visible changes: ", if_else(web_visible, "yes", "no")),
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
  input_lines = c(
    "## Inputs",
    "",
    "### Sources",
    "",
    md_table(input_changes(old, new)),
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
    if (nrow(web_mismatches) > 0) {
      c(
        paste0(
          "**In ", n_distinct(web_mismatches$Year), " quarters, the web data changed from or to ",
          "being the indexes rounded to one decimal: ", web_method_change_label, ".**"
        ),
        ""
      )
    },
    "### Full data file",
    "",
    if (nrow(data_changes) > 0) md_table(data_changes) else c("No values changed.", "")
  )

  # ---- why ----
  common_last = revisions |> slice_max(year * 4 + quarter, n = 1)
  common_period = quarter_label(common_last$year[1], common_last$quarter[1])
  index_sentence = function(index_name) {
    rows = filter(common_last, index == index_name)
    change = rows$new[1] - rows$old[1]
    if (!revised(rows$old[1], rows$new[1])) {
      return(paste0("- The ", index_name, " index for ", common_period, " is unchanged."))
    }
    paste0(
      "- The ", index_name, " index for ", common_period, " was revised from ",
      sprintf("%.3f", rows$old[1]), " to ", sprintf("%.3f", rows$new[1]),
      " (", signed(change), " points): ", contribution_text(rows), "."
    )
  }
  across_quarters = function(index_name) {
    revised_rows = revisions |> filter(index == index_name, revised(old, new))
    if (nrow(revised_rows) == 0) {
      return(paste0("- ", str_to_sentence(index_name), ": no quarter revised."))
    }
    periods = revised_rows |> distinct(year, quarter) |> arrange(year, quarter)
    shares = revised_rows |>
      filter(!is_method_change(label) | abs(log_contribution) > method_change_threshold) |>
      summarize(absolute = sum(abs(points)), .by = label) |>
      mutate(share = absolute / sum(absolute)) |>
      filter(share >= 0.005) |>
      arrange(desc(share))
    paste0(
      "- ", str_to_sentence(index_name), ": ", nrow(periods), " quarters revised (",
      quarter_label(periods$year[1], periods$quarter[1]), " to ",
      quarter_label(last(periods$year), last(periods$quarter)),
      "). Share of the absolute revisions: ",
      paste(paste0(shares$label, " ", round(100 * shares$share), "%"), collapse = ", "),
      "."
    )
  }
  base_revisions = base_period_revisions(old_inputs, new_inputs)
  ratio = filter(stats, stat == "ratio")
  ratio_method_change = (ratio$value_new - expected_published_ratio(new$web)) -
    (ratio$value_old - expected_published_ratio(old$web))
  method_changes = c(
    revisions |> filter(is_method_change(label), abs(log_contribution) > method_change_threshold) |> nrow(),
    stat_revisions |> filter(is_method_change(label), abs(log_contribution) > method_change_threshold) |> nrow(),
    nrow(web_mismatches),
    abs(ratio_method_change) > method_change_threshold
  )
  # rows too small to show at four decimals are dropped, and a total row shows
  # that the rest add up to the published change
  shown_stat_rows = stat_revisions |>
    filter(abs(points) >= 0.00005 | label == "Rounding") |>
    filter(!is_method_change(label) | abs(log_contribution) > method_change_threshold)
  stat_tables = distinct(stat_revisions, stat, index) |>
    pmap(\(stat, index) {
      all_rows = stat_revisions[stat_revisions$stat == stat & stat_revisions$index == index, ]
      rows = shown_stat_rows[shown_stat_rows$stat == stat & shown_stat_rows$index == index, ] |>
        bind_rows(tibble(label = "Total", points = sum(all_rows$points)))
      c(
        paste0(
          "**", rows$name[1], "**: ",
          before_after(rows$text_old[1], rows$text_new[1]),
          " (unrounded: ", sprintf("%.3f", rows$unrounded_old[1]), " → ",
          sprintf("%.3f", rows$unrounded_new[1]), ")"
        ),
        "",
        md_table(transmute(rows, Contribution = label, `Percentage points` = signed(points, 4)))
      )
    }) |>
    unlist()
  why_lines = c(
    "## Why",
    "",
    paste0("### Index revisions in ", common_period, ", the latest quarter in both"),
    "",
    index_sentence("productivity"),
    index_sentence("pay"),
    "",
    if (sum(method_changes) > 0) {
      c(
        paste0(
          "**The inputs don't explain all of the changes: the calculation itself changed.** ",
          "See the \"", method_change_label, "\" lines, and the code changes under Inputs."
        ),
        ""
      )
    },
    if (length(unsplit_code) > 0) {
      c(
        paste0(
          "**These changed files shape what an input contains, and the report can't separate ",
          "their effect from data revisions: ", paste0("`", unsplit_code, "`", collapse = ", "),
          ". The contributions of the inputs they shape may include a change in method.**"
        ),
        ""
      )
    },
    "### Base period (1948q1)",
    "",
    if (nrow(base_revisions) > 0) {
      c(
        "Revisions to 1948q1 inputs move every quarter of an index:",
        "",
        md_table(transmute(base_revisions, Input = label, `Revision (%)` = signed(percent, 4)))
      )
    } else {
      c("No 1948q1 input was revised.", "")
    },
    "### Across all revised quarters",
    "",
    across_quarters("productivity"),
    across_quarters("pay"),
    "",
    "### Headline stats",
    "",
    paste0(
      "Each stat's revision split by input, from the unrounded indexes. ",
      "\"Rounding\" is the extra change in the published stats, which are ",
      "computed from indexes rounded to one decimal."
    ),
    "",
    stat_tables,
    paste0(
      "**", ratio$name_new, "**: ", before_after(ratio$text_old, ratio$text_new),
      " (not split; it follows from the two total growth stats).",
      if (abs(ratio_method_change) > method_change_threshold) {
        paste0(" ", web_method_change_label, ": ", signed(ratio_method_change, 1), ".")
      }
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

write_change_report = function(baseline, packages_ok, file, ...) {
  # `...` takes the final files only so the report runs after them
  report = build_change_report(
    old = read_snapshot(baseline),
    new = read_snapshot(),
    baseline = baseline,
    packages_ok = packages_ok
  )
  dir.create(dirname(file), showWarnings = FALSE, recursive = TRUE)
  writeLines(report, file)
  file
}
