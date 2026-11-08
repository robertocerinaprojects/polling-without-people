# From the repository root: Rscript <helper path>/build_district_race_donors.R
# Estimate race shares among Hispanic citizen adults in each CD120 district,
# sex/gender, education and age group. A person's contribution to a district
# is already population weighted in Script 03. Script 04 defines the categories.
build_district_race_donors <- function(data_dir = file.path("01_frame", "data")) {
  intermediate <- file.path(data_dir, "intermediate")
  national_path <- file.path(data_dir, "output", "04_pums_hispanic_race_probabilities.csv")
  allocation_path <- file.path(intermediate, "pums_cd_allocation.rds")
  demo_path <- file.path(intermediate, "pums_demographics.rds")
  output_path <- file.path(intermediate, "hispanic_race_by_district_profile.rds")
  stopifnot(all(file.exists(c(national_path, allocation_path, demo_path))))
  tolerance <- 1e-12  # Same relative numerical tolerance as Script 03.
  close_enough <- function(x, reference) {
    all(is.finite(x) & is.finite(reference) &
        abs(x - reference) <= tolerance * pmax(1, abs(reference)))
  }

  person_key <- c("SAMPLE", "SERIAL", "PERNUM")
  predictors <- c("gender_cat", "educ_cat", "age_cat")
  race_levels <- c("White", "Black", "Native American", "Asian", "Other/Multi")
  demographics <- readRDS(demo_path)
  required <- c(person_key, "hispanic_cat", predictors, "race_cat")
  stopifnot(all(required %in% names(demographics)))
  field_levels <- lapply(demographics[predictors], levels)
  stopifnot(all(lengths(field_levels) > 0L))
  donors <- as.data.frame(demographics[which(demographics$hispanic_cat == "Hispanic"),
                                      c(person_key, predictors, "race_cat")])
  rm(demographics)
  invisible(gc())
  stopifnot(nrow(donors) > 0L, !anyNA(donors), !anyDuplicated(donors[person_key]),
            all(donors$race_cat %in% race_levels))
  key <- function(x) do.call(paste, c(lapply(x, as.character), sep = "|"))
  donor_keys <- key(donors[person_key])
  stopifnot(!anyDuplicated(donor_keys))
  profiles <- expand.grid(field_levels, KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE)
  donor_profile <- match(key(donors[predictors]), key(profiles))
  donor_race <- match(donors$race_cat, race_levels)
  stopifnot(!anyNA(donor_profile), !anyNA(donor_race))
  donor_count <- nrow(donors)
  rm(donors)

  # Rows within each area and demographic profile follow the five race
  # categories in order. Empty cells are kept for every area and profile.
  tabulate_donors <- function(areas, area_index, person, weight) {
    n_races <- length(race_levels)
    n_profiles <- nrow(profiles)
    grid <- expand.grid(race = seq_len(n_races), profile = seq_len(n_profiles),
                        area = seq_len(nrow(areas)), KEEP.OUT.ATTRS = FALSE)
    totals <- matrix(0, nrow(grid), 3L)
    if (length(person)) {
      profile_index <- donor_profile[person] + n_profiles * (area_index - 1L)
      group <- donor_race[person] + n_races * (profile_index - 1L)
      observed <- rowsum(cbind(n = 1, w = weight, squared = weight^2),
                         group, reorder = FALSE)
      totals[as.integer(rownames(observed)), ] <- observed
    }
    # At district level each row here corresponds to a different person in
    # that district. At state and national level each donor occurs just once.
    profile_totals <- function(values) colSums(matrix(values, nrow = n_races))
    profile_n <- profile_totals(totals[, 1L])
    profile_w <- profile_totals(totals[, 2L])
    profile_w2 <- profile_totals(totals[, 3L])
    cell <- rep(seq_along(profile_n), each = n_races)
    result <- data.frame(areas[grid$area, , drop = FALSE],
                         profiles[grid$profile, , drop = FALSE],
                         race_cat = race_levels[grid$race],
                         donor_records = as.integer(totals[, 1L]),
                         donor_weight = totals[, 2L],
                         profile_donors = as.integer(profile_n[cell]),
                         profile_weight = profile_w[cell],
                         effective_donors = ifelse(profile_w2[cell] > 0,
                           profile_w[cell]^2 / profile_w2[cell], 0),
                         stringsAsFactors = FALSE, row.names = NULL)
    result$probability <- ifelse(result$profile_weight > 0,
                                 result$donor_weight / result$profile_weight, NA_real_)
    supported <- profile_w > 0
    stopifnot(all(is.na(result$probability) == (result$profile_weight == 0)),
              close_enough(profile_totals(result$probability)[supported], 1))
    result
  }

  allocation <- readRDS(allocation_path)
  required <- c(person_key, "STATEFIP", "CDFP", "PERWT",
                "allocation_weight", "allocated_person_weight")
  stopifnot(all(required %in% names(allocation)), !anyNA(allocation$STATEFIP))
  states <- sort(unique(as.integer(allocation$STATEFIP)))
  rows_by_state <- split(seq_len(nrow(allocation)), factor(allocation$STATEFIP, levels = states))
  donor_state <- integer(donor_count)
  person_weight <- numeric(donor_count)
  district_tables <- vector("list", length(states))

  # Match to the smaller Hispanic donor key table one state at a time. Keep
  # only that state's donor rows while checking and summing its allocations.
  for (i in seq_along(states)) {
    rows <- rows_by_state[[i]]
    codes <- sort(unique(as.character(allocation$CDFP[rows])))
    stopifnot(!anyNA(codes), all(grepl("^[0-9]{2}$", codes)))
    matched <- match(key(allocation[rows, person_key, drop = FALSE]), donor_keys, nomatch = 0L)
    rows <- rows[matched > 0L]
    person <- matched[matched > 0L]
    district <- match(as.character(allocation$CDFP[rows]), codes)
    weight <- as.numeric(allocation$allocated_person_weight[rows])
    fraction <- allocation$allocation_weight[rows]
    original <- allocation$PERWT[rows]
    if (length(person)) {
      # A national donor can contribute to several districts, once in each
      # district and exclusively in their own state.
      pair <- as.double(person) + donor_count * as.double(district - 1L)
      stopifnot(!anyDuplicated(pair), !anyNA(district),
                all(is.finite(fraction) & fraction > 0 & fraction <= 1 + tolerance),
                all(is.finite(weight) & weight > 0), all(is.finite(original) & original > 0))
      checked <- rowsum(cbind(fraction, weight), group = person, reorder = FALSE)
      first <- !duplicated(person)
      ids <- person[first]
      stopifnot(identical(ids, as.integer(rownames(checked))), all(donor_state[ids] == 0L),
                close_enough(checked[, 1L], 1), close_enough(checked[, 2L], original[first]))
      donor_state[ids] <- states[i]
      # Recombine all districts before counting support in broader donor pools.
      person_weight[ids] <- checked[, 2L]
      stopifnot(close_enough(original, person_weight[person]),
                close_enough(weight, original * fraction))
    }
    areas <- data.frame(STATEFIP = states[i], CDFP = codes, stringsAsFactors = FALSE)
    district_tables[[i]] <- tabulate_donors(areas, district, person, weight)
  }
  stopifnot(all(donor_state > 0L), all(person_weight > 0))
  rm(allocation, rows_by_state, donor_keys)
  invisible(gc())

  all_donors <- seq_len(donor_count)
  district <- do.call(rbind, district_tables)
  state <- tabulate_donors(data.frame(STATEFIP = states), match(donor_state, states),
                           all_donors, person_weight)
  national <- tabulate_donors(data.frame(pool = "national"), rep(1L, donor_count),
                              all_donors, person_weight)

  # Reconcile to independently saved Script 04 national race totals. National
  # and state donor counts count people, district counts count people per district.
  reference <- read.csv(national_path, stringsAsFactors = FALSE)
  stopifnot(nrow(reference) == length(race_levels), setequal(reference$race_cat, race_levels))
  reference <- reference[match(race_levels, reference$race_cat), , drop = FALSE]
  for (x in list(district, state, national)) {
    sums <- tapply(x$donor_weight, factor(x$race_cat, levels = race_levels), sum)
    stopifnot(close_enough(unname(sums), reference$donor_weight))
  }
  for (x in list(state, national)) {
    counts <- tapply(x$donor_records, factor(x$race_cat, levels = race_levels), sum)
    stopifnot(all(unname(counts) == reference$donor_records))
  }

  result <- list(district = district, state = state, national = national)
  tmp <- tempfile("district_race_", tmpdir = intermediate)
  on.exit(unlink(tmp), add = TRUE)
  saveRDS(result, tmp)
  if (!file.rename(tmp, output_path)) stop("Could not save ", output_path)
  cat("Hispanic citizen adult donor records:", donor_count,
      "\nRecombined person weight:", format(sum(person_weight), scientific = FALSE),
      "\nCD120 districts:", nrow(unique(district[c("STATEFIP", "CDFP")])),
      "\nDistrict donor tables saved:", output_path, "\n")
  invisible(output_path)
}
if (sys.nframe() == 0L) build_district_race_donors()
