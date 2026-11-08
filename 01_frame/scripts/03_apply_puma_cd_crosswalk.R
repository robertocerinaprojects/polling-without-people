# Apply the PUMA-to-district crosswalk to cleaned PUMS records.
# Plain-language summary: 01_frame/docs/03_apply_puma_cd_crosswalk.md
# Run from repository root: Rscript 01_frame/scripts/03_apply_puma_cd_crosswalk.R
# Distribute each person's survey weight across districts using their PUMA.

library(dplyr)

check <- function(condition, message) {
  if (!isTRUE(condition)) stop(message, call. = FALSE)
}

# Section 1: validate inputs and check geographic coverage.
intermediate_dir <- here::here("01_frame", "data", "intermediate")
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
output_dir <- here::here("01_frame", "data", "output")
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

# Section 2: apply the district probabilities to each person's survey weight.
# The stable person key was established in Script 01. Keep demographic fields
# in pums_clean.rds so they need not be repeated for every district.
person_key <- c("SAMPLE", "SERIAL", "PERNUM")
check(all(person_key %in% names(pums)), "Required person identifiers are missing.")
people <- select(pums, all_of(person_key), STATEFIP, PUMA, PERWT)
rm(pums)
check(
  !anyNA(people[person_key]) &&
    n_distinct(people$SAMPLE, people$SERIAL, people$PERNUM) == nrow(people),
  "Expected one input row per SAMPLE, SERIAL and PERNUM."
)

# A zero probability contributes zero person weight. Keep positive pairs only.
districts <- crosswalk |>
  filter(allocation_weight > 0) |>
  transmute(STATEFIP = as.integer(STATEFP), PUMA = as.integer(PUMA5CE),
            CDFP, allocation_weight) |>
  arrange(STATEFIP, PUMA, CDFP) |>
  mutate(district_row = row_number())

state_plan <- coverage |>
  filter(coverage_status == "matched") |>
  group_by(STATEFP) |>
  summarise(
    expected_rows = sum(as.double(person_records) * positive_districts),
    input_weight = sum(weighted_population),
    person_records = sum(person_records),
    .groups = "drop"
  )
cat("Expected positive-probability person/district rows:",
    format(sum(state_plan$expected_rows), scientific = FALSE), "\n")

# Print one actual split-PUMA example alongside the national checks.
example <- coverage |>
  filter(coverage_status == "matched", positive_districts > 1L) |>
  arrange(positive_districts, STATEFP, PUMA5CE) |>
  slice_head(n = 1L)

state_indices <- split(seq_len(nrow(people)), people$STATEFIP)
allocate_state <- function(i) {
  plan <- state_plan[i, ]
  state <- as.integer(plan$STATEFP)
  source_rows <- state_indices[[as.character(state)]]
  residents <- people[source_rows, , drop = FALSE]
  residents$person_row <- seq_len(nrow(residents))
  weights <- filter(districts, STATEFIP == state)
  pairs <- inner_join(
    residents, weights, by = c("STATEFIP", "PUMA"), relationship = "many-to-many"
  ) |>
    mutate(allocated_person_weight = PERWT * allocation_weight)

  # Verify the actual expansion for each person using the positive district
  # count from the independent Section 1 summary.
  support <- filter(coverage, STATEFP == plan$STATEFP, coverage_status == "matched")
  district_counts <- support$positive_districts[
    match(residents$PUMA, as.integer(support$PUMA5CE))
  ]
  check(
    nrow(pairs) == plan$expected_rows && nrow(residents) == plan$person_records &&
      all(tabulate(pairs$person_row, nbins = nrow(residents)) == district_counts),
    paste("Unexpected person/district row counts for state", plan$STATEFP)
  )

  # Section 1 uses 1e-12 for probabilities. Scale that rounding tolerance
  # by the original survey weight when checking weighted counts.
  tolerance <- 1e-12
  totals <- rowsum(cbind(probability = pairs$allocation_weight,
                         weight = pairs$allocated_person_weight),
                   group = pairs$person_row, reorder = TRUE)
  check(identical(as.integer(rownames(totals)), residents$person_row),
        paste("Missing or misordered person totals for state", plan$STATEFP))
  error <- abs(totals[, "weight"] - residents$PERWT)
  allocated_weight <- sum(pairs$allocated_person_weight)
  check(
    all(is.finite(pairs$allocated_person_weight) & pairs$allocated_person_weight > 0) &&
      all(abs(totals[, "probability"] - 1) <= tolerance) &&
      all(error <= tolerance * pmax(1, residents$PERWT)) &&
      abs(allocated_weight - plan$input_weight) <= tolerance * max(1, plan$input_weight),
    paste("District contributions do not reconcile for state", plan$STATEFP)
  )

  if (nrow(example) == 1L && plan$STATEFP == example$STATEFP) {
    example_person <- match(as.integer(example$PUMA5CE), residents$PUMA)
    cat("\nOne person in a split PUMA:\n")
    pairs |>
      filter(person_row == example_person) |>
      select(STATEFIP, PUMA, CDFP, PERWT, allocation_weight, allocated_person_weight) |>
      tibble::as_tibble() |>
      print(n = Inf, width = Inf)
  }
  audit <- transmute(plan, STATEFP, person_records, expected_rows,
                     allocated_rows = nrow(pairs), input_weight,
                     allocated_weight = allocated_weight,
                     max_person_weight_error = max(error))
  list(
    person_row = source_rows[pairs$person_row],
    district_row = pairs$district_row,
    contribution = pairs$allocated_person_weight,
    audit = audit
  )
}

parts <- lapply(seq_len(nrow(state_plan)), allocate_state)
state_audit <- bind_rows(lapply(parts, "[[", "audit"))
# Keep only the checked weights and row indices from each state in memory.
# Gather the output columns once, after the temporary state joins have finished.
collect_column <- function(name) unlist(lapply(parts, "[[", name), use.names = FALSE)
person_rows <- collect_column("person_row")
district_rows <- collect_column("district_row")
contributions <- collect_column("contribution")
rm(parts)
allocation <- people[person_rows, , drop = FALSE] |>
  mutate(CDFP = districts$CDFP[district_rows],
         allocation_weight = districts$allocation_weight[district_rows],
         allocated_person_weight = contributions) |>
  relocate(CDFP, .before = PERWT)
rm(person_rows, district_rows, contributions)
input_weight <- sum(people$PERWT)
national_weight <- sum(allocation$allocated_person_weight)
check(
  sum(state_audit$person_records) == nrow(people) &&
    sum(state_audit$allocated_rows) == nrow(allocation) &&
    nrow(allocation) == sum(state_plan$expected_rows) &&
    abs(national_weight - input_weight) <= 1e-12 * max(1, input_weight),
  "National row counts or allocated weights do not reconcile."
)

allocation_path <- file.path(intermediate_dir, "pums_cd_allocation.rds")
state_audit_path <- file.path(output_dir, "03_pums_allocation_by_state.csv")
save_results <- function() {
  staged_rds <- tempfile("pums_cd_", tmpdir = intermediate_dir)
  staged_csv <- tempfile("pums_cd_", tmpdir = output_dir)
  previous_csv <- tempfile("previous_allocation_audit_", tmpdir = output_dir)
  on.exit(unlink(c(staged_rds, staged_csv)), add = TRUE)
  saveRDS(allocation, staged_rds)
  readr::write_csv(state_audit, staged_csv)
  # Keep a copy of the small previous audit until its matching RDS is replaced.
  had_audit <- file.exists(state_audit_path)
  if (had_audit) {
    check(file.copy(state_audit_path, previous_csv), "Could not back up the state audit.")
  }
  if (!file.rename(staged_csv, state_audit_path)) {
    unlink(previous_csv)
    stop("Could not save the state audit.", call. = FALSE)
  }
  if (!file.rename(staged_rds, allocation_path)) {
    restored <- if (had_audit) {
      file.rename(previous_csv, state_audit_path)
    } else {
      file.remove(state_audit_path)
    }
    check(restored,
          paste("Could not restore the prior state audit. Review", state_audit_path, "and", previous_csv))
    stop("Could not save the allocation RDS. Restored the previous audit state.", call. = FALSE)
  }
  unlink(previous_csv)
}
cat("\nSaving checked person/district allocations...\n")
save_results()
cat("Allocation checks passed.\n")
cat("Person records:", nrow(people), "\n")
cat("Person/district rows:", nrow(allocation), "\n")
cat("Input weighted population:", format(input_weight, scientific = FALSE), "\n")
cat("Allocated weighted population:", format(national_weight, scientific = FALSE), "\n")
cat("Largest absolute person-weight error:", max(state_audit$max_person_weight_error), "\n")
cat("Allocation saved:", allocation_path, "\nState audit saved:", state_audit_path, "\n")
