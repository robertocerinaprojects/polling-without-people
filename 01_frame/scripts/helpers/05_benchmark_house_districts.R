# Compare 2024 House candidate choices in their 119th Congress ballot-wave districts.
# See 01_frame/docs/05_vote_rules.md for input provenance and the benchmark commands.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) > 3L) stop("Expected optional paths: detailed CES RDS, official CSV, output directory.")
settings <- c("01_frame/data/intermediate/ces_demographics_harmonized.rds",
              "01_frame/data/output/05_vote_benchmark/reference/house_by_district.csv",
              "01_frame/data/output/05_vote_benchmark")
settings[seq_along(args)] <- args
output <- settings[3]
ces <- readRDS(settings[1])
clerk <- read.csv(settings[2], colClasses = c(state = "character", district = "character"))
parties <- c("Democratic", "Republican", "Other")
required <- c("caseid", "house_contest_2024", "house_vote_2024", "commonweight",
              "house_vote_state_2024", "house_vote_cd119_2024")
stopifnot(all(required %in% names(ces)), !anyNA(ces$caseid), !anyDuplicated(ces$caseid),
          all(ces$house_vote_2024 %in% c(parties, "No Vote", NA)),
          !anyNA(ces$commonweight), all(is.finite(ces$commonweight) & ces$commonweight >= 0),
          all(c("state", "district", parties, "total") %in% names(clerk)),
          nrow(clerk) == 435L, setequal(clerk$state, state.abb),
          all(grepl("^[0-9]{2}$", clerk$district)), !anyNA(clerk),
          all(as.matrix(clerk[parties]) >= 0), all(rowSums(clerk[parties]) == clerk$total))
# Build keys on the original 2024 ballot map. DC elected a delegate.
state_codes <- c(1, 2, 4, 5, 6, 8:10, 12:13, 15:42, 44:51, 53:56)
us_state <- setNames(state.abb, sprintf("%02d", state_codes))
keep <- ces$house_contest_2024 %in% "US House representative" &
        ces$house_vote_2024 %in% parties & ces$commonweight > 0
ballots <- ces[keep, required]
district_label <- paste(clerk$state, clerk$district, sep = "-")
stopifnot(!anyDuplicated(district_label), setequal(district_label[clerk$total == 0],
                                                    c("FL-20", "OK-03")))
ballot_keys <- paste(us_state[ballots$house_vote_state_2024],
                     ballots$house_vote_cd119_2024, sep = "-")
stopifnot(all(ballot_keys %in% district_label))
# Keep all 435 official rows, including districts with zero reported votes.
group <- factor(ballot_keys, levels = district_label)
party <- factor(ballots$house_vote_2024, levels = parties)
weighted_choices <- as.matrix(xtabs(ballots$commonweight ~ group + party))
respondents <- as.matrix(table(group, party))
stopifnot(
  sum(respondents) == nrow(ballots),
  abs(sum(weighted_choices) - sum(ballots$commonweight)) < 1e-7
)

# The error is the CES minus the Clerk Democratic share among D and R votes.
dem_two_party_pct <- function(democratic, republican) {
  major_party <- democratic + republican
  ifelse(major_party > 0, 100 * democratic / major_party, NA_real_)
}
audit <- clerk
audit$ces_valid <- rowSums(respondents)
audit$ces_two_party <- respondents[, "Democratic"] + respondents[, "Republican"]
for (party_name in parties) {
  audit[[paste0("ces_weight_", party_name)]] <- weighted_choices[, party_name]
}
audit$ces_D_two_pct <- dem_two_party_pct(weighted_choices[, "Democratic"], weighted_choices[, "Republican"])
audit$clerk_D_two_pct <- dem_two_party_pct(clerk$Democratic, clerk$Republican)
audit$error_pp <- audit$ces_D_two_pct - audit$clerk_D_two_pct
# An unavailable official result takes priority when the CES share is also missing.
audit$status <- "compared"
audit$status[is.na(audit$ces_D_two_pct)] <- "no_CES_major_party_choice"
audit$status[is.na(audit$clerk_D_two_pct)] <- "no_official_major_party_vote"
audit$status[clerk$total == 0] <- "no_official_vote_total"
compared <- audit$status == "compared"
district_metrics <- function(scope, mask) {
  error <- audit$error_pp[mask]
  data.frame(scope, districts = length(error), median_two_party_respondents = median(audit$ces_two_party[mask]),
             mean_error_pp = mean(error), rmse_pp = sqrt(mean(error^2)),
             mae_pp = mean(abs(error)), median_absolute_error_pp = median(abs(error)))
}
metrics <- rbind(district_metrics("Comparable seats", compared),
                 district_metrics("Both major parties received official votes",
                                  compared & clerk$Democratic > 0 & clerk$Republican > 0))
national <- function(scope, mask) {
  survey <- colSums(weighted_choices[mask, , drop = FALSE])
  official <- colSums(clerk[mask, parties, drop = FALSE])
  data.frame(scope, districts = sum(mask), ces_valid_choices = sum(respondents[mask, , drop = FALSE]),
             party = parties, ces_pct = as.numeric(100 * survey / sum(survey)),
             official_pct = as.numeric(100 * official / sum(official)))
}
national_results <- rbind(national("All voting seats", rep(TRUE, nrow(clerk))),
                          national("Seats with an official count", clerk$total > 0))
dir.create(output, recursive = TRUE, showWarnings = FALSE)
write.csv(audit, file.path(output, "house_district_accuracy.csv"), row.names = FALSE, na = "")
write.csv(metrics, file.path(output, "house_district_metrics.csv"), row.names = FALSE)
write.csv(national_results, file.path(output, "house_counted_seat_sensitivity.csv"), row.names = FALSE)
print(metrics, row.names = FALSE)
print(national_results, row.names = FALSE)
print(audit[!compared, c("state", "district", "total", "ces_valid", "ces_two_party", "status")], row.names = FALSE)
