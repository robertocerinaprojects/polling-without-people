# Describe the same citizen-adult population on two House district maps.
# From the repository root: Rscript 01_frame/scripts/08_build_district_predictors.R
# CD119 is the map used in the 2024 election. CD120 is the map used in 2026.
# Sources and allocation decisions: 01_frame/docs/08_build_district_predictors.md

library(dplyr)

# Each Step 04 label names the district share it contributes to. All 29 shares
# use the district's total PUMS citizen-adult population as their denominator.
column_for_label <- list(
  age_cat = c(
    "18-22" = "age_18_22", "23-27" = "age_23_27", "28-32" = "age_28_32",
    "33-37" = "age_33_37", "38-42" = "age_38_42", "43-47" = "age_43_47",
    "48-52" = "age_48_52", "53-57" = "age_53_57", "58-62" = "age_58_62",
    "63-67" = "age_63_67", "68-72" = "age_68_72", "73-77" = "age_73_77",
    "78-82" = "age_78_82", "83+" = "age_83_plus"
  ),
  gender_cat = c("Male" = "sex_male", "Female" = "sex_female"),
  educ_cat = c(
    "No HS" = "educ_no_hs", "HS grad" = "educ_hs", "Some college" = "educ_some_college",
    "2-year" = "educ_two_year", "4-year" = "educ_four_year", "Post-grad" = "educ_postgrad"
  ),
  race_cat = c(
    "White" = "race_white", "Black" = "race_black", "Native American" = "race_native",
    "Asian" = "race_asian", "Other/Multi" = "race_other_multi"
  ),
  hispanic_cat = c("Hispanic" = "eth_hispanic", "Not Hispanic" = "eth_not_hispanic")
)
demographic_levels <- lapply(column_for_label, names)
share_columns <- lapply(column_for_label, unname)

build_predictors <- function() {
  data_dir <- file.path("01_frame", "data")
  intermediate <- file.path(data_dir, "intermediate")
  output <- file.path(data_dir, "output")
  stage <- tempfile("step08_", tmpdir = data_dir)
  stopifnot(dir.create(stage))
  on.exit(unlink(stage, recursive = TRUE), add = TRUE)

  # Reconstruct the 2024 districts. Step 06 already built the 2026 cells.
  helper <- file.path("01_frame", "scripts", "helpers", "08_cd119_weights.py")
  status <- system2("python3", c(shQuote(helper), shQuote(stage)))
  if (status != 0L) stop("The CD119 crosswalk failed. See the preceding geographic diagnostic.")
  read_text <- function(path) read.csv(path, colClasses = "character", check.names = FALSE)
  cd119_weights <- read_text(file.path(stage, "08_puma_cd119_weights.csv"))
  cd119_weights$allocation_weight <- as.numeric(cd119_weights$allocation_weight)
  cd119_cells <- build_old_cells(intermediate, cd119_weights)
  cd120_cells <- readRDS(file.path(intermediate, "pums_cd_cells.rds"))
  saveRDS(cd119_cells, file.path(stage, "08_pums_cd119_cells.rds"))

  # Use the same share calculation on both sets of cells.
  cd119_shares <- district_shares(cd119_cells, 119L)
  cd120_shares <- district_shares(cd120_cells, 120L)
  both_maps <- bind_rows(cd119_shares, cd120_shares)
  step03_totals <- read_text(file.path(output, "03_pums_allocation_by_state.csv"))
  check_map_populations(cd119_shares, cd120_shares, both_maps, step03_totals)

  # Compare CD119 with the published Census estimates. The model input keeps
  # the original PUMS totals even when the two sources differ.
  census <- published_cd119_cvap(file.path(data_dir, "input", "CVAP_2020-2024_ACS_csv_files.zip"))
  benchmark <- cd119_shares |>
    select(STATEFP, CDFP, pums_cvap = cvap) |>
    left_join(census, by = c("STATEFP", "CDFP"), relationship = "one-to-one") |>
    mutate(difference = pums_cvap - census_cvap)
  stopifnot("A CD119 district lacks a Census benchmark." = !anyNA(benchmark))
  readr::write_csv(benchmark, file.path(stage, "08_cd119_cvap_benchmark.csv"))
  readr::write_csv(both_maps, file.path(stage, "08_district_demographics.csv"))

  targets <- c(
    file.path(intermediate, c("08_pums_cd119_cells.rds", "08_puma_cd119_weights.csv",
                              "08_district_demographics.csv")),
    file.path(output, c("08_district_overlap.csv", "08_cd119_allocation_exceptions.csv",
                        "08_cd119_cvap_benchmark.csv"))
  )
  publish_predictors(stage, targets)
  cat("Published", nrow(both_maps), "district/map rows, including DC on both maps.\n",
      "CD119 PUMS CVAP:", format(sum(cd119_shares$cvap), scientific = FALSE),
      "| CD120 PUMS CVAP:", format(sum(cd120_shares$cvap), scientific = FALSE), "\n")
}

# Fractional contributions may sum in different orders on the two maps.
close_counts <- function(x, y) {
  if (length(x) != length(y)) return(FALSE)
  tolerance <- 1e-10 * pmax(1, abs(y))
  all(is.finite(x) & is.finite(y) & abs(x - y) <= tolerance)
}

build_old_cells <- function(intermediate, crosswalk) {
  # Match the Step 01 person weights to the Step 04 demographic answers.
  person_key <- c("SAMPLE", "SERIAL", "PERNUM")
  demographics <- names(demographic_levels)
  person_fields <- c(person_key, "STATEFIP", "PUMA", "PERWT")
  people <- readRDS(file.path(intermediate, "pums_clean.rds"))[person_fields]
  profiles <- readRDS(file.path(intermediate, "pums_demographics.rds"))
  stopifnot(
    "Missing person identifier, district input or demographic field." =
      !anyNA(people) && !anyNA(profiles[c(person_key, demographics)]),
    "The two person tables differ in size." = nrow(profiles) == nrow(people),
    "Expected finite positive person weights." = all(is.finite(people$PERWT) & people$PERWT > 0)
  )

  person_ids <- people[person_key]
  profile_ids <- profiles[person_key]
  stopifnot(
    "Duplicate PUMS person identifiers." =
      !vctrs::vec_duplicate_any(person_ids) && !vctrs::vec_duplicate_any(profile_ids)
  )
  profile_row <- if (identical(person_ids, profile_ids)) {
    seq_len(nrow(people))
  } else {
    vctrs::vec_match(person_ids, profile_ids)
  }
  rm(person_ids, profile_ids)
  rows_by_state <- split(seq_len(nrow(people)), sprintf("%02d", people$STATEFIP))
  stopifnot(
    "A PUMS person has no Step 04 profile." = !anyNA(profile_row),
    "State coverage differs between PUMS and the CD119 crosswalk." =
      setequal(names(rows_by_state), unique(crosswalk$STATEFP))
  )

  # All people in the same PUMA use the same district probabilities. Add up
  # their weights within each demographic profile first, then split that total.
  cells_by_state <- vector("list", length(rows_by_state))
  names(cells_by_state) <- names(rows_by_state)
  for (state in names(rows_by_state)) {
    person_rows <- rows_by_state[[state]]
    residents <- profiles[profile_row[person_rows], demographics, drop = FALSE]
    residents$PUMA5CE <- sprintf("%05d", as.integer(people$PUMA[person_rows]))
    residents$PERWT <- people$PERWT[person_rows]
    weights <- crosswalk[crosswalk$STATEFP == state, c("PUMA5CE", "CDFP119", "allocation_weight")]
    if (!setequal(residents$PUMA5CE, weights$PUMA5CE)) {
      stop("State ", state, ": PUMS and the CD119 crosswalk have different PUMAs.", call. = FALSE)
    }

    puma_profiles <- residents |>
      group_by(across(all_of(c("PUMA5CE", demographics)))) |>
      summarise(weight_in_puma = sum(PERWT), .groups = "drop")
    cells <- puma_profiles |>
      inner_join(filter(weights, allocation_weight > 0), by = "PUMA5CE",
                 relationship = "many-to-many") |>
      group_by(across(all_of(c("CDFP119", demographics)))) |>
      summarise(N = sum(weight_in_puma * allocation_weight), .groups = "drop") |>
      mutate(STATEFP = .env$state, .before = 1)
    if (!close_counts(sum(cells$N), sum(residents$PERWT))) {
      stop("State ", state, ": CD119 cell weights differ from the original person weights.", call. = FALSE)
    }
    cells_by_state[[state]] <- cells
  }
  bind_rows(cells_by_state)
}

district_shares <- function(cells, congress) {
  district_column <- paste0("CDFP", congress)
  district_key <- c("STATEFP", district_column)
  cell_key <- c(district_key, names(demographic_levels))
  stopifnot(
    "Missing population-cell columns." = all(c(cell_key, "N") %in% names(cells)),
    "Expected positive, finite population in each cell." = all(is.finite(cells$N) & cells$N > 0),
    "Missing or duplicate population-cell key." =
      !anyNA(cells[cell_key]) && !vctrs::vec_duplicate_any(cells[cell_key])
  )

  # Put districts in state/district order and give each cell its district row.
  districts <- unique(as.data.frame(cells[district_key]))
  districts <- districts[order(districts$STATEFP, districts[[district_column]]), , drop = FALSE]
  district_row <- factor(vctrs::vec_match(cells[district_key], districts),
                         levels = seq_len(nrow(districts)))
  district_cvap <- as.numeric(tapply(cells$N, district_row, sum))
  result <- tibble::tibble(
    congress = congress, STATEFP = districts$STATEFP, CDFP = districts[[district_column]],
    cvap = district_cvap
  )

  for (field in names(demographic_levels)) {
    category <- factor(cells[[field]], levels = demographic_levels[[field]])
    if (anyNA(category)) stop("Unexpected category in ", field, call. = FALSE)
    # One row per district, one column per category. Zero preserves categories
    # that have no population in a district. Divide each row by its district's CVAP.
    counts <- tapply(cells$N, list(district_row, category), sum, default = 0)
    if (!close_counts(rowSums(counts), district_cvap)) {
      stop("District subtotals for ", field, " differ from CVAP on CD", congress, ".", call. = FALSE)
    }
    shares <- as.data.frame(sweep(counts, 1L, district_cvap, "/"))
    names(shares) <- unname(column_for_label[[field]][colnames(counts)])
    result <- bind_cols(result, shares)
  }
  result
}

check_map_populations <- function(cd119, cd120, both_maps, step03_totals) {
  state_totals <- both_maps |>
    group_by(congress, STATEFP) |>
    summarise(cvap = sum(cvap), .groups = "drop")
  reference_row <- match(state_totals$STATEFP, step03_totals$STATEFP)
  stopifnot(
    "Expected 435 voting districts and DC on each map." =
      nrow(cd119) == 436L && nrow(cd120) == 436L &&
      sum(both_maps$STATEFP == "11" & both_maps$CDFP == "98") == 2L,
    "Expected 51 jurisdictions in Step 03 and 102 state/map totals." =
      nrow(step03_totals) == 51L && !anyDuplicated(step03_totals$STATEFP) &&
      nrow(state_totals) == 102L,
    "District totals on the two maps must reproduce each state's Step 03 CVAP." =
      close_counts(state_totals$cvap, as.numeric(step03_totals$input_weight[reference_row]))
  )

  # A new district boundary can change a district's composition. Within the
  # state, the population of every demographic category must be conserved.
  for (column in unlist(share_columns, use.names = FALSE)) {
    cd119_count <- tapply(cd119[[column]] * cd119$cvap, cd119$STATEFP, sum)
    cd120_count <- tapply(cd120[[column]] * cd120$cvap, cd120$STATEFP, sum)
    if (!identical(names(cd119_count), names(cd120_count)) || !close_counts(cd119_count, cd120_count)) {
      stop("The state populations for ", column, " differ between CD119 and CD120.", call. = FALSE)
    }
  }
}

published_cd119_cvap <- function(archive) {
  # Step 02 pins this Census release. In CD.csv, lnnumber = 1 identifies
  # the Total estimate and its margin of error for each district.
  fingerprint <- "0c67665c62de843de7a3521a8110de05b4aa158cdc2db304015380615941056c"
  if (digest::digest(archive, algo = "sha256", file = TRUE, serialize = FALSE) != fingerprint) {
    stop("Unexpected 2020–2024 CVAP source fingerprint.")
  }
  member <- unz(archive, "CD.csv", open = "rt")
  on.exit(close(member))
  entries <- read.csv(member, colClasses = "character", check.names = FALSE)
  totals <- entries[entries$lnnumber == "1", ]
  stopifnot(
    all(totals$lntitle == "Total"),
    all(grepl("^5001900US[0-9]{2}([0-9]{2}|ZZ)$", totals$geoid))
  )
  # After "5001900US", the GEOID has two state digits and two district characters.
  # Puerto Rico (72) and unassigned areas (ZZ) fall outside the model's districts.
  benchmark <- tibble::tibble(
    STATEFP = substr(totals$geoid, 10, 11), CDFP = substr(totals$geoid, 12, 13),
    census_cvap = as.numeric(totals$cvap_est), census_moe = as.numeric(totals$cvap_moe)
  ) |> filter(STATEFP != "72", CDFP != "ZZ")
  stopifnot(
    nrow(benchmark) == 436L, !anyDuplicated(benchmark[c("STATEFP", "CDFP")]),
    all(benchmark$census_cvap > 0 & is.finite(benchmark$census_cvap)),
    all(benchmark$census_moe >= 0 & is.finite(benchmark$census_moe))
  )
  benchmark
}

publish_predictors <- function(stage, targets) {
  # Back up existing outputs before replacing the first file. If a rename
  # fails, restore files replaced earlier in this loop and remove new ones.
  backups <- file.path(stage, paste0("previous_", basename(targets)))
  had_prior <- file.exists(targets)
  if (any(had_prior) && !all(file.copy(targets[had_prior], backups[had_prior]))) {
    stop("Could not back up existing Step 08 products before publication.")
  }
  for (i in seq_along(targets)) {
    if (!file.rename(file.path(stage, basename(targets[i])), targets[i])) {
      for (j in seq_len(i - 1L)) {
        if (had_prior[j]) file.rename(backups[j], targets[j]) else unlink(targets[j])
      }
      stop("Could not publish ", targets[i])
    }
  }
}

if (sys.nframe() == 0L) build_predictors()
