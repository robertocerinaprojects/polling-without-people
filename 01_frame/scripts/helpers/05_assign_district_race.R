# Called by Script 05. Store a distribution over 120th districts for every CES
# citizen, then draw district first and race conditional on that same district.
# Design and fallback rules: 01_frame/docs/05_citizenship_district_decisions.md

assign_district_race <- function(ces, lookup, donor_tables) {
  ces <- as.data.frame(ces)
  lookup <- as.data.frame(lookup)
  races <- c("White", "Black", "Native American", "Asian", "Other/Multi")
  demographic <- c("gender_cat", "educ_cat", "age_cat")
  required <- c("caseid", "inputstate", "cdid119", "countyfips", "cit1", "race",
                "race_cat", "race_imputed", demographic)
  stopifnot(all(required %in% names(ces)), nrow(ces) > 0L, all(ces$cit1 == 1L),
            !anyNA(ces$caseid), !anyDuplicated(ces$caseid),
            identical(ces$race_imputed, ces$race %in% 3L),
            identical(levels(ces$race_cat), races),
            all(is.na(ces$race_cat) == ces$race_imputed))
  if (anyNA(ces[ces$race_imputed, demographic, drop = FALSE])) {
    stop("A draw recipient lacks age, education or sex/gender.")
  }

  # CES calls DC and the six at-large seats district 1. Match the Census codes.
  ces$STATEFP <- sprintf("%02d", as.integer(ces$inputstate))
  ces$CD119 <- sprintf("%02d", as.integer(ces$cdid119))
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
  stopifnot(!anyNA(lookup[lookup_fields]), all(grepl("^[0-9]{2}$", lookup$STATEFP)),
            all(grepl("^[0-9]{2}$", lookup$CD119)), all(grepl("^[0-9]{2}$", lookup$CD120)),
            all(lookup$county_fips == "" | grepl("^[0-9]{5}$", lookup$county_fips)),
            !anyDuplicated(lookup[c("STATEFP", "CD119", "county_fips", "CD120")]),
            all(is.finite(lookup$district_probability) & lookup$district_probability >= 0))
  group_key <- function(st, old, co) paste(st, old, co, sep = "/")
  lookup$key <- with(lookup, group_key(STATEFP, CD119, county_fips))
  sums <- tapply(lookup$district_probability, lookup$key, sum)
  stopifnot(all(abs(sums - 1) < 1e-10))
  broad <- group_key(ces$STATEFP, ces$CD119, "")
  stopifnot("Unknown state / 119th district." = all(broad %in% names(sums)))
  narrow <- group_key(ces$STATEFP, ces$CD119, county)
  use_county <- county != "" & narrow %in% names(sums)
  loc <- data.frame(id = seq_len(nrow(ces)), key = ifelse(use_county, narrow, broad))
  candidates <- merge(loc, lookup[lookup$district_probability > 0, ], by = "key", sort = FALSE)
  candidates$caseid <- as.character(ces$caseid[candidates$id])
  candidates$ces_county_fips <- county[candidates$id]
  candidates <- candidates[order(candidates$caseid, candidates$CD120, method = "radix"), ]
  stopifnot(length(unique(candidates$id)) == nrow(ces))

  # Keep old-CD-only matches auditable when the county was missing or its
  # intersection did not exist. The separate method describes the actual weights.
  candidates$location_match <- ifelse(use_county[candidates$id], "county_and_old_district",
    ifelse(candidates$ces_county_fips == "", "old_district_missing_county",
           "old_district_no_county_lookup"))
  # Reproducible choices in canonical case-ID and district order. Each case
  # contributes at most one row to the harmonized survey table.
  candidates$cumulative <- ave(candidates$district_probability, candidates$id, FUN = cumsum)
  last <- !duplicated(candidates$id, fromLast = TRUE)
  stopifnot(all(abs(candidates$cumulative[last] - 1) < 1e-10))
  candidates$cumulative[last] <- 1
  sorted_ids <- candidates$id[!duplicated(candidates$id)]
  set.seed(20261108L, kind = "Mersenne-Twister", normal.kind = "Inversion", sample.kind = "Rejection")
  geography_u <- numeric(nrow(ces))
  geography_u[sorted_ids] <- runif(length(sorted_ids))
  winner <- which(candidates$cumulative > geography_u[candidates$id])
  winner <- winner[!duplicated(candidates$id[winner])]
  chosen <- winner[match(seq_len(nrow(ces)), candidates$id[winner])]
  stopifnot(!anyNA(chosen))
  ces$CDFP120 <- candidates$CD120[chosen]
  ces$district_probability <- candidates$district_probability[chosen]
  ces$geography_method <- candidates$geography_method[chosen]
  candidates$selected <- FALSE
  candidates$selected[chosen] <- TRUE

  # Use the same five-way distribution for every recipient of a given profile,
  # evaluating all possible locations so the audit preserves district uncertainty.
  target <- candidates[ces$race_imputed[candidates$id], , drop = FALSE]
  stopifnot(nrow(target) > 0L)
  target$CDFP <- target$CD120
  target[demographic] <- ces[target$id, demographic, drop = FALSE]
  target$STATEFIP <- as.integer(target$STATEFP)
  by_level <- list(district = c("STATEFIP", "CDFP", demographic),
                   state = c("STATEFIP", demographic), national = demographic)
  profile_key <- function(data, fields) {
    do.call(paste, c(lapply(data[fields], as.character), sep = "|"))
  }
  used <- rep(NA_character_, nrow(target))
  support <- effective <- exact_support <- exact_effective <- rep(0, nrow(target))
  probs <- matrix(NA_real_, nrow(target), length(races))
  for (level in names(by_level)) {
    tab <- as.data.frame(donor_tables[[level]])
    fields <- by_level[[level]]
    stopifnot(all(c(fields, "race_cat", "probability", "profile_donors",
                    "effective_donors", "profile_weight") %in% names(tab)),
              all(tab$race_cat %in% races), !anyNA(tab[fields]))
    k <- profile_key(tab, fields)
    full <- paste(k, tab$race_cat, sep = "/")
    stopifnot(!anyDuplicated(full))
    needed <- which(is.na(used))
    if (!length(needed)) break
    target_k <- profile_key(target[needed, , drop = FALSE], fields)
    idx <- vapply(races, function(r) match(paste(target_k, r, sep = "/"), full),
                  integer(length(needed)))
    idx <- matrix(idx, nrow = length(needed), ncol = length(races))
    known <- !is.na(idx[, 1L])
    if (any(rowSums(is.na(idx)) %in% 1:4)) stop("Incomplete five-race donor table: ", level)
    ok <- known
    ok[known] <- tab$profile_weight[idx[known, 1L]] > 0
    if (level == "district" && any(known)) {
      exact_support[needed[known]] <- tab$profile_donors[idx[known, 1L]]
      exact_effective[needed[known]] <- tab$effective_donors[idx[known, 1L]]
    }
    if (any(ok)) {
      rows <- needed[ok]
      indices <- idx[ok, , drop = FALSE]
      probs[rows, ] <- matrix(tab$probability[indices], nrow = length(rows))
      used[rows] <- level
      support[rows] <- tab$profile_donors[indices[, 1L]]
      effective[rows] <- tab$effective_donors[indices[, 1L]]
    }
  }
  if (anyNA(used)) stop("A recipient has no Hispanic citizen donors with this demographic profile even nationally.")
  stopifnot(all(is.finite(probs) & probs >= 0 & probs <= 1),
            all(abs(rowSums(probs) - 1) < 1e-10), all(support > 0), all(effective > 0))
  target$donor_level <- used
  target$district_donors <- exact_support
  target$district_effective_donors <- exact_effective
  target$used_donors <- support
  target$used_effective_donors <- effective
  colnames(probs) <- c("p_white", "p_black", "p_native_american", "p_asian", "p_other_multi")
  target[colnames(probs)] <- as.data.frame(probs)
  selected <- which(target$selected)
  ids <- target$id[selected]  # Already sorted by case ID.
  stopifnot(length(ids) == sum(ces$race_imputed), !anyDuplicated(ids))
  set.seed(2024L, kind = "Mersenne-Twister", normal.kind = "Inversion", sample.kind = "Rejection")
  u <- runif(length(ids))
  cumulative <- probs[selected, , drop = FALSE]
  for (j in 2:ncol(cumulative)) cumulative[, j] <- cumulative[, j] + cumulative[, j - 1L]
  cumulative[, ncol(cumulative)] <- 1
  draw <- 1L + rowSums(cumulative <= u)
  stopifnot(all(probs[cbind(selected, draw)] > 0))
  ces$race_cat[ids] <- races[draw]
  stopifnot(!anyNA(ces$race_cat))
  ces$race_donor_level <- NA_character_
  ces$race_donor_level[ids] <- target$donor_level[selected]

  expected <- colSums(probs * target$district_probability)
  realized <- tabulate(draw, nbins = length(races))
  stopifnot(abs(sum(expected) - length(ids)) < 1e-6, sum(realized) == length(ids))
  audit <- data.frame(race_cat = races, expected_respondents = expected,
                      expected_share = expected / length(ids),
                      imputed_respondents = realized, realized_share = realized / length(ids),
                      row.names = NULL)
  geo_cols <- c("caseid", "STATEFP", "CD119", "ces_county_fips", "CD120",
                "district_probability", "geography_method", "location_match", "selected")
  support_cols <- c(geo_cols, demographic, "donor_level", "district_donors",
                    "district_effective_donors", "used_donors", "used_effective_donors", colnames(probs))
  list(ces = ces, district_probabilities = candidates[geo_cols],
       draw_audit = audit, support_audit = target[support_cols])
}
