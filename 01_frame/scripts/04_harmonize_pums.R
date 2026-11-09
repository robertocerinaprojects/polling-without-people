# Give each citizen adult in PUMS the demographic categories used in the CES.
# Run from the repository root: Rscript 01_frame/scripts/04_harmonize_pums.R
# Codebook decisions and national results: 01_frame/docs/04_harmonize_pums.md
#
# The person table has one row per SAMPLE, SERIAL and PERNUM. A second table
# gives the national race distribution among Hispanic citizen adults. Step 05
# checks its district-specific donor totals against these national totals.

library(dplyr)

# Read the citizen-adult records prepared in Step 01 ----
intermediate_dir <- here::here("01_frame", "data", "intermediate")
output_dir <- here::here("01_frame", "data", "output")
input_path <- file.path(intermediate_dir, "pums_clean.rds")
if (!file.exists(input_path)) stop("Run Script 01 to create ", input_path)

person_key <- c("SAMPLE", "SERIAL", "PERNUM")
pums <- readRDS(input_path) |>
  select(all_of(person_key), AGE, SEX, EDUCD, RACE, hispanic_flag, CITIZEN, PERWT)

stopifnot(
  "Expected unique, complete PUMS person identifiers." =
    nrow(pums) > 0L && !anyNA(pums[person_key]) &&
    n_distinct(pums$SAMPLE, pums$SERIAL, pums$PERNUM) == nrow(pums),
  # In the IPUMS codebook checked in Step 01, CITIZEN codes 0–2 are citizens.
  "Expected citizens aged 18+." =
    all(is.finite(pums$AGE) & pums$AGE >= 18) && all(pums$CITIZEN %in% 0:2),
  "Expected finite positive person weights." =
    all(is.finite(pums$PERWT) & pums$PERWT > 0),
  "Unexpected Hispanic-origin flag." =
    all(is.na(pums$hispanic_flag) | pums$hispanic_flag %in% 0:1)
)

# Map IPUMS codes to the five shared demographic fields ----
# Group the detailed EDUCD codes in the approved IPUMS codebook into the six
# CES education categories. The labels below set the factor order in the
# person file, including categories with no people in this run.
education_codes <- list(
  "No HS"        = c(2L, 11L, 12L, 14:17, 22L, 23L, 25L, 26L, 30L, 40L, 50L, 61L),
  "HS grad"      = c(63L, 64L),
  "Some college" = c(65L, 71L),
  "2-year"       = 81L,
  "4-year"       = 101L,
  "Post-grad"    = 114:116
)

# Use general RACE and keep Hispanic origin as a separate field. Code 6
# includes other Asian or Pacific Islander. Codes 7, 8 and 9 mean other race
# alone, two races and three or more races, respectively.
race_codes <- list(
  "White"           = 1L,
  "Black"           = 2L,
  "Native American" = 3L,
  "Asian"           = 4:6,
  "Other/Multi"     = 7:9
)

recode_groups <- function(values, codes_by_group) {
  # Build the small lookup once. Each source code gets the factor label of its
  # group, so both 63 and 64 return "HS grad". An unlisted code returns NA.
  codes <- unlist(codes_by_group, use.names = FALSE)
  labels <- rep(names(codes_by_group), lengths(codes_by_group))
  category_for_code <- factor(labels, levels = names(codes_by_group))
  category_for_code[match(values, codes)]
}

# Include the upper age in each band. Age 22 belongs to 18–22 and 23 to 23–27.
age_band_ends <- seq(22L, 82L, by = 5L)
age_labels <- c(paste(age_band_ends - 4L, age_band_ends, sep = "-"), "83+")
demographics <- pums |>
  transmute(
    across(all_of(person_key)),
    age_cat = cut(AGE, breaks = c(17, age_band_ends, Inf), labels = age_labels, right = TRUE),
    # SEX is recorded sex in PUMS. The output name gender_cat is shared with CES.
    gender_cat = factor(SEX, levels = 1:2, labels = c("Male", "Female")),
    educ_cat = recode_groups(EDUCD, education_codes),
    race_cat = recode_groups(RACE, race_codes),
    hispanic_cat = factor(hispanic_flag, levels = c(1L, 0L),
                          labels = c("Hispanic", "Not Hispanic"))
  )

# Calculate the national race shares among Hispanic citizen adults ----
# Work from the original people so that each donor's PERWT enters once.
# Only flag 1 qualifies. People with unknown origin still receive a demographic row.
donor_rows <- which(pums$hispanic_flag == 1L)
stopifnot(
  "No Hispanic PUMS donors." = length(donor_rows) > 0L,
  "A Hispanic donor lacks a mapped race." = !anyNA(demographics$race_cat[donor_rows])
)

# donor_records counts survey records. donor_weight counts the people they
# represent. Keep all five races, even when a race has zero donors.
probabilities <- tibble(
  race_cat = demographics$race_cat[donor_rows],
  person_weight = pums$PERWT[donor_rows]
) |>
  group_by(race_cat, .drop = FALSE) |>
  summarise(
    donor_records = n(),
    donor_weight = sum(person_weight),
    .groups = "drop"
  ) |>
  arrange(race_cat) |>
  mutate(probability = donor_weight / sum(donor_weight))

stopifnot(
  identical(as.character(probabilities$race_cat), names(race_codes)),
  sum(probabilities$donor_records) == length(donor_rows),
  sum(probabilities$donor_weight) == sum(pums$PERWT[donor_rows]),
  all(is.finite(probabilities$probability) & probabilities$probability >= 0),
  abs(sum(probabilities$probability) - 1) <= 1e-12
)
rm(pums, donor_rows)

# Count missing categories and save the three products ----
categories <- c("age_cat", "gender_cat", "educ_cat", "race_cat", "hispanic_cat")
coverage <- tibble(
  variable = categories,
  records = nrow(demographics),
  missing = vapply(demographics[categories], function(column) sum(is.na(column)), integer(1))
)

save_outputs <- function(demographics, coverage, probabilities, paths) {
  # Write all three temporary files first, each beside its destination. Once
  # writing succeeds, rename them in order: demographics, coverage, donor shares.
  temp_paths <- vapply(
    paths, function(path) tempfile("pums04_", tmpdir = dirname(path)), character(1)
  )
  on.exit(unlink(temp_paths), add = TRUE)
  saveRDS(demographics, temp_paths[["demographics"]])
  readr::write_csv(coverage, temp_paths[["coverage"]])
  readr::write_csv(probabilities, temp_paths[["donor_shares"]])

  for (product in names(paths)) {
    if (!file.rename(temp_paths[[product]], paths[[product]])) {
      stop("Could not publish ", paths[[product]])
    }
  }
}

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
paths <- c(
  demographics = file.path(intermediate_dir, "pums_demographics.rds"),
  coverage = file.path(output_dir, "04_pums_demographic_coverage.csv"),
  donor_shares = file.path(output_dir, "04_pums_hispanic_race_probabilities.csv")
)
save_outputs(demographics, coverage, probabilities, paths)
print(coverage, n = Inf)
print(probabilities, n = Inf, width = Inf)
cat("Hispanic donor records:", sum(probabilities$donor_records), "\n")
cat("Hispanic donor population:", sum(probabilities$donor_weight), "\n")
cat("Saved PUMS demographics, coverage audit and the five race probabilities.\n")
