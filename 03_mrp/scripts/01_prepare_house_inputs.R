# Run from the repository root: Rscript 03_mrp/scripts/01_prepare_house_inputs.R
# Input sources and the result denominator: 03_mrp/docs/01_prepare_house_inputs.md
source("01_frame/scripts/helpers/09_ballot_groups.R")

prepare_house_inputs <- function() {
  baseline <- read.csv("01_frame/data/intermediate/10_district_election_predictors_cd120.csv",
                       colClasses = c(state_fips = "character", district_fips = "character",
                                      matching_cd119 = "character"), na.strings = "")
  roster <- read.csv("01_frame/data/intermediate/08_house_slates_2026.csv",
                     colClasses = c(STATEFP = "character", CDFP = "character"))
  counts <- c("n_dem", "n_rep", "n_other")
  incumbent <- c("incumbent_dem", "incumbent_rep", "incumbent_other")
  choices <- c("Democratic", "Republican", "Other", "No Vote")

  # Match the reviewed annual roster to each district and select its choice fields.
  roster_key <- paste0(roster$STATEFP, roster$CDFP)
  district_key <- paste0(baseline$state_fips, baseline$district_fips)
  district_row <- match(district_key, roster_key)
  choice <- match(baseline$vote_choice, choices)
  stopifnot(nrow(roster) == 436L, !anyDuplicated(roster_key),
            setequal(district_key, roster_key), !anyNA(choice),
            !anyDuplicated(baseline[c("state_fips", "district_fips", "vote_choice")]),
            all(table(district_key) == length(choices)), all(baseline$congress == 120L),
            all(is.finite(baseline$cvap) & baseline$cvap > 0))

  lookup <- cbind(district_row, choice)
  predictors <- baseline
  predictors$lineup <- roster$slate[district_row]
  predictors$lineup_year <- 2026L
  predictors$nominee_count <- cbind(as.matrix(roster[counts]), NA_integer_)[lookup]
  predictors$on_ballot <- as.integer(predictors$nominee_count > 0L)
  predictors$incumbent <- cbind(as.matrix(roster[incumbent]), NA_integer_)[lookup]
  predictors$same_party_multiple <- roster$same_party_multiple[district_row]
  groups <- house_ballot_groups(roster[counts])
  predictors$ballot_group <- as.character(groups$ballot_group[district_row])
  predictors$major_party_direction <- groups$major_party_direction[district_row]
  predictors$unopposed_party <- ifelse(roster$unopposed[district_row] == 1L,
                                       roster$slate[district_row], NA_character_)

  # Tabulate the separate November results snapshot. Each reported candidate
  # count is used once. Keep unpolled contests missing, as in the Step 07 returns.
  source_votes <- read.csv("03_mrp/docs/01_house_2026_source_votes.csv", na.strings = "")
  race_id <- paste0(baseline$state_abbr, "-",
                    ifelse(baseline$district_fips == "00", "AL", baseline$district_fips))
  stopifnot(setequal(race_id, source_votes$race_id),
            all(source_votes$party %in% c("D", "R", "I", "L", "G", "O")))
  race_votes <- split(source_votes, source_votes$race_id)
  totals <- lapply(names(race_votes), function(id) {
    race <- race_votes[[id]]
    reported <- unique(race$total_votes)
    party <- match(race$party, c("D", "R"), nomatch = 3L)
    if (id == "FL-10") {
      stopifnot(nrow(race) == 1L, is.na(race$votes), is.na(reported) || reported == 0L)
      return(rep(NA_real_, length(choices)))
    }
    stopifnot(length(reported) == 1L, !is.na(reported), reported > 0L,
              all(is.finite(race$votes) & race$votes >= 0 & race$votes == floor(race$votes)),
              !anyDuplicated(race[c("candidate", "party")]), sum(race$votes) == reported)
    c(vapply(1:3, function(i) sum(race$votes[party == i]), numeric(1)), reported)
  })
  totals <- do.call(rbind, totals)
  race_row <- match(race_id, names(race_votes))
  total_votes <- totals[race_row, 4L]
  vote_count <- totals[cbind(race_row, choice)]
  no_vote <- choice == 4L
  vote_count[no_vote] <- baseline$cvap[no_vote] - total_votes[no_vote]
  stopifnot(all(total_votes <= baseline$cvap, na.rm = TRUE),
            all(is.na(vote_count) == (race_id == "FL-10")))

  # Publish observed results separately from the predictors used before MrP.
  results <- baseline[c("district_name", "state_name", "vote_choice",
                        "state_fips", "district_fips", "state_abbr", "congress", "cvap")]
  results$vote_house_2026 <- vote_count / results$cvap
  results$vote_count <- vote_count
  results$total_votes <- total_votes
  results$source_race_id <- race_id
  results$result_status <- vapply(race_votes, function(race) {
    paste(sort(unique(race$status)), collapse = " / ")
  }, character(1))[race_id]
  results$result_status[race_id == "FL-10"] <- "unopposed_no_tabulation"

  input <- "03_mrp/data/input"
  dir.create(input, recursive = TRUE, showWarnings = FALSE)
  paths <- file.path(input, c("district_election_inputs_cd120_2026.csv",
                              "house_election_results_cd120_2026.csv"))
  staged <- tempfile(".01-house-", tmpdir = input)
  dir.create(staged)
  on.exit(unlink(staged, recursive = TRUE), add = TRUE)
  write.csv(predictors, file.path(staged, basename(paths[1L])), row.names = FALSE, na = "")
  write.csv(results, file.path(staged, basename(paths[2L])), row.names = FALSE, na = "")
  for (path in paths) {
    if (!file.rename(file.path(staged, basename(path)), path)) stop("Could not save ", path)
    message("Saved ", nrow(baseline), " rows to ", path)
  }
  invisible(paths)
}

if (sys.nframe() == 0L) prepare_house_inputs()
