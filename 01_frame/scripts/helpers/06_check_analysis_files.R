# Independently check the saved CES, population cells and coverage audit.
# Run from the repository root: Rscript 01_frame/scripts/helpers/06_check_analysis_files.R
check_analysis_files <- function(data_dir = file.path("01_frame", "data")) {
  intermediate <- file.path(data_dir, "intermediate")
  output <- file.path(data_dir, "output")
  ces <- readRDS(file.path(intermediate, "ces_demographics_harmonized.rds"))
  analysis <- readRDS(file.path(intermediate, "ces_analysis.rds"))
  cells <- readRDS(file.path(intermediate, "pums_cd_cells.rds"))

  area <- c("STATEFP", "CDFP120")
  cell_key <- c(area, "age_cat", "gender_cat", "race_cat", "hispanic_cat", "educ_cat")
  analysis_fields <- c("caseid", "commonweight", cell_key, "house_vote_2024", "pres_vote_2024")
  stopifnot(
    "Unexpected CES analysis columns" = identical(names(analysis), analysis_fields),
    "Invalid detailed CES respondent IDs" =
      nrow(ces) > 0L && !anyNA(ces$caseid) && !anyDuplicated(ces$caseid),
    "Slim and detailed CES records differ" = all(vapply(analysis_fields, function(field) {
      identical(analysis[[field]], ces[[field]])
    }, logical(1)))
  )

  # The reviewed map has 435 voting districts and DC, identified by 11/98.
  districts <- unique(cells[area])
  stopifnot(
    "Invalid population cells" = identical(names(cells), c(cell_key, "N")) &&
      !anyNA(cells[cell_key]) && !vctrs::vec_duplicate_any(cells[cell_key]) &&
      all(is.finite(cells$N) & cells$N > 0),
    "Unexpected district coverage" = nrow(districts) == 436L &&
      identical(districts$CDFP120[districts$STATEFP == "11"], "98") &&
      any(ces$STATEFP == "11" & ces$CDFP120 == "98") &&
      !anyNA(vctrs::vec_match(ces[area], districts))
  )
  check_saved_state_weights(cells, file.path(output, "03_pums_allocation_by_state.csv"))
  audit_path <- file.path(output, "06_ces_pums_cell_coverage.csv")
  coverage <- check_saved_cell_coverage(ces, cells, cell_key, audit_path)
  check_saved_race_draws(ces, cells, cell_key, coverage$by_respondent)

  cat("Verified", nrow(analysis), "CES respondents and", ncol(analysis), "analysis columns.\n")
  cat("Verified", nrow(cells), "positive population cells across", nrow(districts),
      "districts including DC. Allocated CVAP:", format(sum(cells$N), scientific = FALSE), "\n")
  statuses <- c("matched_positive_N", "no_positive_pums_cell", "missing_ces_key")
  count_statuses <- function(x) tabulate(match(x, statuses), nbins = length(statuses))
  summary_by_status <- data.frame(
    coverage_status = statuses,
    respondents = count_statuses(coverage$by_respondent),
    distinct_profiles = count_statuses(coverage$by_profile)
  )
  print(summary_by_status, row.names = FALSE)
}

saved_weights_agree <- function(value, reference) {
  all(is.finite(value) & is.finite(reference) &
        abs(value - reference) <= 1e-12 * pmax(1, abs(reference)))
}

check_saved_state_weights <- function(cells, path) {
  states <- readr::read_csv(path, col_types = readr::cols_only(
    STATEFP = readr::col_character(),
    input_weight = readr::col_double(),
    allocated_weight = readr::col_double()
  ))
  readr::stop_for_problems(states)
  population_by_state <- tapply(cells$N, cells$STATEFP, sum)
  stopifnot(
    "State totals differ from Step 03" = nrow(states) == 51L &&
      !anyDuplicated(states$STATEFP) && setequal(states$STATEFP, names(population_by_state)) &&
      saved_weights_agree(population_by_state[states$STATEFP], states$input_weight) &&
      saved_weights_agree(population_by_state[states$STATEFP], states$allocated_weight)
  )
}

check_saved_cell_coverage <- function(ces, cells, cell_key, path) {
  audit <- readr::read_csv(path, col_types = readr::cols(
    .default = readr::col_character(),
    ces_respondents = readr::col_integer(),
    N = readr::col_double()
  ))
  readr::stop_for_problems(audit)
  # The audit has one row per distinct CES profile. Several respondents can share it.
  audit_row_for_respondent <- vctrs::vec_match(ces[cell_key], audit[cell_key])
  stopifnot(
    "Coverage audit differs from the saved CES profiles" =
      !vctrs::vec_duplicate_any(audit[cell_key]) && !anyNA(audit_row_for_respondent) &&
      all(audit$ces_respondents > 0L) &&
      identical(tabulate(audit_row_for_respondent, nbins = nrow(audit)), audit$ces_respondents)
  )

  # A complete profile with no population cell has N = 0. An incomplete
  # survey key leaves N unknown even if its reported demographic fields match.
  cell_row_for_profile <- vctrs::vec_match(audit[cell_key], cells[cell_key])
  missing_key <- !complete.cases(audit[cell_key])
  no_population <- !missing_key & is.na(cell_row_for_profile)
  status <- rep("matched_positive_N", nrow(audit))
  status[missing_key] <- "missing_ces_key"
  status[no_population] <- "no_positive_pums_cell"
  population <- cells$N[cell_row_for_profile]
  population[no_population] <- 0
  known <- !is.na(population)
  stopifnot(
    "Coverage status or population differs from the saved frame" =
      identical(status, audit$coverage_status) && identical(is.na(population), is.na(audit$N)) &&
      saved_weights_agree(population[known], audit$N[known])
  )
  list(by_profile = status, by_respondent = status[audit_row_for_respondent])
}

check_saved_race_draws <- function(ces, cells, cell_key, status_by_respondent) {
  stopifnot(
    "Missing or invalid race imputation flags" =
      all(c("race_imputed", "race_donor_level") %in% names(ces)) &&
      is.logical(ces$race_imputed) && !anyNA(ces$race_imputed)
  )
  recipient_rows <- which(ces$race_imputed)
  donor_level <- ces$race_donor_level[recipient_rows]

  # First look for any Hispanic population in the same district, age, gender
  # and education profile. If found, the drawn race must also have positive N.
  # Otherwise the respondent must have used a state or national donor pool.
  profile_without_race <- setdiff(cell_key, "race_cat")
  district_profiles <- unique(
    cells[cells$hispanic_cat == "Hispanic", profile_without_race, drop = FALSE]
  )
  recipient_profiles <- ces[recipient_rows, profile_without_race, drop = FALSE]
  has_district_donors <- !is.na(vctrs::vec_match(recipient_profiles, district_profiles))
  has_drawn_race <- status_by_respondent[recipient_rows] == "matched_positive_N"
  stopifnot(
    "Conditional race draws disagree with district population support" =
      all(ces$hispanic_cat[recipient_rows] == "Hispanic") &&
      all(donor_level %in% c("district", "state", "national")) &&
      all(has_district_donors == (donor_level == "district")) &&
      all(has_drawn_race == has_district_donors)
  )
}

if (sys.nframe() == 0L) check_analysis_files()
