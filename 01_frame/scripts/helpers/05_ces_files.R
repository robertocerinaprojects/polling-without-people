# File access for 05_prepare_ces.R. The driver specifies the CES release and
# names the products. Only an absent source CSV triggers a download.
get_ces_release <- function(path, url, expected_md5) {
  verify_release <- function(file) {
    if (!identical(unname(tools::md5sum(file)), expected_md5)) {
      stop("Unexpected CES source checksum: ", file, call. = FALSE)
    }
  }

  if (file.exists(path)) {
    verify_release(path)
    message("Reusing verified CES source: ", path)
    return(invisible(path))
  }

  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  temporary <- tempfile(".ces-download-", tmpdir = dirname(path))
  on.exit(unlink(temporary), add = TRUE)
  old_options <- options(timeout = max(600L, getOption("timeout")))
  on.exit(options(old_options), add = TRUE)
  status <- utils::download.file(url, temporary, mode = "wb")
  if (status != 0L) stop("CES download failed.", call. = FALSE)
  verify_release(temporary)
  if (!file.rename(temporary, path)) stop("Could not save ", path, call. = FALSE)
  invisible(path)
}

read_ces_respondents <- function(path) {
  types <- readr::cols_only(
    caseid = readr::col_character(),
    birthyr = readr::col_integer(),
    gender4 = readr::col_integer(),
    educ = readr::col_integer(),
    race = readr::col_integer(),
    hispanic = readr::col_integer(),
    commonweight = readr::col_double(),
    cit1 = readr::col_integer(),
    inputstate = readr::col_integer(),
    cdid119 = readr::col_integer(),
    countyfips = readr::col_integer()
  )
  # The vote decoder lists the pre/post answers and the five party labels
  # shown on the respondent's House ballot in each wave.
  types$cols <- c(types$cols, vote_input_types())
  respondents <- readr::read_csv(path, col_types = types, lazy = FALSE, progress = FALSE)
  readr::stop_for_problems(respondents)

  # The pinned Dataverse release has 60,000 respondents, each with one caseid.
  stopifnot(
    setequal(names(respondents), names(types$cols)),
    nrow(respondents) == 60000L,
    !anyNA(respondents$caseid), all(nzchar(respondents$caseid)),
    !anyDuplicated(respondents$caseid),
    all(is.finite(respondents$commonweight) & respondents$commonweight >= 0),
    all(is.na(respondents$cit1) | respondents$cit1 %in% 1:2)
  )
  respondents
}

run_input_helper <- function(command, script_path) {
  status <- system2(command, shQuote(script_path))
  if (status != 0L) {
    stop("Failed to prepare conditional race inputs: ", basename(script_path), call. = FALSE)
  }
}

read_ces_district_lookup <- function(path) {
  lookup <- readr::read_csv(
    path,
    col_types = readr::cols_only(
      STATEFP = readr::col_character(),
      CD119 = readr::col_character(),
      county_fips = readr::col_character(),
      CD120 = readr::col_character(),
      district_probability = readr::col_double(),
      geography_method = readr::col_character()
    ),
    na = c("", "NA"), progress = FALSE
  )
  readr::stop_for_problems(lookup)
  lookup
}

# Finish writing each product beside its destination before replacing that file.
publish_ces_file <- function(path, writer, object) {
  temporary <- tempfile(".ces-", tmpdir = dirname(path))
  on.exit(unlink(temporary), add = TRUE)
  writer(object, temporary)
  if (!file.rename(temporary, path)) stop("Could not publish ", path, call. = FALSE)
}
