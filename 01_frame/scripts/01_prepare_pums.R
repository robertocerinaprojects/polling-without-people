# Prepare IPUMS 2020–2024 ACS five-year person records.
# Plain-language summary: 01_frame/docs/01_prepare_pums.md
# Target: citizen voting-age population, including institutional residents.
# DC is retained at this stage.
# Run from repository root: Rscript 01_frame/scripts/01_prepare_pums.R
# Inputs: stored Script 00 snapshot and 01_frame/docs/00_pums_source.json
# Output: 01_frame/data/intermediate/pums_clean.rds
# Audit tables: 01_frame/data/output/01_pums_*.csv

library(dplyr)

input_dir <- here::here("01_frame", "data", "input")

# Script 00 selects a stored snapshot; the tracked specification identifies
# the reviewed data and variable definitions independently of account filenames.
source_spec <- jsonlite::read_json(
  here::here("01_frame", "docs", "00_pums_source.json"),
  simplifyVector = TRUE
)
stopifnot(
  source_spec$schema_version == 1L,
  source_spec$collection == "usa",
  source_spec$sample == "us2024c",
  source_spec$data_format == "csv",
  source_spec$variable_info_encoding == "ipums_var_info_json_v1"
)

source_dir <- file.path(input_dir, "ipums_pums")
pointer <- file.path(source_dir, "current_snapshot.txt")
if (!file.exists(pointer)) {
  stop("Run 00_download_pums.R first to acquire the PUMS source.")
}
snapshot <- readLines(pointer, warn = FALSE)
stopifnot(
  length(snapshot) == 1L,
  grepl("^[0-9]{8}T[0-9]{6}_[0-9]+$", snapshot)
)
snapshot_dir <- file.path(source_dir, snapshot)
receipt_path <- file.path(snapshot_dir, "download_manifest.csv")
if (!file.exists(receipt_path)) {
  stop("This download is incomplete. Resume 00_download_pums.R first.")
}
receipt <- readr::read_csv(
  receipt_path,
  col_types = readr::cols(.default = readr::col_character())
)
receipt_fields <- c("role", "file", "bytes", "sha256", "sample", "request_sha256")
stopifnot(
  all(receipt_fields %in% names(receipt)),
  nrow(receipt) == 2L,
  !anyNA(receipt[receipt_fields]),
  !anyDuplicated(receipt$role),
  !anyDuplicated(receipt$file),
  setequal(receipt$role, c("ddi_codebook", "data")),
  all(grepl("^[A-Za-z0-9_.-]+$", receipt$file)),
  all(grepl("^[a-f0-9]{64}$", receipt$sha256)),
  all(receipt$sample == source_spec$sample)
)
source_paths <- file.path(snapshot_dir, "files", receipt$file)
names(source_paths) <- receipt$role
sha256 <- function(path) digest::digest(file = path, algo = "sha256")
stopifnot(
  all(file.exists(source_paths)),
  all(file.info(source_paths)$size == as.numeric(receipt$bytes)),
  all(unname(vapply(source_paths, sha256, character(1))) == receipt$sha256)
)
request_path <- file.path(snapshot_dir, "request.json")
stopifnot(
  file.exists(request_path),
  length(unique(receipt$request_sha256)) == 1L,
  all(grepl("^[a-f0-9]{64}$", receipt$request_sha256)),
  sha256(request_path) == receipt$request_sha256[[1]]
)

# A refreshed download may be intact yet differ from the reviewed analysis input.
# Approved IPUMS CSV fingerprint and byte count: docs/00_pums_source.json.
data_path <- source_paths[["data"]]
if (sha256(data_path) != source_spec$data_sha256 ||
    file.info(data_path)$size != source_spec$data_bytes) {
  stop("Downloaded PUMS data differ from the reviewed source. Review before updating 00_pums_source.json.")
}

ddi <- ipumsr::read_ipums_ddi(source_paths[["ddi_codebook"]])
variable_info <- ipumsr::ipums_var_info(ddi)
# Canonical metadata encoding v1: all ipums_var_info fields, in source order.
# Administrative XML fields (extract date, description and filename) are excluded.
# https://tech.popdata.org/ipumsr/reference/ipums_var_info.html
variable_info_json <- jsonlite::toJSON(
  variable_info, dataframe = "rows", auto_unbox = TRUE,
  na = "null", null = "null", digits = NA, pretty = FALSE
)
variable_info_sha256 <- digest::digest(
  enc2utf8(as.character(variable_info_json)), algo = "sha256", serialize = FALSE
)
if (variable_info_sha256 != source_spec$variable_info_sha256) {
  stop("IPUMS variable definitions differ from the reviewed source. Review before updating 00_pums_source.json.")
}
stopifnot(identical(variable_info$var_name, source_spec$required_columns))
cat("Verified approved IPUMS source:", snapshot, "\n")

# Read all raw columns, preserving identifiers and sample provenance.
pums <- ipumsr::read_ipums_micro(
  ddi,
  data_file = data_path,
  var_attrs = NULL
)

stopifnot(nrow(readr::problems(pums)) == 0L)

required <- c(
  "YEAR", "MULTYEAR", "SAMPLE", "SERIAL", "CBSERIAL", "PERNUM",
  "STATEFIP", "PERWT", "GQ", "CITIZEN", "AGE"
)
stopifnot(all(required %in% names(pums)))

# SAMPLE label: the reviewed IPUMS DDI; YEAR/MULTYEAR: verified input audit.
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
# GQ codes 1-5: household/group-quarters categories in the reviewed IPUMS DDI.
pums <- filter(pums, GQ %in% 1:5)
audit <- bind_rows(audit, stage_totals(pums, "Valid person records"))

# Retain native-born citizens, citizens born abroad, and naturalized citizens.
# Codes: the reviewed IPUMS DDI. ACS universe explains retaining code 0:
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

# HISPAND 0 = Not Hispanic; 900 = Not Reported (the reviewed IPUMS DDI).
recode_hispanic <- function(x) {
  case_when(
    is.na(x) | x == 900 ~ NA_integer_,
    x == 0             ~ 0L,
    x > 0 & x < 900    ~ 1L,
    TRUE               ~ NA_integer_
  )
}

# Check that unknown Hispanic-origin code 900 remains missing.
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

# SEX records sex; 'gender' is the downstream compatibility column name.
pums$gender <- ddi_label(pums$SEX, "SEX")
# SEX 1 = Male, 2 = Female (the reviewed IPUMS DDI).
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

# Code source: STATEFIP labels in the reviewed IPUMS DDI.
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

intermediate_dir <- here::here("01_frame", "data", "intermediate")
output_dir <- here::here("01_frame", "data", "output")
dir.create(intermediate_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

output_path <- file.path(intermediate_dir, "pums_clean.rds")
audit_tables <- list(
  filtering = audit,
  recoding = recoding_audit,
  hispanic = hispanic_audit,
  income_by_gq = income_audit
)

save_outputs <- function(people, audits, destination, audit_dir) {
  paths <- file.path(audit_dir, paste0("01_pums_", names(audits), ".csv"))
  temporary_audits <- tempfile(paste0("01-", names(audits), "-"), tmpdir = audit_dir)
  temporary_people <- tempfile("01-people-", tmpdir = dirname(destination))
  on.exit(unlink(c(temporary_audits, temporary_people)), add = TRUE)

  # Write all five products before publishing any. The RDS is published last.
  saveRDS(people, temporary_people, compress = "gzip")
  for (i in seq_along(audits)) {
    readr::write_csv(audits[[i]], temporary_audits[i])
  }
  for (i in seq_along(paths)) {
    if (!file.rename(temporary_audits[i], paths[i])) {
      stop("Could not publish the completed audit: ", paths[i])
    }
  }
  if (!file.rename(temporary_people, destination)) {
    stop("Could not publish the completed RDS: ", destination)
  }
}

cat("\nSaving cleaned PUMS data...\n")
save_outputs(pums, audit_tables, output_path, output_dir)
cat("Saved:", output_path, "\n")
cat("File size:",
    round(file.info(output_path)$size / 1024^2, 1), "MiB\n")
cat("Audit tables saved in:", output_dir, "\n")
