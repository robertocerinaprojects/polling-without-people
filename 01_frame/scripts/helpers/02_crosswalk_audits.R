# Checks used in Sections 10 and 11 of 02_build_puma_cd_crosswalk.R.

# Numerical tolerance for floating-point arithmetic, not statistical error.
cvap_close <- function(actual, expected) {
  is.finite(actual) & is.finite(expected) &
    abs(actual - expected) <= 1e-8 + 1e-12 * abs(expected)
}

# A total containing unknown contributions must remain unknown.
sum_cvap_or_na <- function(x) {
  if (anyNA(x)) NA_real_ else sum(x)
}

check_contribution_inputs <- function(parts, expected_rows) {
  allowed_methods <- c(
    "adult_proportions", "direct_containment",
    "exclude_unassigned", "missing_cvap",
    "structural_zero_reviewed", "zero_cvap"
  )

  check(
    nrow(parts) == expected_rows &&
      anyDuplicated(select(parts, STATEFP, bg_cvap, PUMA5CE, CDFP)) == 0L &&
      !anyNA(parts$allocation_case) &&
      all(parts$allocation_case %in% allowed_methods) &&
      !anyNA(parts$block_group_adults),
    "Contribution inputs have missing methods, duplicated cells or unmatched rows."
  )

  zero_case <- parts$allocation_case %in% c(
    "zero_cvap", "structural_zero_reviewed", "exclude_unassigned"
  )
  direct_case <- parts$allocation_case == "direct_containment"
  adult_case <- parts$allocation_case == "adult_proportions"

  direct_counts <- parts |>
    filter(allocation_case == "direct_containment") |>
    count(STATEFP, bg_cvap, name = "target_cells")

  check(
    all(direct_counts$target_cells == 1L) &&
      all(parts$CDFP[direct_case] != "ZZ") &&
      all(parts$block_group_cvap[zero_case] == 0) &&
      all(parts$block_group_adults[adult_case] > 0),
    "Direct allocation, zero allocation or adult denominators are inconsistent."
  )
}

audit_block_group_contributions <- function(bg_cvap_contributions, allocation_readiness,
                                            ny_missing, output_dir) {
  amount <- bg_cvap_contributions$cvap_contribution
  suppressed <- bg_cvap_contributions$allocation_case == "missing_cvap"
  unassigned <- bg_cvap_contributions$CDFP == "ZZ"
  observed <- amount[!is.na(amount)]

  check(
    identical(is.na(amount), suppressed) &&
      setequal(bg_cvap_contributions$bg_cvap[suppressed], ny_missing$bg_geoid) &&
      all(is.finite(observed) & observed >= 0) &&
      all(amount[unassigned] == 0),
    "Contributions contain unexpected missing, invalid or unassigned amounts."
  )

  # Reconcile once per block group, never by summing repeated source estimates.
  bg_contribution_audit <- bg_cvap_contributions |>
    group_by(STATEFP, bg_cvap) |>
    summarise(
      cell_rows = n(),
      cell_adults = sum(vap20),
      unknown_cells = sum(is.na(cvap_contribution)),
      contributed_cvap = sum_cvap_or_na(cvap_contribution),
      .groups = "drop"
    ) |>
    left_join(
      allocation_readiness,
      by = c("STATEFP", "bg_cvap"),
      relationship = "one-to-one"
    ) |>
    mutate(
      cvap_difference = contributed_cvap - cvap_for_allocation,
      allocation_check_passed = if_else(
        is.na(cvap_for_allocation),
        is.na(contributed_cvap) & unknown_cells == cell_rows,
        unknown_cells == 0L &
          cvap_close(contributed_cvap, cvap_for_allocation)
      )
    )

  # Save detailed evidence before checking the reconciliation results.
  readr::write_csv(
    bg_cvap_contributions,
    file.path(output_dir, "02_bg_cvap_contributions.csv")
  )
  readr::write_csv(
    bg_contribution_audit,
    file.path(output_dir, "02_bg_cvap_conservation.csv")
  )

  check(
    nrow(bg_contribution_audit) == nrow(allocation_readiness) &&
      setequal(bg_contribution_audit$bg_cvap, allocation_readiness$bg_cvap) &&
      all(bg_contribution_audit$cell_rows ==
            bg_contribution_audit$intersections) &&
      all(bg_contribution_audit$cell_adults ==
            bg_contribution_audit$vap20) &&
      all(bg_contribution_audit$allocation_check_passed),
    "Block-group contribution checks failed; inspect 02_bg_cvap_conservation.csv."
  )

  # These sums cover observed estimates only; missing New York CVAP is unknown.
  expected_observed_cvap <- sum(
    allocation_readiness$cvap_for_allocation, na.rm = TRUE
  )
  contributed_observed_cvap <- sum(
    bg_cvap_contributions$cvap_contribution, na.rm = TRUE
  )

  check(
    cvap_close(contributed_observed_cvap, expected_observed_cvap),
    "National contributions do not sum to the observed adjusted CVAP inputs."
  )

  ct_land_contribution <- bg_cvap_contributions |>
    filter(bg_cvap == "091902114003")

  check(
    nrow(ct_land_contribution) == 1L &&
      ct_land_contribution$PUMA5CE[[1]] == "20904" &&
      ct_land_contribution$CDFP[[1]] == "05" &&
      ct_land_contribution$cvap_contribution[[1]] == 5,
    "The reviewed Connecticut land estimate was not allocated exactly once."
  )

  contribution_summary <- bg_contribution_audit |>
    group_by(allocation_case) |>
    summarise(
      block_groups = n(),
      expected_cvap_total = sum_cvap_or_na(cvap_for_allocation),
      contributed_cvap_total = sum_cvap_or_na(contributed_cvap),
      .groups = "drop"
    )

  cat("\nBlock-group CVAP contribution audit:\n")
  print(contribution_summary, n = Inf, width = Inf)

  cat("\nContribution checks passed for every block group.\n")
  cat("Contributed CVAP from observed estimates:",
      format(contributed_observed_cvap, scientific = FALSE, trim = TRUE), "\n")
  cat("Block groups with unknown CVAP:",
      sum(is.na(bg_contribution_audit$cvap_for_allocation)), "\n")
  cat("Largest absolute block-group balance error:",
      max(abs(bg_contribution_audit$cvap_difference), na.rm = TRUE), "\n")
  cat("Continuing with PUMA-to-district weight construction.\n")

  contributed_observed_cvap
}

check_district_aggregation <- function(assigned_intersections, district_totals,
                                       contributed_observed_cvap) {
  district_key <- c("STATEFP", "PUMA5CE", "CDFP")
  missing_pairs <- anti_join(assigned_intersections, district_totals, by = district_key)
  extra_pairs <- anti_join(district_totals, assigned_intersections, by = district_key)
  check(
    nrow(missing_pairs) == 0L && nrow(extra_pairs) == 0L &&
      cvap_close(sum(district_totals$known_cvap_subtotal), contributed_observed_cvap),
    "PUMA-district aggregation changed geographic coverage or known CVAP."
  )
}

audit_district_weights <- function(puma_cd_crosswalk, puma_allocation_audit,
                                   assigned_intersections, target_states) {
  weight <- puma_cd_crosswalk$allocation_weight
  district_keys <- select(puma_cd_crosswalk, STATEFP, PUMA5CE, CDFP)
  check(
    !anyNA(puma_cd_crosswalk) &&
      nrow(puma_cd_crosswalk) == nrow(assigned_intersections) &&
      anyDuplicated(district_keys) == 0L &&
      all(is.finite(weight) & weight >= 0 & weight <= 1) &&
      all(puma_cd_crosswalk$CDFP != "ZZ") &&
      setequal(puma_cd_crosswalk$STATEFP, target_states),
    "Crosswalk identifiers or allocation weights are invalid."
  )

  weight_sums <- puma_cd_crosswalk |>
    group_by(STATEFP, PUMA5CE) |>
    summarise(
      weight_rows = n(),
      weight_sum = sum(allocation_weight),
      zero_weight_rows = sum(allocation_weight == 0),
      .groups = "drop"
    )

  puma_allocation_audit <- puma_allocation_audit |>
    left_join(
      weight_sums,
      by = c("STATEFP", "PUMA5CE"),
      relationship = "one-to-one"
    )

  # Numerical tolerance for dimensionless weights, not statistical uncertainty.
  check(
    !anyNA(puma_allocation_audit$weight_sum) &&
      nrow(weight_sums) == nrow(puma_allocation_audit) &&
      all(puma_allocation_audit$weight_rows ==
            puma_allocation_audit$assigned_districts) &&
      all(abs(puma_allocation_audit$weight_sum - 1) <= 1e-12),
    "Crosswalk coverage or within-PUMA weight sums failed."
  )

  expected_districts <- assigned_intersections |>
    distinct(STATEFP, CDFP)

  positive_districts <- puma_cd_crosswalk |>
    filter(allocation_weight > 0) |>
    distinct(STATEFP, CDFP)

  districts_without_weight <- anti_join(
    expected_districts, positive_districts, by = c("STATEFP", "CDFP")
  )
  check(
    nrow(districts_without_weight) == 0L,
    "An assigned district has no positive allocation weight."
  )

  # Exact reviewed NY cases: see 02_cvap_allocation_decisions.md.
  ny_weights <- puma_cd_crosswalk |>
    filter(STATEFP == "36", PUMA5CE %in% c("03310", "03313"))

  ny_puma_audit <- puma_allocation_audit |>
    filter(STATEFP == "36", PUMA5CE %in% c("03310", "03313"))

  check(
    nrow(ny_weights) == 2L &&
      setequal(ny_weights$PUMA5CE, c("03310", "03313")) &&
      all(ny_weights$CDFP == "02") &&
      all(ny_weights$allocation_weight == 1) &&
      all(ny_weights$weight_method == "structural_single_district") &&
      nrow(ny_puma_audit) == 2L &&
      all(is.na(ny_puma_audit$puma_cvap)) &&
      sum(ny_puma_audit$missing_block_groups) == 39L,
    "NY containment weights or preservation of unknown CVAP failed."
  )

  puma_allocation_audit
}

publish_crosswalk <- function(puma_cd_crosswalk, puma_cd_cvap, puma_allocation_audit,
                              output_dir, blocked_path) {
  # Save outputs only after the crosswalk checks pass.
  readr::write_csv(
    puma_cd_cvap,
    file.path(output_dir, "02_puma_cd_cvap.csv")
  )
  readr::write_csv(
    puma_cd_crosswalk,
    file.path(output_dir, "02_puma_cd_weights.csv")
  )

  intermediate_dir <- here::here("01_frame", "data", "intermediate")
  dir.create(intermediate_dir, recursive = TRUE, showWarnings = FALSE)

  crosswalk_path <- file.path(intermediate_dir, "puma_cd_crosswalk.rds")
  temporary_crosswalk <- tempfile(
    pattern = "puma_cd_crosswalk_",
    tmpdir = intermediate_dir,
    fileext = ".rds"
  )
  saveRDS(puma_cd_crosswalk, temporary_crosswalk, compress = "gzip")
  check(
    file.rename(temporary_crosswalk, crosswalk_path),
    "Could not move the completed crosswalk to its final filename."
  )

  # Replace the last complete audit only after the validated crosswalk is saved.
  audit_path <- file.path(output_dir, "02_puma_allocation_audit.csv")
  temporary_audit <- tempfile("puma_allocation_audit_", tmpdir = output_dir)
  readr::write_csv(puma_allocation_audit, temporary_audit)
  check(
    file.rename(temporary_audit, audit_path),
    "Could not move the completed PUMA allocation audit to its final filename."
  )

  if (file.exists(blocked_path)) {
    check(file.remove(blocked_path), paste("Could not remove the old diagnostic:", blocked_path))
  }

  cat("\nPUMA allocation methods:\n")
  puma_allocation_audit |>
    count(weight_method, name = "pumas") |>
    print(n = Inf, width = Inf)

  cat("\nReviewed New York weights:\n")
  puma_cd_crosswalk |>
    filter(STATEFP == "36", PUMA5CE %in% c("03310", "03313")) |>
    print(n = Inf, width = Inf)

  cat("\nCrosswalk validation passed.\n")
  cat("PUMAs:", nrow(puma_allocation_audit), "\n")
  cat("Assigned districts including DC:", nrow(distinct(puma_cd_crosswalk, STATEFP, CDFP)), "\n")
  cat("PUMA-district rows:", nrow(puma_cd_crosswalk), "\n")
  cat("Zero-weight rows:",
      sum(puma_cd_crosswalk$allocation_weight == 0), "\n")
  cat("Largest within-PUMA weight-sum error:",
      max(abs(puma_allocation_audit$weight_sum - 1)), "\n")
  cat("Saved:", crosswalk_path, "\n")
  cat("PUMS coverage and application will be checked in the next stage.\n")
}
