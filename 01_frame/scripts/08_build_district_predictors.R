# Reconstruct the citizen-adult PUMS frame for the districts elected in 2024.
# Run from repository root: Rscript 01_frame/scripts/08_build_district_predictors.R
# Read 01_frame/docs/08_build_district_predictors.md for geography and data lineage.
library(dplyr)

demographic_levels <- list(
  age_cat = c(paste(seq(18, 78, 5), seq(22, 82, 5), sep = "-"), "83+"),
  gender_cat = c("Male", "Female"),
  educ_cat = c("No HS", "HS grad", "Some college", "2-year", "4-year", "Post-grad"),
  race_cat = c("White", "Black", "Native American", "Asian", "Other/Multi"),
  hispanic_cat = c("Hispanic", "Not Hispanic")
)
share_columns <- list(
  age_cat = c(paste0("age_", seq(18, 78, 5), "_", seq(22, 82, 5)), "age_83_plus"),
  gender_cat = c("sex_male", "sex_female"),
  educ_cat = c("educ_no_hs", "educ_hs", "educ_some_college", "educ_two_year",
               "educ_four_year", "educ_postgrad"),
  race_cat = c("race_white", "race_black", "race_native", "race_asian", "race_other_multi"),
  hispanic_cat = c("eth_hispanic", "eth_not_hispanic")
)

close_counts <- function(x, y) {
  length(x) == length(y) && all(is.finite(x) & is.finite(y) &
    abs(x - y) <= 1e-10 * pmax(1, abs(y)))
}

build_old_cells <- function(intermediate, crosswalk) {
  ids <- c("SAMPLE", "SERIAL", "PERNUM")
  original <- readRDS(file.path(intermediate, "pums_clean.rds"))[
    c(ids, "STATEFIP", "PUMA", "PERWT")]
  demo <- readRDS(file.path(intermediate, "pums_demographics.rds"))
  groups <- names(demographic_levels)
  stopifnot(!anyNA(original), nrow(demo) == nrow(original), !anyNA(demo[c(ids, groups)]),
            all(is.finite(original$PERWT) & original$PERWT > 0))
  old <- split(seq_len(nrow(original)), sprintf("%02d", original$STATEFIP))
  # Find each person's Step 04 demographic values, even if file row order changed.
  source_id <- original[ids]
  demo_id <- demo[ids]
  stopifnot(!vctrs::vec_duplicate_any(source_id), !vctrs::vec_duplicate_any(demo_id))
  paired <- if (identical(source_id, demo_id)) seq_len(nrow(original)) else
    vctrs::vec_match(source_id, demo_id)
  stopifnot(!anyNA(paired), setequal(names(old), unique(crosswalk$STATEFP)))
  rm(source_id, demo_id)
  cells <- vector("list", length(old))
  names(cells) <- names(old)
  for (state in names(old)) {
    idx <- old[[state]]
    data <- demo[paired[idx], groups, drop = FALSE]
    data$PUMA5CE <- sprintf("%05d", as.integer(original$PUMA[idx]))
    data$PERWT <- original$PERWT[idx]
    weights <- crosswalk[crosswalk$STATEFP == state, c("PUMA5CE", "CDFP119", "allocation_weight")]
    stopifnot(setequal(data$PUMA5CE, weights$PUMA5CE))
    # All people in a PUMA use the same district weights. Summing PERWT within
    # PUMA and demographic cell before multiplying is exactly the same as
    # expanding each person/district pair and then summing their weights.
    cells[[state]] <- data |>
      group_by(across(all_of(c("PUMA5CE", groups)))) |>
      summarise(weight_in_puma = sum(PERWT), .groups = "drop") |>
      inner_join(filter(weights, allocation_weight > 0), by = "PUMA5CE",
                 relationship = "many-to-many") |>
      group_by(across(all_of(c("CDFP119", groups)))) |>
      summarise(N = sum(weight_in_puma * allocation_weight), .groups = "drop") |>
      mutate(STATEFP = .env$state, .before = 1)
    stopifnot(close_counts(sum(cells[[state]]$N), sum(data$PERWT)))
  }
  bind_rows(cells)
}

district_shares <- function(cells, congress) {
  field <- paste0("CDFP", congress)
  keys <- c("STATEFP", field)
  stopifnot(all(c(keys, names(demographic_levels), "N") %in% names(cells)),
            all(is.finite(cells$N) & cells$N > 0),
            !anyNA(cells[c(keys, names(demographic_levels))]),
            !vctrs::vec_duplicate_any(cells[c(keys, names(demographic_levels))]))
  districts <- unique(as.data.frame(cells[keys]))
  districts <- districts[order(districts[[1]], districts[[2]]), , drop = FALSE]
  ix <- factor(vctrs::vec_match(cells[keys], districts), levels = seq_len(nrow(districts)))
  names(districts)[2] <- "CDFP"
  n <- as.numeric(tapply(cells$N, ix, sum))
  out <- tibble::tibble(congress = congress, STATEFP = districts$STATEFP,
                        CDFP = districts$CDFP, cvap = n)
  for (field in names(demographic_levels)) {
    category <- factor(cells[[field]], levels = demographic_levels[[field]])
    stopifnot(!anyNA(category))
    totals <- tapply(cells$N, list(ix, category), sum, default = 0)
    stopifnot(close_counts(rowSums(totals), n))
    shares <- as.data.frame(sweep(totals, 1, n, "/"))
    names(shares) <- share_columns[[field]]
    out <- bind_cols(out, shares)
  }
  out
}

published_cd119_cvap <- function(archive) {
  # Reviewed Step 02 CVAP archive; the published district counts are used only for comparison.
  fingerprint <- "0c67665c62de843de7a3521a8110de05b4aa158cdc2db304015380615941056c"
  if (digest::digest(archive, algo = "sha256", file = TRUE, serialize = FALSE) != fingerprint) {
    stop("Unexpected 2020–2024 CVAP source fingerprint.")
  }
  member <- unz(archive, "CD.csv", open = "rt")
  on.exit(close(member))
  x <- read.csv(member, colClasses = "character", check.names = FALSE)
  x <- x[x$lnnumber == "1", ]
  stopifnot(all(x$lntitle == "Total"), all(grepl("^5001900US[0-9]{2}([0-9]{2}|ZZ)$", x$geoid)))
  out <- tibble::tibble(
    STATEFP = substr(x$geoid, 10, 11), CDFP = substr(x$geoid, 12, 13),
    census_cvap = as.numeric(x$cvap_est), census_moe = as.numeric(x$cvap_moe)
  ) |> filter(STATEFP != "72", CDFP != "ZZ")
  stopifnot(nrow(out) == 436L, !anyDuplicated(out[c("STATEFP", "CDFP")]),
            all(out$census_cvap > 0 & is.finite(out$census_cvap)),
            all(out$census_moe >= 0 & is.finite(out$census_moe)))
  out
}

build_predictors <- function() {
  data <- file.path("01_frame", "data")
  output <- file.path(data, "output")
  intermediate <- file.path(data, "intermediate")
  stage <- tempfile("step08_", tmpdir = data)
  stopifnot(dir.create(stage))
  on.exit(unlink(stage, recursive = TRUE), add = TRUE)
  helper <- file.path("01_frame", "scripts", "helpers", "08_cd119_weights.py")
  status <- system2("python3", c(shQuote(helper), shQuote(stage)))
  if (status != 0L) stop("The CD119 crosswalk failed. See the preceding geographic diagnostic.")
  read_text <- function(path) read.csv(path, colClasses = "character", check.names = FALSE)
  weights <- read_text(file.path(stage, "08_puma_cd119_weights.csv"))
  weights$allocation_weight <- as.numeric(weights$allocation_weight)
  old <- build_old_cells(intermediate, weights)
  new <- readRDS(file.path(intermediate, "pums_cd_cells.rds"))
  old_name <- "08_pums_cd119_cells.rds"
  saveRDS(old, file.path(stage, old_name))
  old_share <- district_shares(old, 119L)
  new_share <- district_shares(new, 120L)
  all_areas <- bind_rows(old_share, new_share)
  state_totals <- all_areas |>
    group_by(congress, STATEFP) |>
    summarise(cvap = sum(cvap), .groups = "drop")
  reference <- read_text(file.path(output, "03_pums_allocation_by_state.csv"))
  stopifnot(nrow(old_share) == 436L, nrow(new_share) == 436L,
            nrow(reference) == 51L, !anyDuplicated(reference$STATEFP),
            sum(all_areas$STATEFP == "11" & all_areas$CDFP == "98") == 2L,
            nrow(state_totals) == 102L,
            close_counts(state_totals$cvap, as.numeric(reference$input_weight[
              match(state_totals$STATEFP, reference$STATEFP)])))
  # Each demographic subtotal must also survive a change of map within a state.
  for (column in unlist(share_columns, use.names = FALSE)) {
    old_n <- tapply(old_share[[column]] * old_share$cvap, old_share$STATEFP, sum)
    new_n <- tapply(new_share[[column]] * new_share$cvap, new_share$STATEFP, sum)
    stopifnot(identical(names(old_n), names(new_n)), close_counts(old_n, new_n))
  }
  census <- published_cd119_cvap(file.path(data, "input", "CVAP_2020-2024_ACS_csv_files.zip"))
  benchmark <- old_share |>
    select(STATEFP, CDFP, pums_cvap = cvap) |>
    left_join(census, by = c("STATEFP", "CDFP"), relationship = "one-to-one") |>
    mutate(difference = pums_cvap - census_cvap)
  stopifnot(!anyNA(benchmark))
  readr::write_csv(benchmark, file.path(stage, "08_cd119_cvap_benchmark.csv"))
  readr::write_csv(all_areas, file.path(stage, "08_district_demographics.csv"))
  targets <- c(
    file.path(intermediate, c(old_name, "08_puma_cd119_weights.csv", "08_district_demographics.csv")),
    file.path(output, c("08_district_overlap.csv", "08_cd119_allocation_exceptions.csv",
                        "08_cd119_cvap_benchmark.csv"))
  )
  # Preserve the previous set if publication fails partway through.
  prior <- file.path(stage, paste0("previous_", basename(targets)))
  had_prior <- file.exists(targets)
  if (any(had_prior) && !all(file.copy(targets[had_prior], prior[had_prior]))) {
    stop("Could not back up existing Step 08 products before publication.")
  }
  for (i in seq_along(targets)) {
    if (!file.rename(file.path(stage, basename(targets[i])), targets[i])) {
      for (j in seq_len(i - 1L)) {
        if (had_prior[j]) file.rename(prior[j], targets[j]) else unlink(targets[j])
      }
      stop("Could not publish ", targets[i])
    }
  }
  cat("Published", nrow(all_areas), "district/map rows, including DC on both maps.\n",
      "CD119 PUMS CVAP:", format(sum(old_share$cvap), scientific = FALSE),
      "| CD120 PUMS CVAP:", format(sum(new_share$cvap), scientific = FALSE), "\n")
}

if (sys.nframe() == 0L) build_predictors()
