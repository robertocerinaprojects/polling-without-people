# Publish the model inputs at district-by-party level. Each district's four
# rows describe one composition and share the same district CVAP denominator.
house_party_covariates <- function(old, new) {
  old$lineup_year <- 2024L
  old$outcome_source <- ifelse(old$status == "observed", "observed_2024", "model_unopposed_2024")
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

# Add the House share for downstream analyses only when the model outputs
# are ready. Historical observed shares keep the raw zeros from the returns.
final_house_party_covariates <- function(old, new, historical, point) {
  result <- house_party_covariates(old, new)
  result$house_share <- result$observed_share_2024
  needs_share <- is.na(result$house_share)

  # The two simulated CD119 contests and all CD120 districts supply the
  # remaining compositions. The same district label can occur on both maps.
  share_column <- c(D = "dem", R = "rep", Other = "other", DidNotVote = "did_not_vote")
  fields <- c("STATEFP", "CDFP", unname(share_column))
  stopifnot(all(historical$congress == 119L))
  sources <- rbind(data.frame(congress = 119L, historical[fields]),
                   data.frame(congress = 120L, point[fields]))
  district_key <- function(d) paste(d$congress, d$STATEFP, d$CDFP, sep = "/")
  target_key <- district_key(result)
  source_key <- district_key(sources)
  if (anyDuplicated(source_key) || !setequal(source_key, target_key[needs_share])) {
    stop("Districts in the simulated or projected shares do not match the party covariates.")
  }
  source_row <- match(target_key, source_key)
  for (party in names(share_column)) {
    fill <- needs_share & result$party == party
    result$house_share[fill] <- sources[[share_column[[party]]]][source_row[fill]]
  }
  district_sum <- rowsum(result$house_share, target_key, reorder = FALSE)
  stopifnot(all(is.finite(result$house_share) & result$house_share >= 0 & result$house_share <= 1),
            all(abs(district_sum - 1) <= 1e-8))
  result
}
