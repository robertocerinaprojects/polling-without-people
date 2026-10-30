# Apply the PUMA-to-district crosswalk to cleaned PUMS records.
# Plain-language summary: frame/docs/03_apply_puma_cd_crosswalk.md
# Run from repository root: Rscript frame/scripts/03_apply_puma_cd_crosswalk.R
# Current scope: validate inputs and PUMA coverage before allocation.

library(dplyr)

check <- function(condition, message) {
  if (!isTRUE(condition)) stop(message, call. = FALSE)
}

# Section 1: validate inputs and check geographic coverage.
intermediate_dir <- here::here("frame", "data", "intermediate")
pums_path <- file.path(intermediate_dir, "pums_clean.rds")
crosswalk_path <- file.path(intermediate_dir, "puma_cd_crosswalk.rds")

check(
  all(file.exists(c(pums_path, crosswalk_path))),
  "Missing input: run Scripts 01 and 02 first."
)

cat("Reading cleaned PUMS and crosswalk...\n")
pums <- readRDS(pums_path)
crosswalk <- readRDS(crosswalk_path)

required_pums <- c("SAMPLE", "YEAR", "STATEFIP", "PUMA", "PERWT")
required_crosswalk <- c("STATEFP", "PUMA5CE", "CDFP", "allocation_weight")

check(
  all(required_pums %in% names(pums)) &&
    all(required_crosswalk %in% names(crosswalk)),
  "Required input columns are missing."
)
check(
  nrow(pums) > 0L && nrow(crosswalk) > 0L &&
    all(vapply(pums[required_pums], is.numeric, logical(1))),
  "PUMS columns must be numeric and both inputs must contain records."
)

# Extract identity: pinned IPUMS DDI and checks in Script 01.
# This reviewed extract uses 2020 PUMA definitions.
# Matching identifiers alone would not establish the boundary vintage.
check(
  all(pums$SAMPLE == 202403 & pums$YEAR == 2024),
  "Unexpected PUMS sample or year; review geographic compatibility."
)
check(
  all(is.finite(pums$PERWT) & pums$PERWT > 0),
  "Missing, nonfinite or nonpositive person weights."
)

# Aggregate numeric keys first; format only this small summary table.
pums_by_puma <- pums |>
  group_by(STATEFIP, PUMA) |>
  summarise(
    person_records = n(),
    weighted_population = sum(PERWT),
    .groups = "drop"
  )

check(
  all(
    is.finite(pums_by_puma$STATEFIP) &
      pums_by_puma$STATEFIP == trunc(pums_by_puma$STATEFIP) &
      pums_by_puma$STATEFIP >= 1 & pums_by_puma$STATEFIP <= 99 &
      is.finite(pums_by_puma$PUMA) &
      pums_by_puma$PUMA == trunc(pums_by_puma$PUMA) &
      pums_by_puma$PUMA >= 1 & pums_by_puma$PUMA <= 99999
  ),
  "PUMS geographic codes cannot be formatted as the expected identifiers."
)

# Match the two- and five-digit character identifiers saved by Script 02.
pums_by_puma <- pums_by_puma |>
  transmute(
    STATEFP = sprintf("%02d", as.integer(STATEFIP)),
    PUMA5CE = sprintf("%05d", as.integer(PUMA)),
    person_records,
    weighted_population
  )

key_columns <- c("STATEFP", "PUMA5CE", "CDFP")
check(
  all(vapply(crosswalk[key_columns], is.character, logical(1))) &&
    !anyNA(crosswalk[key_columns]) &&
    all(grepl("^[0-9]{2}$", crosswalk$STATEFP)) &&
    all(grepl("^[0-9]{5}$", crosswalk$PUMA5CE)) &&
    all(grepl("^[0-9]{2}$", crosswalk$CDFP)) &&
    anyDuplicated(crosswalk[key_columns]) == 0L,
  "Crosswalk geographic identifiers are invalid or duplicated."
)
check(
  is.numeric(crosswalk$allocation_weight) &&
    all(is.finite(crosswalk$allocation_weight)) &&
    all(crosswalk$allocation_weight >= 0 &
          crosswalk$allocation_weight <= 1),
  "Invalid crosswalk allocation weights."
)

crosswalk_by_puma <- crosswalk |>
  group_by(STATEFP, PUMA5CE) |>
  summarise(
    district_rows = n(),
    positive_districts = sum(allocation_weight > 0),
    weight_sum = sum(allocation_weight),
    .groups = "drop"
  )

# Same numerical tolerance as Script 02; not a statistical error bound.
check(
  all(abs(crosswalk_by_puma$weight_sum - 1) <= 1e-12),
  "Crosswalk weights do not sum to one within every PUMA."
)

coverage <- full_join(
  pums_by_puma,
  crosswalk_by_puma,
  by = c("STATEFP", "PUMA5CE"),
  relationship = "one-to-one"
) |>
  mutate(
    coverage_status = case_when(
      is.na(person_records) ~ "crosswalk_only",
      is.na(weight_sum) ~ "pums_only",
      TRUE ~ "matched"
    )
  ) |>
  arrange(STATEFP, PUMA5CE)

# Save evidence before stopping on an unmatched PUMS geography.
output_dir <- here::here("frame", "data", "output")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
audit_path <- file.path(output_dir, "03_pums_crosswalk_coverage.csv")
readr::write_csv(coverage, audit_path)

pums_only <- filter(coverage, coverage_status == "pums_only")
crosswalk_only <- filter(coverage, coverage_status == "crosswalk_only")

cat("\nPUMS input:\n")
cat("Person records:", nrow(pums), "\n")
cat("Weighted population:", sum(pums$PERWT), "\n")
cat("States including DC:", n_distinct(pums_by_puma$STATEFP), "\n")
cat("PUMAs:", nrow(pums_by_puma), "\n")

cat("\nPUMA coverage:\n")
coverage |>
  count(coverage_status, name = "pumas") |>
  print(n = Inf, width = Inf)

cat("Unmatched PUMS PUMAs:", nrow(pums_only), "\n")
cat("Person records without a crosswalk:", sum(pums_only$person_records), "\n")
cat("Weighted population without a crosswalk:",
    sum(pums_only$weighted_population), "\n")
cat("Crosswalk PUMAs absent from retained PUMS:", nrow(crosswalk_only), "\n")

if (nrow(pums_only) > 0L) {
  print(head(pums_only, 20L), n = 20, width = Inf)
}
if (nrow(crosswalk_only) > 0L) {
  print(head(crosswalk_only, 20L), n = 20, width = Inf)
}

cat("Audit saved:", audit_path, "\n")
check(
  nrow(pums_only) == 0L,
  "Some PUMS PUMAs have no crosswalk entry; inspect the coverage audit."
)

cat("\nPUMS coverage checks passed.\n")
cat("No person records have been allocated yet.\n")
