# Match identical block footprints; the district number can change between maps.
house_projection_matches <- function(target, old) {
  stopifnot(is.character(target$matching_cd119), !anyDuplicated(old[c("STATEFP", "CDFP")]),
            !anyDuplicated(target[c("STATEFP", "CDFP")]), !anyNA(old$status),
            all(old$status %in% c("observed", "unopposed_not_on_ballot")))
  identical_area <- !is.na(target$matching_cd119) & nzchar(target$matching_cd119)
  old_row <- match(paste(target$STATEFP, target$matching_cd119, sep = "-"),
                   paste(old$STATEFP, old$CDFP, sep = "-"))
  if (anyNA(old_row[identical_area]) || anyDuplicated(old_row[identical_area])) {
    stop("An identical footprint must match exactly one original 2024 district.")
  }
  old_row[!identical_area] <- NA_integer_
  old_row
}

# Identify each unpolled 2024 seat from the member who actually took office.
# Compare the official winner record with the included nominees and the party
# flags from Step 08. The model needs the winning party, not a candidate ID.
mark_unpolled_house_scenarios <- function(old, nominee_path) {
  winners <- read_table09("01_frame/docs/09_unpolled_house_winners_2024.csv")
  unpolled <- old$status == "unopposed_not_on_ballot"
  seats <- old[unpolled, ]
  keys <- district_id(seats)
  if (anyDuplicated(district_id(winners)) || !setequal(keys, district_id(winners))) {
    stop("The unpolled 2024 districts differ from the verified House winners.")
  }
  winners <- winners[match(keys, district_id(winners)), ]

  audit <- read_table09(nominee_path)
  eligible <- audit$year == 2024L & audit$included == 1L & district_id(audit) %in% keys
  nominees <- audit[eligible, ]
  if (anyDuplicated(district_id(nominees)) || !setequal(keys, district_id(nominees))) {
    stop("Expected exactly one eligible 2024 nominee per unpolled House contest.")
  }
  nominees <- nominees[match(keys, district_id(nominees)), ]
  stopifnot(identical(winners$winner, nominees$candidate),
            identical(winners$party_group, nominees$party_group),
            identical(winners$incumbent, nominees$incumbent),
            all(winners$party_group %in% c("D", "R")), all(winners$incumbent %in% 0:1),
            all(rowSums(seats[c("n_dem", "n_rep", "n_other")]) == 1L),
            all(seats$slate == winners$party_group))
  for (party in names(house_columns$incumbent)) {
    expected <- as.integer(winners$party_group == party) * winners$incumbent
    if (any(seats[[house_columns$incumbent[[party]]]] != expected)) {
      stop("The district incumbency flag disagrees with the verified unpolled winner.")
    }
  }

  old$unopposed_party <- NA_character_
  old$unopposed_party[unpolled] <- winners$party_group
  old
}

prepare_house_prediction_scope <- function(target, old, roster_path) {
  old_row <- house_projection_matches(target, old)
  redrawn <- is.na(old_row)

  # Both named districts get the historical winner's sole-party ballot. FL-20
  # changed shape. Matching the label here selects a scenario only; its PUMS
  # demographics and population still come from the new Florida district.
  unpolled <- which(!is.na(old$unopposed_party))
  scenario_row <- match(district_id(old[unpolled, ]), district_id(target))
  if (anyNA(scenario_row) || anyDuplicated(scenario_row) ||
      any(!redrawn[scenario_row] & old_row[scenario_row] != unpolled)) {
    stop("Check the target district labels for the two unopposed 2024 scenarios.")
  }
  original_lineup <- old_row
  original_lineup[scenario_row] <- unpolled
  current_lineup <- is.na(original_lineup)

  target$unopposed_party <- old$unopposed_party[original_lineup]
  if (sum(!is.na(target$unopposed_party)) != length(unpolled)) {
    stop("An unpolled district was assigned to more than one projection scenario.")
  }
  target$prediction_source <- "observed_same_footprint"
  target$prediction_source[current_lineup] <- "model_redrawn"
  target$prediction_source[scenario_row] <- "model_unopposed_2024"
  target$needs_prediction <- target$prediction_source != "observed_same_footprint"
  target$lineup_year <- ifelse(current_lineup, 2026L, 2024L)

  # Carry the historical lineup with every identical observed footprint for
  # the covariate table. Those districts' final shares use their actual votes.
  lineup_fields <- c("slate", "n_dem", "n_rep", "n_other", "ballot_dem", "ballot_rep",
                     "ballot_other", "same_party_multiple", "ballot_group", "major_party_direction",
                     house_columns$incumbent)
  target[lineup_fields] <- old[original_lineup, lineup_fields, drop = FALSE]
  if (any(current_lineup)) {
    lineup <- add_slate(target[current_lineup, c("STATEFP", "CDFP"), drop = FALSE], roster_path)
    target[current_lineup, lineup_fields] <- lineup[lineup_fields]
  }
  unsupported <- target$needs_prediction & is.na(target$ballot_group)
  if (any(unsupported)) stop("No fitted ballot group for ", paste(district_id(target)[unsupported], collapse = ", "))
  target
}

# Each target uses the four fitted shares for its demographics and lineup.
# An unopposed nominee changes the predictors in exactly the same way as
# in a tabulated one-nominee race, where write-ins can still receive votes.
modeled_house_shares <- function(fit, districts, seed, ndraws) {
  draws <- predict_house_dirichlet(fit, districts, seed = seed, ndraws = ndraws)$mean_share
  choices <- c("D", "R", "Other", "DidNotVote")
  stopifnot(length(dim(draws)) == 3L, dim(draws)[1L] > 0L,
            dim(draws)[2L] == nrow(districts), setequal(dimnames(draws)[[3]], choices),
            all(is.finite(draws)), all(draws >= 0), all(draws <= 1),
            all(abs(apply(draws, c(1L, 2L), sum) - 1) < 1e-8))
  means <- apply(draws[, , choices, drop = FALSE], c(2L, 3L), mean)
  colnames(means) <- c("dem", "rep", "other", "did_not_vote")
  means
}

# On each identical tabulated footprint, preserve the official candidate
# counts and use CD120 CVAP as the denominator for all four shares.
predict_or_carry_house <- function(fit, target, old, seed, ndraws = 800L) {
  old_row <- house_projection_matches(target, old)
  carry <- target$prediction_source == "observed_same_footprint"
  stopifnot(identical(!carry, target$needs_prediction),
            all(!is.na(old_row[carry])), all(old$status[old_row[carry]] == "observed"),
            all(is.finite(target$cvap) & target$cvap > 0))
  choices <- c("dem", "rep", "other", "did_not_vote")
  shares <- matrix(NA_real_, nrow(target), length(choices), dimnames = list(NULL, choices))
  if (any(carry)) {
    votes <- as.matrix(old[old_row[carry], c("votes_dem", "votes_rep", "votes_other"), drop = FALSE])
    population <- target$cvap[carry]
    remainder <- population - rowSums(votes)
    if (any(!is.finite(votes)) || any(votes < 0) || any(remainder < 0)) {
      stop("Observed candidate counts are missing or exceed the target CVAP on an identical footprint.")
    }
    shares[carry, ] <- cbind(votes, remainder) / population
  }
  if (any(!carry)) {
    shares[!carry, ] <- modeled_house_shares(fit, target[!carry, ], seed, ndraws)
  }
  stopifnot(all(is.finite(shares)), all(shares >= 0), all(shares <= 1),
            all(abs(rowSums(shares) - 1) < 1e-8))
  cbind(target[c("STATEFP", "CDFP")], as.data.frame(shares))
}
