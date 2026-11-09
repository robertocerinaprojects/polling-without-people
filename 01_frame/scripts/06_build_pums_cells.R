# Count citizen adults by 2026 House district and demographic profile.
# Run from the repository root: Rscript 01_frame/scripts/06_build_pums_cells.R
# Method and outputs: 01_frame/docs/06_build_pums_cells.md
#
# The population frame has one row per profile with positive PUMS weight.
# The CES audit has one row per profile reported by a survey respondent.

library(dplyr)

build_pums_cells <- function(data_dir = file.path("01_frame", "data")) {
  intermediate <- file.path(data_dir, "intermediate")
  output <- file.path(data_dir, "output")

  person_key <- c("SAMPLE", "SERIAL", "PERNUM")
  district_key <- c("STATEFP", "CDFP120")
  demographics <- c("age_cat", "gender_cat", "race_cat", "hispanic_cat", "educ_cat")
  cell_key <- c(district_key, demographics)

  # Read the person records, their district weights, and the CES profiles ----
  allocation <- readRDS(file.path(intermediate, "pums_cd_allocation.rds"))
  people <- readRDS(file.path(intermediate, "pums_demographics.rds"))
  ces <- readRDS(file.path(intermediate, "ces_demographics_harmonized.rds"))
  state_totals <- read.csv(
    file.path(output, "03_pums_allocation_by_state.csv"),
    colClasses = c(STATEFP = "character")
  )

  allocation_fields <- c(person_key, "STATEFIP", "CDFP", "allocated_person_weight")
  state_fields <- c("STATEFP", "person_records", "allocated_rows",
                    "input_weight", "allocated_weight")
  stopifnot(
    "Missing columns in the Step 03 district allocations." =
      all(allocation_fields %in% names(allocation)),
    "Missing columns in the Step 04 person table." =
      all(c(person_key, demographics) %in% names(people)),
    "Missing columns in the Step 05 CES." = all(c("caseid", cell_key) %in% names(ces)),
    "Missing columns in the Step 03 state totals." = all(state_fields %in% names(state_totals))
  )

  # A person can contribute to several districts. Their demographics appear
  # just once, under the same three-part identifier in the Step 04 person table.
  stopifnot(
    "Expected a complete demographic profile for each PUMS person." =
      nrow(people) > 0L && !anyNA(people[c(person_key, demographics)]),
    "Duplicate PUMS person identifier." = !vctrs::vec_duplicate_any(people[person_key]),
    "Missing or duplicate CES respondent identifiers." =
      !anyNA(ces$caseid) && !anyDuplicated(ces$caseid),
    "Missing CES state or district." = !anyNA(ces[district_key])
  )

  # Use the CES label order for both datasets, including unused factor levels.
  for (field in demographics) {
    ces_labels <- levels(ces[[field]])
    pums_values <- people[[field]]
    pums_labels <- if (is.factor(pums_values)) {
      levels(pums_values)
    } else {
      unique(as.character(pums_values))
    }
    if (!length(ces_labels) || !setequal(pums_labels, ces_labels)) {
      stop("Different CES/PUMS category labels in ", field, call. = FALSE)
    }
    people[[field]] <- factor(pums_values, levels = ces_labels)
  }

  # Locate each allocation row's person once. Keep only the columns needed
  # below so we can attach demographics one state at a time.
  person_row_for_allocation <- vctrs::vec_match(allocation[person_key], people[person_key])
  n_people <- nrow(people)
  stopifnot(
    "An allocation row has no PUMS person." = !anyNA(person_row_for_allocation),
    "A PUMS person has no district allocation." =
      all(tabulate(person_row_for_allocation, nbins = n_people) > 0L)
  )
  people <- people[demographics]
  allocation <- allocation[c("STATEFIP", "CDFP", "allocated_person_weight")]
  stopifnot(
    "Expected whole-number PUMS state codes." =
      is.numeric(allocation$STATEFIP) && all(is.finite(allocation$STATEFIP)) &&
      all(allocation$STATEFIP == trunc(allocation$STATEFIP)),
    "Expected two-digit district codes." = is.character(allocation$CDFP) &&
      !anyNA(allocation$CDFP) && all(grepl("^[0-9]{2}$", allocation$CDFP)),
    "Expected positive, finite district weights." =
      all(is.finite(allocation$allocated_person_weight) & allocation$allocated_person_weight > 0)
  )

  # Add up district weights within each demographic cell ----
  state_totals <- state_totals[order(state_totals$STATEFP), ]
  allocation_states <- sprintf("%02d", sort(unique(allocation$STATEFIP)))
  stopifnot(
    "State coverage differs from the Step 03 audit for 50 states and DC." =
      nrow(state_totals) == 51L && !anyDuplicated(state_totals$STATEFP) &&
      setequal(allocation_states, state_totals$STATEFP)
  )
  state_order <- factor(allocation$STATEFIP, levels = as.integer(state_totals$STATEFP))
  rows_by_state <- split(seq_len(nrow(allocation)), state_order)
  rm(state_order)

  # Step 03 has already split each person's survey weight. If a weight of
  # 20 became 14 and 6, add 14 to one district's cell and 6 to the other's.
  state_cells <- vector("list", nrow(state_totals))
  for (i in seq_len(nrow(state_totals))) {
    state <- state_totals$STATEFP[i]
    allocation_rows <- rows_by_state[[i]]
    person_rows <- person_row_for_allocation[allocation_rows]
    district <- allocation$CDFP[allocation_rows]

    if (!isTRUE(length(allocation_rows) == state_totals$allocated_rows[i])) {
      stop("State ", state, ": number of district allocations differs from Step 03.", call. = FALSE)
    }
    if (!isTRUE(n_distinct(person_rows) == state_totals$person_records[i])) {
      stop("State ", state, ": person count differs from Step 03.", call. = FALSE)
    }
    if (vctrs::vec_duplicate_any(data.frame(person = person_rows, district = district))) {
      stop("State ", state, ": a person's district contribution appears twice.", call. = FALSE)
    }

    contributions <- bind_cols(tibble(CDFP120 = district), people[person_rows, , drop = FALSE])
    contributions$allocated_person_weight <- allocation$allocated_person_weight[allocation_rows]
    cells <- contributions |>
      group_by(across(all_of(c("CDFP120", demographics)))) |>
      summarise(N = sum(allocated_person_weight), .groups = "drop") |>
      mutate(STATEFP = state, .before = 1)

    state_population <- sum(cells$N)
    if (!weights_agree(state_population, state_totals$input_weight[i]) ||
        !weights_agree(state_population, state_totals$allocated_weight[i])) {
      stop("State ", state, ": cell weights differ from Step 03.", call. = FALSE)
    }
    state_cells[[i]] <- cells
  }

  frame <- bind_rows(state_cells)
  districts <- distinct(frame, STATEFP, CDFP120)
  dc_district <- districts$CDFP120[districts$STATEFP == "11"]
  stopifnot(
    "National person count differs from Step 03." = sum(state_totals$person_records) == n_people,
    # Step 02 verified the 435 voting districts and DC's delegate district (11/98).
    "Unexpected district coverage." = nrow(districts) == 436L && identical(dc_district, "98"),
    "Expected one positive population per cell." = identical(names(frame), c(cell_key, "N")) &&
      !vctrs::vec_duplicate_any(frame[cell_key]) && all(frame$N > 0),
    "National cell population differs from Step 03." =
      weights_agree(sum(frame$N), sum(state_totals$input_weight))
  )

  # Compare the profiles reported in the CES with the population frame ----
  stopifnot(
    "Expected two-digit CES state and district codes." =
      all(vapply(ces[district_key], is.character, logical(1))) &&
      all(grepl("^[0-9]{2}$", ces$STATEFP)) && all(grepl("^[0-9]{2}$", ces$CDFP120)),
    "Expected DC in the CES and a frame district for every respondent." =
      any(ces$STATEFP == "11" & ces$CDFP120 == "98") &&
      !anyNA(vctrs::vec_match(ces[district_key], districts))
  )

  # Count survey respondents before joining N. When all seven fields are
  # known, an absent cell has zero weight in this frame. With a missing key
  # we cannot identify the cell, so its population stays NA.
  coverage <- ces |>
    group_by(across(all_of(cell_key))) |>
    summarise(ces_respondents = n(), .groups = "drop") |>
    left_join(frame, by = cell_key, na_matches = "never") |>
    mutate(
      coverage_status = case_when(
        if_any(all_of(cell_key), is.na) ~ "missing_ces_key",
        is.na(N) ~ "no_positive_pums_cell",
        TRUE ~ "matched_positive_N"
      ),
      N = if_else(coverage_status == "no_positive_pums_cell", 0, N)
    )
  stopifnot(
    "Expected each CES respondent to count once across distinct profiles." =
      !vctrs::vec_duplicate_any(coverage[cell_key]) && sum(coverage$ces_respondents) == nrow(ces),
    "Only an incomplete CES profile may have an unknown cell population." =
      all(is.na(coverage$N) == (coverage$coverage_status == "missing_ces_key"))
  )

  # Write both temporary files before publishing the coverage audit and frame ----
  frame_path <- file.path(intermediate, "pums_cd_cells.rds")
  audit_path <- file.path(output, "06_ces_pums_cell_coverage.csv")
  temporary_frame <- tempfile(".06-cells-", tmpdir = intermediate)
  temporary_audit <- tempfile(".06-coverage-", tmpdir = output)
  on.exit(unlink(c(temporary_frame, temporary_audit)), add = TRUE)
  saveRDS(frame, temporary_frame)
  readr::write_csv(coverage, temporary_audit)
  if (!file.rename(temporary_audit, audit_path)) stop("Could not save ", audit_path)
  if (!file.rename(temporary_frame, frame_path)) stop("Could not save ", frame_path)

  cat("PUMS people:", n_people, "\nPositive population cells:", nrow(frame),
      "\nState/district pairs including DC:", nrow(districts),
      "\nAllocated CVAP:", format(sum(frame$N), scientific = FALSE), "\n")
  coverage_summary <- coverage |>
    group_by(coverage_status) |>
    summarise(ces_respondents = sum(ces_respondents), cells = n(), .groups = "drop")
  print(coverage_summary)
  cat("Population cells:", frame_path, "\nCES coverage audit:", audit_path, "\n")
  invisible(frame_path)
}

# Fractional person weights can accumulate floating-point rounding error.
weights_agree <- function(value, reference) {
  tolerance <- 1e-12 * pmax(1, abs(reference))
  all(is.finite(value) & is.finite(reference) & abs(value - reference) <= tolerance)
}

if (sys.nframe() == 0L) build_pums_cells()
