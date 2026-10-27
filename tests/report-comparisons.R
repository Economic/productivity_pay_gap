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
  any(grepl("Proposed vs main.*No changes.*no", report)),
  any(grepl("Proposed vs release-fixture.*Revisions only.*yes", report)),
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
  any(grepl("Proposed vs main.*No changes", report)),
  any(grepl("Proposed vs release-fixture.*New quarter:", report)),
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
cat("Report comparison checks passed.\n")
