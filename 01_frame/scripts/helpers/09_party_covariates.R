# Publish the model inputs at district-by-party level. Each district's four
# rows describe one composition and share the same district CVAP denominator.
house_party_covariates <- function(old, new) {
  old$lineup_year <- 2024L
  stopifnot(all(old$status %in% c("observed", "unopposed_not_on_ballot")))
  old$outcome_source <- ifelse(old$status == "observed", "observed_2024", "unpolled_2024")
  new$outcome_source <- new$prediction_source

  # Keep every demographic share, including the reference categories omitted
  # from the regression. Repeating a district's CVAP does not add population.
  demographics <- grep("^(age|sex|educ|race|eth)_", names(old), value = TRUE)
  stopifnot(length(demographics) == 29L, all(demographics %in% names(new)))
  district_fields <- c("congress", "STATEFP", "CDFP", "cvap", demographics,
                       "lineup_year", "slate", "ballot_group", "major_party_direction",
                       "same_party_multiple", "outcome_source", "unopposed_party")

  # The suffix identifies matching district columns, e.g. pres_rep is the
  # statewide Republican presidential share for the Republican House row.
  suffixes <- c(D = "dem", R = "rep", Other = "other", DidNotVote = "none")
  party_rows <- function(districts, party, original_map) {
    suffix <- suffixes[[party]]
    rows <- districts[district_fields]
    rows$party <- party
    rows$state_presidential_share <- districts[[paste0("pres_", suffix)]]
    rows$observed_share_2024 <- if (original_map) districts[[paste0("observed_", suffix)]] else NA_real_

    # A zero means the party fielded no eligible named candidate. No vote is
    # a response choice with no nominees, so its three candidate fields are NA.
    rows$nominee_count <- NA_integer_
    rows$has_nominee <- NA_integer_
    rows$incumbent <- NA_integer_
    if (party != "DidNotVote") {
      rows$nominee_count <- districts[[paste0("n_", suffix)]]
      rows$has_nominee <- districts[[paste0("ballot_", suffix)]]
      rows$incumbent <- districts[[paste0("incumbent_", suffix)]]
    }
    rows
  }

  by_party <- lapply(names(suffixes), function(party) {
    rbind(party_rows(old, party, TRUE), party_rows(new, party, FALSE))
  })
  result <- do.call(rbind, by_party)
  keys <- c("congress", "STATEFP", "CDFP", "party")
  result <- result[order(result$congress, result$STATEFP, result$CDFP,
                         match(result$party, names(suffixes))), ]
  result <- result[c(keys, setdiff(names(result), keys))]
  rownames(result) <- NULL

  # The source tables have one row per district. Verify that the reshape kept
  # every choice (including absent parties) and the expected definition of zero.
  candidate <- result$party != "DidNotVote"
  counts <- result$nominee_count[candidate]
  stopifnot(nrow(result) == 2L * 436L * 4L, anyDuplicated(result[keys]) == 0L,
            all(result$lineup_year %in% c(2024L, 2026L)), all(result$cvap > 0),
            all(is.finite(counts) & counts >= 0 & counts == floor(counts)),
            all(result$has_nominee[candidate] == (counts > 0)),
            all(result$incumbent[candidate] %in% 0:1),
            all(result$incumbent[candidate] <= result$has_nominee[candidate]),
            all(is.finite(result$state_presidential_share)),
            identical(!is.na(result$observed_share_2024), result$outcome_source == "observed_2024"))
  result
}
