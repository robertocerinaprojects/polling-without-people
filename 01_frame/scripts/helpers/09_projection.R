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

prepare_house_prediction_scope <- function(target, old, roster_path) {
  old_row <- house_projection_matches(target, old)
  redrawn <- is.na(old_row)
  unpolled <- !redrawn & old$status[old_row] == "unopposed_not_on_ballot"
  target$needs_prediction <- redrawn | unpolled
  target$prediction_source <- ifelse(redrawn, "model_redrawn",
                               ifelse(unpolled, "model_unpolled_2024", "observed_same_footprint"))
  target$lineup_year <- ifelse(redrawn, 2026L, ifelse(unpolled, 2024L, NA_integer_))

  # Copy only the lineup from the original contest on an identical unpolled
  # footprint. Every input describing the population belongs to the target map.
  lineup_fields <- c("slate", "n_dem", "n_rep", "n_other", "ballot_dem", "ballot_rep",
                     "ballot_other", "same_party_multiple", "ballot_group", "major_party_direction")
  lineup_row <- old_row
  lineup_row[!unpolled] <- NA_integer_
  target[lineup_fields] <- old[lineup_row, lineup_fields, drop = FALSE]
  if (any(unpolled)) {
    # The 2024 Clerk nominee roster lists a single Republican for intact OK-03.
    seat <- target[unpolled, , drop = FALSE]
    if (!isTRUE(all(district_id(old[old_row[unpolled], ]) == "40-03" &
                    seat$n_dem == 0L & seat$n_rep == 1L & seat$n_other == 0L &
                    seat$slate == "R" & seat$ballot_group == "main_party_uncontested" &
                    seat$major_party_direction == -1L))) {
      stop("Review the 2024 lineup of the unpolled contest on an identical footprint.")
    }
  }
  if (any(redrawn)) {
    lineup <- add_slate(target[redrawn, c("STATEFP", "CDFP"), drop = FALSE], roster_path)
    target[redrawn, lineup_fields] <- lineup[lineup_fields]
  }
  unsupported <- target$needs_prediction & is.na(target$ballot_group)
  if (any(unsupported)) stop("No fitted ballot group for ", paste(district_id(target)[unsupported], collapse = ", "))
  target
}

# Each modeled district receives one posterior mean per choice. For identical
# tabulated footprints, retain the official candidate counts and use CD120 CVAP
# as the denominator for all four shares.
predict_or_carry_house <- function(fit, target, old, seed, ndraws = 800L) {
  old_row <- house_projection_matches(target, old)
  carry <- !is.na(old_row) & old$status[old_row] == "observed"
  stopifnot(identical(!carry, target$needs_prediction),
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
    districts <- target[!carry, , drop = FALSE]
    p <- predict_house_dm(fit, districts, seed = seed, ndraws = ndraws)$mean_share
    labels <- c("D", "R", "Other", "DidNotVote")
    stopifnot(length(dim(p)) == 3L, dim(p)[1L] > 0L, dim(p)[2L] == nrow(districts),
              dim(p)[3L] == 4L, setequal(dimnames(p)[[3L]], labels),
              all(is.finite(p)), all(p >= 0), all(abs(apply(p, c(1L, 2L), sum) - 1) < 1e-8))
    shares[!carry, ] <- apply(p[, , labels, drop = FALSE], c(2L, 3L), mean)
  }
  stopifnot(all(is.finite(shares)), all(shares >= 0), all(abs(rowSums(shares) - 1) < 1e-8))
  cbind(target[c("STATEFP", "CDFP")], as.data.frame(shares))
}
