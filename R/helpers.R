create_csv <- function(data, file) {
  write_csv(data, file)
  file
}

tar_target_date <- function(name, command, ...) {
  name_str <- deparse(substitute(name))
  command_expr <- substitute(command)

  main_target <- tar_target_raw(
    name = name_str,
    command = command_expr,
    ...
  )

  date_name <- paste0(name_str, "_date")
  date_command <- bquote({
    force(.(as.name(name_str)))
    Sys.Date()
  })

  date_target <- tar_target_raw(
    name = date_name,
    command = date_command
  )

  list(main_target, date_target)
}

tar_api <- function(name, command, age = as.difftime(1, units = "days"), ...) {
  name_str <- deparse(substitute(name))
  command_expr <- substitute(command)

  cue <- tarchetypes::tar_cue_age_raw(name = name_str, age = age)

  main_target <- tar_target_raw(
    name = name_str,
    command = command_expr,
    cue = cue,
    ...
  )

  date_name <- paste0(name_str, "_date")
  date_command <- bquote({
    force(.(as.name(name_str)))
    Sys.Date()
  })

  date_target <- tar_target_raw(
    name = date_name,
    command = date_command
  )

  list(main_target, date_target)
}

collect_source_dates <- function(...) {
  target_names <- as.character(match.call(expand.dots = FALSE)$...)
  target_names <- sub("_date$", "", target_names)
  tibble(
    name = target_names,
    time = c(...)
  )
}
