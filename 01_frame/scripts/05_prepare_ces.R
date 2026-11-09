# Prepare the 2024 Cooperative Election Study (CES) for the citizen-adult frame.
# Run from the repository root: Rscript 01_frame/scripts/05_prepare_ces.R
# Sources, decisions and outputs: 01_frame/docs/05_prepare_ces.md
#
# Two districts matter for a respondent. Use the 2026 residence district to
# match their demographics to PUMS. Use the original 2024 ballot and the
# candidate list shown in that survey wave to identify their House vote.

library(dplyr)

data_dir <- here::here("01_frame", "data")
input_dir <- file.path(data_dir, "input")
intermediate_dir <- file.path(data_dir, "intermediate")
output_dir <- file.path(data_dir, "output")
helpers <- here::here("01_frame", "scripts", "helpers")
source(file.path(helpers, "05_ces_files.R"), local = TRUE)

# Read the reviewed CES release ----
# File 12050325 is the 2024 Common Content vote-validated CSV (V9) from
# Harvard Dataverse. Release and questionnaires: https://doi.org/10.7910/DVN/X11EP6
source_file <- file.path(input_dir, "CCES24_Common_OUTPUT_vv_topost_final.csv")
download_url <- "https://dataverse.harvard.edu/api/access/datafile/12050325"
expected_md5 <- "b740b9305fee50e1a34656b513f55c57"
get_ces_release(source_file, download_url, expected_md5)

source(file.path(helpers, "05_derive_votes.R"), local = TRUE)
ces_raw <- read_ces_respondents(source_file)

# Select respondents and record who enters the frame ----
# Keep the two gender responses used by the PUMS frame and an explicit Yes
# on US citizenship. The sample audit counts respondents before and after
# each restriction. Every retained respondent keeps their original commonweight.
gender_eligible <- ces_raw$gender4 %in% 1:2
ces_raw$harmonization_eligible <- gender_eligible & ces_raw$cit1 %in% 1L
ces <- filter(ces_raw, harmonization_eligible)

sample_counts <- function(rows, sample_name) {
  primary_hispanic <- rows$race %in% 3L
  other_primary_race <- rows$race %in% c(1L, 2L, 4L:8L)
  hispanic_origin <- rows$hispanic %in% 1L
  data.frame(
    sample = sample_name,
    respondents = nrow(rows),
    citizen_yes = sum(rows$cit1 %in% 1L),
    citizen_no = sum(rows$cit1 %in% 2L),
    citizenship_missing = sum(is.na(rows$cit1)),
    primary_hispanic = sum(primary_hispanic),
    primary_hispanic_origin_yes = sum(primary_hispanic & hispanic_origin),
    other_primary_race_origin_yes = sum(other_primary_race & hispanic_origin),
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
  all(ces$cit1 == 1L),
  nrow(ces) == sum(ces_raw$harmonization_eligible)
)

# Map the survey answers to the demographic categories used in Step 04 ----
# CES gives birth year, so age is approximate. Each upper endpoint belongs
# to its band (18–22, 23–27, ..., 83+). PUMS uses age at observation.
age_band_ends <- seq(22L, 82L, by = 5L)
age_labels <- c(paste(age_band_ends - 4L, age_band_ends, sep = "-"), "83+")
educ_levels <- c("No HS", "HS grad", "Some college", "2-year", "4-year", "Post-grad")
race_levels <- c("White", "Black", "Native American", "Asian", "Other/Multi")

# In the CES primary race question, 3 means Hispanic or Latino. Leave that
# race open for the draw. Keep the separate Hispanic-origin response as given,
# including a missing answer.
# Codes 6–8 are Two or more races, Other and Middle Eastern, respectively.
harmonize_primary_race <- function(answer) {
  label <- case_when(
    answer == 1L ~ "White",
    answer == 2L ~ "Black",
    answer == 4L ~ "Asian",
    answer == 5L ~ "Native American",
    answer %in% 6:8 ~ "Other/Multi",
    .default = NA_character_
  )
  factor(label, levels = race_levels)
}
ces <- ces |>
  mutate(
    age = 2024L - birthyr,
    age_cat = cut(age, breaks = c(17, age_band_ends, Inf), labels = age_labels, right = TRUE),
    gender_cat = factor(gender4, levels = 1:2, labels = c("Male", "Female")),
    educ_cat = factor(educ, levels = 1:6, labels = educ_levels),
    hispanic_cat = factor(hispanic, levels = 1:2, labels = c("Hispanic", "Not Hispanic")),
    race_cat = harmonize_primary_race(race),
    race_imputed = race %in% 3L
  )

profile_and_location <- c("inputstate", "cdid119", "age_cat", "gender_cat", "educ_cat")
stopifnot(
  all(ces$age >= 18L),
  !anyNA(ces[profile_and_location]),
  all(ces$hispanic[ces$race_imputed] %in% 1L),
  all(is.na(ces$race_cat) == ces$race_imputed)
)

# Assign a 2026 residence district, then draw race where needed ----
# The lookup gives possible new districts for the original residence. The
# PUMS tables give race probabilities for Hispanic donors of the same gender,
# education and age group in each district, with state and national fallbacks.
run_input_helper("python3", file.path(helpers, "05_ces_district_geography.py"))
run_input_helper(
  file.path(R.home("bin"), "Rscript"),
  file.path(helpers, "build_district_race_donors.R")
)
lookup <- read_ces_district_lookup(file.path(output_dir, "05_ces_district_lookup.csv"))
donor_tables <- readRDS(file.path(intermediate_dir, "hispanic_race_by_district_profile.rds"))

source(file.path(helpers, "05_assign_district_race.R"), local = TRUE)
before_draw <- ces
assigned <- assign_district_race(ces, lookup, donor_tables)
ces <- assigned$ces
race_audit <- assigned$draw_audit
check_ces_race_assignments(before_draw, ces, race_audit, race_levels)

# Decode the two 2024 votes on their original ballots ----
# The House decoder uses the five candidate slots for the wave that supplied
# the answer. A respondent who moved can have different pre/post ballot
# districts. CDFP120 plays no part in decoding either office.
ces <- derive_ces_votes(ces)
stopifnot(identical(ces$caseid, before_draw$caseid))

ballot_places <- ces |>
  filter(house_vote_2024_source != "unresolved") |>
  distinct(STATEFP = house_vote_state_2024, CD119 = house_vote_cd119_2024)
unknown_ballots <- anti_join(ballot_places, lookup, by = c("STATEFP", "CD119"))
if (nrow(unknown_ballots)) stop("Unknown 2024 House ballot state/district pair.")

# Each retained respondent contributes one unweighted outcome per office,
# including people for whom the survey supplied no usable answer.
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
coverage <- tibble(
  variable = categories,
  records = nrow(ces),
  missing = vapply(ces[categories], function(column) sum(is.na(column)), integer(1))
)

# Save the audits, the detailed survey and the 11-column analysis file ----
dir.create(intermediate_dir, recursive = TRUE, showWarnings = FALSE)
write_audit <- function(filename, table) {
  publish_ces_file(file.path(output_dir, filename), readr::write_csv, table)
}
write_audit("05_ces_vote_sources.csv", vote_sources)
write_audit("05_ces_sample.csv", sample_audit)
write_audit("05_ces_race_imputation.csv", race_audit)
write_audit("05_ces_demographic_coverage.csv", coverage)
write_audit("05_ces_district_probabilities.csv", assigned$district_probabilities)
write_audit("05_ces_race_donor_support.csv", assigned$support_audit)
publish_ces_file(file.path(intermediate_dir, "ces_demographics_harmonized.rds"), saveRDS, ces)
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
vote_sources |>
  group_by(office, outcome) |>
  summarise(respondents = sum(respondents), .groups = "drop") |>
  print(n = Inf)
message("Saved harmonized CES demographics and votes for ", nrow(ces), " respondents.")
