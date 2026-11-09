# New York and Connecticut CVAP geography audits for Script 02.
# Sections 6–7 compare missing New York estimates with the Census suppression
# list, then measure district coverage of the affected PUMAs. Section 8 checks
# the correspondence between old Connecticut counties and planning regions.
# The Markdown render functions are in 02_cvap_audit_notes.R.

# Section 6. Published CVAP estimates and the New York suppression list.

read_cvap_and_ny_errata <- function() {
  cvap_path <- here::here(
    "01_frame", "data", "input", "CVAP_2020-2024_ACS_csv_files.zip"
  )
  errata_path <- here::here(
    "01_frame", "data", "input",
    "Errata148_Suppressed_Geographies_for_Wyandanch.xlsx"
  )

  # SHA-256 fingerprints recorded from the downloaded source files.
  cvap_sha256 <- "0c67665c62de843de7a3521a8110de05b4aa158cdc2db304015380615941056c"
  errata_sha256 <- "26975c7dbbcd738b4546416d8753ec0a59e4957b3959fbab29ab7d96f7024369"

  check(file.exists(cvap_path), "Missing CVAP archive.")
  check(file.exists(errata_path), "Missing Census suppression list.")
  check(
    digest::digest(file = cvap_path, algo = "sha256") == cvap_sha256,
    "CVAP archive fingerprint differs."
  )
  check(
    digest::digest(file = errata_path, algo = "sha256") == errata_sha256,
    "Census suppression-list fingerprint differs."
  )

  # Keep the national table for the Connecticut check and national allocation (Section 9).
  national_cvap_source <- readr::read_csv(
    unz(cvap_path, "BlockGr.csv"),
    col_types = readr::cols_only(
      geoid = readr::col_character(),
      lnnumber = readr::col_integer(),
      cvap_est = readr::col_double()
    ),
    progress = FALSE
  )
  cvap_keys <- cvap_block_group_ids(national_cvap_source)

  errata_sheet <- "2020-2024 ACS 5yr"
  suppressed_bg <- read_ny_suppressed_groups(errata_path, errata_sheet)

  list(national_cvap = national_cvap_source, cvap_keys = cvap_keys,
       suppressed = suppressed_bg, errata_sheet = errata_sheet,
       cvap_sha256 = cvap_sha256, errata_sha256 = errata_sha256)
}

cvap_block_group_ids <- function(national_cvap_source) {
  # readr uses positions in the source CSV when reporting parse failures.
  # This audit uses the ID and category; Section 8 checks the estimates.
  estimate_column <- match("cvap_est", names(readr::spec(national_cvap_source)$cols))
  problems <- readr::problems(national_cvap_source)
  identifiers <- select(national_cvap_source, geoid, lnnumber)
  check(
    all(problems$col %in% estimate_column) && !anyNA(identifiers) &&
      all(grepl("^1500000US[0-9]{12}$", identifiers$geoid)),
    "Invalid CVAP geography or category identifiers."
  )

  # CVAP technical documentation: line 1 is the Total for a block group.
  totals <- filter(identifiers, lnnumber == 1L)
  check(
    anyDuplicated(totals$geoid) == 0L && setequal(identifiers$geoid, totals$geoid),
    "Expected exactly one Total record per CVAP block group."
  )
  transmute(totals, bg_geoid = sub("^1500000US", "", geoid))
}

read_ny_suppressed_groups <- function(errata_path, errata_sheet) {
  check(
    errata_sheet %in% readxl::excel_sheets(errata_path),
    "Expected 2020-2024 worksheet is absent."
  )

  errata <- readxl::read_excel(
    errata_path,
    sheet = errata_sheet,
    skip = 2,  # Row 3 contains the column names in the pinned workbook.
    col_types = "text"
  )
  check(
    all(c("GEOID", "NAME") %in% names(errata)),
    "Unexpected suppression-list column names."
  )

  # Census identifiers: 1500000US = block group; state FIPS 36 = New York.
  suppressed_bg <- errata |>
    filter(grepl("^1500000US36[0-9]{10}$", GEOID)) |>
    transmute(
      bg_geoid = sub("^1500000US", "", GEOID),
      geography_name = NAME
    )

  check(
    nrow(suppressed_bg) > 0L &&
      anyDuplicated(suppressed_bg$bg_geoid) == 0L,
    "Suppression list has no New York block groups or contains duplicate IDs."
  )
  suppressed_bg
}

audit_ny_suppression <- function(block_cd, sources) {
  ny_block_groups <- block_cd |>
    filter(STATEFP == "36") |>
    transmute(bg_geoid = substr(GEOID, 1L, 12L)) |>
    distinct()

  ny_missing <- anti_join(ny_block_groups, sources$cvap_keys, by = "bg_geoid")

  suppression_audit <- full_join(
    mutate(ny_missing, missing_from_cvap = TRUE),
    mutate(sources$suppressed, listed_in_errata = TRUE),
    by = "bg_geoid",
    relationship = "one-to-one"
  ) |>
    mutate(
      missing_from_cvap = coalesce(missing_from_cvap, FALSE),
      listed_in_errata = coalesce(listed_in_errata, FALSE)
    ) |>
    arrange(bg_geoid)

  exact_match <- setequal(ny_missing$bg_geoid, sources$suppressed$bg_geoid)

  cat("\nNew York suppression-list comparison:\n")
  print(tibble::tibble(
    missing_block_groups = nrow(ny_missing),
    officially_listed_block_groups = nrow(sources$suppressed),
    exact_identifier_match = exact_match
  ))

  cat("\nIdentifiers that do not agree between the two lists:\n")
  suppression_audit |>
    filter(missing_from_cvap != listed_in_errata) |>
    print(n = Inf, width = Inf)

  audit_path <- here::here(
    "01_frame", "data", "output", "02_cvap_ny_suppression_audit.csv"
  )
  dir.create(dirname(audit_path), recursive = TRUE, showWarnings = FALSE)
  readr::write_csv(suppression_audit, audit_path)

  note_path <- here::here(
    "01_frame", "docs", "02_cvap_suppression_audit.md"
  )
  dir.create(dirname(note_path), recursive = TRUE, showWarnings = FALSE)

  # Write the comparison before enforcing it so a mismatch can be inspected.
  ny_source_note <- ny_suppression_note(
    sources$errata_sheet, sources$errata_sha256, sources$cvap_sha256,
    nrow(ny_missing), nrow(sources$suppressed), exact_match
  )
  writeLines(ny_source_note, note_path)

  cat("Audit saved:", audit_path, "\n")
  cat("Source note saved:", note_path, "\n")

  check(
    exact_match,
    "Missing New York identifiers differ from the official suppression list."
  )

  list(missing = ny_missing, note_path = note_path, source_note = ny_source_note)
}

# Section 7. District coverage for PUMAs with suppressed block groups.

audit_ny_puma_extent <- function(block_cd, suppression) {
  ny_intersection_impact <- ny_puma_district_intersections(block_cd, suppression$missing)

  ny_puma_impact <- ny_intersection_impact |>
    group_by(STATEFP, PUMA5CE) |>
    summarise(
      districts = paste(sort(CDFP), collapse = ", "),
      district_count = n(),
      population_2020 = sum(population_2020),
      suppressed_bg_population_2020 = sum(suppressed_bg_population_2020),
      .groups = "drop"
    )

  check(
    all(ny_puma_impact$population_2020 > 0),
    "An affected PUMA has no 2020 population."
  )

  ny_puma_impact <- ny_puma_impact |>
    mutate(
      suppressed_bg_population_pct =
        100 * suppressed_bg_population_2020 / population_2020,
      entirely_within_one_district = district_count == 1L
    )

  cat("\nNew York suppression: geographic extent\n")
  cat("Affected block groups:", nrow(suppression$missing), "\n")
  cat("Affected PUMAs:", nrow(ny_puma_impact), "\n")
  suppressed_population <- sum(ny_intersection_impact$suppressed_bg_population_2020)
  cat("2020 total population in suppressed block groups:", suppressed_population, "\n")

  cat("\nAll district intersections within affected PUMAs:\n")
  print(ny_intersection_impact, n = Inf, width = Inf)

  cat("\nSummary by affected PUMA:\n")
  print(ny_puma_impact, n = Inf, width = Inf)

  impact_path <- here::here(
    "01_frame", "data", "output", "02_cvap_ny_puma_district_impact.csv"
  )
  readr::write_csv(ny_intersection_impact, impact_path)

  ny_extent_note <- ny_puma_impact_note(nrow(suppression$missing), ny_puma_impact, suppressed_population)
  writeLines(c(suppression$source_note, ny_extent_note), suppression$note_path)

  cat("Impact audit saved:", impact_path, "\n")
  cat("Documentation updated:", suppression$note_path, "\n")

  invisible(NULL)
}

ny_puma_district_intersections <- function(block_cd, ny_missing) {
  ny_impact_blocks <- block_cd |>
    filter(STATEFP == "36") |>
    mutate(
      bg_geoid = substr(GEOID, 1L, 12L),
      cvap_suppressed = bg_geoid %in% ny_missing$bg_geoid
    )

  check(
    setequal(
      ny_impact_blocks$bg_geoid[ny_impact_blocks$cvap_suppressed],
      ny_missing$bg_geoid
    ),
    "Some suppressed block groups are absent from the New York block map."
  )
  check(
    !anyNA(ny_impact_blocks$PUMA5CE) &&
      !anyNA(ny_impact_blocks$CDFP) &&
      !any(ny_impact_blocks$CDFP == "ZZ"),
    "Missing PUMA or unassigned district in the New York impact audit."
  )

  affected_ny_pumas <- ny_impact_blocks |>
    filter(cvap_suppressed) |>
    distinct(STATEFP, PUMA5CE)

  # Retain ALL blocks of each affected PUMA, including zero-population blocks.
  # This establishes whether the whole PUMA lies within one assigned district.
  affected_ny_blocks <- semi_join(
    ny_impact_blocks,
    affected_ny_pumas,
    by = c("STATEFP", "PUMA5CE")
  )

  ny_intersection_impact <- affected_ny_blocks |>
    group_by(STATEFP, PUMA5CE, CDFP) |>
    summarise(
      blocks = n(),
      population_2020 = sum(pop20),
      suppressed_bg_blocks = sum(cvap_suppressed),
      suppressed_bg_population_2020 = sum(pop20[cvap_suppressed]),
      .groups = "drop"
    ) |>
    arrange(STATEFP, PUMA5CE, CDFP)

  check(
    sum(ny_intersection_impact$blocks) == nrow(affected_ny_blocks) &&
      sum(ny_intersection_impact$population_2020) ==
        sum(affected_ny_blocks$pop20) &&
      sum(ny_intersection_impact$suppressed_bg_population_2020) ==
        sum(ny_impact_blocks$pop20[ny_impact_blocks$cvap_suppressed]),
    "Population or block counts changed during impact aggregation."
  )
  ny_intersection_impact
}

# Section 8. Connecticut block-group identifiers under the two county definitions.

audit_ct_block_group_ids <- function(block_cd, national_cvap_source) {
  ct_lookup_path <- here::here(
    "01_frame", "data", "input", "acs22_cousub22_blkgrp20_st09.txt"
  )

  # SHA-256 recorded from our downloaded lookup.
  ct_lookup_sha256 <- "06957a5e777dc96da4c678a79d27dce6617cfbd510c9611dbf7720c3cd16c5bd"

  check(file.exists(ct_lookup_path), "Missing Connecticut relationship file.")
  check(
    digest::digest(file = ct_lookup_path, algo = "sha256") == ct_lookup_sha256,
    "Connecticut relationship-file fingerprint differs."
  )

  ct_pairs <- read_ct_planning_region_overlaps(ct_lookup_path)

  comparison <- compare_ct_block_groups(block_cd, national_cvap_source, ct_pairs)
  print_ct_identifier_review(comparison$candidates, comparison$review, comparison$counts)

  ct_audit_path <- here::here(
    "01_frame", "data", "output", "02_ct_cvap_identifier_audit.csv"
  )
  readr::write_csv(comparison$candidates, ct_audit_path)

  ct_note_path <- here::here(
    "01_frame", "docs", "02_ct_cvap_identifier_audit.md"
  )
  # Keep the candidate CSV and the initial note even when a new exception appears.
  ct_source_note <- ct_identifier_note(ct_lookup_sha256, comparison$counts)
  writeLines(ct_source_note, ct_note_path)

  cat("Identifier audit saved:", ct_audit_path, "\n")
  cat("Source note saved:", ct_note_path, "\n")


  # Reviewed Connecticut exceptions; see docs/02_cvap_allocation_decisions.md.
  # Fingerprint of the saved official 2024 catalogue response.
  ct_catalog_path <- here::here(
    "01_frame", "data", "input", "ct_bg_2024_identifier_check.json"
  )
  ct_catalog_sha256 <- "a01ecdfb5bfe0fe4119a3aab71007408f458ebc5c0c580a04402fe102a51bb87"
  ct_catalog_query_url <- "https://tigerweb.geo.census.gov/arcgis/rest/services/TIGERweb/tigerWMS_ACS2024/MapServer/10/query?where=GEOID+IN+%28%27091403431011%27%2C%27091703431011%27%29&outFields=GEOID%2CNAME%2CSTATE%2CCOUNTY%2CTRACT%2CBLKGRP%2CAREALAND%2CAREAWATER&returnGeometry=false&orderByFields=GEOID&f=json"

  check(file.exists(ct_catalog_path), "Missing 2024 Connecticut catalogue response.")
  check(
    digest::digest(file = ct_catalog_path, algo = "sha256") == ct_catalog_sha256,
    "2024 Connecticut catalogue response fingerprint differs."
  )

  # A 160-square-metre intersection has no corresponding published block-group ID.
  # Verify both that case and the water-only relationships before approving the links.
  check_ct_identifier_exceptions(ct_catalog_path, comparison$candidates, comparison$review)
  ct_verified_note <- ct_verified_exceptions_note(ct_catalog_sha256, ct_catalog_query_url)
  writeLines(c(ct_source_note, ct_verified_note), ct_note_path)

  cat("\nReviewed Connecticut identifier exception checks passed.\n")
  cat("Catalogue SHA256:", ct_catalog_sha256, "\n")
  cat("Continuing with national allocation inputs.\n")

  comparison$candidates
}

compare_ct_block_groups <- function(block_cd, national_cvap_source, ct_pairs) {
  ct_bg_population <- block_cd |>
    filter(STATEFP == "09") |>
    mutate(bg_2020 = substr(GEOID, 1L, 12L)) |>
    group_by(bg_2020) |>
    summarise(population_2020 = sum(pop20), .groups = "drop")

  check(
    setequal(ct_pairs$bg_2020, ct_bg_population$bg_2020),
    "Lookup and district file contain different Connecticut block-group IDs."
  )

  check(
    nrow(readr::problems(national_cvap_source)) == 0L,
    "CVAP parsing problems."
  )

  ct_cvap <- national_cvap_source |>
    filter(lnnumber == 1L, startsWith(geoid, "1500000US09")) |>
    transmute(
      bg_cvap = sub("^1500000US", "", geoid),
      cvap_est
    )

  check(
    nrow(ct_cvap) > 0L &&
      anyDuplicated(ct_cvap$bg_cvap) == 0L &&
      all(is.finite(ct_cvap$cvap_est)),
    "Invalid Connecticut CVAP Total records."
  )
  check(
    setequal(
      ct_pairs$planning_region,
      substr(ct_cvap$bg_cvap, 1L, 5L)
    ),
    "Lookup and CVAP file contain different planning-region codes."
  )

  # Construct candidate identifiers for the reviewed checks below:
  # replace the county prefix while retaining the tract and block-group suffix.
  ct_candidate_audit <- ct_pairs |>
    mutate(
      bg_cvap = paste0(planning_region, substr(bg_2020, 6L, 12L))
    ) |>
    left_join(
      ct_bg_population, by = "bg_2020",
      relationship = "many-to-one"
    ) |>
    left_join(
      ct_cvap, by = "bg_cvap",
      relationship = "many-to-one"
    ) |>
    mutate(present_in_cvap = bg_cvap %in% ct_cvap$bg_cvap) |>
    arrange(bg_2020, bg_cvap)

  review <- summarize_ct_identifier_matches(ct_pairs, ct_candidate_audit, ct_cvap)

  counts <- c(
    origins = nrow(ct_bg_population), pairs = nrow(ct_pairs), cvap_groups = nrow(ct_cvap),
    absent = nrow(review$absent), unmatched = nrow(review$unmatched),
    shared = nrow(review$shared)
  )
  list(candidates = ct_candidate_audit, review = review, counts = counts)
}

summarize_ct_identifier_matches <- function(ct_pairs, ct_candidate_audit, ct_cvap) {
  ct_cardinality <- ct_pairs |>
    group_by(bg_2020) |>
    summarise(
      regions = n(),
      regions_with_overlap = sum(land_m2 + water_m2 > 0),
      regions_with_land = sum(land_m2 > 0),
      .groups = "drop"
    )

  ct_collisions <- ct_candidate_audit |>
    group_by(bg_cvap) |>
    summarise(old_block_groups = n_distinct(bg_2020), .groups = "drop") |>
    filter(old_block_groups > 1L)

  ct_missing_candidates <- filter(ct_candidate_audit, !present_in_cvap)
  ct_unmatched_cvap <- anti_join(
    ct_cvap, ct_candidate_audit, by = "bg_cvap"
  )

  # Keep the unmatched IDs and ambiguous relationships together for review.
  list(
    by_origin = ct_cardinality, absent = ct_missing_candidates,
    unmatched = ct_unmatched_cvap, shared = ct_collisions
  )
}

read_ct_planning_region_overlaps <- function(ct_lookup_path) {
  ct_rel <- readr::read_delim(
    ct_lookup_path,
    delim = "|",
    col_types = readr::cols_only(
      GEOID_BLKGRP_20 = readr::col_character(),
      GEOID_COUSUB_22 = readr::col_character(),
      AREALAND_PART = readr::col_double(),
      AREAWATER_PART = readr::col_double()
    ),
    progress = FALSE
  )

  # Identifier widths and overlap-area definitions:
  # https://www.census.gov/programs-surveys/geography/technical-documentation/records-layout/2022-connecticut-record-layout.html
  check(
    nrow(readr::problems(ct_rel)) == 0L &&
      !anyNA(ct_rel) &&
      all(grepl("^09[0-9]{10}$", ct_rel$GEOID_BLKGRP_20)) &&
      all(grepl("^09[0-9]{8}$", ct_rel$GEOID_COUSUB_22)) &&
      all(is.finite(ct_rel$AREALAND_PART)) &&
      all(is.finite(ct_rel$AREAWATER_PART)) &&
      all(ct_rel$AREALAND_PART >= 0) &&
      all(ct_rel$AREAWATER_PART >= 0),
    "Invalid Connecticut identifiers or overlap areas."
  )

  # First five subdivision-ID characters identify state plus county-equivalent.
  # Collapse multiple town relationships within the same planning region.
  ct_rel |>
    mutate(
      bg_2020 = GEOID_BLKGRP_20,
      planning_region = substr(GEOID_COUSUB_22, 1L, 5L)
    ) |>
    group_by(bg_2020, planning_region) |>
    summarise(
      source_rows = n(),
      land_m2 = sum(AREALAND_PART),
      water_m2 = sum(AREAWATER_PART),
      .groups = "drop"
    )
}

check_ct_identifier_exceptions <- function(ct_catalog_path, candidates, review) {
  ct_catalog <- jsonlite::fromJSON(
    ct_catalog_path, simplifyVector = FALSE
  )
  check(
    is.null(ct_catalog$error) &&
      !isTRUE(ct_catalog$exceededTransferLimit) &&
      length(ct_catalog$features) == 1L,
    "Invalid or incomplete 2024 catalogue response."
  )

  # Expected identifier and areas come from the reviewed catalogue response.
  published <- ct_catalog$features[[1]]$attributes
  check(
    identical(published$GEOID, "091403431011") &&
      isTRUE(published$AREALAND == 3606413) &&
      isTRUE(published$AREAWATER == 0),
    "2024 catalogue geography differs from the reviewed case."
  )

  check(
    nrow(review$unmatched) == 0L,
    "Some Connecticut CVAP identifiers have no candidate source geography."
  )

  # Exact exception identities are from the saved relationship/CVAP audits.
  pair_keys <- function(x) paste(x$bg_2020, x$bg_cvap, sep = "->")

  check(
    identical(
      sort(pair_keys(review$absent)),
      "090093431011->091703431011"
    ),
    "An unreviewed Connecticut candidate is absent from CVAP."
  )

  published_candidate <- candidates |>
    filter(bg_2020 == "090093431011", bg_cvap == "091403431011")

  check(
    nrow(published_candidate) == 1L &&
      isTRUE(published_candidate$present_in_cvap[[1]]) &&
      published_candidate$land_m2[[1]] == published$AREALAND &&
      review$absent$land_m2[[1]] == 160 &&
      review$absent$water_m2[[1]] == 0,
    "The reviewed small-overlap case has changed."
  )

  multiple_regions <- candidates |>
    semi_join(
      filter(review$by_origin, regions > 1L),
      by = "bg_2020"
    )

  reviewed_pairs <- c(
    "090019900000->091209900000",
    "090019900000->091909900000",
    "090093431011->091403431011",
    "090093431011->091703431011",
    "090119901000->091309901000",
    "090119901000->091809901000"
  )

  check(
    identical(
      sort(pair_keys(multiple_regions)),
      sort(reviewed_pairs)
    ),
    "An unreviewed multi-region Connecticut relationship was found."
  )

  shared_target_rows <- candidates |>
    semi_join(review$shared, by = "bg_cvap")

  check(
    identical(
      sort(pair_keys(shared_target_rows)),
      c(
        "090079901000->091309901000",
        "090119901000->091309901000"
      )
    ) &&
      all(shared_target_rows$land_m2 == 0) &&
      all(shared_target_rows$population_2020 == 0),
    "An unreviewed Connecticut target-ID collision was found."
  )
  invisible(NULL)
}

print_ct_identifier_review <- function(candidates, review, counts) {
  cat("\nConnecticut identifier audit\n")
  cat("Original block groups:", counts[["origins"]], "\n")
  cat("Distinct old-block-group / planning-region pairs:", counts[["pairs"]], "\n")
  cat("CVAP block groups:", counts[["cvap_groups"]], "\n")

  cat("\nRelationship counts per original block group:\n")
  review$by_origin |>
    count(regions, regions_with_overlap, regions_with_land) |>
    print(n = Inf, width = Inf)

  cat("\nBlock groups without exactly one region with positive overlap:\n")
  candidates |>
    semi_join(
      filter(review$by_origin, regions != 1L | regions_with_overlap != 1L),
      by = "bg_2020"
    ) |>
    print(n = Inf, width = Inf)

  cat("\nPairs with zero land and water overlap:\n")
  candidates |>
    filter(land_m2 + water_m2 == 0) |>
    print(n = Inf, width = Inf)

  cat("\nCandidate IDs absent from CVAP:\n")
  print(review$absent, n = Inf, width = Inf)

  cat("\nCVAP IDs absent from the candidates:\n")
  print(review$unmatched, n = Inf, width = Inf)

  cat("\nCandidate IDs shared by multiple original block groups:\n")
  print(review$shared, n = Inf, width = Inf)
}
