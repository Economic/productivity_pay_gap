source("renv/activate.R")

# Prefer prebuilt binaries on Linux; Posit PM and r-universe both serve them
# from platform-specific paths there, while macOS/Windows get binaries from
# the plain URLs automatically.
local({
  os_release = function(field) {
    path = "/etc/os-release"
    if (!file.exists(path)) return(NA_character_)
    hit = grep(paste0("^", field, "="), readLines(path, warn = FALSE), value = TRUE)
    if (!length(hit)) return(NA_character_)
    gsub('"', "", sub(paste0("^", field, "="), "", hit[[1]]))
  }

  # codenames with binaries published by Posit PM and r-universe
  supported = c("focal", "jammy", "noble", "bookworm", "bullseye")
  codename = os_release("VERSION_CODENAME")
  linux_binary = Sys.info()[["sysname"]] == "Linux" &&
    !is.na(codename) && codename %in% supported

  repos = if (linux_binary) {
    r_minor = paste(R.version$major,
                    strsplit(R.version$minor, ".", fixed = TRUE)[[1]][[1]],
                    sep = ".")
    c(
      economic = sprintf("https://economic.r-universe.dev/bin/linux/%s-%s/%s",
                         codename, R.version$arch, r_minor),
      CRAN = sprintf("https://packagemanager.posit.co/cran/__linux__/%s/latest",
                     codename)
    )
  } else {
    c(
      economic = "https://economic.r-universe.dev",
      CRAN = "https://packagemanager.posit.co/cran/latest"
    )
  }

  options(repos = repos)
})
