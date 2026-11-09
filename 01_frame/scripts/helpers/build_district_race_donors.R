# Estimate race probabilities among Hispanic citizen adults who share the same
# gender, education and age group. Prepare district, state and national tables
# so the CES can use the most local pool with positive population weight.
# Run from the repository root: Rscript 01_frame/scripts/helpers/build_district_race_donors.R

build_district_race_donors <- function(data_dir = file.path("01_frame", "data")) {
  intermediate <- file.path(data_dir, "intermediate")
  demo_path <- file.path(intermediate, "pums_demographics.rds")
  allocation_path <- file.path(intermediate, "pums_cd_allocation.rds")
  national_path <- file.path(data_dir, "output", "04_pums_hispanic_race_probabilities.csv")
  output_path <- file.path(intermediate, "hispanic_race_by_district_profile.rds")
  stopifnot(all(file.exists(c(national_path, allocation_path, demo_path))))

  person_key <- c("SAMPLE", "SERIAL", "PERNUM")
  donors <- read_hispanic_donors(demo_path, person_key)
  donor_count <- length(donors$keys)

  # Step 03 has one row per person and possible district. Work on one state's
  # rows at a time so the full set of demographic columns stays out of this join.
  allocation <- readRDS(allocation_path)
  required <- c(person_key, "STATEFIP", "CDFP", "PERWT", "allocation_weight", "allocated_person_weight")
  stopifnot(all(required %in% names(allocation)), !anyNA(allocation$STATEFIP))
  states <- sort(unique(as.integer(allocation$STATEFIP)))
  rows_by_state <- split(seq_len(nrow(allocation)), factor(allocation$STATEFIP, levels = states))
  donor_state <- integer(donor_count)
  person_weight <- numeric(donor_count)
  district_tables <- vector("list", length(states))

  for (i in seq_along(states)) {
    rows <- rows_by_state[[i]]
    codes <- sort(unique(as.character(allocation$CDFP[rows])))
    stopifnot(!anyNA(codes), all(grepl("^[0-9]{2}$", codes)))
    matched <- match(donor_key(allocation[rows, person_key, drop = FALSE]), donors$keys)
    has_donor <- !is.na(matched)
    donor_id <- matched[has_donor]
    rows <- rows[has_donor]
    district_id <- match(as.character(allocation$CDFP[rows]), codes)
    district_weight <- as.numeric(allocation$allocated_person_weight[rows])

    if (length(donor_id)) {
      recombined <- recombine_donor_weights(
        donor_id, district_id, district_weight,
        allocation$allocation_weight[rows], allocation$PERWT[rows]
      )
      stopifnot("A Hispanic donor appears in two states." = all(donor_state[recombined$id] == 0L))
      donor_state[recombined$id] <- states[i]
      person_weight[recombined$id] <- recombined$weight
    }
    areas <- data.frame(STATEFIP = states[i], CDFP = codes, stringsAsFactors = FALSE)
    district_tables[[i]] <- donor_table(areas, district_id, donor_id, district_weight, donors)
  }
  stopifnot(all(donor_state > 0L), all(person_weight > 0))
  rm(allocation, rows_by_state)
  donors$keys <- NULL
  invisible(gc())

  # Every donor contributes once in their state and once nationally. A person
  # split across districts contributes their full recombined weight here.
  all_donors <- seq_len(donor_count)
  state <- donor_table(data.frame(STATEFIP = states), match(donor_state, states),
                       all_donors, person_weight, donors)
  national <- donor_table(data.frame(pool = "national"), rep(1L, donor_count),
                          all_donors, person_weight, donors)
  district <- do.call(rbind, district_tables)
  tables <- list(district = district, state = state, national = national)
  check_national_donor_totals(tables, national_path, donors$races)

  tmp <- tempfile("district_race_", tmpdir = intermediate)
  on.exit(unlink(tmp), add = TRUE)
  saveRDS(tables, tmp)
  if (!file.rename(tmp, output_path)) stop("Could not save ", output_path)
  cat("Hispanic citizen adult donor records:", donor_count,
      "\nRecombined person weight:", format(sum(person_weight), scientific = FALSE),
      "\nCD120 districts:", nrow(unique(district[c("STATEFIP", "CDFP")])),
      "\nDistrict donor tables saved:", output_path, "\n")
  invisible(output_path)
}

donor_key <- function(columns) do.call(paste, c(lapply(columns, as.character), sep = "|"))

# Step 03 uses the same relative tolerance for sums of fractional person weights.
donor_weights_agree <- function(x, expected) {
  all(is.finite(x) & is.finite(expected) & abs(x - expected) <= 1e-12 * pmax(1, abs(expected)))
}

read_hispanic_donors <- function(path, person_key) {
  profile_fields <- c("gender_cat", "educ_cat", "age_cat")
  races <- c("White", "Black", "Native American", "Asian", "Other/Multi")
  demographics <- readRDS(path)
  required <- c(person_key, "hispanic_cat", profile_fields, "race_cat")
  stopifnot(all(required %in% names(demographics)))
  categories <- lapply(demographics[profile_fields], levels)
  stopifnot(all(lengths(categories) > 0L))
  hispanic <- which(demographics$hispanic_cat == "Hispanic")
  people <- as.data.frame(demographics[hispanic, c(person_key, profile_fields, "race_cat")])
  rm(demographics)
  invisible(gc())
  stopifnot(nrow(people) > 0L, !anyNA(people), !anyDuplicated(people[person_key]),
            all(people$race_cat %in% races))

  profiles <- expand.grid(categories, KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE)
  keys <- donor_key(people[person_key])
  profile_id <- match(donor_key(people[profile_fields]), donor_key(profiles))
  race_id <- match(people$race_cat, races)
  stopifnot(!anyDuplicated(keys), !anyNA(profile_id), !anyNA(race_id))
  list(keys = keys, profiles = profiles, races = races, profile_id = profile_id, race_id = race_id)
}

recombine_donor_weights <- function(donor_id, district_id, district_weight, fraction, original_weight) {
  stopifnot(!anyNA(district_id),
            !vctrs::vec_duplicate_any(data.frame(donor_id, district_id)),
            all(is.finite(fraction) & fraction > 0 & fraction <= 1 + 1e-12),
            all(is.finite(district_weight) & district_weight > 0),
            all(is.finite(original_weight) & original_weight > 0))
  # For example, weights of 14 and 6 in two districts become one person of weight 20.
  sums <- rowsum(cbind(fraction, district_weight), group = donor_id, reorder = FALSE)
  first_row <- !duplicated(donor_id)
  ids <- donor_id[first_row]
  weights <- sums[, "district_weight"]
  stopifnot(identical(ids, as.integer(rownames(sums))),
            donor_weights_agree(sums[, "fraction"], 1),
            donor_weights_agree(weights, original_weight[first_row]),
            donor_weights_agree(original_weight, weights[match(donor_id, ids)]),
            donor_weights_agree(district_weight, original_weight * fraction))
  list(id = ids, weight = weights)
}

donor_table <- function(areas, area_id, donor_id, weight, donors) {
  # Include every race for every profile in every area, even where there are no donors.
  n_races <- length(donors$races)
  n_profiles <- nrow(donors$profiles)
  grid <- expand.grid(race = seq_len(n_races), profile = seq_len(n_profiles),
                      area = seq_len(nrow(areas)), KEEP.OUT.ATTRS = FALSE)
  totals <- matrix(0, nrow(grid), 3L, dimnames = list(NULL, c("records", "weight", "squared_weight")))
  if (length(donor_id)) {
    # Look up a grid row by its three coordinates. expand.grid cycles through
    # races first, so the five rows for one demographic profile are consecutive.
    grid_row <- array(seq_len(nrow(grid)), dim = c(n_races, n_profiles, nrow(areas)))
    coordinates <- cbind(donors$race_id[donor_id], donors$profile_id[donor_id], area_id)
    observed <- rowsum(cbind(1, weight, weight^2), group = grid_row[coordinates], reorder = FALSE)
    totals[as.integer(rownames(observed)), ] <- observed
  }

  sum_races <- function(x) colSums(matrix(x, nrow = n_races))
  profile_records <- sum_races(totals[, "records"])
  profile_weight <- sum_races(totals[, "weight"])
  squared_weights <- sum_races(totals[, "squared_weight"])
  # profile_donors counts people in this area's profile. effective_donors is
  # (sum of weights)^2 / sum of squared weights, which reflects unequal weights.
  effective <- ifelse(squared_weights > 0, profile_weight^2 / squared_weights, 0)
  profile_row <- rep(seq_along(profile_records), each = n_races)
  result <- data.frame(
    areas[grid$area, , drop = FALSE], donors$profiles[grid$profile, , drop = FALSE],
    race_cat = donors$races[grid$race],
    donor_records = as.integer(totals[, "records"]), donor_weight = totals[, "weight"],
    profile_donors = as.integer(profile_records[profile_row]),
    profile_weight = profile_weight[profile_row], effective_donors = effective[profile_row],
    stringsAsFactors = FALSE, row.names = NULL
  )
  # A supported profile can have a zero race probability. If it has no
  # population weight at all, all five probabilities are missing.
  result$probability <- ifelse(result$profile_weight > 0, result$donor_weight / result$profile_weight, NA_real_)
  supported <- profile_weight > 0
  stopifnot(all(is.na(result$probability) == (result$profile_weight == 0)),
            donor_weights_agree(sum_races(result$probability)[supported], 1))
  result
}

check_national_donor_totals <- function(tables, path, races) {
  reference <- read.csv(path, stringsAsFactors = FALSE)
  stopifnot(nrow(reference) == length(races), setequal(reference$race_cat, races))
  reference <- reference[match(races, reference$race_cat), , drop = FALSE]
  # All three tables must reproduce the Step 04 population weight for each race.
  for (pool in tables) {
    weights <- tapply(pool$donor_weight, factor(pool$race_cat, levels = races), sum)
    stopifnot(donor_weights_agree(unname(weights), reference$donor_weight))
  }
  # A donor split across districts appears in multiple district counts. Only
  # the state and national counts total the number of individual donors.
  for (pool in tables[c("state", "national")]) {
    counts <- tapply(pool$donor_records, factor(pool$race_cat, levels = races), sum)
    stopifnot(all(unname(counts) == reference$donor_records))
  }
}

if (sys.nframe() == 0L) build_district_race_donors()
