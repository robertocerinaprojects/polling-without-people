# Prepare one record per citizen aged 18 or older in the 2020–2024 ACS.
# Run from the repository root: Rscript 01_frame/scripts/01_prepare_pums.R
# Reads the approved IPUMS snapshot selected by Script 00.
# Writes 01_frame/data/intermediate/pums_clean.rds and four 01_pums_*.csv audits.
# Source decisions and audit definitions: 01_frame/docs/01_prepare_pums.md

library(dplyr)
source(here::here("01_frame", "scripts", "helpers", "01_pums_files.R"), local = TRUE)

# Read the approved person records ----
pums_source <- open_approved_pums(
  snapshot_store = here::here("01_frame", "data", "input", "ipums_pums"),
  specification_path = here::here("01_frame", "docs", "00_pums_source.json")
)
ddi <- pums_source$codebook
pums <- ipumsr::read_ipums_micro(ddi, data_file = pums_source$data_path, var_attrs = NULL)
stopifnot(nrow(readr::problems(pums)) == 0L)

required_person_fields <- c(
  "YEAR", "MULTYEAR", "SAMPLE", "SERIAL", "CBSERIAL", "PERNUM",
  "STATEFIP", "PERWT", "GQ", "CITIZEN", "AGE"
)
stopifnot(all(required_person_fields %in% names(pums)))

# The approved IPUMS codebook identifies sample 202403. The extract contains
# observations from 2020 through 2024 and reports 2024 as its sample year.
stopifnot(
  all(pums$SAMPLE == 202403),
  all(pums$YEAR == 2024),
  all(pums$MULTYEAR %in% 2020:2024)
)
stopifnot(
  all(is.finite(pums$PERWT)), all(pums$PERWT > 0),
  all(pums$GQ %in% 0:6), all(pums$CITIZEN %in% 0:3),
  all(is.finite(pums$AGE)), all(pums$AGE >= 0)
)

# Select the citizen-adult population ----
# Keep one audit row per stage. PERWT is the number of people represented by
# a record. Summing it gives the estimated population at that stage.
stage_totals <- function(people, stage) {
  tibble(stage = stage, rows = nrow(people), weighted_population = sum(people$PERWT))
}
filtering_audit <- stage_totals(pums, "Raw extract")

# GQ 1–5 covers households and both types of group quarters, including institutions.
# Source: GQ labels in the approved IPUMS codebook.
pums <- filter(pums, GQ %in% 1:5)
filtering_audit <- bind_rows(filtering_audit, stage_totals(pums, "Valid person records"))

# For this ACS sample, codes 0–2 retain native-born citizens, those born abroad
# of American parents, and naturalized citizens. https://usa.ipums.org/usa-action/variables/CITIZEN
pums <- filter(pums, CITIZEN %in% 0:2)
filtering_audit <- bind_rows(filtering_audit, stage_totals(pums, "Citizens"))

# Our age threshold applies at the time of the survey.
pums <- filter(pums, AGE >= 18)
filtering_audit <- bind_rows(filtering_audit, stage_totals(pums, "Citizens aged 18+"))

# Measure each loss against the preceding stage. At the first stage, the loss is zero.
filtering_audit <- filtering_audit |>
  mutate(
    rows_removed = lag(rows, default = first(rows)) - rows,
    weighted_removed = lag(weighted_population, default = first(weighted_population)) -
      weighted_population
  )
cat("\nPopulation filtering audit:\n")
print(filtering_audit, n = Inf, width = Inf)

# Derive the Hispanic-origin flag ----
stopifnot("HISPAND" %in% names(pums))
hispanic_labels <- ipumsr::ipums_val_labels(ddi, HISPAND)
observed_codes <- unique(pums$HISPAND[!is.na(pums$HISPAND)])
codes_absent_from_codebook <- setdiff(observed_codes, hispanic_labels$val)
if (length(codes_absent_from_codebook) > 0L) {
  stop("HISPAND codes absent from the codebook: ", paste(codes_absent_from_codebook, collapse = ", "))
}

# The codebook labels HISPAND 0 as Not Hispanic and 900 as Not Reported.
# Check observed codes first so a new, undocumented value cannot enter the flag.
recode_hispanic <- function(code) {
  case_when(
    is.na(code) | code == 900 ~ NA_integer_,
    code == 0                 ~ 0L,
    code > 0 & code < 900     ~ 1L,
    TRUE                      ~ NA_integer_
  )
}
stopifnot(identical(
  recode_hispanic(c(0, 100, 498, 900, NA_real_)),
  c(0L, 1L, 1L, NA_integer_, NA_integer_)
))
cat("\nHispanic recoding check passed: code 900 remains unknown.\n")
pums <- mutate(pums, hispanic_flag = recode_hispanic(HISPAND))

hispanic_audit <- pums |>
  group_by(hispanic_flag) |>
  summarise(rows = n(), weighted_population = sum(PERWT), .groups = "drop")
cat("\nHispanic-origin audit among retained citizens aged 18+:\n")
print(hispanic_audit, n = Inf, width = Inf)
cat("Records with unknown Hispanic origin:", sum(is.na(pums$hispanic_flag)), "\n")

# Label demographics and clean household income ----
demographic_fields <- c("SEX", "HISPAND", "RACED", "EDUCD", "HHINCOME")
stopifnot(all(demographic_fields %in% names(pums)))

# match() finds one label for each person's original code, in person order.
# Missing input stays missing. An undocumented code needs review.
label_codes <- function(codes, labels, field) {
  stopifnot(!anyDuplicated(labels$val), !anyNA(labels$val), !anyNA(labels$lbl))
  label_row <- match(codes, labels$val)
  unrecognised <- unique(codes[!is.na(codes) & is.na(label_row)])
  if (length(unrecognised) > 0L) {
    stop(field, " has unrecognised codes: ", paste(unrecognised, collapse = ", "))
  }
  labels$lbl[label_row]
}

# The downstream column is named gender. IPUMS records sex here, with 1 = Male
# and 2 = Female. Validate every observed code before masking the other labels.
sex_labels <- ipumsr::ipums_val_labels(ddi, SEX)
pums$gender <- label_codes(pums$SEX, sex_labels, "SEX")
pums$gender[!pums$SEX %in% c(1, 2)] <- NA_character_

race_labels <- ipumsr::ipums_val_labels(ddi, RACED)
education_labels <- ipumsr::ipums_val_labels(ddi, EDUCD)
pums <- pums |>
  mutate(
    hispanic_detailed = label_codes(HISPAND, hispanic_labels, "HISPAND"),
    race_detailed = label_codes(RACED, race_labels, "RACED"),
    educ_detailed = label_codes(EDUCD, education_labels, "EDUCD"),
    # IPUMS 9999999 means income is unavailable. Keep zero and negative amounts.
    # https://usa.ipums.org/usa-action/variables/HHINCOME
    hhincome_clean = if_else(HHINCOME == 9999999, NA_real_, as.numeric(HHINCOME))
  )

# Audit the six derived columns ----
sex_audit <- pums |>
  group_by(SEX, gender) |>
  summarise(rows = n(), weighted_population = sum(PERWT), .groups = "drop")
cat("\nRecorded-sex distribution:\n")
print(sex_audit, n = Inf, width = Inf)

recoded_columns <- c(
  "gender", "hispanic_flag", "hispanic_detailed",
  "race_detailed", "educ_detailed", "hhincome_clean"
)
recoding_audit <- tibble(
  variable = recoded_columns,
  missing_rows = vapply(pums[recoded_columns], function(column) sum(is.na(column)), integer(1))
)
cat("\nMissing values after recoding:\n")
print(recoding_audit, n = Inf, width = Inf)

income_audit <- pums |>
  group_by(GQ) |>
  summarise(
    rows = n(),
    missing_income = sum(is.na(hhincome_clean)),
    weighted_missing_income = sum(PERWT[is.na(hhincome_clean)]),
    .groups = "drop"
  )
cat("\nHousehold-income summary:\n")
print(summary(pums$hhincome_clean))
cat("\nMissing household income by group-quarters code:\n")
print(income_audit, n = Inf, width = Inf)

# Verify the people, weights and geography before saving ----
# Adding labels must preserve the population from the last filtering stage.
stopifnot(
  all(pums_source$raw_columns %in% names(pums)),
  all(recoded_columns %in% names(pums)),
  nrow(pums) == last(filtering_audit$rows),
  sum(pums$PERWT) == last(filtering_audit$weighted_population)
)
person_key <- c("SAMPLE", "SERIAL", "PERNUM")
stopifnot(!anyNA(pums[person_key]))
unique_people <- n_distinct(pums$SAMPLE, pums$SERIAL, pums$PERNUM)
stopifnot(unique_people == nrow(pums))

# STATEFIP codes in the approved codebook cover all 50 states and DC.
expected_states <- c(1, 2, 4, 5, 6, 8:13, 15:42, 44:51, 53:56)
stopifnot(
  all(c("STATEFIP", "PUMA", "CPUMA1020") %in% names(pums)),
  setequal(unique(pums$STATEFIP), expected_states),
  # The crosswalk stage checks membership. Here we check only the range.
  all(pums$PUMA %in% 1:99999),
  # https://usa.ipums.org/usa-action/variables/CPUMA1020
  all(pums$CPUMA1020 %in% 1:1722)
)
cat("\nFinal validation passed.\n")
cat("Rows:", nrow(pums), "\n")
cat("Columns:", ncol(pums), "\n")
cat("Unique person identifiers:", unique_people, "\n")
cat("States including DC:", n_distinct(pums$STATEFIP), "\n")
cat("Weighted population:", sum(pums$PERWT), "\n")

# Save the person file and four audits ----
intermediate_dir <- here::here("01_frame", "data", "intermediate")
output_dir <- here::here("01_frame", "data", "output")
dir.create(intermediate_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

output_path <- file.path(intermediate_dir, "pums_clean.rds")
audit_tables <- list(
  filtering = filtering_audit,
  recoding = recoding_audit,
  hispanic = hispanic_audit,
  income_by_gq = income_audit
)
cat("\nSaving cleaned PUMS data...\n")
save_outputs(pums, audit_tables, output_path, output_dir)
cat("Saved:", output_path, "\n")
cat("File size:", round(file.info(output_path)$size / 1024^2, 1), "MiB\n")
cat("Audit tables saved in:", output_dir, "\n")
