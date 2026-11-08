# Prepare the 2024 CES for matching to harmonized PUMS demographics.
# Run from the repository root: Rscript 01_frame/scripts/05_prepare_ces.R
# Companion document: 01_frame/docs/05_prepare_ces.md

library(dplyr)

data_dir <- here::here("01_frame", "data")
input_dir <- file.path(data_dir, "input")
intermediate_dir <- file.path(data_dir, "intermediate")
output_dir <- file.path(data_dir, "output")
helpers <- here::here("01_frame", "scripts", "helpers")
race_levels <- c("White", "Black", "Native American", "Asian", "Other/Multi")

# Official annual CES vote-validated CSV and its reviewed file MD5.
# Release and questionnaires: https://doi.org/10.7910/DVN/X11EP6
download_url <- "https://dataverse.harvard.edu/api/access/datafile/12050325"
source_file <- file.path(input_dir, "CCES24_Common_OUTPUT_vv_topost_final.csv")
expected_md5 <- "b740b9305fee50e1a34656b513f55c57"
verify_source <- function(path) {
  if (!identical(unname(tools::md5sum(path)), expected_md5)) {
    stop("Unexpected CES source checksum: ", path, call. = FALSE)
  }
}

download_source <- function() {
  dir.create(input_dir, recursive = TRUE, showWarnings = FALSE)
  temporary <- tempfile(".ces-download-", tmpdir = input_dir)
  on.exit(unlink(temporary), add = TRUE)
  old_options <- options(timeout = max(600L, getOption("timeout")))
  on.exit(options(old_options), add = TRUE)
  status <- utils::download.file(download_url, temporary, mode = "wb")
  if (status != 0L) stop("CES download failed.", call. = FALSE)
  verify_source(temporary)
  if (!file.rename(temporary, source_file)) stop("Could not save ", source_file, call. = FALSE)
}

if (file.exists(source_file)) {
  verify_source(source_file)
  message("Reusing verified CES source: ", source_file)
} else {
  download_source()
}

# Read the exact candidate, turnout and ballot fields used by the vote rule.
source(file.path(helpers, "05_derive_votes.R"), local = TRUE)
types <- readr::cols_only(
  caseid = readr::col_character(), birthyr = readr::col_integer(),
  gender4 = readr::col_integer(), educ = readr::col_integer(),
  race = readr::col_integer(), hispanic = readr::col_integer(),
  commonweight = readr::col_double(), cit1 = readr::col_integer(),
  inputstate = readr::col_integer(), cdid119 = readr::col_integer(),
  countyfips = readr::col_integer()
)
types$cols <- c(types$cols, vote_input_types())
ces_raw <- readr::read_csv(source_file, col_types = types, lazy = FALSE, progress = FALSE)
readr::stop_for_problems(ces_raw)
stopifnot(
  setequal(names(ces_raw), names(types$cols)), nrow(ces_raw) == 60000L,
  !anyNA(ces_raw$caseid), all(nzchar(ces_raw$caseid)), !anyDuplicated(ces_raw$caseid),
  all(is.finite(ces_raw$commonweight) & ces_raw$commonweight >= 0),
  all(is.na(ces_raw$cit1) | ces_raw$cit1 %in% 1:2)
)

# The frame's two gender categories correspond to CES 1 (man) and 2 (woman).
# The 2024 CES questionnaire codes an explicit US citizenship Yes as cit1 = 1.
# This project requires that answer for the citizen-adult frame.
gender_eligible <- ces_raw$gender4 %in% 1:2
ces_raw$harmonization_eligible <- gender_eligible & ces_raw$cit1 %in% 1L
ces <- filter(ces_raw, harmonization_eligible)
sample_counts <- function(rows, sample_name) {
  data.frame(
    sample = sample_name, respondents = nrow(rows),
    citizen_yes = sum(rows$cit1 %in% 1L),
    citizen_no = sum(rows$cit1 %in% 2L),
    citizenship_missing = sum(is.na(rows$cit1)),
    primary_hispanic = sum(rows$race %in% 3L),
    primary_hispanic_origin_yes = sum(rows$race %in% 3L & rows$hispanic %in% 1L),
    other_primary_race_origin_yes = sum(rows$race %in% c(1L, 2L, 4L:8L) & rows$hispanic %in% 1L),
    unresolved_hispanic_origin = sum(!rows$hispanic %in% 1:2)
  )
}
sample_audit <- bind_rows(
  sample_counts(ces_raw, "full_release"),
  sample_counts(ces_raw[gender_eligible, ], "gender_eligible"),
  sample_counts(ces, "harmonization_eligible")
)
stopifnot(
  all(sample_audit$citizen_yes + sample_audit$citizen_no +
        sample_audit$citizenship_missing == sample_audit$respondents),
  all(ces$cit1 == 1L), nrow(ces) == sum(ces_raw$harmonization_eligible)
)

# Source codes: the 2024 pre-election questionnaire. Age, gender, education
# and category order use the same definitions as the PUMS script.
educ_levels <- c("No HS", "HS grad", "Some college", "2-year", "4-year", "Post-grad")
age_labels <- c(paste(seq(18, 78, 5), seq(22, 82, 5), sep = "-"), "83+")
ces_race_map <- c("White", "Black", NA_character_, "Asian", "Native American",
                  "Other/Multi", "Other/Multi", "Other/Multi")
ces <- ces |>
  mutate(
    age = 2024L - birthyr,
    age_cat = cut(age, breaks = c(seq(17, 82, 5), Inf), labels = age_labels),
    gender_cat = factor(gender4, levels = 1:2, labels = c("Male", "Female")),
    educ_cat = factor(educ, levels = 1:6, labels = educ_levels),
    hispanic_cat = factor(hispanic, levels = 1:2, labels = c("Hispanic", "Not Hispanic")),
    race_cat = factor(ces_race_map[match(race, 1:8)], levels = race_levels),
    race_imputed = race %in% 3L
  )

# Map the CES residence geography to CD120, then draw the harmonized race
# for primary Hispanic/Latino respondents in that same assigned district.
# Keep the original PUMS and CES values available via their person identifiers.
stopifnot(all(ces$age >= 18L), !anyNA(ces[c("inputstate", "cdid119", "age_cat",
                                            "gender_cat", "educ_cat")]),
          all(ces$hispanic[ces$race_imputed] %in% 1L),
          all(is.na(ces$race_cat) == ces$race_imputed))

run_helper <- function(command, file) {
  status <- system2(command, shQuote(file.path(helpers, file)))
  if (status != 0L) stop("Failed to prepare conditional race inputs: ", file, call. = FALSE)
}
run_helper("python3", "05_ces_district_geography.py")
run_helper(file.path(R.home("bin"), "Rscript"), "build_district_race_donors.R")

lookup <- readr::read_csv(
  file.path(output_dir, "05_ces_district_lookup.csv"),
  col_types = readr::cols_only(
    STATEFP = readr::col_character(), CD119 = readr::col_character(),
    county_fips = readr::col_character(), CD120 = readr::col_character(),
    district_probability = readr::col_double(),
    geography_method = readr::col_character()
  ), na = c("", "NA"), progress = FALSE
)
readr::stop_for_problems(lookup)
donor_tables <- readRDS(file.path(intermediate_dir, "hispanic_race_by_district_profile.rds"))
source(file.path(helpers, "05_assign_district_race.R"), local = TRUE)
assigned <- assign_district_race(ces, lookup, donor_tables)
before <- ces
ces <- assigned$ces
race_audit <- assigned$draw_audit
observed <- !before$race_imputed
# Outputs must retain every eligible person and their original CES answers.
stopifnot(
  identical(before$caseid, ces$caseid),
  identical(before$race, ces$race), identical(before$hispanic, ces$hispanic),
  identical(before$commonweight, ces$commonweight), identical(before$cit1, ces$cit1),
  identical(before$race_imputed, ces$race_imputed), !anyNA(ces$race_cat),
  identical(as.character(ces$race_cat[observed]), as.character(before$race_cat[observed])),
  nrow(race_audit) == length(race_levels), setequal(race_audit$race_cat, race_levels),
  all(as.character(ces$race_cat) %in% race_levels),
  identical(
    as.integer(race_audit$imputed_respondents[match(race_levels, race_audit$race_cat)]),
    tabulate(match(ces$race_cat[ces$race_imputed], race_levels), nbins = length(race_levels))
  ),
  sum(race_audit$imputed_respondents) == sum(before$race_imputed)
)
ces <- derive_ces_votes(ces)
stopifnot(identical(ces$caseid, before$caseid))
# The 2024 ballot's state and district must form a valid 119th Congress pair,
# including when the answer comes from a post-election respondent who moved.
ballot_places <- ces |>
  filter(house_vote_2024_source != "unresolved") |>
  distinct(STATEFP = house_vote_state_2024, CD119 = house_vote_cd119_2024)
unknown_ballots <- anti_join(ballot_places, lookup, by = c("STATEFP", "CD119"))
if (nrow(unknown_ballots)) stop("Unknown 2024 House ballot state/district pair.")
vote_sources <- bind_rows(
  transmute(ces, office = "House", source = house_vote_2024_source, outcome = house_vote_2024),
  transmute(ces, office = "President", source = pres_vote_2024_source, outcome = pres_vote_2024)
) |>
  count(office, source, outcome, name = "respondents")
stopifnot(
  all(is.na(vote_sources$outcome) == (vote_sources$source == "unresolved")),
  all(tapply(vote_sources$respondents, vote_sources$office, sum) == nrow(ces))
)
categories <- c("age_cat", "gender_cat", "educ_cat", "race_cat", "hispanic_cat")
coverage <- tibble(variable = categories, records = nrow(ces),
                   missing = vapply(ces[categories], function(x) sum(is.na(x)), integer(1)))

# Stage each product in its destination directory. Save the detailed CES
# after its audits, then build the analysis file from that saved table.
dir.create(intermediate_dir, recursive = TRUE, showWarnings = FALSE)
publish <- function(path, writer, object) {
  temporary <- tempfile(".ces-", tmpdir = dirname(path))
  on.exit(unlink(temporary), add = TRUE)
  writer(object, temporary)
  if (!file.rename(temporary, path)) stop("Could not publish ", path, call. = FALSE)
}
publish(file.path(output_dir, "05_ces_vote_sources.csv"), readr::write_csv, vote_sources)
publish(file.path(output_dir, "05_ces_sample.csv"), readr::write_csv, sample_audit)
publish(file.path(output_dir, "05_ces_race_imputation.csv"), readr::write_csv, race_audit)
publish(file.path(output_dir, "05_ces_demographic_coverage.csv"), readr::write_csv, coverage)
publish(file.path(output_dir, "05_ces_district_probabilities.csv"),
        readr::write_csv, assigned$district_probabilities)
publish(file.path(output_dir, "05_ces_race_donor_support.csv"),
        readr::write_csv, assigned$support_audit)
publish(file.path(intermediate_dir, "ces_demographics_harmonized.rds"), saveRDS, ces)
source(file.path(helpers, "05_export_ces_analysis.R"), local = TRUE)
export_ces_analysis(intermediate_dir)
print(as_tibble(sample_audit), width = Inf)
cat("\nPositive 120th-district candidates for the race-draw recipients:\n")
assigned$support_audit |>
  count(caseid, name = "positive_districts") |>
  count(multiple_positive_districts = positive_districts > 1L, name = "respondents") |>
  print()
cat("\nDonor level used in the selected district for the race-draw recipients:\n")
ces |>
  filter(race_imputed) |>
  count(race_donor_level, name = "respondents") |>
  print()
print(race_audit)
print(coverage)
cat("\n2024 House and presidential outcomes (unweighted respondents):\n")
print(summarise(group_by(vote_sources, office, outcome),
                respondents = sum(respondents), .groups = "drop"), n = Inf)
message("Saved harmonized CES demographics and votes for ", nrow(ces), " respondents.")
