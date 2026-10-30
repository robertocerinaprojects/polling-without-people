# Prepare IPUMS 2020–2024 ACS five-year person records.
# Plain-language summary: frame/docs/01_prepare_pums.md
# Target: citizen voting-age population, including institutional residents.
# DC is retained at this stage.
# Run from repository root: Rscript frame/scripts/01_prepare_pums.R
# Inputs: frame/data/input/usa_00003.xml and usa_00003.csv.gz
# Output: frame/data/intermediate/pums_clean.rds
# Audit tables: frame/data/output/01_pums_*.csv

library(dplyr)

input_dir <- here::here("frame", "data", "input")

# Pin the exact source files used in this replication.
# Source: https://zenodo.org/records/21285306
expected_md5 <- c(
  "usa_00003.xml" = "0b2b19b40c0fa4e7a35f6338b85d4b8f",
  "usa_00003.csv.gz" = "6945d5353a48361713b49c521f5d1f5a"
)
input_files <- file.path(input_dir, names(expected_md5))

stopifnot(all(file.exists(input_files)))
stopifnot(
  all(unname(tools::md5sum(input_files)) == unname(expected_md5))
)

# Read all raw columns, preserving identifiers and sample provenance.
ddi <- ipumsr::read_ipums_ddi(file.path(input_dir, "usa_00003.xml"))
pums <- ipumsr::read_ipums_micro(
  ddi,
  data_file = file.path(input_dir, "usa_00003.csv.gz"),
  var_attrs = NULL
)

stopifnot(nrow(readr::problems(pums)) == 0L)

required <- c(
  "YEAR", "MULTYEAR", "SAMPLE", "SERIAL", "CBSERIAL", "PERNUM",
  "STATEFIP", "PERWT", "GQ", "CITIZEN", "AGE"
)
stopifnot(all(required %in% names(pums)))

# SAMPLE label: usa_00003.xml; YEAR/MULTYEAR: verified input audit.
# Stop on unexpected sample definitions, weights or filter codes.
stopifnot(
  all(pums$SAMPLE == 202403),
  all(pums$YEAR == 2024),
  all(pums$MULTYEAR %in% 2020:2024),
  all(is.finite(pums$PERWT)),
  all(pums$PERWT > 0),
  all(pums$GQ %in% 0:6),
  all(pums$CITIZEN %in% 0:3),
  all(is.finite(pums$AGE)),
  all(pums$AGE >= 0)
)

stage_totals <- function(data, stage) {
  tibble(
    stage = stage,
    rows = nrow(data),
    weighted_population = sum(data$PERWT)
  )
}

audit <- stage_totals(pums, "Raw extract")

# Retain households and all institutional/non-institutional group quarters.
# GQ codes 1-5: household/group-quarters categories in usa_00003.xml.
pums <- filter(pums, GQ %in% 1:5)
audit <- bind_rows(audit, stage_totals(pums, "Valid person records"))

# Retain native-born citizens, citizens born abroad, and naturalized citizens.
# Codes: usa_00003.xml. ACS universe explains retaining code 0:
# https://usa.ipums.org/usa-action/variables/CITIZEN
pums <- filter(pums, CITIZEN %in% 0:2)
audit <- bind_rows(audit, stage_totals(pums, "Citizens"))

# Age is measured in the source survey; no projection to 2026 is applied.
# Age 18 is our chosen CVAP threshold.
pums <- filter(pums, AGE >= 18)
audit <- bind_rows(audit, stage_totals(pums, "Citizens aged 18+"))

# Calculate removals relative to the immediately preceding stage.
audit <- mutate(
  audit,
  rows_removed = lag(rows, default = first(rows)) - rows,
  weighted_removed =
    lag(weighted_population, default = first(weighted_population)) -
    weighted_population
)

cat("\nPopulation filtering audit:\n")
print(audit, n = Inf, width = Inf)

# Recode Hispanic origin: 0 = not Hispanic, 1 = Hispanic, NA = unknown.
stopifnot("HISPAND" %in% names(pums))

known_codes <- ipumsr::ipums_val_labels(ddi, HISPAND)$val
observed_codes <- unique(pums$HISPAND[!is.na(pums$HISPAND)])
unexpected_codes <- setdiff(observed_codes, known_codes)

if (length(unexpected_codes) > 0L) {
  stop(
    "HISPAND codes absent from the codebook: ",
    paste(unexpected_codes, collapse = ", ")
  )
}

# HISPAND 0 = Not Hispanic; 900 = Not Reported (usa_00003.xml).
recode_hispanic <- function(x) {
  case_when(
    is.na(x) | x == 900 ~ NA_integer_,
    x == 0             ~ 0L,
    x > 0 & x < 900    ~ 1L,
    TRUE               ~ NA_integer_
  )
}

# Explicitly test the previously problematic case.
stopifnot(identical(
  recode_hispanic(c(0, 100, 498, 900, NA_real_)),
  c(0L, 1L, 1L, NA_integer_, NA_integer_)
))
cat("\nHispanic recoding check passed: code 900 remains unknown.\n")

pums <- mutate(
  pums,
  hispanic_flag = recode_hispanic(HISPAND)
)

hispanic_audit <- pums |>
  group_by(hispanic_flag) |>
  summarise(
    rows = n(),
    weighted_population = sum(PERWT),
    .groups = "drop"
  )

cat("\nHispanic-origin audit among retained citizens aged 18+:\n")
print(hispanic_audit, n = Inf, width = Inf)
cat("Records with unknown Hispanic origin:",
    sum(is.na(pums$hispanic_flag)), "\n")

# Add demographic labels and clean household income.
required_demographics <- c("SEX", "HISPAND", "RACED", "EDUCD", "HHINCOME")
stopifnot(all(required_demographics %in% names(pums)))

# Look up labels without changing the number or order of person records.
ddi_label <- function(x, variable) {
  lookup <- ipumsr::ipums_val_labels(
    ddi, tidyselect::all_of(variable)
  )

  stopifnot(
    !anyDuplicated(lookup$val),
    !anyNA(lookup$val),
    !anyNA(lookup$lbl)
  )

  index <- match(x, lookup$val)
  unmatched <- unique(x[!is.na(x) & is.na(index)])

  if (length(unmatched) > 0L) {
    stop(variable, " has unrecognised codes: ",
         paste(unmatched, collapse = ", "))
  }

  lookup$lbl[index]
}

# SEX records sex; retain the legacy name 'gender' for downstream compatibility.
pums$gender <- ddi_label(pums$SEX, "SEX")
# SEX 1 = Male, 2 = Female (usa_00003.xml).
pums$gender[!pums$SEX %in% c(1, 2)] <- NA_character_

pums <- mutate(
  pums,
  hispanic_detailed = ddi_label(HISPAND, "HISPAND"),
  race_detailed = ddi_label(RACED, "RACED"),
  educ_detailed = ddi_label(EDUCD, "EDUCD"),
  # 9999999 = N/A: https://usa.ipums.org/usa-action/variables/HHINCOME
  hhincome_clean = if_else(
    HHINCOME == 9999999,
    NA_real_,
    as.numeric(HHINCOME)
  )
)

# Preserve income amounts as supplied in the IPUMS multi-year extract.
# Retain all raw columns, including identifiers and sample provenance.
stopifnot(
  nrow(pums) == tail(audit$rows, 1),
  sum(pums$PERWT) == tail(audit$weighted_population, 1)
)

cat("\nRecorded-sex distribution:\n")
print(
  pums |>
    group_by(SEX, gender) |>
    summarise(
      rows = n(),
      weighted_population = sum(PERWT),
      .groups = "drop"
    ),
  n = Inf, width = Inf
)

recoded_columns <- c(
  "gender", "hispanic_flag", "hispanic_detailed",
  "race_detailed", "educ_detailed", "hhincome_clean"
)
recoding_audit <- tibble(
  variable = recoded_columns,
  missing_rows = vapply(
    pums[recoded_columns],
    function(x) sum(is.na(x)),
    integer(1)
  )
)

cat("\nMissing values after recoding:\n")
print(recoding_audit, n = Inf, width = Inf)

cat("\nHousehold-income summary:\n")
print(summary(pums$hhincome_clean))

cat("\nMissing household income by group-quarters code:\n")
print(
  pums |>
    group_by(GQ) |>
    summarise(
      rows = n(),
      missing_income = sum(is.na(hhincome_clean)),
      weighted_missing_income = sum(PERWT[is.na(hhincome_clean)]),
      .groups = "drop"
    ),
  n = Inf, width = Inf
)

# Final validation before saving.
raw_columns <- ipumsr::ipums_var_info(ddi)$var_name
stopifnot(
  all(raw_columns %in% names(pums)),
  all(recoded_columns %in% names(pums)),
  nrow(pums) == tail(audit$rows, 1),
  sum(pums$PERWT) == tail(audit$weighted_population, 1)
)

# Every retained person must have a complete, unique identifier.
id_columns <- c("SAMPLE", "SERIAL", "PERNUM")
stopifnot(!anyNA(pums[id_columns]))

unique_people <- n_distinct(
  pums$SAMPLE, pums$SERIAL, pums$PERNUM
)
stopifnot(unique_people == nrow(pums))

# Code source: STATEFIP labels in usa_00003.xml.
# Expected state FIPS codes: all 50 states plus DC.
expected_states <- c(1, 2, 4, 5, 6, 8:13, 15:42, 44:51, 53:56)

stopifnot(
  all(c("STATEFIP", "PUMA", "CPUMA1020") %in% names(pums)),
  setequal(unique(pums$STATEFIP), expected_states),
  # Broad five-digit guard; actual area membership checked later.
  all(pums$PUMA %in% 1:99999),
  # Range source: https://usa.ipums.org/usa-action/variables/CPUMA1020
  all(pums$CPUMA1020 %in% 1:1722)
)

# Crosswalk coverage will be checked when we apply the crosswalk.
cat("\nFinal validation passed.\n")
cat("Rows:", nrow(pums), "\n")
cat("Columns:", ncol(pums), "\n")
cat("Unique person identifiers:", unique_people, "\n")
cat("States including DC:", n_distinct(pums$STATEFIP), "\n")
cat("Weighted population:", sum(pums$PERWT), "\n")

# Store the income diagnostic alongside the other audit tables.
income_audit <- pums |>
  group_by(GQ) |>
  summarise(
    rows = n(),
    missing_income = sum(is.na(hhincome_clean)),
    weighted_missing_income = sum(PERWT[is.na(hhincome_clean)]),
    .groups = "drop"
  )

intermediate_dir <- here::here("frame", "data", "intermediate")
output_dir <- here::here("frame", "data", "output")
dir.create(intermediate_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

# Finish writing before assigning the final filename.
output_path <- file.path(intermediate_dir, "pums_clean.rds")
temporary_path <- tempfile(
  pattern = "pums_clean_",
  tmpdir = intermediate_dir,
  fileext = ".rds"
)

cat("\nSaving cleaned PUMS data...\n")
saveRDS(pums, temporary_path, compress = "gzip")

if (!file.rename(temporary_path, output_path)) {
  stop("Could not move the completed RDS file to: ", output_path)
}

audit_tables <- list(
  filtering = audit,
  recoding = recoding_audit,
  hispanic = hispanic_audit,
  income_by_gq = income_audit
)

for (audit_name in names(audit_tables)) {
  readr::write_csv(
    audit_tables[[audit_name]],
    file.path(output_dir, paste0("01_pums_", audit_name, ".csv"))
  )
}

cat("Saved:", output_path, "\n")
cat("File size:",
    round(file.info(output_path)$size / 1024^2, 1), "MiB\n")
cat("Audit tables saved in:", output_dir, "\n")
