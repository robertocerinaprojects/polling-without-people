# Optional national and state checks. Run from the repository root after Step 05.
# See 01_frame/docs/05_vote_rules.md for the three benchmark commands.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) > 4L) {
  stop("Expected optional paths: detailed CES RDS, source CSV, result directory, reference directory.")
}
settings <- c("01_frame/data/intermediate/ces_demographics_harmonized.rds",
              "01_frame/data/input/CCES24_Common_OUTPUT_vv_topost_final.csv",
              "01_frame/data/output/05_vote_benchmark")
n <- min(length(args), 3L)
settings[seq_len(n)] <- args[seq_len(n)]
reference_dir <- if (length(args) == 4L) args[4] else file.path(settings[3], "reference")
clean <- readRDS(settings[[1]])
# Reviewed file MD5 from the CES V9 Dataverse record (see Step 05).
stopifnot(identical(unname(tools::md5sum(settings[[2]])), "b740b9305fee50e1a34656b513f55c57"))
source("01_frame/scripts/helpers/05_derive_votes.R", local = TRUE)
col_types <- c(
  list(caseid = readr::col_character(), cit1 = readr::col_integer(), gender4 = readr::col_integer(),
       inputstate = readr::col_integer(), cdid119 = readr::col_integer(), TS_g2024 = readr::col_integer(),
       TS_state = readr::col_character(), commonweight = readr::col_double(),
       commonpostweight = readr::col_double(), vvweight_post = readr::col_double()),
  vote_input_types()
)
fields <- names(col_types)
stopifnot(!anyDuplicated(fields))
raw <- readr::read_csv(settings[[2]], col_types = do.call(readr::cols_only, col_types),
                      lazy = FALSE, progress = FALSE)
readr::stop_for_problems(raw)
stopifnot(setequal(names(raw), fields), nrow(raw) == 60000L, !anyNA(raw$caseid),
          !anyDuplicated(raw$caseid), !anyDuplicated(clean$caseid),
          setequal(raw$caseid[raw$cit1 %in% 1 & raw$gender4 %in% 1:2], clean$caseid))
index <- match(raw$caseid, clean$caseid)
eligible <- !is.na(index)
clean <- clean[index, , drop = FALSE]
stopifnot(identical(raw$commonweight[eligible], clean$commonweight[eligible]),
          identical(raw$inputstate[eligible], clean$inputstate[eligible]),
          identical(raw$inputstate_post[eligible], clean$inputstate_post[eligible]))
# Recompute both complete vote hierarchies from pinned raw answers, then compare
# by case ID. This also checks pre-wave fallbacks and the original House ballot geography.
recomputed <- derive_ces_votes(raw[eligible, , drop = FALSE])
vote_fields <- c("house_vote_2024", "pres_vote_2024", "house_vote_2024_source",
                 "pres_vote_2024_source", "house_vote_state_2024", "house_vote_cd119_2024",
                 "house_contest_2024")
stopifnot(all(vote_fields %in% names(clean)),
          all(vapply(vote_fields, function(name) {
            identical(recomputed[[name]], clean[[name]][eligible])
          }, logical(1))))
parties <- c("Democratic", "Republican", "Other")
clean_vote <- list(President = as.character(clean$pres_vote_2024),
                   House = as.character(clean$house_vote_2024))
# Count checks also identify an earlier or incompatible preparation version.
expected_counts <- list(
  President = c(Democratic = 28846L, Republican = 22062L, Other = 1860L,
                "No Vote" = 4836L, Missing = 1023L),
  House = c(Democratic = 26906L, Republican = 20551L, Other = 1079L,
            "No Vote" = 7286L, Missing = 2805L)
)
for (office in names(clean_vote)) {
  actual <- table(factor(clean_vote[[office]][eligible], levels = c(parties, "No Vote")),
                  useNA = "always")
  stopifnot(identical(as.integer(actual), unname(expected_counts[[office]])))
}
# Direct post-election observations, without substitution from another item or wave.
post_pres <- unname(c(`1`="Democratic", `2`="Republican", `3`="Other",
                       `4`="Other", `5`="Other", `6`="Other", `8`="Other", `9`="No Vote"
                      )[as.character(raw$CC24_410)])
post_house <- rep(NA_character_, nrow(raw))
choose_slot <- which(raw$CC24_412 %in% 1:5)
roster <- as.matrix(raw[paste0("HouseCand", 1:5, "Party_post")])
selected_party <- trimws(roster[cbind(choose_slot, raw$CC24_412[choose_slot])])
selected_party[selected_party %in% c("", "-1", "__NA__", "NA")] <- NA_character_
post_house[choose_slot] <- ifelse(
  is.na(selected_party) | selected_party %in% parties[1:2], selected_party, "Other"
)
post_house[raw$CC24_412 %in% 10] <- "Other"
post_house[raw$CC24_412 %in% c(11,12)] <- "No Vote"
post_vote <- list(President = post_pres, House = post_house)
for (office in names(clean_vote)) {
  source_col <- if (office == "President") "pres_vote_2024_source" else "house_vote_2024_source"
  direct <- eligible & !is.na(post_vote[[office]])
  stopifnot(identical(post_vote[[office]][direct], clean_vote[[office]][direct]),
            all(clean[[source_col]][direct] == "post_choice"))
}
# Codebook pp. 20–21: 1–6 = matched to a record showing voted, 7/missing do not qualify.
validated <- raw$TS_g2024 %in% 1:6
stopifnot(all(is.na(raw$TS_g2024) | raw$TS_g2024 %in% 1:7))
post_wave <- raw$inputstate_post
clean_states <- list(
  President = ifelse(clean$pres_vote_2024_source %in% c("post_choice","post_nonvoter"),
                     raw$inputstate_post, raw$inputstate),
  House = as.integer(clean$house_vote_state_2024)
)
fips_by_abbr <- setNames(c(1,2,4,5,6,8,9,10,12,13,15:42,44:51,53:56,11),
                         c(state.abb, "DC"))
stopifnot(length(fips_by_abbr) == 51L)

# All-party percentages use candidate choices as the denominator. The two-party
# percentage and its approximate standard error use only Democratic and Republican choices.
shares <- function(votes, weights, indices) {
  votes <- votes[indices]
  weights <- weights[indices]
  party_weight <- vapply(parties, function(k) sum(weights[votes == k]), numeric(1))
  two <- votes %in% parties[1:2]
  democratic_share <- party_weight[["Democratic"]] / sum(party_weight[c("Democratic", "Republican")])
  effective_n <- sum(weights[two])^2 / sum(weights[two]^2)
  pct <- 100 * party_weight / sum(party_weight)
  c(ballots = length(votes), n_dem = sum(votes == parties[1]), n_rep = sum(votes == parties[2]),
    n_other = sum(votes == parties[3]), n_two = sum(two), sum_wt = sum(party_weight),
    pct_dem = pct[[1]], pct_rep = pct[[2]], pct_other = pct[[3]], pct_dem_two = 100 * democratic_share,
    n_eff_two = effective_n, se_two_pp = 100 * sqrt(democratic_share * (1 - democratic_share) / effective_n))
}
summarize_method <- function(office, method, votes, weight_name, keep, place, alt_state = FALSE) {
  w <- raw[[weight_name]]
  stopifnot(all(is.na(w) | (is.finite(w) & w >= 0)))
  included <- keep & votes %in% parties & is.finite(w) & w > 0
  # For House the contest follows the wave used for that person's candidate choice.
  if (office == "House") included <- included & place != 11L
  stopifnot(!anyNA(included))
  # Optional sensitivity uses voter-file state, which may be absent even among validated voters.
  # National shares retain those people. State-only sensitivity groups omit missing locations.
  if (!alt_state && anyNA(place[included])) stop("Missing state for an included ballot.")
  states <- sort(unique(place[included & !is.na(place)]))
  national <- shares(votes, w, which(included))
  by_state <- t(vapply(states, function(st) shares(votes, w, which(included & place == st)), national))
  data.frame(method = method, office = office, weight = weight_name,
             STATEFP = c("US", sprintf("%02d",states)), rbind(unname(national),by_state),
             row.names = NULL, check.names = FALSE)
}
tables <- list()
for (office in names(clean_vote)) {
  estimates <- list(
    summarize_method(office, "clean_commonweight", clean_vote[[office]], "commonweight", eligible, clean_states[[office]]),
    summarize_method(office, "clean_commonpostweight", clean_vote[[office]], "commonpostweight", eligible, clean_states[[office]]),
    summarize_method(office, "direct_post_commonpostweight_clean", post_vote[[office]], "commonpostweight", eligible, post_wave),
    summarize_method(office, "direct_validated_vvweight_post_clean", post_vote[[office]], "vvweight_post", eligible & validated, post_wave),
    summarize_method(office, "direct_validated_vvweight_post_full", post_vote[[office]], "vvweight_post", validated, post_wave)
  )
  # The guide gives a presidential state RMSE without specifying which state field it used.
  # Repeat that comparison using pre-election residence and voter-file state.
  if (office == "President"){
    estimates <- c(estimates,list(
      summarize_method(office,"direct_validated_full_pre_state",post_vote[[office]],"vvweight_post",validated,raw$inputstate),
      summarize_method(office,"direct_validated_full_voter_file_state",post_vote[[office]],"vvweight_post",validated,
                       unname(fips_by_abbr[raw$TS_state]),alt_state=TRUE)))
  }
  tables[[office]] <- do.call(rbind,estimates)
}
out <- do.call(rbind,tables)
rownames(out) <- NULL
dir.create(settings[[3]], recursive=TRUE, showWarnings=FALSE)
utils::write.csv(out, file.path(settings[[3]],"ces_vote_benchmark_shares.csv"), row.names=FALSE,na="")
print(out[out$STATEFP=="US",c("method","office","ballots","n_two","pct_dem","pct_rep","pct_other","pct_dem_two")],row.names=FALSE)

# Official references are generated by 05_benchmark_official.py.
read_returns <- function(office, name) {
  r <- read.csv(file.path(reference_dir, name), stringsAsFactors = FALSE)
  r$Other <- r$total - r$Democratic - r$Republican
  stopifnot(!anyDuplicated(r$state), all(r$Other >= 0), all(r$total > 0),
            setequal(r$state, if (office == "House") state.abb else c(state.abb, "DC")))
  counts <- c("Democratic", "Republican", "Other", "total")
  national <- as.data.frame(as.list(colSums(r[counts])))
  national$state <- "US"
  r <- rbind(r, national)
  r$STATEFP <- ifelse(r$state == "US", "US", sprintf("%02d", fips_by_abbr[r$state]))
  r$office <- office
  r$actual_dem <- 100 * r$Democratic / r$total
  r$actual_rep <- 100 * r$Republican / r$total
  r$actual_other <- 100 * r$Other / r$total
  r$actual_dem_two <- 100 * r$Democratic / (r$Democratic + r$Republican)
  r
}
returns <- rbind(read_returns("President", "president_by_state.csv"),
                 read_returns("House", "house_by_state.csv"))
compare <- merge(out, returns, by = c("STATEFP", "office"), sort = FALSE)
stopifnot(nrow(compare) == nrow(out), !anyNA(compare$actual_dem_two))
compare$dem_two_error_pp <- compare$pct_dem_two - compare$actual_dem_two
for (party in c("dem", "rep", "other")) {
  compare[[paste0(party, "_all_error_pp")]] <-
    compare[[paste0("pct_", party)]] - compare[[paste0("actual_", party)]]
}
compare <- compare[order(compare$office, compare$method, compare$STATEFP), ]
out_dir <- settings[[3]]
write.csv(compare[compare$state == "US", ], file.path(out_dir, "national_comparison.csv"), row.names = FALSE)
states <- compare[compare$state != "US", ]
write.csv(states, file.path(out_dir, "state_comparison.csv"), row.names = FALSE)
state_summary <- lapply(split(states, list(states$method, states$office), drop = TRUE), function(g) {
  e <- g$dem_two_error_pp
  data.frame(office = g$office[1], method = g$method[1], states_including_dc_if_president = nrow(g),
             signed_mean_error_pp = mean(e), mean_absolute_error_pp = mean(abs(e)),
             median_absolute_error_pp = median(abs(e)), rmse_pp = sqrt(mean(e^2)),
             inside_approximate_95pct_interval = sum(abs(e) <= 1.96 * g$se_two_pp))
})
state_summary <- do.call(rbind, state_summary)
write.csv(state_summary, file.path(out_dir, "state_error_summary.csv"), row.names = FALSE)
cat("\nUnweighted averages across states. Errors refer to Democratic two-party share.\n")
print(subset(state_summary, method %in% c("clean_commonweight", "direct_validated_vvweight_post_full")),
      row.names = FALSE)
