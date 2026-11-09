# Checks and audit files for 03_apply_puma_cd_crosswalk.R.
check <- function(condition, message) {
  if (!isTRUE(condition)) stop(message, call. = FALSE)
}

# Compare the state/PUMA pairs on the two files before expanding any person.
# A PUMA found only in the crosswalk is reported. A PUMA found only in PUMS
# would leave people unallocated, so we write the coverage audit and stop.
audit_puma_coverage <- function(pums, crosswalk, output_dir, tolerance) {
  required_pums <- c("SAMPLE", "YEAR", "STATEFIP", "PUMA", "PERWT")
  required_crosswalk <- c("STATEFP", "PUMA5CE", "CDFP", "allocation_weight")
  check(
    all(required_pums %in% names(pums)) && all(required_crosswalk %in% names(crosswalk)),
    "Required input columns are missing."
  )
  check(
    nrow(pums) > 0L && nrow(crosswalk) > 0L &&
      all(vapply(pums[required_pums], is.numeric, logical(1))),
    "PUMS columns must be numeric and both inputs must contain records."
  )

  # The IPUMS codebook checked in Step 01 identifies the 2020 PUMA definitions
  # for this five-year extract. SAMPLE and YEAR identify that extract here.
  check(
    all(pums$SAMPLE == 202403 & pums$YEAR == 2024),
    "Unexpected PUMS sample or year; review geographic compatibility."
  )
  check(
    all(is.finite(pums$PERWT) & pums$PERWT > 0),
    "Missing, nonfinite or nonpositive person weights."
  )

  pums_by_puma <- count_people_by_puma(pums)
  crosswalk_by_puma <- count_districts_by_puma(crosswalk, tolerance)
  coverage <- full_join(
    pums_by_puma, crosswalk_by_puma,
    by = c("STATEFP", "PUMA5CE"), relationship = "one-to-one"
  ) |>
    mutate(
      coverage_status = case_when(
        is.na(person_records) ~ "crosswalk_only",
        is.na(weight_sum) ~ "pums_only",
        TRUE ~ "matched"
      )
    ) |>
    arrange(STATEFP, PUMA5CE)

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
  cat("Weighted population without a crosswalk:", sum(pums_only$weighted_population), "\n")
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
  coverage
}

count_people_by_puma <- function(pums) {
  # Count on the numeric PUMS keys first. Only the small PUMA summary needs
  # its codes padded with leading zeroes to match the Census crosswalk.
  counts <- pums |>
    group_by(STATEFIP, PUMA) |>
    summarise(
      person_records = n(),
      weighted_population = sum(PERWT),
      .groups = "drop"
    )

  valid_code <- function(code, largest) {
    all(is.finite(code) & code == trunc(code) & code >= 1 & code <= largest)
  }
  check(
    valid_code(counts$STATEFIP, 99) && valid_code(counts$PUMA, 99999),
    "PUMS geographic codes cannot be formatted as the expected identifiers."
  )
  counts |>
    transmute(
      STATEFP = sprintf("%02d", as.integer(STATEFIP)),
      PUMA5CE = sprintf("%05d", as.integer(PUMA)),
      person_records, weighted_population
    )
}

count_districts_by_puma <- function(crosswalk, tolerance) {
  # The crosswalk stores state, PUMA and district as fixed-width text. This
  # preserves codes such as 00 and lets us check uniqueness on all three keys.
  keys <- crosswalk[c("STATEFP", "PUMA5CE", "CDFP")]
  check(
    all(vapply(keys, is.character, logical(1))) && !anyNA(keys) &&
      all(grepl("^[0-9]{2}$", keys$STATEFP)) &&
      all(grepl("^[0-9]{5}$", keys$PUMA5CE)) &&
      all(grepl("^[0-9]{2}$", keys$CDFP)) &&
      anyDuplicated(keys) == 0L,
    "Crosswalk geographic identifiers are invalid or duplicated."
  )
  probability <- crosswalk$allocation_weight
  check(
    is.numeric(probability) && all(is.finite(probability)) &&
      all(probability >= 0 & probability <= 1),
    "Invalid crosswalk allocation weights."
  )

  counts <- crosswalk |>
    group_by(STATEFP, PUMA5CE) |>
    summarise(
      district_rows = n(),
      positive_districts = sum(allocation_weight > 0),
      weight_sum = sum(allocation_weight),
      .groups = "drop"
    )
  check(
    all(abs(counts$weight_sum - 1) <= tolerance),
    "Crosswalk weights do not sum to one within every PUMA."
  )
  counts
}

audit_state_allocation <- function(plan, residents, pairs, state_pumas, tolerance) {
  # First check each resident got exactly the districts counted in Section 1.
  puma_row <- match(residents$PUMA, as.integer(state_pumas$PUMA5CE))
  expected_rows_per_person <- state_pumas$positive_districts[puma_row]
  actual_rows_per_person <- tabulate(pairs$state_person_row, nbins = nrow(residents))
  check(
    nrow(pairs) == plan$expected_rows && nrow(residents) == plan$person_records &&
      all(actual_rows_per_person == expected_rows_per_person),
    paste("Unexpected person/district row counts for state", plan$STATEFP)
  )

  # Add the district rows back up for each person, in the original order of
  # this state's residents. Probabilities should total 1 and weights should total PERWT.
  person_totals <- rowsum(
    cbind(probability = pairs$allocation_weight, weight = pairs$allocated_person_weight),
    group = pairs$state_person_row, reorder = TRUE
  )
  check(
    identical(as.integer(rownames(person_totals)), residents$state_person_row),
    paste("Missing or misordered person totals for state", plan$STATEFP)
  )
  person_weight_error <- abs(person_totals[, "weight"] - residents$PERWT)
  allocated_weight <- sum(pairs$allocated_person_weight)
  check(
    all(is.finite(pairs$allocated_person_weight) & pairs$allocated_person_weight > 0) &&
      all(abs(person_totals[, "probability"] - 1) <= tolerance) &&
      all(person_weight_error <= tolerance * pmax(1, residents$PERWT)) &&
      abs(allocated_weight - plan$input_weight) <= tolerance * max(1, plan$input_weight),
    paste("District contributions do not reconcile for state", plan$STATEFP)
  )

  transmute(
    plan, STATEFP, person_records, expected_rows,
    allocated_rows = nrow(pairs), input_weight, allocated_weight = allocated_weight,
    max_person_weight_error = max(person_weight_error)
  )
}

save_allocation_and_audit <- function(allocation, state_audit, allocation_path, state_audit_path) {
  # Write both files to temporary names first. Keep the previous audit until
  # we have replaced its matching allocation, so we can restore it on failure.
  staged_rds <- tempfile("pums_cd_", tmpdir = dirname(allocation_path))
  staged_csv <- tempfile("pums_cd_", tmpdir = dirname(state_audit_path))
  previous_csv <- tempfile("previous_allocation_audit_", tmpdir = dirname(state_audit_path))
  on.exit(unlink(c(staged_rds, staged_csv)), add = TRUE)
  saveRDS(allocation, staged_rds)
  readr::write_csv(state_audit, staged_csv)

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
    check(
      restored,
      paste("Could not restore the prior state audit. Review", state_audit_path, "and", previous_csv)
    )
    stop("Could not save the allocation RDS. Restored the previous audit state.", call. = FALSE)
  }
  unlink(previous_csv)
}
