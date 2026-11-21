# Run from the repository root: Rscript 01_frame/scripts/10_prepare_handoff.R
# Inputs, outputs, and field definitions: get_us_2024_xframe_data.md
prepare_handoff <- function(frame_dir = "01_frame") {
  intermediate <- file.path(frame_dir, "data", "intermediate")
  output <- file.path(frame_dir, "data", "output")
  bundle <- file.path(output, "10_handoff")

  read_table <- function(path, text_fields = "STATEFP") {
    classes <- setNames(rep("character", length(text_fields)), text_fields)
    read.csv(path, colClasses = classes, na.strings = "", check.names = FALSE)
  }
  district_key <- c("STATEFP", "CDFP")
  district_codes <- c(district_key, "matching_cd119")
  target <- read_table(file.path(intermediate, "09_house_target_cd120.csv"), district_codes)
  house <- read_table(file.path(output, "09_house_final_shares_cd120.csv"), district_codes)
  president <- read_table(file.path(intermediate, "07_state_presidential_covariates_2024.csv"))
  states <- read_table(file.path(frame_dir, "docs", "02_pl_2020_sources.csv"))

  # Align by district first, then confirm the export matches the scenario inputs.
  district_id <- function(table) do.call(paste0, table[district_key])
  house_rows <- match(district_id(target), district_id(house))
  stopifnot(
    "Expected the same 436 unique district keys in both Step 09 inputs." =
      nrow(target) == 436L && nrow(house) == 436L &&
      !anyNA(target[district_key]) && !anyNA(house[district_key]) &&
      !anyDuplicated(district_id(target)) && !anyDuplicated(district_id(house)) &&
      !anyNA(house_rows),
    "Expected CD120 predictors." = all(target$congress == 120L)
  )
  house <- house[house_rows, , drop = FALSE]
  shared <- intersect(names(target), names(house))
  stopifnot("Step 09 export and scenario inputs disagree." =
              all(vapply(shared, function(field) {
                isTRUE(all.equal(target[[field]], house[[field]]))
              }, logical(1))))

  state_rows <- match(target$STATEFP, states$STATEFP)
  president_rows <- match(target$STATEFP, president$STATEFP)
  stopifnot(
    "Expected one name and one presidential return per state and DC." =
      length(unique(target$STATEFP)) == 51L &&
      !anyDuplicated(states$STATEFP) && !anyDuplicated(president$STATEFP) &&
      !anyNA(state_rows) && !anyNA(president_rows),
    "State abbreviations disagree." =
      identical(states$STUSAB[state_rows], president$STUSAB[president_rows])
  )
  state_returns <- president[president_rows, , drop = FALSE]
  stopifnot("Step 07 and Step 09 presidential shares disagree." =
              isTRUE(all.equal(target$pres_dem, state_returns$share_dem)) &&
              isTRUE(all.equal(target$pres_rep, state_returns$share_rep)) &&
              isTRUE(all.equal(target$pres_other, state_returns$share_other)) &&
              isTRUE(all.equal(target$pres_none, state_returns$share_did_not_vote)))

  district_names <- data.frame(
    state_abbr = states$STUSAB[state_rows],
    state_name = states$state_name[state_rows],
    district_name = ifelse(target$CDFP == "00", "At-large",
                           ifelse(target$STATEFP == "11" & target$CDFP == "98",
                                  "Delegate district", paste("District", as.integer(target$CDFP))))
  )
  house_shares <- c("share_dem", "share_rep", "share_other", "share_no_vote")
  pres_shares <- c("share_dem", "share_rep", "share_other", "share_did_not_vote")
  pres_counts <- c("votes_dem", "votes_rep", "votes_other", "did_not_vote_est")
  pres_predictors <- c("pres_dem", "pres_rep", "pres_other", "pres_none")
  incumbency <- c("incumbent_dem", "incumbent_rep", "incumbent_other")
  nominee_counts <- c("n_dem", "n_rep", "n_other")
  ballot_presence <- c("ballot_dem", "ballot_rep", "ballot_other")
  choice_covariates <- c(incumbency, nominee_counts, ballot_presence, pres_predictors)
  districts <- cbind(target[district_key], district_names,
                     target[setdiff(names(target), c(district_key, choice_covariates))],
                     house[setdiff(names(house), c(shared, house_shares))])
  names(districts)[match(district_key, names(districts))] <- c("state_fips", "district_fips")
  names(districts)[match("slate", names(districts))] <- "lineup"

  # Step 06 already produced these cells. Harmonize the geography names for export.
  mother_path <- file.path(intermediate, "pums_cd_cells.rds")
  mother <- readRDS(mother_path)
  cell_key <- setdiff(names(mother), "N")
  ces <- readRDS(file.path(intermediate, "ces_analysis.rds"))
  stopifnot(
    "Expected unique, complete mother-frame cells with positive populations." =
      "N" %in% names(mother) && !anyNA(mother[cell_key]) &&
      !anyDuplicated(mother[cell_key]) && all(is.finite(mother$N) & mother$N > 0),
    "Mother-frame geography differs from Step 09." =
      setequal(paste0(mother$STATEFP, mother$CDFP120), district_id(target)),
    "CES cell keys have different types or category levels." =
      all(cell_key %in% names(ces)) && all(vapply(cell_key, function(field) {
        identical(class(mother[[field]]), class(ces[[field]])) &&
          identical(levels(mother[[field]]), levels(ces[[field]]))
      }, logical(1)))
  )
  vote_columns <- c("house_vote_2024", "pres_vote_2024")
  ces <- ces[c(cell_key, vote_columns)]
  vote_names <- c("vote_house_2024", "vote_pres_2024")
  geo_names <- c("state_fips", "district_fips")
  names(mother)[match(c("STATEFP", "CDFP120"), names(mother))] <- geo_names
  mother$state_name <- states$state_name[match(mother$state_fips, states$STATEFP)]
  mother <- mother[c(geo_names, "state_name", setdiff(names(mother), c(geo_names, "state_name")))]
  names(ces)[match(c("STATEFP", "CDFP120", vote_columns), names(ces))] <-
    c(geo_names, vote_names)

  # Use the same outcome labels as the respondent file.
  choices <- c("Democratic", "Republican", "Other", "No Vote")
  stopifnot(all(vapply(ces[vote_names], function(vote) {
    identical(levels(vote), choices)
  }, logical(1))))
  choice_fields <- function(fields) cbind(target[fields], no_vote = NA_integer_)
  incumbent_by_choice <- choice_fields(incumbency)
  nominees_by_choice <- choice_fields(nominee_counts)
  ballot_by_choice <- choice_fields(ballot_presence)
  results <- do.call(rbind, lapply(seq_along(choices), function(i) {
    cbind(districts, data.frame(
      vote_choice = choices[i],
      vote_house_2024 = house[[house_shares[i]]],
      vote_pres_2024 = state_returns[[pres_shares[i]]],
      incumbent = incumbent_by_choice[[i]],
      nominee_count = nominees_by_choice[[i]],
      on_ballot = ballot_by_choice[[i]],
      pres_vote_count = state_returns[[pres_counts[i]]],
      pres_total_votes = state_returns$total_votes,
      pres_cvap = state_returns$cvap,
      pres_share_turnout = state_returns$share_turnout,
      pres_source_used = state_returns$source_used
    ))
  }))
  first_columns <- c("district_name", "state_name", "vote_choice", vote_names,
                     "lineup", "incumbent")
  results <- results[c(first_columns, setdiff(names(results), first_columns))]
  results <- results[order(results$state_fips, results$district_fips), ]
  stopifnot(
    "Expected four choices per district." =
      nrow(results) == 4L * nrow(target) &&
      !anyDuplicated(results[c(geo_names, "vote_choice")]),
    "Election shares must sum to one in each area." =
      all(abs(rowSums(house[house_shares]) - 1) < 1e-8) &&
      all(abs(rowSums(state_returns[pres_shares]) - 1) < 1e-8)
  )

  handoff_columns <- c(geo_names, "state_name", "vote_choice", vote_names,
                       "lineup", "incumbent", "on_ballot")

  # Stage the public handoff and the full predictor table used by MrP.
  dir.create(bundle, recursive = TRUE, showWarnings = FALSE)
  filenames <- c("district_election_inputs_cd120.csv", "pums_cd_cells.rds", "ces_2024_harmonized.rds")
  staged <- tempfile(".10-handoff-", tmpdir = bundle)
  dir.create(staged)
  on.exit(unlink(staged, recursive = TRUE), add = TRUE)
  write.csv(results[handoff_columns], file.path(staged, filenames[1]), row.names = FALSE, na = "")
  predictor_name <- "10_district_election_predictors_cd120.csv"
  write.csv(results, file.path(staged, predictor_name), row.names = FALSE, na = "")
  saveRDS(mother, file.path(staged, filenames[2]))
  saveRDS(ces, file.path(staged, filenames[3]))

  paths <- file.path(bundle, filenames)
  for (i in seq_along(paths)) {
    if (!file.rename(file.path(staged, filenames[i]), paths[i])) stop("Could not save ", paths[i])
  }
  predictor_path <- file.path(intermediate, predictor_name)
  if (!file.rename(file.path(staged, predictor_name), predictor_path)) {
    stop("Could not save ", predictor_path)
  }
  cat(paste(c(nrow(results), nrow(mother), nrow(ces)), "rows:", paths), sep = "\n")
  invisible(paths)
}

if (sys.nframe() == 0L) prepare_handoff()
