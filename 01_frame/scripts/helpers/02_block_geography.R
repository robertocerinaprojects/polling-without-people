# Block geography and 2020 population for Step 02.
# The main script loads dplyr, check(), and the readers in 02_census_inputs.R.

# Section 1: Read the 120th Congress block assignments ----
read_block_districts <- function(target_states, allowed_states, output_dir) {
  # Each row of the Census Block Equivalency File (BEF) identifies one 2020
  # block and the district to which Census assigns the whole block.
  # https://www.census.gov/geographies/mapping-files/2027/dec/rdo/120-congressional-district-bef.html

  # SHA-256 of the Census archive downloaded on 2026-10-30.
  # https://www2.census.gov/programs-surveys/decennial/rdo/mapping-files/2027/120-congressional-district-befs/cd120.zip
  zip_path <- here::here("01_frame", "data", "input", "cd120.zip")
  expected_sha256 <- "bc9a4fc543b8b279ce3663642a5cc4e19e32a8ef84f12371e26f754e5b8cc8a5"

  check(file.exists(zip_path), "Missing input: 01_frame/data/input/cd120.zip")
  check(
    digest::digest(zip_path, algo = "sha256", file = TRUE,
                   serialize = FALSE) == expected_sha256,
    "Archive checksum differs from the pinned snapshot."
  )

  member <- "NationalCD120.txt"
  check(
    sum(unzip(zip_path, list = TRUE)$Name == member) == 1L,
    "Expected exactly one NationalCD120.txt in the archive."
  )

  cat("Reading national block assignments...\n")
  block_cd <- read_national_bef(zip_path, member)

  expected_columns <- c(
    "GEOID", "STATEFP", "COUNTYFP", "TRACTCE", "BLOCKCE", "CDFP"
  )
  check(identical(names(block_cd), expected_columns), "Unexpected columns.")
  check(nrow(block_cd) > 0L, "National table is empty.")
  check(nrow(readr::problems(block_cd)) == 0L, "CSV parsing problems found.")
  check(!anyNA(block_cd), "Missing values found in block assignments.")

  # Validate digit-only geographic identifiers and their fixed widths.
  # Identifier widths and concatenation: https://www.census.gov/programs-surveys/geography/guidance/geo-identifiers.html
  widths <- c(GEOID = 15L, STATEFP = 2L, COUNTYFP = 3L,
              TRACTCE = 6L, BLOCKCE = 4L)

  for (variable in names(widths)) {
    pattern <- sprintf("^[0-9]{%d}$", widths[[variable]])
    check(
      all(grepl(pattern, block_cd[[variable]])),
      paste("Malformed identifiers in", variable)
    )
  }

  check(
    all(block_cd$GEOID == paste0(
      block_cd$STATEFP, block_cd$COUNTYFP,
      block_cd$TRACTCE, block_cd$BLOCKCE
    )),
    "GEOID disagrees with its geographic components."
  )
  check(anyDuplicated(block_cd$GEOID) == 0L, "Duplicate block GEOIDs found.")

  # CDFP is the district code: 01–53 are numbered seats, 00 is at-large,
  # and 98 identifies the nonvoting seat in DC and Puerto Rico. ZZ means the
  # block lies outside a defined district. Keep its row so we can audit its
  # population later. Codes come from notes 2–3 of the BEF documentation.

  allowed_cd_codes <- c(sprintf("%02d", 0:53), "98", "ZZ")
  check(
    all(block_cd$CDFP %in% allowed_cd_codes),
    "Unexpected congressional district codes."
  )

  # Require all 50 states plus DC; retain and report any territories.

  check(
    all(block_cd$STATEFP %in% allowed_states),
    "Unrecognized state or territory codes."
  )
  check(
    all(target_states %in% block_cd$STATEFP),
    "At least one required state or DC is missing."
  )

  coverage <- block_cd |>
    group_by(STATEFP) |>
    summarise(
      blocks = n(),
      assigned_districts = n_distinct(CDFP[CDFP != "ZZ"]),
      unassigned_blocks = sum(CDFP == "ZZ"),
      .groups = "drop"
    ) |>
    mutate(in_target = STATEFP %in% target_states)

  cat("\nJurisdiction coverage:\n")
  print(coverage, n = Inf, width = Inf)

  cat("\nSpecial district codes:\n")
  block_cd |>
    filter(CDFP %in% c("00", "98", "ZZ")) |>
    count(STATEFP, CDFP, name = "blocks") |>
    print(n = Inf, width = Inf)

  cat("\nStructural checks passed.\n")
  cat("Total block records:", nrow(block_cd), "\n")
  cat(
    "Assigned districts across the 50 states plus DC:",
    sum(coverage$assigned_districts[coverage$in_target]), "\n"
  )

  # Section 2: Check the districts in each jurisdiction, then retain the 50 states and DC ----
  # Compare the assigned codes with the seats published for each state. The
  # delegate in DC is an additional district outside the 435 voting seats.

  # Seat allocations: 2020 Census apportionment, Table 1.
  # https://www.census.gov/data/tables/2020/dec/2020-apportionment-data.html
  seats <- c(
    "01" = 7L,  "02" = 1L,  "04" = 9L,  "05" = 4L,  "06" = 52L,
    "08" = 8L,  "09" = 5L,  "10" = 1L,  "12" = 28L, "13" = 14L,
    "15" = 2L,  "16" = 2L,  "17" = 17L, "18" = 9L,  "19" = 4L,
    "20" = 4L,  "21" = 6L,  "22" = 6L,  "23" = 2L,  "24" = 8L,
    "25" = 9L,  "26" = 13L, "27" = 8L,  "28" = 4L,  "29" = 8L,
    "30" = 2L,  "31" = 3L,  "32" = 4L,  "33" = 2L,  "34" = 12L,
    "35" = 3L,  "36" = 26L, "37" = 14L, "38" = 1L,  "39" = 15L,
    "40" = 5L,  "41" = 6L,  "42" = 17L, "44" = 2L,  "45" = 7L,
    "46" = 1L,  "47" = 9L,  "48" = 38L, "49" = 4L,  "50" = 1L,
    "51" = 11L, "53" = 10L, "54" = 2L,  "55" = 8L,  "56" = 1L
  )

  check(sum(seats) == 435L, "Seat reference does not total 435.")
  check(
    setequal(names(seats), setdiff(target_states, "11")),
    "Seat reference does not cover exactly the 50 states."
  )

  expected_codes <- lapply(seats, function(n) {
    if (n == 1L) "00" else sprintf("%02d", seq_len(n))
  })
  expected_codes[["11"]] <- "98"  # District of Columbia
  expected_codes[["72"]] <- "98"  # Puerto Rico, audited before exclusion

  check(
    setequal(names(expected_codes), unique(block_cd$STATEFP)),
    "Input jurisdictions differ from the district-code reference."
  )

  assigned_codes <- block_cd |>
    distinct(STATEFP, CDFP) |>
    filter(CDFP != "ZZ")

  district_checks <- vector("list", length(expected_codes))
  for (i in seq_along(expected_codes)) {
    state <- names(expected_codes)[i]
    observed <- assigned_codes$CDFP[assigned_codes$STATEFP == state]
    expected <- expected_codes[[state]]

    district_checks[[i]] <- tibble(
      STATEFP = state,
      expected_districts = length(expected),
      observed_districts = length(observed),
      missing_codes = paste(setdiff(expected, observed), collapse = ","),
      unexpected_codes = paste(setdiff(observed, expected), collapse = ","),
      passed = setequal(expected, observed)
    )
  }
  district_audit <- bind_rows(district_checks) |>
    arrange(STATEFP)

  if (!all(district_audit$passed)) {
    print(filter(district_audit, !passed), n = Inf, width = Inf)
    stop("District-code validation failed.", call. = FALSE)
  }

  cat("\nExact district-code validation passed for all",
      nrow(district_audit), "jurisdictions.\n")

  # Apply the same 50-state-plus-DC scope used in PUMS preparation.
  excluded_jurisdictions <- coverage |>
    filter(!in_target)

  rows_before_scope <- nrow(block_cd)
  block_cd <- block_cd |>
    filter(STATEFP %in% target_states)

  check(
    rows_before_scope ==
      nrow(block_cd) + sum(excluded_jurisdictions$blocks),
    "Block counts do not reconcile after applying geographic scope."
  )
  check(
    setequal(unique(block_cd$STATEFP), target_states),
    "Retained geography differs from the 50 states plus DC."
  )

  cat("\nExcluded jurisdictions:\n")
  print(excluded_jurisdictions, n = Inf, width = Inf)
  cat("Retained block records:", nrow(block_cd), "\n")
  cat("Retained unassigned blocks:", sum(block_cd$CDFP == "ZZ"), "\n")

  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  readr::write_csv(
    coverage, file.path(output_dir, "02_cd120_coverage.csv")
  )
  readr::write_csv(
    district_audit, file.path(output_dir, "02_cd120_district_codes.csv")
  )
  readr::write_csv(
    excluded_jurisdictions,
    file.path(output_dir, "02_cd120_excluded_jurisdictions.csv")
  )

  cat("District and geographic-scope audits saved.\n")

  block_cd
}

# Section 3: Give each block the PUMA of its 2020 census tract ----
attach_block_pumas <- function(block_cd, target_states, allowed_states, output_dir) {
  # The Census lookup gives one Public Use Microdata Area (PUMA) per tract.
  # A left join preserves blocks whose tract might be missing, so we can
  # report which blocks matched and check their identifiers and order.

  # SHA-256 of the downloaded Census tract-to-PUMA lookup.
  # https://www2.census.gov/geo/docs/maps-data/data/rel2020/2020_Census_Tract_to_2020_PUMA.txt
  puma_path <- here::here(
    "01_frame", "data", "input", "2020_Census_Tract_to_2020_PUMA.txt"
  )
  puma_sha256 <- "5262f460b2c8dbe86b00549e916317b1791fdc595c9af72ab18f6f6a67040531"

  check(file.exists(puma_path), "Missing tract-to-PUMA input.")
  check(
    digest::digest(puma_path, algo = "sha256", file = TRUE,
                   serialize = FALSE) == puma_sha256,
    "Tract-to-PUMA checksum differs from the pinned snapshot."
  )

  tract_puma <- readr::read_csv(
    puma_path,
    col_types = readr::cols(.default = readr::col_character()),
    trim_ws = FALSE,
    name_repair = "minimal",
    skip_empty_rows = FALSE,
    show_col_types = FALSE,
    lazy = FALSE
  )

  check(
    identical(names(tract_puma),
              c("STATEFP", "COUNTYFP", "TRACTCE", "PUMA5CE")),
    "Unexpected tract-to-PUMA columns."
  )
  check(nrow(tract_puma) > 0L, "Tract-to-PUMA table is empty.")
  check(nrow(readr::problems(tract_puma)) == 0L, "Lookup parsing problems.")
  check(!anyNA(tract_puma), "Missing values in the tract-to-PUMA lookup.")

  # Widths: GEOID guidance above and PUMA coding guidelines below.
  puma_widths <- c(STATEFP = 2L, COUNTYFP = 3L, TRACTCE = 6L, PUMA5CE = 5L)
  for (variable in names(puma_widths)) {
    check(
      all(grepl(sprintf("^[0-9]{%d}$", puma_widths[[variable]]),
                tract_puma[[variable]])),
      paste("Malformed lookup identifiers in", variable)
    )
  }

  # Census 2020 PUMA coding guidelines specify 00100 through 99995.
  # https://www2.census.gov/geo/pdfs/reference/puma2020/2020PUMA_CodingGuidelines.pdf
  puma_numbers <- as.integer(tract_puma$PUMA5CE)
  check(
    all(puma_numbers >= 100L & puma_numbers <= 99995L),
    "PUMA codes outside the documented range; review required."
  )
  check(
    all(tract_puma$STATEFP %in% allowed_states),
    "Unrecognized lookup jurisdiction codes."
  )
  check(
    all(target_states %in% tract_puma$STATEFP),
    "Lookup does not cover all 50 states plus DC."
  )

  tract_puma <- tract_puma |>
    mutate(tract_geoid = paste0(STATEFP, COUNTYFP, TRACTCE))

  check(
    anyDuplicated(tract_puma$tract_geoid) == 0L,
    "Duplicate tract keys: each tract must have one lookup row."
  )

  puma_lookup_audit <- tract_puma |>
    group_by(STATEFP) |>
    summarise(
      tracts = n(),
      pumas = n_distinct(PUMA5CE),
      .groups = "drop"
    ) |>
    mutate(in_target = STATEFP %in% target_states)

  tract_puma <- tract_puma |>
    filter(STATEFP %in% target_states)

  # Join only the tract key and PUMA code, preserving all block rows.
  rows_before_join <- nrow(block_cd)
  block_ids_before <- block_cd$GEOID

  block_cd <- block_cd |>
    # Tract key: first 11 digits = state 2 + county 3 + tract 6 (GEOID guidance).
    mutate(tract_geoid = substr(GEOID, 1L, 11L)) |>
    left_join(
      select(tract_puma, tract_geoid, PUMA5CE),
      by = "tract_geoid",
      relationship = "many-to-one",
      na_matches = "never"
    )

  check(
    nrow(block_cd) == rows_before_join,
    "The tract-to-PUMA join changed the number of blocks."
  )
  check(
    identical(block_cd$GEOID, block_ids_before),
    "Block identifiers or their order changed during the join."
  )
  rm(block_ids_before)

  puma_join_audit <- block_cd |>
    group_by(STATEFP) |>
    summarise(
      blocks = n(),
      matched_blocks = sum(!is.na(PUMA5CE)),
      unmatched_blocks = sum(is.na(PUMA5CE)),
      unmatched_tracts = n_distinct(tract_geoid[is.na(PUMA5CE)]),
      matched_pumas = n_distinct(PUMA5CE, na.rm = TRUE),
      .groups = "drop"
    )

  # Each audit row below represents a tract-district combination.
  unmatched_tract_districts <- block_cd |>
    filter(is.na(PUMA5CE)) |>
    count(STATEFP, tract_geoid, CDFP, name = "blocks") |>
    arrange(STATEFP, tract_geoid, CDFP)

  check(
    sum(unmatched_tract_districts$blocks) == sum(is.na(block_cd$PUMA5CE)),
    "Unmatched-block audit does not reconcile."
  )

  readr::write_csv(
    puma_lookup_audit,
    file.path(output_dir, "02_puma_lookup_coverage.csv")
  )
  readr::write_csv(
    puma_join_audit,
    file.path(output_dir, "02_block_puma_join.csv")
  )
  readr::write_csv(
    unmatched_tract_districts,
    file.path(output_dir, "02_unmatched_tract_districts.csv")
  )

  cat("\nBlock-to-PUMA matching audit:\n")
  print(puma_join_audit, n = Inf, width = Inf)

  cat("\nUnmatched tract-district combinations (first 20):\n")
  print(head(unmatched_tract_districts, 20L), n = 20, width = Inf)

  cat("\nBlock count and identifier checks passed.\n")
  cat("Unmatched blocks retained:", sum(is.na(block_cd$PUMA5CE)), "\n")
  cat("Tract-to-PUMA audits saved.\n")

  block_cd
}

# Section 4: Locate the 2020 Census population counts ----
attach_block_population <- function(block_cd, target_states, output_dir) {
  # The Public Law 94-171 (PL) Redistricting Data Summary File supplies two
  # counts per block. POP100 counts residents of all ages. P0030001 counts
  # residents aged 18 and over, including noncitizens. read_pl_population()
  # in helpers/02_census_inputs.R joins these tables by their record number
  # and checks that block counts sum to the published state total for each age measure.
  # The manifest records the source URL, file size and SHA-256 of each archive.

  population_sources <- readr::read_csv(
    here::here("01_frame", "docs", "02_pl_2020_sources.csv"),
    col_types = readr::cols(.default = readr::col_character()),
    name_repair = "minimal",
    trim_ws = FALSE,
    show_col_types = FALSE,
    lazy = FALSE
  )

  check(
    identical(names(population_sources),
              c("STATEFP", "STUSAB", "state_name", "path", "url", "bytes", "sha256")),
    "Unexpected population-manifest columns."
  )
  check(
    nrow(readr::problems(population_sources)) == 0L &&
      !anyNA(population_sources),
    "Population manifest has parsing problems or incomplete entries."
  )
  check(
    nrow(population_sources) == length(target_states) &&
      anyDuplicated(population_sources$STATEFP) == 0L &&
      anyDuplicated(population_sources$STUSAB) == 0L &&
      setequal(population_sources$STATEFP, target_states),
    "Population manifest must cover exactly the 50 states plus DC."
  )
  check(
    all(grepl("^[A-Z]{2}$", population_sources$STUSAB)) &&
      all(grepl("^[0-9a-f]{64}$", population_sources$sha256)) &&
      all(grepl("^[1-9][0-9]*$", population_sources$bytes)),
    "Invalid abbreviation, checksum or file size in population manifest."
  )
  check(
    all(population_sources$path == paste0(
      "01_frame/data/input/pl_2020/",
      tolower(population_sources$STUSAB), "2020.pl.zip"
    )),
    "Unexpected population-file paths."
  )

  population_sources <- arrange(population_sources, STATEFP)

  # Section 5: Match the block counts and audit the state totals ----
  # Attach population to the exact 2020 blocks used for district assignment.
  # All-age counts help identify lost or duplicated residents and show how
  # many live in unassigned blocks. Adult counts get the same checks and later
  # supply the split when a block group's CVAP spans multiple intersections.

  state_audits <- vector("list", nrow(population_sources))
  unassigned_audits <- vector("list", nrow(population_sources))
  block_cd$pop20 <- rep(NA_real_, nrow(block_cd))
  block_cd$vap20 <- rep(NA_real_, nrow(block_cd))

  for (i in seq_len(nrow(population_sources))) {
    entry <- population_sources[i, ]
    st <- entry$STATEFP
    abbreviation <- entry$STUSAB
    archive_path <- here::here(entry$path)

    cat(sprintf("\nReading population %d/%d: %s\n",
                i, nrow(population_sources), abbreviation))

    check(
      file.exists(archive_path) &&
        file.info(archive_path)$size == as.numeric(entry$bytes),
      paste(abbreviation, "archive is missing or has an unexpected size.")
    )

    population <- read_pl_population(
      path = archive_path,
      abbreviation = abbreviation,
      state_fips = st,
      sha256 = entry$sha256
    )

    # Both inputs list exactly the same block IDs for this state. The two
    # files can order them differently, so align by GEOID before copying counts.
    state_block_rows <- which(block_cd$STATEFP == st)
    district_block_ids <- block_cd$GEOID[state_block_rows]
    population_block_ids <- population$blocks$GEOID

    missing_ids <- sum(!district_block_ids %in% population_block_ids)
    extra_ids <- sum(!population_block_ids %in% district_block_ids)
    check(
      missing_ids == 0L && extra_ids == 0L &&
        length(district_block_ids) == length(population_block_ids),
      sprintf(
        "%s block identifiers differ: %d missing population records; %d extra.",
        abbreviation, missing_ids, extra_ids
      )
    )

    population_row <- match(district_block_ids, population_block_ids)
    check(!anyNA(population_row), paste(abbreviation, "has unmatched population records."))
    block_population <- population$blocks$pop20[population_row]
    block_adults <- population$blocks$vap20[population_row]

    check(
      !anyNA(block_adults) &&
        sum(block_adults) == population$state_vap,
      paste(abbreviation, "adult population changed during matching.")
    )

    check(
      !anyNA(block_population) && sum(block_population) == population$state_total,
      paste(abbreviation, "population total changed during matching.")
    )

    # Fill the original national block rows in place.
    block_cd$pop20[state_block_rows] <- block_population
    block_cd$vap20[state_block_rows] <- block_adults
    unassigned_block_rows <- state_block_rows[block_cd$CDFP[state_block_rows] == "ZZ"]

    state_audits[[i]] <- tibble(
      STATEFP = st,
      STUSAB = abbreviation,
      blocks = length(state_block_rows),
      state_population = population$state_total,
      matched_population = sum(block_population),
      state_vap = population$state_vap,
      matched_vap = sum(block_adults),
      unassigned_blocks = length(unassigned_block_rows),
      unassigned_population = sum(block_cd$pop20[unassigned_block_rows]),
      unassigned_vap = sum(block_cd$vap20[unassigned_block_rows])
    )

    # Retain all unassigned blocks for review, including any populated blocks.
    unassigned_audits[[i]] <- block_cd[
      unassigned_block_rows,
      c("GEOID", "STATEFP", "CDFP", "PUMA5CE", "pop20", "vap20")
    ]

    rm(population, block_population, block_adults, population_row)
  }

  population_audit <- bind_rows(state_audits)
  unassigned_population <- bind_rows(unassigned_audits)

  check(
    !anyNA(block_cd$pop20) &&
      all(is.finite(block_cd$pop20)) &&
      all(block_cd$pop20 >= 0),
    "Missing or invalid population values after nationwide matching."
  )
  check(
    sum(population_audit$blocks) == nrow(block_cd) &&
      sum(population_audit$state_population) == sum(block_cd$pop20) &&
      nrow(unassigned_population) == sum(block_cd$CDFP == "ZZ"),
    "National population audit does not reconcile."
  )

  check(
    !anyNA(block_cd$vap20) &&
      all(is.finite(block_cd$vap20) &
          block_cd$vap20 >= 0 &
          block_cd$vap20 == floor(block_cd$vap20) &
          block_cd$vap20 <= block_cd$pop20) &&
      sum(population_audit$state_vap) == sum(block_cd$vap20),
    "National adult-population audit does not reconcile."
  )

  readr::write_csv(
    population_audit,
    file.path(output_dir, "02_population_by_state.csv")
  )
  readr::write_csv(
    unassigned_population,
    file.path(output_dir, "02_unassigned_block_population.csv")
  )

  cat("\nNational population audit:\n")
  print(population_audit, n = Inf, width = Inf)

  cat("\nUnassigned-block population audit:\n")
  unassigned_population |>
    group_by(STATEFP) |>
    summarise(
      blocks = n(),
      population = sum(pop20),
      populated_blocks = sum(pop20 > 0),
      .groups = "drop"
    ) |>
    print(n = Inf, width = Inf)

  cat("\nJurisdictions processed:", nrow(population_audit), "\n")
  cat("Matched blocks:", nrow(block_cd), "\n")
  cat("Total population:", sum(block_cd$pop20), "\n")
  cat("Unassigned blocks retained:", nrow(unassigned_population), "\n")
  cat("National population matching passed.\n")
  cat("Total adult population:", sum(block_cd$vap20), "\n")
  cat("Unassigned adult population:",
      sum(block_cd$vap20[block_cd$CDFP == "ZZ"]), "\n")
  cat("National adult-population matching passed.\n")

  block_cd
}
