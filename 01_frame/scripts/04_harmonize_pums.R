# Harmonize citizen-adult PUMS demographics and estimate national race shares
# among Hispanic citizens aged 18+. Script 05 uses the totals to check its
# conditional CES donor tables by race.
# Run from the repository root: Rscript 01_frame/scripts/04_harmonize_pums.R
# Methods and code mappings: 01_frame/docs/04_harmonize_pums.md

library(dplyr)

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
  # Script 01 verifies that 0, 1 and 2 designate citizens in the approved sample.
  "Expected citizens aged 18+." =
    all(is.finite(pums$AGE) & pums$AGE >= 18) && all(pums$CITIZEN %in% 0:2),
  "Expected finite positive person weights." = all(is.finite(pums$PERWT) & pums$PERWT > 0),
  "Unexpected Hispanic-origin flag." = all(is.na(pums$hispanic_flag) | pums$hispanic_flag %in% 0:1)
)

# Detailed IPUMS EDUCD codes from the source codebook, pooled to match the
# six 2024 CES education answers. Unmapped or missing codes remain missing.
educ_levels <- c("No HS", "HS grad", "Some college", "2-year", "4-year", "Post-grad")
educd_by_group <- list(
  c(2L, 11L, 12L, 14:17, 22L, 23L, 25L, 26L, 30L, 40L, 50L, 61L),
  c(63L, 64L), c(65L, 71L), 81L, 101L, 114:116
)
educd_codes <- unlist(educd_by_group, use.names = FALSE)
educd_groups <- rep(seq_along(educ_levels), lengths(educd_by_group))

# IPUMS general RACE codes 1–9: White, Black, AI/AN, Chinese, Japanese,
# other Asian/PI, other race, two races, three or more races.
race_levels <- c("White", "Black", "Native American", "Asian", "Other/Multi")
race_group <- c(1L, 2L, 3L, 4L, 4L, 4L, 5L, 5L, 5L)
age_labels <- c(paste(seq(18, 78, by = 5), seq(22, 82, by = 5), sep = "-"), "83+")
pums_demo <- pums |>
  transmute(
    across(all_of(person_key)),
    age_cat = cut(AGE, breaks = c(seq(17, 82, by = 5), Inf), labels = age_labels),
    gender_cat = factor(SEX, levels = 1:2, labels = c("Male", "Female")),
    educ_cat = factor(educd_groups[match(EDUCD, educd_codes)],
                      levels = seq_along(educ_levels), labels = educ_levels),
    race_cat = factor(race_group[match(RACE, 1:9)],
                      levels = seq_along(race_levels), labels = race_levels),
    hispanic_cat = factor(hispanic_flag, levels = c(1L, 0L),
                          labels = c("Hispanic", "Not Hispanic"))
  )

# Count each Hispanic citizen adult's original PERWT exactly once.
donors <- which(pums$hispanic_flag == 1L)
stopifnot(
  "No Hispanic PUMS donors." = length(donors) > 0L,
  "A Hispanic donor lacks a mapped race." = !anyNA(pums_demo$race_cat[donors])
)
probabilities <- tibble(race_cat = pums_demo$race_cat[donors], weight = pums$PERWT[donors]) |>
  group_by(race_cat, .drop = FALSE) |>
  summarise(donor_records = n(), donor_weight = sum(weight), .groups = "drop") |>
  arrange(race_cat) |>
  mutate(probability = donor_weight / sum(donor_weight))
stopifnot(
  identical(as.character(probabilities$race_cat), race_levels),
  sum(probabilities$donor_records) == length(donors),
  sum(probabilities$donor_weight) == sum(pums$PERWT[donors]),
  all(is.finite(probabilities$probability) & probabilities$probability >= 0),
  abs(sum(probabilities$probability) - 1) <= 1e-12
)
rm(pums, donors)

categories <- c("age_cat", "gender_cat", "educ_cat", "race_cat", "hispanic_cat")
coverage <- tibble(
  variable = categories,
  records = nrow(pums_demo),
  missing = vapply(pums_demo[categories], function(x) sum(is.na(x)), integer(1))
)

# Stage the demographic records and both audits before publishing each file.
# Script 05 reads the demographic records and the national donor totals.
save_outputs <- function() {
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  paths <- c(file.path(intermediate_dir, "pums_demographics.rds"),
             file.path(output_dir, "04_pums_demographic_coverage.csv"),
             file.path(output_dir, "04_pums_hispanic_race_probabilities.csv"))
  staged <- vapply(dirname(paths), function(dir) tempfile("pums04_", tmpdir = dir), "")
  on.exit(unlink(staged), add = TRUE)
  saveRDS(pums_demo, staged[1])
  readr::write_csv(coverage, staged[2])
  readr::write_csv(probabilities, staged[3])
  for (i in seq_along(paths)) {
    if (!file.rename(staged[i], paths[i])) stop("Could not publish ", paths[i])
  }
}

save_outputs()
print(coverage, n = Inf)
print(probabilities, n = Inf, width = Inf)
cat("Hispanic donor records:", sum(probabilities$donor_records), "\n")
cat("Hispanic donor population:", sum(probabilities$donor_weight), "\n")
cat("Saved PUMS demographics, coverage audit and the five race probabilities.\n")
