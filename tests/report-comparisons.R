# Run from the repository root: Rscript tests/report-comparisons.R
# These fixtures alter in-memory snapshots only. No fetch or data write occurs.
source("packages.R")
for (file in c("document_data", "report_snapshot", "report_why", "report", "web")) {
  source(paste0("R/", file, ".R"))
}

base = read_snapshot(git_commit("HEAD"))
latest = last_quarter(index_inputs(base))

update_stats = function(snapshot) {
  file = tempfile(fileext = ".csv")
  on.exit(unlink(file))
  create_web_stats_csv(snapshot$web, file)
  snapshot$web_stats = read_csv(file, show_col_types = FALSE)
  snapshot
}

# Revise only the latest quarter's NDP and its productivity index. The exact
# attribution should identify NDP independently for each baseline.
revise_ndp = function(snapshot, factor, commit) {
  snapshot$commit = commit
  snapshot$bea_api = snapshot$bea_api |>
    mutate(value = if_else(
      frequency == "quarterly" & year == latest[1] & quarter == latest[2] & name == "nipa_ndp",
      value * factor, value
    ))
  snapshot$data = snapshot$data |>
    mutate(value = if_else(
      frequency == "quarterly" & year == latest[1] & quarter == latest[2] &
        name == "productivity_real_index_1948",
      value * factor, value
    ))
  productivity = snapshot$data |>
    filter(frequency == "quarterly", year == latest[1], quarter == latest[2],
           name == "productivity_real_index_1948") |>
    pull(value)
  snapshot$web$Productivity[nrow(snapshot$web)] = round(productivity, 1)
  update_stats(snapshot)
}

released = revise_ndp(base, 0.99, "released-fixture")
main = revise_ndp(base, 1.01, "main-fixture")
proposed = revise_ndp(base, 1.02, "proposed-fixture")
for (old in list(main, released)) {
  comparison = compare_snapshots(old, proposed)
  rows = comparison$revisions |>
    filter(index == "productivity", year == latest[1], quarter == latest[2])
  actual = first(rows$new - rows$old)
  stopifnot(
    comparison$web_visible,
    abs(sum(rows$points) - actual) < 1e-8,
    abs(sum(rows$points[rows$label == "NDP (BEA)"]) - actual) < 1e-8,
    all(abs(rows$points[rows$label != "NDP (BEA)"]) < 1e-8)
  )
}

report = build_dual_change_report(main, released, proposed, "release-fixture")
stopifnot(
  sum(grepl("^Compared with", report)) == 2,
  any(grepl("^Compared with `main`", report)),
  any(grepl("^Compared with `release-fixture`", report)),
  any(grepl("Statistic.*Last release.*main.*Proposed", report))
)

# A PR with no new data must still show all changes since the release.
report = build_dual_change_report(main, released, main, "release-fixture")
stopifnot(
  any(grepl("No data changes introduced", report, fixed = TRUE)),
  any(grepl("Proposed vs main.*No output changes", report)),
  any(grepl("Proposed vs release-fixture.*existing values revised", report)),
  !any(grepl("Web-visible changes", report, fixed = TRUE)),
  sum(grepl("^Compared with", report)) == 2
)

# Access dates do not become data changes. Different baseline commits retain
# their own details even when their outputs match.
access_only = main
access_only$sources$date_accessed = access_only$sources$date_accessed + 1
stopifnot(compare_snapshots(main, access_only)$label == "No changes")
other_commit = main
other_commit$commit = "other-fixture"
other_commit$packages$version[1] = "test-version"
report = build_dual_change_report(main, other_commit, main, "release-fixture")
stopifnot(sum(grepl("^Compared with", report)) == 2, any(grepl("test-version", report)))

# Only identical baseline commits share their details.
report = build_dual_change_report(main, main, proposed, "release-fixture")
stopifnot(
  sum(grepl("^Compared with", report)) == 1,
  any(grepl("same commit", report, fixed = TRUE))
)

# New periods are release changes even when they are already on main.
earlier = released
earlier$web = slice_head(earlier$web, n = nrow(earlier$web) - 1)
earlier$data = earlier$data |>
  filter(!(frequency == "quarterly" & year == latest[1] & quarter == latest[2]))
earlier = update_stats(earlier)
report = build_dual_change_report(main, earlier, main, "release-fixture")
stopifnot(
  any(grepl("Proposed vs main.*No output changes", report)),
  any(grepl("Proposed vs release-fixture.*quarters added:", report)),
  any(grepl("Added quarters", report, fixed = TRUE))
)

# The local/release single-baseline path stays available. Missing release
# metadata must fail visibly rather than quietly omit the second comparison.
single = build_change_report(base, base, "HEAD")
stopifnot(single[1] == "# Change report", !any(single == "<details>"))
file = tempfile(fileext = ".md")
problem = tryCatch(
  write_change_report("HEAD", TRUE, file, release_baseline = "missing-release-fixture"),
  error = identity
)
stopifnot(inherits(problem, "error"), !file.exists(file))

# Output descriptions distinguish new files from existing value revisions.
# The real release has no counterfactual file or its two full-data series.
before_counter = base
before_counter$commit = "before-counter-fixture"
before_counter$counter_web = NULL
before_counter$data = filter(before_counter$data, !name %in% c("wage_actual_real", "wage_counter_real"))
report = build_dual_change_report(base, before_counter, base, "release-fixture")
description = compare_snapshots(before_counter, base)$output_description
stopifnot(
  compare_snapshots(base, base)$output_description == "No output changes.",
  compare_snapshots(main, access_only)$output_description == "No output changes.",
  grepl("wage file added", description, fixed = TRUE),
  grepl("series added: wage_actual_real, wage_counter_real", description, fixed = TRUE),
  grepl("Existing published productivity, pay, and headline values unchanged", description, fixed = TRUE),
  !grepl("existing values revised", description, fixed = TRUE),
  sum(grepl(description, report, fixed = TRUE)) == 2,
  any(grepl("Proposed vs main.*No output changes", report))
)

# A file addition must not hide a simultaneous revision or headline change.
report = build_change_report(before_counter, proposed, "HEAD")
description = compare_snapshots(before_counter, proposed)$output_description
stopifnot(
  grepl("wage file added", description, fixed = TRUE),
  grepl("Productivity and pay: existing values revised", description, fixed = TRUE),
  grepl("Published headline statistics changed", description, fixed = TRUE),
  !grepl("productivity, pay, and headline values unchanged", description, fixed = TRUE),
  any(grepl(paste0("- Output changes: ", description), report, fixed = TRUE))
)

# Added or removed periods and revisions can appear in the same comparison.
period_revision = main
period_revision$web$Productivity[nrow(earlier$web)] = period_revision$web$Productivity[nrow(earlier$web)] + 1
for (pair in list(list(earlier, period_revision), list(period_revision, earlier))) {
  description = compare_snapshots(pair[[1]], pair[[2]])$output_description
  direction = if (nrow(pair[[1]]$web) < nrow(pair[[2]]$web)) "added" else "removed"
  stopifnot(
    grepl(paste0("quarters ", direction, ":"), description, fixed = TRUE),
    grepl("existing values revised", description, fixed = TRUE)
  )
}

# Counterfactual revisions and removals also get their own descriptions.
wages_changed = base
wages_changed$counter_web$`Counterfactual wage`[1] = wages_changed$counter_web$`Counterfactual wage`[1] + 1
description = compare_snapshots(base, wages_changed)$output_description
stopifnot(
  grepl("Actual and counterfactual wage: existing values revised", description, fixed = TRUE),
  grepl("Existing published productivity, pay, and headline values unchanged", description, fixed = TRUE)
)
report = build_change_report(base, before_counter, "HEAD")
stopifnot(
  any(grepl("wage file removed", report, fixed = TRUE)),
  any(grepl("series removed: wage_actual_real, wage_counter_real", report, fixed = TRUE))
)

# Changes below web rounding and stats-only edits must still be reported.
unrounded = base
unrounded$data$value[1] = unrounded$data$value[1] * 1.001
description = compare_snapshots(base, unrounded)$output_description
stopifnot(
  grepl("Full data: 1 existing value revised", description, fixed = TRUE),
  grepl("Existing published productivity, pay, and headline values unchanged", description, fixed = TRUE)
)
stats_only = base
stats_only$web_stats$value[1] = "99.9%"
description = compare_snapshots(base, stats_only)$output_description
stopifnot(
  grepl("Published headline statistics changed", description, fixed = TRUE),
  grepl("Existing published productivity and pay values unchanged", description, fixed = TRUE)
)

# A web series addition/removal is distinct from revisions to common values.
extra_series = base
extra_series$counter_web$`Extra wage series` = extra_series$counter_web$`Actual wage`
for (pair in list(list(base, extra_series), list(extra_series, base))) {
  description = compare_snapshots(pair[[1]], pair[[2]])$output_description
  direction = if (ncol(pair[[1]]$counter_web) < ncol(pair[[2]]$counter_web)) "added" else "removed"
  stopifnot(
    grepl(paste0("series ", direction, ": Extra wage series"), description, fixed = TRUE),
    !grepl("existing values revised", description, fixed = TRUE)
  )
}

# Reordering headline rows does not create a change; source documentation does.
reordered = base
reordered$web_stats = slice(reordered$web_stats, n():1)
stopifnot(compare_snapshots(base, reordered)$output_description == "No output changes.")
source_only = base
source_only$sources$date_published[1] = as.Date("2026-10-28")
stopifnot(grepl("Source documentation changed", compare_snapshots(base, source_only)$output_description, fixed = TRUE))

# The Why section uses the same complete input layout for index levels and
# growth stats. Unchanged inputs remain visible, and unused inputs get a dash.
comparison = compare_snapshots(main, proposed)
latest_revisions = comparison$revisions |> slice_max(year * 4 + quarter, n = 1)
table = why_index_table(latest_revisions)
cell = function(table, label, index) {
  table[[index]][match(label, table$`Measure or contribution`)]
}
stopifnot(
  cell(table, "Hours (BLS)", "Productivity") == "+0.000",
  cell(table, "Hours (BLS)", "Pay") == "\u2014",
  cell(table, "Production/nonsupervisory wages (BLS)", "Pay") == "+0.000",
  cell(table, "CPI", "Productivity") == "+0.000",
  cell(table, "CPI", "Pay") == "+0.000"
)

# Signed averages use each index's own revised-quarter population. Opposing
# effects cancel, and unchanged quarters do not dilute the average.
fixture = expand_grid(year = 2020, quarter = 1:3) |>
  cross_join(distinct(index_terms, index, label)) |>
  mutate(
    old = 100,
    new = case_when(
      index == "productivity" & quarter == 1 ~ 103,
      index == "productivity" & quarter == 2 ~ 99,
      index == "pay" & quarter == 2 ~ 98,
      .default = 100
    ),
    points = case_when(
      label == "NDP (BEA)" & quarter == 1 ~ 5,
      label == "NDP (BEA)" & quarter == 2 ~ -1,
      label == "Hours (BLS)" & quarter == 1 ~ -2,
      label == "Compensation (BEA)" & quarter == 2 ~ 1,
      label == "NIPA wages (BEA)" & quarter == 2 ~ -3,
      .default = 0
    ),
    log_contribution = 0
  )
table = why_index_table(fixture, average = TRUE)
stopifnot(
  cell(table, "NDP (BEA)", "Productivity") == "+2.000",
  cell(table, "Hours (BLS)", "Productivity") == "-1.000",
  cell(table, "**Net revision**", "Productivity") == "**+1.000**",
  cell(table, "NIPA compensation", "Pay") == "+1.000",
  cell(table, "NIPA wages", "Pay") == "-3.000",
  cell(table, "**Net revision**", "Pay") == "**-2.000**"
)
unchanged = compare_snapshots(base, base)
table = why_index_table(unchanged$revisions, average = TRUE)
stopifnot(cell(table, "CPI", "Pay") == "n/a")
table = why_index_table(comparison$revisions, average = TRUE)
stopifnot(cell(table, "CPI", "Pay") == "n/a", cell(table, "CPI", "Productivity") == "+0.000")

# Headline totals include rounding and moving endpoints. Calculation changes
# retain their own row and warning, even if other inputs are unchanged.
for (pair in list(list(earlier, main), list(main, earlier))) {
  stats = headline_stat_revisions(pair[[1]], pair[[2]], index_inputs(pair[[1]]), index_inputs(pair[[2]]))
  effect = if (nrow(pair[[1]]$web) < nrow(pair[[2]]$web)) "Added quarters" else "Removed quarters"
  for (stat_name in unique(stats$stat)) {
    rows = filter(stats, stat == stat_name)
    table = why_stat_table(rows, if (stat_name != "growth_1948_1979") effect else character())
    for (index_name in c("productivity", "pay")) {
      values = filter(rows, index == index_name)
      expected = first(parse_number(values$text_new) - parse_number(values$text_old))
      stopifnot(abs(sum(values$points) - expected) < 1e-8)
      column = str_to_sentence(index_name)
      displayed = parse_number(cell(table, "**Net revision**", column))
      stopifnot(abs(displayed - expected) < 0.00005)
    }
    stopifnot("Rounding" %in% table$`Measure or contribution`)
    if (stat_name != "growth_1948_1979") stopifnot(effect %in% table$`Measure or contribution`)
  }
}
method_new = base
method_new$data = method_new$data |>
  mutate(value = if_else(
    name == "productivity_real_index_1948" & year == latest[1] & quarter == latest[2],
    value * 1.01, value
  ))
method = compare_snapshots(base, method_new)
stopifnot(method_change_label %in% why_index_table(method$revisions |> slice_max(year * 4 + quarter, n = 1))$`Measure or contribution`)
report = build_change_report(base, method_new, "HEAD")
stopifnot(any(grepl("the calculation itself changed", report, fixed = TRUE)))
report = build_change_report(base, base, "HEAD")
stopifnot(
  !any(grepl("### Base period", report, fixed = TRUE)),
  !any(grepl("Share of the absolute revisions", report, fixed = TRUE)),
  sum(grepl("^#### (Total growth|Average annual growth)", report)) == 3,
  any(grepl("as much as pay.*[0-9]x → [0-9].*x$", report)),
  !any(grepl("not split; it follows", report, fixed = TRUE))
)
cat("Report comparison checks passed.\n")
