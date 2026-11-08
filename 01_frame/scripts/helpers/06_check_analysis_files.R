# Check the saved CES and population frame from the repository root:
# Rscript 01_frame/scripts/helpers/06_check_analysis_files.R
check_analysis_files <- function(data_dir = file.path("01_frame", "data")) {
  intermediate <- file.path(data_dir, "intermediate")
  output <- file.path(data_dir, "output")
  ces <- readRDS(file.path(intermediate, "ces_demographics_harmonized.rds"))
  slim <- readRDS(file.path(intermediate, "ces_analysis.rds"))
  frame <- readRDS(file.path(intermediate, "pums_cd_cells.rds"))
  area <- c("STATEFP", "CDFP120")
  keys <- c(area, "age_cat", "gender_cat", "race_cat", "hispanic_cat", "educ_cat")
  fields <- c("caseid", "commonweight", keys, "house_vote_2024", "pres_vote_2024")
  stopifnot("Unexpected CES analysis columns" = identical(names(slim), fields),
            "Invalid detailed CES respondent IDs" = nrow(ces) > 0L &&
              !anyNA(ces$caseid) && !anyDuplicated(ces$caseid),
            "Slim and detailed CES records differ" =
              all(vapply(fields, function(x) identical(slim[[x]], ces[[x]]), logical(1))))

  districts <- unique(frame[area])
  stopifnot("Invalid population cells" = identical(names(frame), c(keys, "N")) &&
              !anyNA(frame[keys]) && !vctrs::vec_duplicate_any(frame[keys]) &&
              all(is.finite(frame$N) & frame$N > 0),
            # The reviewed 120th Congress map has 435 voting districts plus DC.
            "Unexpected district coverage" = nrow(districts) == 436L &&
              identical(districts$CDFP120[districts$STATEFP == "11"], "98") &&
              any(ces$STATEFP == "11" & ces$CDFP120 == "98") &&
              !anyNA(vctrs::vec_match(ces[area], districts)))

  states <- readr::read_csv(file.path(output, "03_pums_allocation_by_state.csv"),
    col_types = readr::cols_only(STATEFP = readr::col_character(),
      input_weight = readr::col_double(), allocated_weight = readr::col_double()))
  readr::stop_for_problems(states)
  totals <- tapply(frame$N, frame$STATEFP, sum)
  close_weight <- function(value, reference) {
    all(is.finite(value) & is.finite(reference) &
          abs(value - reference) <= 1e-12 * pmax(1, abs(reference)))
  }
  stopifnot("State totals differ from Step 03" = nrow(states) == 51L &&
              !anyDuplicated(states$STATEFP) && setequal(states$STATEFP, names(totals)) &&
              close_weight(totals[states$STATEFP], states$input_weight) &&
              close_weight(totals[states$STATEFP], states$allocated_weight))

  audit <- readr::read_csv(file.path(output, "06_ces_pums_cell_coverage.csv"),
    col_types = readr::cols(.default = readr::col_character(),
      ces_respondents = readr::col_integer(), N = readr::col_double()))
  readr::stop_for_problems(audit)
  profile <- vctrs::vec_match(ces[keys], audit[keys])
  stopifnot("Coverage audit differs from the saved CES profiles" =
              !vctrs::vec_duplicate_any(audit[keys]) && !anyNA(profile) &&
              all(audit$ces_respondents > 0L) &&
              identical(tabulate(profile, nbins = nrow(audit)), audit$ces_respondents))

  cell <- vctrs::vec_match(audit[keys], frame[keys])
  statuses <- c("matched_positive_N", "no_positive_pums_cell", "missing_ces_key")
  expected <- ifelse(!complete.cases(audit[keys]), statuses[3L],
                     ifelse(is.na(cell), statuses[2L], statuses[1L]))
  weight <- frame$N[cell]
  weight[expected == "no_positive_pums_cell"] <- 0
  present <- !is.na(weight)
  stopifnot("Coverage status or population differs from the saved frame" =
              identical(expected, audit$coverage_status) &&
              identical(is.na(weight), is.na(audit$N)) &&
              close_weight(weight[present], audit$N[present]))

  # A district donor draw can only select a race with positive weight in its
  # own Hispanic district/profile. State or national fallback requires an empty
  # local Hispanic profile across all races.
  stopifnot("Missing or invalid race imputation flags" =
              all(c("race_imputed", "race_donor_level") %in% names(ces)) &&
              is.logical(ces$race_imputed) && !anyNA(ces$race_imputed))
  recipients <- which(ces$race_imputed)
  level <- ces$race_donor_level[recipients]
  donor_key <- setdiff(keys, "race_cat")
  local_profiles <- unique(frame[frame$hispanic_cat == "Hispanic", donor_key, drop = FALSE])
  local <- !is.na(vctrs::vec_match(ces[recipients, donor_key, drop = FALSE], local_profiles))
  positive_cell <- expected[profile[recipients]] == "matched_positive_N"
  stopifnot("Conditional race draws disagree with district population support" =
              all(ces$hispanic_cat[recipients] == "Hispanic") &&
              all(level %in% c("district", "state", "national")) &&
              all(local == (level == "district")) && all(positive_cell == local))

  cat("Verified", nrow(slim), "CES respondents and", ncol(slim), "analysis columns.\n")
  cat("Verified", nrow(frame), "positive population cells across", nrow(districts),
      "districts including DC. Allocated CVAP:", format(sum(frame$N), scientific = FALSE), "\n")
  print(data.frame(coverage_status = statuses,
                   respondents = tabulate(match(expected[profile], statuses), length(statuses)),
                   distinct_profiles = tabulate(match(expected, statuses), length(statuses))),
        row.names = FALSE)
}

if (sys.nframe() == 0L) check_analysis_files()
