# Section 9: choose how to allocate each block group's citizen-adult estimate ----
# Sections 10 and 11 use the original geography to check containment and the ACS
# geography to calculate contributions. Keep both sets of intersections.
prepare_allocation_inputs <- function(block_cd, national_cvap_source, ct_candidate_audit,
                                      ny_missing, target_states, output_dir) {
  geography <- build_block_group_geography(block_cd, ct_candidate_audit)
  cases <- classify_cvap_block_groups(
    geography$bg_target_cells, national_cvap_source, target_states
  )
  allocation_readiness <- apply_reviewed_cvap_adjustments(
    cases, geography$bg_target_cells, output_dir
  )

  audit_allocation_inputs(
    geography$bg_links, geography$bg_target_cells, allocation_readiness, ny_missing, output_dir
  )
  list(
    bg_2020_cells = geography$bg_2020_cells,
    bg_target_cells = geography$bg_target_cells,
    allocation_readiness = allocation_readiness
  )
}

# 9a. Match 2020 block groups to the block groups in the ACS release ----
build_block_group_geography <- function(block_cd, ct_candidate_audit) {
  # Each row of bg_2020_cells is the portion of a 2020 block group in one PUMA
  # and district. Keep counts for all residents (pop20) and adults (vap20).
  # The first 12 block-ID digits identify the block group: state (2), county (3),
  # tract (6), then the block-group digit (1).
  bg_2020_cells <- block_cd |>
    mutate(bg_2020 = substr(GEOID, 1L, 12L)) |>
    group_by(STATEFP, bg_2020, PUMA5CE, CDFP) |>
    summarise(
      blocks = n(),
      pop20 = sum(pop20),
      vap20 = sum(vap20),
      .groups = "drop"
    )

  check(
    !anyNA(bg_2020_cells) &&
      sum(bg_2020_cells$blocks) == nrow(block_cd) &&
      sum(bg_2020_cells$pop20) == sum(block_cd$pop20) &&
      sum(bg_2020_cells$vap20) == sum(block_cd$vap20),
    "Original block-group aggregation changed block or population totals."
  )

  bg_2020_totals <- bg_2020_cells |>
    group_by(STATEFP, bg_2020) |>
    summarise(
      pop20 = sum(pop20),
      vap20 = sum(vap20),
      .groups = "drop"
    )

  # In Connecticut, Section 8 reviewed which old-to-new ID pairs are valid.
  # Elsewhere the two sources use the same block-group IDs.
  ct_valid_pairs <- ct_candidate_audit |>
    filter(present_in_cvap)
  ct_source_counts <- count(ct_valid_pairs, bg_2020, name = "targets")
  ct_target_counts <- count(ct_valid_pairs, bg_cvap, name = "sources")

  # Some water areas split or merge. Keep every possible link for locating
  # their blocks. A populated 2020 block group must have exactly one destination.
  ct_split_sources <- ct_source_counts |> filter(targets > 1L) |> pull(bg_2020)
  ct_merged_targets <- ct_target_counts |> filter(sources > 1L) |> pull(bg_cvap)
  ct_valid_pairs <- ct_valid_pairs |>
    mutate(coverage_only = bg_2020 %in% ct_split_sources | bg_cvap %in% ct_merged_targets)

  ct_water_support <- filter(ct_valid_pairs, coverage_only)
  check(
    all(ct_water_support$land_m2 == 0) &&
      all(ct_water_support$population_2020 == 0),
    "Ambiguous CT correspondence includes land or recorded population."
  )

  ct_population_links <- bg_2020_totals |>
    filter(STATEFP == "09") |>
    left_join(ct_source_counts, by = "bg_2020", relationship = "one-to-one")

  check(
    !anyNA(ct_population_links$targets) &&
      all(ct_population_links$targets[ct_population_links$pop20 > 0] == 1L),
    "A populated CT source block group lacks one reviewed destination."
  )

  ct_links <- ct_valid_pairs |>
    transmute(STATEFP = "09", bg_2020, bg_cvap, coverage_only)

  other_state_links <- bg_2020_totals |>
    filter(STATEFP != "09") |>
    transmute(STATEFP, bg_2020, bg_cvap = bg_2020, coverage_only = FALSE)

  bg_links <- bind_rows(other_state_links, ct_links)

  check(
    !anyNA(bg_links) &&
      anyDuplicated(select(bg_links, STATEFP, bg_2020, bg_cvap)) == 0L &&
      setequal(bg_links$bg_2020, bg_2020_totals$bg_2020),
    "Block-group correspondence is incomplete or duplicated."
  )

  # Sum block counts for each ACS block group, PUMA and district. Keep the
  # published ACS estimate in its own table so a split cannot count it twice.
  bg_target_cells <- bg_2020_cells |>
    left_join(
      bg_links,
      by = c("STATEFP", "bg_2020"),
      relationship = "many-to-many"
    ) |>
    group_by(STATEFP, bg_cvap, PUMA5CE, CDFP) |>
    summarise(
      source_block_links = sum(blocks),
      pop20 = sum(pop20),
      vap20 = sum(vap20),
      coverage_only = any(coverage_only),
      .groups = "drop"
    )

  check(
    !anyNA(bg_target_cells) &&
      sum(bg_target_cells$pop20) == sum(block_cd$pop20) &&
      sum(bg_target_cells$vap20) == sum(block_cd$vap20),
    "Identifier reconciliation changed recorded population totals."
  )

  # source_block_links counts links. One unpopulated Connecticut water block
  # can appear under more than one ACS block group.

  list(bg_2020_cells = bg_2020_cells, bg_links = bg_links, bg_target_cells = bg_target_cells)
}

# 9b. Choose an allocation method for each ACS block group ----
classify_cvap_block_groups <- function(bg_target_cells, national_cvap_source, target_states) {
  # Line 1 of the national ACS file is the published Total across race and ethnicity.
  cvap_totals <- national_cvap_source |>
    filter(lnnumber == 1L) |>
    transmute(
      bg_cvap = sub("^1500000US", "", geoid),
      STATEFP = substr(bg_cvap, 1L, 2L),
      cvap_est
    ) |>
    filter(STATEFP %in% target_states)

  check(
    !anyNA(cvap_totals) &&
      anyDuplicated(cvap_totals$bg_cvap) == 0L &&
      setequal(cvap_totals$STATEFP, target_states) &&
      all(is.finite(cvap_totals$cvap_est) & cvap_totals$cvap_est >= 0),
    "Invalid national CVAP Total estimates."
  )

  # Count the geographic destinations and the adults in them. ZZ means the
  # block has no district assignment. Compute its adult subtotal from the
  # original cell counts before renaming the block-group totals.
  bg_coverage <- bg_target_cells |>
    group_by(STATEFP, bg_cvap) |>
    summarise(
      intersections = n(),
      pumas = n_distinct(PUMA5CE),
      has_unassigned = any(CDFP == "ZZ"),
      wholly_unassigned = all(CDFP == "ZZ"),
      pop20_total = sum(pop20),
      vap20_total = sum(vap20),
      unassigned_vap20 = sum(vap20[CDFP == "ZZ"]),
      coverage_only = any(coverage_only),
      .groups = "drop"
    ) |>
    rename(
      pop20 = pop20_total,
      vap20 = vap20_total
    )

  check(
    !anyNA(bg_coverage) &&
      all(is.finite(bg_coverage$vap20)) &&
      all(is.finite(bg_coverage$unassigned_vap20)) &&
      all(bg_coverage$vap20 >= 0 &
          bg_coverage$vap20 <= bg_coverage$pop20) &&
      all(bg_coverage$unassigned_vap20 >= 0 &
          bg_coverage$unassigned_vap20 <= bg_coverage$vap20) &&
      sum(bg_coverage$vap20) == sum(bg_target_cells$vap20) &&
      sum(bg_coverage$unassigned_vap20) ==
        sum(bg_target_cells$vap20[bg_target_cells$CDFP == "ZZ"]),
    "Block-group adult totals or unassigned subtotals do not reconcile."
  )

  # A full join also exposes an estimate without mapped blocks or mapped
  # blocks without an estimate. Sections 9d and 10 use these case labels.
  full_join(
    bg_coverage,
    cvap_totals,
    by = c("STATEFP", "bg_cvap"),
    relationship = "one-to-one"
  ) |>
    mutate(
      allocation_case = case_when(
        is.na(intersections) ~ "missing_geography",
        is.na(cvap_est) ~ "missing_cvap",
        cvap_est == 0 ~ "zero_cvap",
        wholly_unassigned ~ "exclude_unassigned",
        intersections == 1L & !has_unassigned ~ "direct_containment",
        vap20 > 0 & unassigned_vap20 == 0 ~ "adult_proportions",
        TRUE ~ "review_required"
      )
    ) |>
    arrange(STATEFP, bg_cvap)
}

# 9c. Apply and verify the five reviewed structural zeros ----
apply_reviewed_cvap_adjustments <- function(allocation_readiness, bg_target_cells, output_dir) {
  # These block groups span districts and have zero recorded 2020 residents.
  # Retain their published ACS estimates and set their contribution to zero.
  # IDs, estimates and districts are pinned in 01_frame/docs/02_cvap_allocation_decisions.md.
  structural_zero_rules <- tibble::tribble(
    ~bg_cvap,       ~expected_cvap, ~expected_puma, ~expected_districts,
    "060379800031", 5,              "03772",        "23,27",
    "120219900000", 4,              "02102",        "19,22",
    "120719800001", 5,              "07105",        "17,19",
    "120869806001", 5,              "08623",        "27,28",
    "120999900000", 5,              "09902",        "21,23,25"
  )

  zero_locations <- bg_target_cells |>
    semi_join(structural_zero_rules, by = "bg_cvap") |>
    group_by(bg_cvap) |>
    summarise(
      observed_pumas = paste(sort(unique(PUMA5CE)), collapse = ","),
      observed_districts = paste(sort(unique(CDFP)), collapse = ","),
      .groups = "drop"
    )

  reviewed_zero_inputs <- structural_zero_rules |>
    left_join(
      allocation_readiness,
      by = "bg_cvap",
      relationship = "one-to-one"
    ) |>
    left_join(
      zero_locations,
      by = "bg_cvap",
      relationship = "one-to-one"
    )

  # Check both the published value and the original reason for the exception.
  check(
    nrow(reviewed_zero_inputs) == 5L && !anyNA(reviewed_zero_inputs) &&
      with(reviewed_zero_inputs,
        all(cvap_est == expected_cvap & observed_pumas == expected_puma &
              observed_districts == expected_districts) &&
        all(pop20 == 0 & vap20 == 0 & pumas == 1L & intersections > 1L &
              !has_unassigned & !coverage_only & allocation_case == "review_required")
      ),
    "The five structural-zero cases no longer match their reviewed evidence."
  )

  published_before_override <- allocation_readiness$cvap_est
  cases_before_override <- allocation_readiness$allocation_case

  allocation_readiness <- allocation_readiness |>
    mutate(
      structural_zero_override = bg_cvap %in% structural_zero_rules$bg_cvap,
      cvap_structural_zero_adjustment = if_else(
        structural_zero_override, cvap_est, 0
      ),
      # A separate adjustment records CVAP entirely outside assigned districts.
      cvap_geographic_exclusion = if_else(
        allocation_case == "exclude_unassigned", cvap_est, 0
      ),
      cvap_for_allocation =
        cvap_est -
        cvap_structural_zero_adjustment -
        cvap_geographic_exclusion,
      allocation_case = if_else(
        structural_zero_override,
        "structural_zero_reviewed",
        allocation_case
      )
    )

  observed_cvap <- allocation_readiness |>
    filter(!is.na(cvap_est))

  # Every published estimate must reconcile with the amount to allocate and
  # both recorded adjustments. Preserve missing estimates and all other methods.
  ordinary_rows <- !allocation_readiness$structural_zero_override
  excluded_groups <- observed_cvap$bg_cvap[observed_cvap$cvap_geographic_exclusion > 0]
  check(
    identical(allocation_readiness$cvap_est, published_before_override) &&
      identical(
        is.na(allocation_readiness$cvap_for_allocation),
        is.na(published_before_override)
      ) &&
      all(allocation_readiness$allocation_case[ordinary_rows] ==
            cases_before_override[ordinary_rows]) &&
      with(observed_cvap,
        all(is.finite(cvap_for_allocation) & cvap_for_allocation >= 0) &&
        all(cvap_est == cvap_for_allocation + cvap_structural_zero_adjustment +
              cvap_geographic_exclusion) &&
        sum(cvap_structural_zero_adjustment) == 24 &&
        sum(cvap_geographic_exclusion) == 5
      ) &&
      setequal(excluded_groups, "091309901000"),
    "Published CVAP, allocation inputs and adjustment amounts do not reconcile."
  )

  structural_zero_audit <- allocation_readiness |>
    filter(structural_zero_override) |>
    left_join(
      zero_locations,
      by = "bg_cvap",
      relationship = "one-to-one"
    )

  readr::write_csv(
    structural_zero_audit,
    file.path(output_dir, "02_cvap_structural_zero_audit.csv")
  )

  cat("\nStructural-zero override audit:\n")
  structural_zero_audit |>
    select(
      bg_cvap, observed_pumas, observed_districts,
      cvap_est, cvap_for_allocation, cvap_structural_zero_adjustment
    ) |>
    print(n = Inf, width = Inf)

  allocation_readiness
}

# 9d. Save the allocation evidence and stop on unreviewed cases ----
audit_allocation_inputs <- function(bg_links, bg_target_cells, allocation_readiness,
                                   ny_missing, output_dir) {
  # Publish the methods and inputs before reporting an unexpected geography.
  # Section 10 uses cvap_for_allocation. The source estimate stays in cvap_est.
  readr::write_csv(
    bg_links,
    file.path(output_dir, "02_bg_identifier_links.csv")
  )
  readr::write_csv(
    bg_target_cells,
    file.path(output_dir, "02_bg_district_support.csv")
  )
  readr::write_csv(
    allocation_readiness,
    file.path(output_dir, "02_cvap_allocation_readiness.csv")
  )

  # A case with no published estimates has an unknown subtotal. Elsewhere
  # report the sum of the available estimates.
  sum_available_cvap <- function(x) {
    if (all(is.na(x))) NA_real_ else sum(x, na.rm = TRUE)
  }

  case_summary <- allocation_readiness |>
    group_by(allocation_case) |>
    summarise(
      block_groups = n(),
      missing_estimates = sum(is.na(cvap_est)),
      published_cvap = sum_available_cvap(cvap_est),
      allocation_cvap = sum_available_cvap(cvap_for_allocation),
      structural_zero_adjustment = sum(cvap_structural_zero_adjustment),
      geographic_exclusion = sum(cvap_geographic_exclusion),
      .groups = "drop"
    )

  readr::write_csv(
    case_summary,
    file.path(output_dir, "02_cvap_allocation_case_summary.csv")
  )

  cat("\nNational CVAP allocation cases:\n")
  print(case_summary, n = Inf, width = Inf)

  cat("\nPositive CVAP with zero recorded adult population (first 20):\n")
  allocation_readiness |>
    filter(cvap_est > 0, vap20 == 0) |>
    head(20L) |>
    print(n = 20, width = Inf)

  review_cases <- allocation_readiness |>
    filter(allocation_case %in% c("missing_geography", "review_required"))

  cat("\nCases requiring further review (first 20):\n")
  print(head(review_cases, 20L), n = 20, width = Inf)

  # Missing values must remain exactly the previously verified NY omissions.
  missing_cvap_ids <- allocation_readiness$bg_cvap[
    allocation_readiness$allocation_case == "missing_cvap"
  ]
  check(
    setequal(missing_cvap_ids, ny_missing$bg_geoid),
    "Missing CVAP does not match the reviewed New York suppression list."
  )

  # Two Connecticut estimates of five have different destinations. The land
  # group lies wholly in CT-05. The water group links only to unassigned blocks.
  ct_land_support <- filter(
    bg_target_cells, bg_cvap == "091902114003"
  )
  ct_water_locations <- filter(
    bg_target_cells, bg_cvap == "091309901000"
  )

  check(
    nrow(ct_land_support) == 1L &&
      ct_land_support$PUMA5CE[[1]] == "20904" &&
      ct_land_support$CDFP[[1]] == "05",
    "The reviewed CT land case is no longer contained in PUMA 20904 / CT-05."
  )
  check(
    nrow(ct_water_locations) > 0L &&
      all(ct_water_locations$CDFP == "ZZ") &&
      setequal(ct_water_locations$PUMA5CE, c("20401", "20500")),
    "The reviewed CT water case has unexpected district or PUMA coverage."
  )

  check(
    nrow(review_cases) == 0L,
    paste(
      "Further allocation decisions are needed.",
      "See 01_frame/data/output/02_cvap_allocation_readiness.csv."
    )
  )

  cat("\nNational allocation-input checks passed.\n")
  cat("Continuing with block-group CVAP contributions.\n")
}
