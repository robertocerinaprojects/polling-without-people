# Prepare the district outcomes and covariates used by the House beta regressions.
# Run from the repository root: Rscript 01_frame/scripts/09_model_house_votes.R prepare
for (helper in c("09_ballot_groups.R", "09_projection.R",
                 "09_party_covariates.R")) {
  source(file.path("01_frame", "scripts", "helpers", helper))
}

house_columns <- list(
  age = c(paste0("age_", seq(18, 78, 5), "_", seq(22, 82, 5)), "age_83_plus"),
  president = c("pres_dem", "pres_rep", "pres_other", "pres_none"),
  slate = c("ballot_dem", "ballot_rep", "ballot_other"),
  incumbent = c(D = "incumbent_dem", R = "incumbent_rep", Other = "incumbent_other"),
  shares = c("observed_dem", "observed_rep", "observed_other", "observed_none")
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

house_matrix <- function(data, columns, n, label) {
  if (length(columns) != n || anyDuplicated(columns) || !all(columns %in% names(data))) {
    stop("Invalid ", label, " columns: ", paste(columns, collapse = ", "))
  }
  selected <- data[columns]
  if (!all(vapply(selected, function(x) is.numeric(x) || is.logical(x), logical(1)))) {
    stop(label, " columns must be numeric")
  }
  values <- as.matrix(selected)
  storage.mode(values) <- "double"
  if (any(!is.finite(values))) stop("Missing or non-finite ", label)
  values
}

# Each flag describes a candidate on this particular ballot. A sitting member
# running against another nominee of the same party still counts just once.
house_incumbency_flags <- function(data, columns, nominees) {
  flags <- house_matrix(data, columns, 3L, "party incumbency")
  if (any(!flags %in% c(0, 1)) || any(flags == 1 & nominees == 0)) {
    stop("Incumbency must be 0 or 1, and a party with no nominee must have 0.")
  }
  flags
}

add_slate <- function(x, path, complete = FALSE) {
  roster <- read_table09(path)
  if (complete && !setequal(district_id(x), district_id(roster))) {
    stop("The 2024 candidate roster and the CD119 frame have different district keys.")
  }
  roster <- roster[district_id(roster) %in% district_id(x), , drop = FALSE]
  if (!all(house_columns$incumbent %in% names(roster))) {
    stop("The roster in ", path, " lacks the party incumbency flags. Rerun 08_prepare_house_slates.py.")
  }
  fields <- c("n_dem", "n_rep", "n_other", "slate", house_columns$incumbent)
  x <- attach_fields(x, roster, fields, c("STATEFP", "CDFP"))
  n <- as.matrix(x[c("n_dem", "n_rep", "n_other")])
  stopifnot(all(is.finite(n) & n >= 0 & n == round(n)), all(rowSums(n) > 0))
  house_incumbency_flags(x, house_columns$incumbent, n)
  x[house_columns$slate] <- as.data.frame(1L * (n > 0))
  x$same_party_multiple <- as.integer(rowSums(n > 0) == 1L & rowSums(n) > 1L)
  group <- house_ballot_groups(n)
  x$ballot_group <- group$ballot_group
  x$major_party_direction <- group$major_party_direction
  x
}

prepare_house_tables <- function(mid, out) {
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
  vote_cols <- c("votes_dem", "votes_rep", "votes_other")
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
  old <- mark_unpolled_house_scenarios(old, file.path(out, "08_house_slate_nominees.csv"))
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
  totals <- as.matrix(old[c(vote_cols, "without_house_vote")])
  old[house_columns$shares] <- as.data.frame(sweep(totals, 1L, old$cvap, "/"))
  old$candidate_structure <- ifelse(rowSums(old[c("n_dem","n_rep","n_other")]) == 1L,
                                    "one_nominee", ifelse(old$same_party_multiple == 1L,
                                    "multiple_in_one_party_group", "multiple_party_groups"))
  stage_write(old, file.path(mid, "09_house_training_cd119.csv"))
  census <- old
  census$ballot_group <- ifelse(is.na(old$ballot_group), "excluded_other_only", as.character(old$ballot_group))
  freq <- as.data.frame(xtabs(~ ballot_group + slate + candidate_structure + status, data = census))
  stage_write(freq[freq$Freq > 0, ], file.path(out, "09_training_slate_counts.csv"))
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
  stage_write(house_party_covariates(old, new), file.path(mid, "09_house_party_inputs.csv"))
  list(old = old, new = new)
}

score_matrix <- function(x, columns) {
  m <- as.matrix(x[columns])
  colnames(m) <- choice_names
  m
}

eligible_house_rows <- function(old) {
  eligible <- old[old$status == "observed" & !is.na(old$ballot_group), , drop = FALSE]
  eligible[order(district_id(eligible)), , drop = FALSE]
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) && !identical(args, "prepare")) {
    stop("Usage: Rscript 01_frame/scripts/09_model_house_votes.R [prepare]")
  }
  mid <- "01_frame/data/intermediate"
  out <- "01_frame/data/output"
  dir.create(mid, recursive = TRUE, showWarnings = FALSE)
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  tables <- prepare_house_tables(mid, out)
  message("Prepared ", nrow(tables$old), " CD119 districts (",
          nrow(eligible_house_rows(tables$old)), " eligible contests) and ",
          nrow(tables$new), " CD120 districts.")
}
