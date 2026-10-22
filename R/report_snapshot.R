# Reading the committed files, at a git ref or in the working tree, for the
# change report. Before Phase 1 (every release through v2026.9.14), the final
# files sat in release/ and the fetched files in data_outputs/ and data_inputs/.

snapshot_files = list(
  data = c(
    "data_final/epi_productivity_pay_gap.csv",
    "release/epi_productivity_pay_gap.csv"
  ),
  web = c(
    "data_final/epi_productivity_pay_gap_web.csv",
    "release/epi_productivity_pay_gap_web.csv"
  ),
  web_stats = c(
    "data_final/epi_productivity_pay_gap_web_stats.csv",
    "release/epi_productivity_pay_gap_web_stats.csv"
  ),
  sources = c(
    "data_final/epi_productivity_pay_gap_sources.csv",
    "release/epi_productivity_pay_gap_sources.csv"
  ),
  bls_api = c("data_raw/bls_api_output.csv", "data_outputs/bls_api_output.csv"),
  bea_api = c("data_raw/bea_api_output.csv", "data_outputs/bea_api_output.csv"),
  bls_pay = "data_outputs/bls_pay.csv",
  bls_hours = "data_outputs/bls_hours.csv",
  prices = "data_outputs/prices.csv"
)

# system2() runs git through the shell, so every argument is quoted: a ref
# can come from PPG_BASELINE and contain shell characters
git_args = function(...) {
  shQuote(c(...))
}

# Output lines of a git command; empty if it fails (for example, no tag found)
git_lines = function(...) {
  suppressWarnings(system2("git", git_args(...), stdout = TRUE, stderr = FALSE))
}

git_succeeds = function(...) {
  system2("git", git_args(...), stdout = FALSE, stderr = FALSE) == 0
}

git_commit = function(ref) {
  if (!git_succeeds("rev-parse", "--verify", "--quiet", paste0(ref, "^{commit}"))) {
    stop("The git ref '", ref, "' doesn't exist. Run `git fetch`, or set PPG_BASELINE.")
  }
  git_lines("rev-parse", paste0(ref, "^{commit}"))
}

snapshot_has_file = function(ref, path) {
  if (is.null(ref)) {
    return(file.exists(path))
  }
  git_succeeds("cat-file", "-e", paste0(ref, ":", path))
}

# The first of `paths` that exists at `ref` (NULL means the working tree)
locate_file = function(ref, paths) {
  exists = map_lgl(paths, \(path) snapshot_has_file(ref, path))
  if (!any(exists)) {
    stop("None of ", paste(paths, collapse = ", "), " exists at ", ref %||% "the working tree")
  }
  paths[exists][1]
}

# Whether two data frames have the same contents. Compares column by column:
# readr attaches attributes that differ on every read, and as.list() keeps them.
same_contents = function(a, b) {
  identical(names(a), names(b)) && all(map2_lgl(a, b, identical))
}

read_snapshot_csv = function(ref, paths) {
  path = locate_file(ref, paths)
  if (is.null(ref)) {
    return(read_csv(path, show_col_types = FALSE))
  }
  read_csv(I(git_lines("show", paste0(ref, ":", path))), show_col_types = FALSE)
}

# Copies a file at `ref` to a temporary file and returns its path
snapshot_file_path = function(ref, paths) {
  path = locate_file(ref, paths)
  if (is.null(ref)) {
    return(path)
  }
  temp_file = tempfile(fileext = paste0(".", tools::file_ext(path)))
  system2("git", git_args("show", paste0(ref, ":", path)), stdout = temp_file)
  temp_file
}

read_snapshot_packages = function(ref) {
  lockfile = renv::lockfile_read(snapshot_file_path(ref, "renv.lock"))
  tibble(
    package = c("R", names(lockfile$Packages)),
    version = c(lockfile$R$Version, map_chr(lockfile$Packages, "Version"))
  )
}

read_snapshot = function(ref = NULL) {
  has_fetch_log = snapshot_has_file(ref, "data_raw/fetch_log.csv")
  files = map(snapshot_files, \(paths) read_snapshot_csv(ref, paths))
  # the BLS API results took their current form in v2026.3.11, the first
  # release with renv.lock too
  if (!"date" %in% names(files$bls_api)) {
    stop(
      "The change report reads releases from v2026.3.11 on; ", ref,
      " stores the BLS API results in an older format."
    )
  }

  c(
    files,
    list(
      ref = ref,
      commit = if (!is.null(ref)) git_commit(ref),
      packages = read_snapshot_packages(ref),
      fetch_log = if (has_fetch_log) {
        read_fetch_log(snapshot_file_path(ref, "data_raw/fetch_log.csv"))
      }
    )
  )
}

# Changed code and static inputs between two refs (new_ref NULL: the working
# tree, including untracked files)
changed_code_files = function(old_ref, new_ref = NULL) {
  code_paths = c("R", "_targets.R", "_targets.yaml", "packages.R", "data_inputs")
  changed = git_lines("diff", "--name-only", old_ref, new_ref, "--", code_paths)
  if (is.null(new_ref)) {
    changed = c(
      changed,
      git_lines("ls-files", "--others", "--exclude-standard", "--", code_paths)
    )
  }
  # before Phase 1 the hours spreadsheet sat in data_inputs/, but it's data
  setdiff(sort(unique(changed)), "data_inputs/total-economy-hours-employment.xlsx")
}

# The final files at `ref` that differ from the latest release reachable from
# it, ignoring access dates, which change with every fetch
unreleased_changes = function(ref) {
  tag = git_lines("describe", "--tags", "--abbrev=0", "--match", "v*", ref)
  if (length(tag) == 0 || git_commit(tag) == git_commit(ref)) {
    return(NULL)
  }

  final_files = c("data", "web", "web_stats", "sources")
  differs = map_lgl(final_files, \(file) {
    current = read_snapshot_csv(ref, snapshot_files[[file]])
    released = read_snapshot_csv(tag, snapshot_files[[file]])
    if (file == "sources") {
      current = select(current, -date_accessed)
      released = select(released, -date_accessed)
    }
    !same_contents(current, released)
  })

  list(
    tag = tag,
    files = basename(map_chr(snapshot_files[final_files[differs]], 1))
  )
}
