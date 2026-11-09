# Script 05 draws a CD120 district for every eligible CES respondent. For those
# who gave Hispanic/Latino as their primary race, it then draws a harmonized
# race from Hispanic citizen-adult donors in the selected district or a broader
# area with the same demographic profile. See 05_citizenship_district_decisions.md.

assign_district_race <- function(ces, lookup, donor_tables) {
  ces <- as.data.frame(ces)
  lookup <- as.data.frame(lookup)
  races <- c("White", "Black", "Native American", "Asian", "Other/Multi")
  demographic <- c("gender_cat", "educ_cat", "age_cat")

  # Identify the respondents who need a race draw ----
  required <- c("caseid", "inputstate", "cdid119", "countyfips", "cit1", "race",
                "race_cat", "race_imputed", demographic)
  stopifnot(
    all(required %in% names(ces)), nrow(ces) > 0L, all(ces$cit1 == 1L),
    !anyNA(ces$caseid), !anyDuplicated(ces$caseid),
    identical(ces$race_imputed, ces$race %in% 3L),
    identical(levels(ces$race_cat), races),
    all(is.na(ces$race_cat) == ces$race_imputed)
  )
  if (anyNA(ces[ces$race_imputed, demographic, drop = FALSE])) {
    stop("A draw recipient lacks age, education or sex/gender.")
  }

  # Assign one district to each respondent, keeping every possible district for the audit.
  geography <- draw_ces_districts(ces, lookup)
  ces <- geography$ces
  candidates <- geography$candidates

  # Find a race distribution for each possible district of each draw recipient.
  target <- candidates[ces$race_imputed[candidates$id], , drop = FALSE]
  stopifnot(nrow(target) > 0L)
  target$CDFP <- target$CD120
  target[demographic] <- ces[target$id, demographic, drop = FALSE]
  target$STATEFIP <- as.integer(target$STATEFP)
  donors <- match_ces_race_donors(target, donor_tables, demographic, races)
  target <- donors$target
  probabilities <- donors$probabilities

  # Draw race using only the respondent's selected district ----
  selected <- which(target$selected)
  recipient_rows <- target$id[selected]  # Sorted by character case ID in draw_ces_districts().
  stopifnot(length(recipient_rows) == sum(ces$race_imputed), !anyDuplicated(recipient_rows))
  set.seed(2024L, kind = "Mersenne-Twister", normal.kind = "Inversion", sample.kind = "Rejection")
  race_draw <- runif(length(recipient_rows))
  cumulative <- probabilities[selected, , drop = FALSE]
  for (j in 2:ncol(cumulative)) {
    cumulative[, j] <- cumulative[, j] + cumulative[, j - 1L]
  }
  cumulative[, ncol(cumulative)] <- 1
  # The first cumulative probability above the draw gives the race.
  race_index <- 1L + rowSums(cumulative <= race_draw)
  stopifnot(all(probabilities[cbind(selected, race_index)] > 0))
  ces$race_cat[recipient_rows] <- races[race_index]
  stopifnot(!anyNA(ces$race_cat))
  ces$race_donor_level <- NA_character_
  ces$race_donor_level[recipient_rows] <- target$donor_level[selected]

  # Expected counts average over all possible districts and races. For example,
  # a district chance of .5 and a White donor share of .4 contribute .2 to the
  # expected White count. The realized counts use the one race actually drawn.
  expected <- colSums(probabilities * target$district_probability)
  realized <- tabulate(race_index, nbins = length(races))
  n_recipients <- length(recipient_rows)
  stopifnot(abs(sum(expected) - n_recipients) < 1e-6, sum(realized) == n_recipients)
  audit <- data.frame(
    race_cat = races, expected_respondents = expected, expected_share = expected / n_recipients,
    imputed_respondents = realized, realized_share = realized / n_recipients, row.names = NULL
  )
  geography_columns <- c("caseid", "STATEFP", "CD119", "ces_county_fips", "CD120",
                         "district_probability", "geography_method", "location_match", "selected")
  support_columns <- c(geography_columns, demographic, "donor_level", "district_donors",
                       "district_effective_donors", "used_donors", "used_effective_donors",
                       colnames(probabilities))
  list(ces = ces, district_probabilities = candidates[geography_columns],
       draw_audit = audit, support_audit = target[support_columns])
}

# Translate 2024 residence to one CD120 district ----
draw_ces_districts <- function(ces, lookup) {
  ces$STATEFP <- sprintf("%02d", as.integer(ces$inputstate))
  ces$CD119 <- sprintf("%02d", as.integer(ces$cdid119))
  # CES records DC and the six at-large seats as district 1.
  at_large <- ces$STATEFP %in% c("02", "10", "38", "46", "50", "56")
  dc <- ces$STATEFP == "11"
  stopifnot(!anyNA(ces$inputstate), !anyNA(ces$cdid119),
            all(ces$cdid119[at_large | dc] == 1L))
  ces$CD119[at_large] <- "00"
  ces$CD119[dc] <- "98"
  county <- ifelse(is.na(ces$countyfips), "", sprintf("%05d", as.integer(ces$countyfips)))

  lookup_fields <- c("STATEFP", "CD119", "county_fips", "CD120",
                     "district_probability", "geography_method")
  stopifnot(all(lookup_fields %in% names(lookup)))
  lookup$county_fips[is.na(lookup$county_fips)] <- ""
  stopifnot(
    !anyNA(lookup[lookup_fields]),
    all(grepl("^[0-9]{2}$", lookup$STATEFP)), all(grepl("^[0-9]{2}$", lookup$CD119)),
    all(grepl("^[0-9]{2}$", lookup$CD120)),
    all(lookup$county_fips == "" | grepl("^[0-9]{5}$", lookup$county_fips)),
    !anyDuplicated(lookup[c("STATEFP", "CD119", "county_fips", "CD120")]),
    all(is.finite(lookup$district_probability) & lookup$district_probability >= 0)
  )

  # Prefer county plus old district when the lookup has that intersection.
  # Otherwise use the old district alone and record why the county was unused.
  geography_key <- function(state, old_district, county) paste(state, old_district, county, sep = "/")
  lookup$key <- with(lookup, geography_key(STATEFP, CD119, county_fips))
  sums <- tapply(lookup$district_probability, lookup$key, sum)
  stopifnot(all(abs(sums - 1) < 1e-10))
  district_key <- geography_key(ces$STATEFP, ces$CD119, "")
  stopifnot("Unknown state / 119th district." = all(district_key %in% names(sums)))
  county_key <- geography_key(ces$STATEFP, ces$CD119, county)
  use_county <- county != "" & county_key %in% names(sums)
  locations <- data.frame(id = seq_len(nrow(ces)), key = ifelse(use_county, county_key, district_key))

  candidates <- merge(locations, lookup[lookup$district_probability > 0, ], by = "key", sort = FALSE)
  candidates$caseid <- as.character(ces$caseid[candidates$id])
  candidates$ces_county_fips <- county[candidates$id]
  candidates <- candidates[order(candidates$caseid, candidates$CD120, method = "radix"), ]
  stopifnot(length(unique(candidates$id)) == nrow(ces))
  candidates$location_match <- ifelse(
    use_county[candidates$id], "county_and_old_district",
    ifelse(candidates$ces_county_fips == "", "old_district_missing_county", "old_district_no_county_lookup")
  )

  # Draw once per respondent in character case-ID order, including people with
  # only one possible district. Walk the district probabilities in CD120 order.
  candidates$cumulative <- ave(candidates$district_probability, candidates$id, FUN = cumsum)
  last <- !duplicated(candidates$id, fromLast = TRUE)
  stopifnot(all(abs(candidates$cumulative[last] - 1) < 1e-10))
  candidates$cumulative[last] <- 1
  sorted_ids <- candidates$id[!duplicated(candidates$id)]
  set.seed(20261108L, kind = "Mersenne-Twister", normal.kind = "Inversion", sample.kind = "Rejection")
  district_draw <- numeric(nrow(ces))
  district_draw[sorted_ids] <- runif(length(sorted_ids))
  above_draw <- which(candidates$cumulative > district_draw[candidates$id])
  first_above <- above_draw[!duplicated(candidates$id[above_draw])]
  # Return the selected rows in the same order as the original respondents.
  chosen <- first_above[match(seq_len(nrow(ces)), candidates$id[first_above])]
  stopifnot(!anyNA(chosen))
  ces$CDFP120 <- candidates$CD120[chosen]
  ces$district_probability <- candidates$district_probability[chosen]
  ces$geography_method <- candidates$geography_method[chosen]
  candidates$selected <- FALSE
  candidates$selected[chosen] <- TRUE
  list(ces = ces, candidates = candidates)
}

# Find Hispanic citizen-adult donors for each possible respondent/district pair ----
match_ces_race_donors <- function(target, donor_tables, demographic, races) {
  # Age, education and sex/gender must match at every level. Only the
  # geographic area widens when a profile has no positive donor weight.
  profile_fields <- list(district = c("STATEFIP", "CDFP", demographic),
                         state = c("STATEFIP", demographic), national = demographic)
  profile_key <- function(data, fields) {
    do.call(paste, c(lapply(data[fields], as.character), sep = "|"))
  }
  n <- nrow(target)
  target$donor_level <- rep(NA_character_, n)
  target$district_donors <- numeric(n)
  target$district_effective_donors <- numeric(n)
  target$used_donors <- numeric(n)
  target$used_effective_donors <- numeric(n)
  probabilities <- matrix(NA_real_, n, length(races))

  for (level in names(profile_fields)) {
    donors <- as.data.frame(donor_tables[[level]])
    fields <- profile_fields[[level]]
    stopifnot(all(c(fields, "race_cat", "probability", "profile_donors",
                    "effective_donors", "profile_weight") %in% names(donors)),
              all(donors$race_cat %in% races), !anyNA(donors[fields]))
    donor_keys <- paste(profile_key(donors, fields), donors$race_cat, sep = "/")
    stopifnot(!anyDuplicated(donor_keys))
    pending <- which(is.na(target$donor_level))
    if (!length(pending)) break

    # Look up five donor rows per pending pair, one for each race. An absent
    # profile can use the next area. A partly missing five-race table is invalid.
    keys <- profile_key(target[pending, , drop = FALSE], fields)
    indices <- vapply(races, function(race) match(paste(keys, race, sep = "/"), donor_keys),
                      integer(length(pending)))
    indices <- matrix(indices, nrow = length(pending), ncol = length(races))
    missing_races <- rowSums(is.na(indices))
    if (any(missing_races > 0 & missing_races < length(races))) {
      stop("Incomplete five-race donor table: ", level)
    }
    # All five rows repeat the same profile totals in the donor tables.
    # Column one supplies those totals, including district support of zero.
    present <- !is.na(indices[, 1L])
    first_race <- indices[present, 1L]
    if (level == "district" && any(present)) {
      target$district_donors[pending[present]] <- donors$profile_donors[first_race]
      target$district_effective_donors[pending[present]] <- donors$effective_donors[first_race]
    }
    usable <- present
    usable[present] <- donors$profile_weight[first_race] > 0
    if (any(usable)) {
      rows <- pending[usable]
      matched <- indices[usable, , drop = FALSE]
      probabilities[rows, ] <- matrix(donors$probability[matched], nrow = length(rows))
      target$donor_level[rows] <- level
      target$used_donors[rows] <- donors$profile_donors[matched[, 1L]]
      target$used_effective_donors[rows] <- donors$effective_donors[matched[, 1L]]
    }
  }

  if (anyNA(target$donor_level)) {
    stop("A recipient has no Hispanic citizen donors with this demographic profile even nationally.")
  }
  stopifnot(all(is.finite(probabilities) & probabilities >= 0 & probabilities <= 1),
            all(abs(rowSums(probabilities) - 1) < 1e-10),
            all(target$used_donors > 0), all(target$used_effective_donors > 0))
  colnames(probabilities) <- c("p_white", "p_black", "p_native_american", "p_asian", "p_other_multi")
  target[colnames(probabilities)] <- as.data.frame(probabilities)
  list(target = target, probabilities = probabilities)
}

# Check the published survey races against the original answers and the draw audit.
check_ces_race_assignments <- function(before, after, race_audit, race_levels) {
  observed <- !before$race_imputed
  stopifnot(
    identical(before$caseid, after$caseid),
    identical(before$race, after$race), identical(before$hispanic, after$hispanic),
    identical(before$commonweight, after$commonweight), identical(before$cit1, after$cit1),
    identical(before$race_imputed, after$race_imputed), !anyNA(after$race_cat),
    identical(as.character(after$race_cat[observed]), as.character(before$race_cat[observed])),
    nrow(race_audit) == length(race_levels), setequal(race_audit$race_cat, race_levels),
    all(as.character(after$race_cat) %in% race_levels)
  )
  # The race-audit rows may arrive in a different order from the factor levels.
  counts_from_audit <- race_audit$imputed_respondents[match(race_levels, race_audit$race_cat)]
  imputed_races <- after$race_cat[after$race_imputed]
  stopifnot(
    identical(as.integer(counts_from_audit),
              tabulate(match(imputed_races, race_levels), nbins = length(race_levels))),
    sum(race_audit$imputed_respondents) == sum(before$race_imputed)
  )
}
