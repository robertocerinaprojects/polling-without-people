# Split each citizen adult's PUMS survey weight among 120th Congress districts.
# Run from the repository root: Rscript 01_frame/scripts/03_apply_puma_cd_crosswalk.R
# Worked example and output columns: 01_frame/docs/03_apply_puma_cd_crosswalk.md
#
# A person with weight 20 in a PUMA split 70% / 30% contributes 14 to one
# district and 6 to the other. Both rows keep the same person ID. Section 2
# makes those rows; Section 3 saves them after checking the national totals.

library(dplyr)

source(here::here("01_frame", "scripts", "helpers", "03_allocation_audits.R"),
       local = TRUE)

# Section 1: Can we locate every person in the district crosswalk? ----
intermediate_dir <- here::here("01_frame", "data", "intermediate")
output_dir <- here::here("01_frame", "data", "output")
pums_path <- file.path(intermediate_dir, "pums_clean.rds")
crosswalk_path <- file.path(intermediate_dir, "puma_cd_crosswalk.rds")

check(
  all(file.exists(c(pums_path, crosswalk_path))),
  "Missing input: run Scripts 01 and 02 first."
)
cat("Reading cleaned PUMS and crosswalk...\n")
pums <- readRDS(pums_path)
crosswalk <- readRDS(crosswalk_path)

# Use the same rounding tolerance for district probabilities as Step 02.
# When comparing population counts, scale it by the original survey weight.
tolerance <- 1e-12
coverage <- audit_puma_coverage(pums, crosswalk, output_dir, tolerance)

# Keep the person ID from Step 01, their PUMA and their survey weight.
# Demographics stay in pums_clean.rds and can be joined back on this ID.
person_key <- c("SAMPLE", "SERIAL", "PERNUM")
check(all(person_key %in% names(pums)), "Required person identifiers are missing.")
people <- select(pums, all_of(person_key), STATEFIP, PUMA, PERWT)
rm(pums)
check(
  !anyNA(people[person_key]) &&
    n_distinct(people$SAMPLE, people$SERIAL, people$PERNUM) == nrow(people),
  "Expected one input row per SAMPLE, SERIAL and PERNUM."
)

# Section 2: Make one row per person and positive-probability district ----
# PUMA numbers can repeat across states. Use both state and PUMA in the join.
# Keep CDFP as text so district codes such as 00 (at-large) keep their zeroes.
districts <- crosswalk |>
  filter(allocation_weight > 0) |>
  transmute(
    STATEFIP = as.integer(STATEFP), PUMA = as.integer(PUMA5CE),
    CDFP, allocation_weight
  ) |>
  arrange(STATEFIP, PUMA, CDFP) |>
  mutate(district_row = row_number())

# Predict the number of rows from the coverage audit before joining any people.
# Each PUMA contributes its number of people times its number of positive districts.
matched_pumas <- filter(coverage, coverage_status == "matched")
state_plan <- matched_pumas |>
  group_by(STATEFP) |>
  summarise(
    expected_rows = sum(as.double(person_records) * positive_districts),
    input_weight = sum(weighted_population),
    person_records = sum(person_records),
    .groups = "drop"
  )
cat("Expected positive-probability person/district rows:",
    format(sum(state_plan$expected_rows), scientific = FALSE), "\n")

# Pick one split PUMA so the console can show a real person's allocation.
example_puma <- matched_pumas |>
  filter(positive_districts > 1L) |>
  arrange(positive_districts, STATEFP, PUMA5CE) |>
  slice_head(n = 1L)

# Expand one state at a time. Keep just the two source row numbers and the
# allocated weight from each join; the full national table is assembled once.
pums_rows_by_state <- split(seq_len(nrow(people)), people$STATEFIP)
person_indices <- vector("list", nrow(state_plan))
district_indices <- vector("list", nrow(state_plan))
allocated_weights <- vector("list", nrow(state_plan))
audits_by_state <- vector("list", nrow(state_plan))

for (i in seq_len(nrow(state_plan))) {
  plan <- state_plan[i, ]
  state_fips <- as.integer(plan$STATEFP)
  pums_rows <- pums_rows_by_state[[as.character(state_fips)]]
  residents <- people[pums_rows, , drop = FALSE]
  residents$state_person_row <- seq_len(nrow(residents))
  state_districts <- filter(districts, STATEFIP == state_fips)

  # Every person in this PUMA receives the same district probabilities.
  # PERWT stays on each row; allocated_person_weight is what we add by district.
  pairs <- inner_join(
    residents, state_districts,
    by = c("STATEFIP", "PUMA"), relationship = "many-to-many"
  ) |>
    mutate(allocated_person_weight = PERWT * allocation_weight)

  state_pumas <- filter(matched_pumas, STATEFP == plan$STATEFP)
  audits_by_state[[i]] <- audit_state_allocation(
    plan, residents, pairs, state_pumas, tolerance
  )

  if (nrow(example_puma) == 1L && plan$STATEFP == example_puma$STATEFP) {
    example_person <- match(as.integer(example_puma$PUMA5CE), residents$PUMA)
    cat("\nOne person in a split PUMA:\n")
    pairs |>
      filter(state_person_row == example_person) |>
      select(STATEFIP, PUMA, CDFP, PERWT, allocation_weight, allocated_person_weight) |>
      tibble::as_tibble() |>
      print(n = Inf, width = Inf)
  }

  # state_person_row counts from 1 inside this state. Convert it back to
  # a row in the original PUMS file before combining states.
  person_indices[[i]] <- pums_rows[pairs$state_person_row]
  district_indices[[i]] <- pairs$district_row
  allocated_weights[[i]] <- pairs$allocated_person_weight
  rm(residents, pairs)
}

# Section 3: Assemble the national file and check the totals before saving ----
pums_rows <- unlist(person_indices, use.names = FALSE)
district_rows <- unlist(district_indices, use.names = FALSE)
contributions <- unlist(allocated_weights, use.names = FALSE)
state_audit <- bind_rows(audits_by_state)
rm(person_indices, district_indices, allocated_weights, audits_by_state)

allocation <- people[pums_rows, , drop = FALSE] |>
  mutate(
    CDFP = districts$CDFP[district_rows],
    allocation_weight = districts$allocation_weight[district_rows],
    allocated_person_weight = contributions
  ) |>
  relocate(CDFP, .before = PERWT)
rm(pums_rows, district_rows, contributions)

input_weight <- sum(people$PERWT)
national_weight <- sum(allocation$allocated_person_weight)
check(
  sum(state_audit$person_records) == nrow(people) &&
    sum(state_audit$allocated_rows) == nrow(allocation) &&
    nrow(allocation) == sum(state_plan$expected_rows) &&
    abs(national_weight - input_weight) <= tolerance * max(1, input_weight),
  "National row counts or allocated weights do not reconcile."
)

allocation_path <- file.path(intermediate_dir, "pums_cd_allocation.rds")
state_audit_path <- file.path(output_dir, "03_pums_allocation_by_state.csv")
cat("\nSaving checked person/district allocations...\n")
save_allocation_and_audit(allocation, state_audit, allocation_path, state_audit_path)

cat("Allocation checks passed.\n")
cat("Person records:", nrow(people), "\n")
cat("Person/district rows:", nrow(allocation), "\n")
cat("Input weighted population:", format(input_weight, scientific = FALSE), "\n")
cat("Allocated weighted population:", format(national_weight, scientific = FALSE), "\n")
cat("Largest absolute person-weight error:", max(state_audit$max_person_weight_error), "\n")
cat("Allocation saved:", allocation_path, "\nState audit saved:", state_audit_path, "\n")
