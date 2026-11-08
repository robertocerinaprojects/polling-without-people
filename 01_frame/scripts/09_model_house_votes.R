# Estimate 2024 House voting on the 2026 map. Run from the repository root.
# Modes: prepare, fit, predict, or all (default). See ../docs/09_model_house_votes.md.
for (helper in c("09_ballot_groups.R", "09_model.R", "09_validate.R", "09_projection.R")) {
  source(file.path("01_frame", "scripts", "helpers", helper))
}

house_columns <- list(
  age = c(paste0("age_", seq(18, 78, 5), "_", seq(22, 82, 5)), "age_83_plus"),
  demographic = c("sex_female", "educ_no_hs", "educ_some_college", "educ_two_year",
                  "educ_four_year", "educ_postgrad", "race_black", "race_native",
                  "race_asian", "race_other_multi", "eth_hispanic"),
  president = c("pres_dem", "pres_rep", "pres_other", "pres_none"),
  slate = c("ballot_dem", "ballot_rep", "ballot_other"),
  counts = c("votes_dem", "votes_rep", "votes_other"),
  state = "STATEFP", cvap = "cvap"
)
choice_names <- c("dem", "rep", "other", "none")
district_id <- function(x) paste(x$STATEFP, x$CDFP, sep = "-")
read_table09 <- function(path) {
  if (!file.exists(path)) stop("Missing ", path, call. = FALSE)
  header <- names(read.csv(path, nrows = 0, check.names = FALSE))
  types <- setNames(rep(NA_character_, length(header)), header)
  types[intersect(header, c("STATEFP", "CDFP", "CDFP119", "CDFP120", "matching_cd119", "status", "slate"))] <- "character"
  read.csv(path, colClasses = types, check.names = FALSE, stringsAsFactors = FALSE,
           na.strings = c("NA", ""))
}

# Read directly from the Step 07 office tables. Preserve its original reporting
# flag for inspection. The reviewed two omitted contests are identified by
# their FIPS keys plus their absence of candidate counts.
office_fields <- function(x, fields, path) {
  for (name in names(fields)) {
    i <- match(tolower(c(name, fields[[name]])), tolower(names(x)), nomatch = 0L)
    i <- i[i != 0L]
    if (!length(i)) stop(path, " is missing ", name, ". Columns: ", paste(names(x), collapse=", "))
    names(x)[i[1L]] <- name
  }
  x
}

office_geo <- function(x, district = FALSE) {
  # Some official exports use postal codes. Use the same 51-state source
  # manifest as the frame. Numeric conversions preserve two-character keys.
  state <- trimws(as.character(x$STATEFP))
  num <- grepl("^[0-9]{1,2}$", state)
  if (any(!num)) {
    manifest <- read_table09("01_frame/docs/02_pl_2020_sources.csv")
    map <- c(setNames(manifest$STATEFP, manifest$STUSAB),
             setNames(manifest$STATEFP, toupper(manifest$state_name)))
    state[!num] <- unname(map[toupper(state[!num])])
  }
  if (anyNA(state) || any(!grepl("^[0-9]{1,2}$", state))) stop("Unexpected Step 07 state key.")
  x$STATEFP <- sprintf("%02d", as.integer(state))
  if (district) {
    d <- trimws(as.character(x$CDFP))
    if (anyNA(d) || any(!grepl("^[0-9]{1,2}$", d))) stop("Unexpected Step 07 CD119 district key.")
    x$CDFP <- sprintf("%02d", as.integer(d))
  }
  x
}

# Each key must match exactly one row. Reject omissions rather than losing districts in a join.
attach_fields <- function(left, right, fields, keys) {
  key <- function(x) do.call(paste, c(x[keys], sep = "/"))
  stopifnot(all(keys %in% names(left)), all(c(fields, keys) %in% names(right)),
            !anyNA(left[keys]), !anyNA(right[keys]), !anyDuplicated(right[keys]))
  positions <- match(key(left), key(right))
  if (anyNA(positions)) stop("Missing geography: ", paste(head(key(left)[is.na(positions)]), collapse = ", "))
  for (field in fields) left[[field]] <- right[[field]][positions]
  left
}

stage_write <- function(object, destination, rds = FALSE) {
  temp <- tempfile(tmpdir = dirname(destination))
  on.exit(unlink(temp), add = TRUE)
  if (rds) saveRDS(object, temp) else write.csv(object, temp, na = "", row.names = FALSE)
  if (!file.rename(temp, destination)) stop("Could not publish ", destination)
}

add_slate <- function(x, path, complete = FALSE) {
  roster <- read_table09(path)
  if (complete && !setequal(district_id(x), district_id(roster))) {
    stop("The 2024 candidate roster and the CD119 frame have different district keys.")
  }
  roster <- roster[district_id(roster) %in% district_id(x), , drop = FALSE]
  x <- attach_fields(x, roster, c("n_dem", "n_rep", "n_other", "slate"), c("STATEFP", "CDFP"))
  n <- as.matrix(x[c("n_dem", "n_rep", "n_other")])
  stopifnot(all(is.finite(n) & n >= 0 & n == round(n)), all(rowSums(n) > 0))
  x[house_columns$slate] <- as.data.frame(1L * (n > 0))
  x$same_party_multiple <- as.integer(rowSums(n > 0) == 1L & rowSums(n) > 1L)
  group <- house_ballot_groups(n)
  x$ballot_group <- group$ballot_group
  x$major_party_direction <- group$major_party_direction
  x
}

prepare_house_tables <- function(mid, out, need_target = TRUE) {
  demos <- read_table09(file.path(mid, "08_district_demographics.csv"))
  state_file <- file.path(mid, "07_state_presidential_covariates_2024.csv")
  pres <- office_fields(read_table09(state_file), list(
    STATEFP=c("state_fips","STUSAB","state"), cvap=c("pums_cvap", "cvap_pums", "state_cvap"),
    share_dem=c("dem_share","share_democratic"), share_rep=c("rep_share","share_republican"),
    share_other="other_share", share_did_not_vote=c("did_not_vote_share","share_none","share_no_vote")
  ), state_file)
  pres <- office_geo(pres)
  fields <- c("share_dem", "share_rep", "share_other", "share_did_not_vote")
  stopifnot(nrow(pres) == 51L, !anyDuplicated(pres$STATEFP), all(fields %in% names(pres)),
            !anyNA(pres[fields]), all(as.matrix(pres[fields]) >= 0),
            max(abs(rowSums(pres[fields]) - 1)) < 1e-8)
  names(pres)[match(fields, names(pres))] <- house_columns$president
  demos <- attach_fields(demos, pres, house_columns$president, "STATEFP")
  stopifnot(setequal(demos$congress, c(119L,120L)),
            !anyDuplicated(demos[c("congress","STATEFP","CDFP")]), all(demos$cvap > 0),
            all(grepl("^[0-9]{2}$", demos$STATEFP)), all(grepl("^[0-9]{2}$", demos$CDFP)))
  for (prefix in c("age_", "sex_", "educ_", "race_", "eth_")) {
    group <- demos[startsWith(names(demos), prefix)]
    stopifnot(ncol(group) > 1, all(is.finite(as.matrix(group))), all(as.matrix(group) >= 0),
              max(abs(rowSums(group) - 1)) < 1e-8)
  }
  demos <- demos[order(demos$STATEFP, demos$CDFP), ]
  old <- demos[demos$congress == 119L, ]
  new <- demos[demos$congress == 120L, ]
  stopifnot(nrow(old) == 436L, nrow(new) == 436L, "11-98" %in% district_id(old),
            "11-98" %in% district_id(new))
  for (d in list(old, new)) {
    total <- tapply(d$cvap, d$STATEFP, sum)
    ref <- pres$cvap[match(names(total), pres$STATEFP)]
    stopifnot(length(total) == 51L, length(ref) == 51L, all(abs(total - ref) <= 1e-8 * ref))
  }
  house_file <- file.path(mid, "07_house_votes_cd119.csv")
  house <- office_fields(read_table09(house_file), list(
    STATEFP=c("state_fips","STUSAB","state"), CDFP=c("CDFP119","district"),
    votes_dem=c("dem_votes","votes_democratic","Democratic"),
    votes_rep=c("rep_votes","votes_republican","Republican"),
    votes_other=c("other_votes","Other")
  ), house_file)
  house <- office_geo(house, district = TRUE)
  stopifnot(nrow(house) == nrow(old))
  vote_cols <- house_columns$counts
  office_count <- as.matrix(house[vote_cols])
  unpolled <- district_id(house) %in% c("12-20", "40-03")
  missing <- rowSums(is.na(office_count))
  if (any(missing[!unpolled] != 0L) ||
      any(!(missing[unpolled] == 3L | (missing[unpolled] == 0L &
            rowSums(abs(office_count[unpolled, , drop=FALSE]), na.rm=TRUE) == 0L)))) {
    stop("Check the two unpolled contests and candidate counts for each tabulated district.")
  }
  house$source_status <- if ("status" %in% names(house)) as.character(house$status) else NA_character_
  house$status <- ifelse(unpolled, "unopposed_not_on_ballot", "observed")
  house[unpolled, vote_cols] <- NA_real_
  # Count only classified candidate votes. Ballots cast and accounting rows
  # can produce a different total in a source table.
  house$total_votes <- rowSums(house[vote_cols])
  old <- attach_fields(old, house, c(vote_cols, "source_status", "status", "total_votes"), c("STATEFP","CDFP"))
  old <- add_slate(old, file.path(mid, "08_house_slates_2024.csv"), complete = TRUE)
  ok <- old$status == "observed"
  stopifnot(!anyNA(ok), setequal(district_id(old)[!ok], c("12-20","40-03")),
            all(old$status[!ok] == "unopposed_not_on_ballot"),
            all(is.na(old[!ok, c(vote_cols,"total_votes")])))
  count <- as.matrix(old[ok, vote_cols])
  stopifnot(all(is.finite(count) & count >= 0 & count == round(count)),
            all(rowSums(count) > 0), all(rowSums(count) == old$total_votes[ok]))
  residual <- old$cvap - old$total_votes
  if (any(residual[ok] < 0)) stop("Candidate votes exceed the PUMS CVAP in ",
    paste(district_id(old)[which(ok & residual < 0)], collapse = ", "), ". Review the district inputs.")
  old$without_house_vote <- residual
  old$none_fit <- round(old$cvap) - old$total_votes
  totals <- as.matrix(old[c(vote_cols, "without_house_vote")])
  old[paste0("observed_", choice_names)] <- as.data.frame(sweep(totals, 1L, old$cvap, "/"))
  old$candidate_structure <- ifelse(rowSums(old[c("n_dem","n_rep","n_other")]) == 1L,
                                    "one_nominee", ifelse(old$same_party_multiple == 1L,
                                    "multiple_in_one_party_group", "multiple_party_groups"))
  stage_write(old, file.path(mid, "09_house_training_cd119.csv"))
  census <- old
  census$ballot_group <- ifelse(is.na(old$ballot_group), "excluded_other_only", as.character(old$ballot_group))
  freq <- as.data.frame(xtabs(~ ballot_group + slate + candidate_structure + status, data = census))
  stage_write(freq[freq$Freq > 0, ], file.path(out, "09_training_slate_counts.csv"))
  if (!need_target) return(list(old = old))
  overlay <- read_table09(file.path(out, "08_district_overlap.csv"))
  flag <- tolower(as.character(overlay$same_footprint))
  stopifnot(all(flag %in% c("true", "false")))
  overlay$same_footprint <- flag == "true"
  stopifnot(
            !anyDuplicated(overlay[c("STATEFP","CDFP119","CDFP120")]),
            setequal(paste(overlay$STATEFP, overlay$CDFP120, sep="-"), district_id(new)),
            setequal(paste(overlay$STATEFP, overlay$CDFP119, sep="-"), district_id(old)))
  eq <- overlay[overlay$same_footprint, ]
  stopifnot(!anyDuplicated(eq[c("STATEFP","CDFP119")]), !anyDuplicated(eq[c("STATEFP","CDFP120")]))
  new$matching_cd119 <- eq$CDFP119[match(district_id(new), paste(eq$STATEFP,eq$CDFP120,sep="-"))]
  new <- prepare_house_prediction_scope(new, old, file.path(mid, "08_house_slates_2026.csv"))
  stage_write(new, file.path(mid, "09_house_target_cd120.csv"))
  list(old = old, new = new)
}

score_matrix <- function(x, columns) {
  m <- as.matrix(x[columns])
  colnames(m) <- choice_names
  m
}

check_house_chains <- function(fit, label, out) {
  report <- house_sampler_diagnostics(fit)
  path <- file.path(out, paste0("09_", label, "_sampler_diagnostics.csv"))
  stage_write(report, path)
  if (!isTRUE(report$passed)) {
    stop("Sampler diagnostics require review before publishing predictions. See ", path)
  }
}

eligible_house_rows <- function(old) {
  eligible <- old[old$status == "observed" & !is.na(old$ballot_group), , drop = FALSE]
  eligible[order(district_id(eligible)), , drop = FALSE]
}

model_source_hashes <- function() {
  helpers <- c("09_ballot_groups.R", "09_model.R")
  tools::md5sum(file.path("01_frame", "scripts", "helpers", helpers))
}

fit_and_validate <- function(old, mid, out, seed) {
  eligible <- eligible_house_rows(old)
  stopifnot(nrow(eligible) > 30L)
  set.seed(seed, kind = "Mersenne-Twister", normal.kind = "Inversion", sample.kind = "Rejection")
  # Count districts on the complete CD119 map, including off-ballot seats.
  # DC has one delegate district and is evaluated alongside the at-large states.
  district_counts <- table(old$STATEFP)
  single_states <- names(district_counts)[district_counts == 1L]
  forced <- which(eligible$STATEFP %in% single_states)
  # Six 2024 at-large states and DC; see the district-code audit in Step 02.
  stopifnot(setequal(district_id(eligible[forced, ]),
                     c("02-00", "10-00", "11-98", "38-00", "46-00", "50-00", "56-00")))
  remaining <- setdiff(seq_len(nrow(eligible)), forced)
  # The other 23 come from all remaining eligible seats on the 2024 map.
  random <- sample(remaining, 30L - length(forced), replace = FALSE)
  hold <- sort(c(forced, random))
  train <- eligible[-hold, ]
  test <- eligible[hold, ]
  selection <- test[c("STATEFP","CDFP")]
  selection$holdout_selection <- ifelse(hold %in% forced, "at_large_state", "sampled")
  selection$holdout_selection[selection$STATEFP == "11"] <- "dc_delegate"
  stage_write(selection, file.path(out,"09_holdout_districts.csv"))
  audit <- fit_house_dm(train, house_columns, seed = seed)
  check_house_chains(audit, "holdout", out)
  prediction <- predict_house_dm(audit, test, seed = seed + 1L)
  get <- function(draws, stat, ...) {
    m <- apply(draws, c(2L,3L), stat, ...)
    colnames(m) <- choice_names
    m
  }
  # Score direct predictions on the held-out districts before the full refit.
  y <- paste0("observed_", choice_names)
  validate_house_predictions(score_matrix(train,y), score_matrix(train,house_columns$president),
    score_matrix(test,y), score_matrix(test,house_columns$president),
    get(prediction$mean_share, mean), get(prediction$predictive_share, quantile, probs=.05),
    get(prediction$predictive_share, quantile, probs=.95), district_id(test), out)
  rm(audit, prediction)
  gc()
  fit <- fit_house_dm(eligible, house_columns, seed = seed + 2L)
  check_house_chains(fit, "full", out)
  # A saved fit is valid only for this set of predictors, observations and IDs.
  stage_write(list(fit=fit, trained_on=eligible, schema=house_columns, seed=seed,
                   source_md5=model_source_hashes()),
              file.path(mid, "09_house_full_fit.rds"), rds=TRUE)
}

project_house <- function(tables, mid, out) {
  saved <- readRDS(file.path(mid,"09_house_full_fit.rds"))
  old <- tables$old
  eligible <- eligible_house_rows(old)
  if (!identical(saved$trained_on, eligible) || !identical(saved$schema, house_columns) ||
      !identical(saved$source_md5, model_source_hashes())) {
    stop("The saved model and training inputs differ. Run fit before predict.")
  }
  target <- tables$new
  point <- predict_or_carry_house(saved$fit, target, old, seed = saved$seed + 3L, ndraws = 800L)
  flags <- c("STATEFP", "CDFP", "matching_cd119", "needs_prediction", "prediction_source",
             "lineup_year", "slate", "ballot_group")
  status <- target[flags]

  # Publish the share matrix and the corresponding record of how each district
  # was filled together. Retain the previous pair if a file cannot be replaced.
  staging <- tempfile("09_projection_", tmpdir = dirname(mid))
  dir.create(staging)
  on.exit(unlink(staging, recursive = TRUE), add = TRUE)
  destinations <- c(file.path(mid, "09_house_final_shares_cd120.csv"),
                    file.path(out, "09_house_district_status.csv"))
  staged <- file.path(staging, basename(destinations))
  stage_write(point, staged[1])
  stage_write(status, staged[2])
  # Check keys and share precision after serialization as well as in memory.
  on_disk <- read_table09(staged[1])
  on_disk_status <- read_table09(staged[2])
  choices <- c("dem", "rep", "other", "did_not_vote")
  shares <- as.matrix(on_disk[choices])
  stopifnot(identical(names(on_disk), c("STATEFP", "CDFP", choices)),
            identical(district_id(on_disk), district_id(target)),
            identical(district_id(on_disk_status), district_id(target)),
            identical(on_disk_status$prediction_source, status$prediction_source),
            all(is.finite(shares) & shares >= 0 & shares <= 1),
            max(abs(rowSums(shares) - 1)) < 1e-8,
            max(abs(shares - as.matrix(point[choices]))) < 1e-12)
  backups <- file.path(staging, paste0("previous_", basename(destinations)))
  previous <- file.exists(destinations)
  if (any(previous) && !all(file.copy(destinations[previous], backups[previous]))) {
    stop("Could not back up existing Step 09 projections.")
  }
  for (i in seq_along(staged)) {
    if (!file.rename(staged[i], destinations[i])) {
      for (j in seq_len(i - 1L)) {
        if (previous[j]) file.rename(backups[j], destinations[j]) else unlink(destinations[j])
      }
      stop("Could not publish ", destinations[i])
    }
  }
  message("Saved four shares for ", nrow(point), " districts: ",
          sum(!target$needs_prediction), " carried from observed returns and ",
          sum(target$needs_prediction), " predicted.")
}

main_house09 <- function(args = commandArgs(trailingOnly = TRUE)) {
  mode <- if (length(args) == 0L) "all" else match.arg(args, c("prepare","fit","predict","all"))
  mid <- "01_frame/data/intermediate"
  out <- "01_frame/data/output"
  dir.create(mid, recursive=TRUE, showWarnings=FALSE)
  dir.create(out, recursive=TRUE, showWarnings=FALSE)
  tables <- prepare_house_tables(mid, out, need_target = mode != "fit")
  if (mode %in% c("fit","all")) fit_and_validate(tables$old, mid, out, seed=20241105L)
  if (mode %in% c("predict","all")) project_house(tables, mid, out)
  invisible(tables)
}
if (sys.nframe() == 0L) main_house09()
