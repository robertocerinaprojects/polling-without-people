# Fit on every tabulated 2024 contest and publish four shares per CD120 district.
# Run from the repository root after Step 09 preparation.
source("01_frame/scripts/09_validate_house_beta.R")

house_cd120_shares <- function(old, target, prediction) {
  observed <- target$prediction_source == "observed_same_footprint"
  modeled <- target$needs_prediction
  stopifnot(all(observed == !modeled), !anyDuplicated(district_id(target)))
  old_row <- house_projection_matches(target, old)[observed]
  stopifnot(!anyNA(old_row), all(old$status[old_row] == "observed"))

  # Carry observed counts to the matching geography. Both observed and
  # predicted shares use the target district's citizen-adult denominator.
  votes <- as.matrix(old[old_row, c("votes_dem", "votes_rep", "votes_other")])
  cvap <- target$cvap[observed]
  observed_shares <- cbind(votes, cvap - rowSums(votes)) / cvap
  catalog <- target[c("STATEFP", "CDFP", "cvap", "prediction_source", "matching_cd119",
                      "lineup_year", "n_dem", "n_rep", "n_other")]
  shares <- function(point) {
    values <- matrix(NA_real_, nrow(target), 4L,
                     dimnames = list(NULL, c("share_dem", "share_rep", "share_other", "share_no_vote")))
    stopifnot(identical(dim(point), c(sum(modeled), 4L)),
              identical(colnames(point), choice_names))
    values[observed, ] <- observed_shares
    values[modeled, ] <- point
    stopifnot(all(is.finite(values) & values >= 0 & values <= 1),
              all(abs(rowSums(values) - 1) < 1e-9))
    cbind(catalog, as.data.frame(values))
  }
  list(raw = shares(prediction$raw_point), final = shares(prediction$point))
}

run_house_cd120 <- function(mid = "01_frame/data/intermediate",
                            out = "01_frame/data/output") {
  training_file <- file.path(mid, "09_house_training_cd119.csv")
  target_file <- file.path(mid, "09_house_target_cd120.csv")
  old <- read_table09(training_file)
  target <- read_table09(target_file)
  beta_validate_table(old)
  training <- eligible_house_rows(old)
  stopifnot(nrow(training) == 434L, nrow(target) == 436L, all(target$congress == 120L))

  # Keep the production fit separate from the holdout. Use more retained
  # draws per chain to estimate point shares and check effective sample size.
  plan <- beta_sampler_plan()
  plan$sampling <- 500L
  plan$iter <- plan$warmup + plan$sampling
  plan$draws <- plan$chains * plan$sampling
  plan$refresh <- 100L
  # The first production no-vote fit passed on its retry at 0.995.
  # Start there on future runs and retain one higher-acceptance retry.
  plan$adapt_delta <- c(0.995, 0.999)
  key <- beta_run_key(training_file, plan)
  fit_dir <- file.path(mid, "09_house_cd120_fit", key)
  fit <- fit_beta_sequence(training, seed = 20243000L, cache_dir = fit_dir, plan = plan)
  beta_message("Predicting ", sum(target$needs_prediction), " CD120 scenarios.")
  prediction <- predict_beta_sequence(fit, target[target$needs_prediction, ],
                                      seed = 20243005L, ndraws = plan$draws)
  tables <- house_cd120_shares(old, target, prediction)
  tables$raw$fit_status <- tables$final$fit_status <- ifelse(
    target$needs_prediction, if (all(fit$diagnostics$passed)) "passed" else "provisional", "observed")
  stage_write(fit$diagnostics, file.path(out, "09_house_cd120_sampler_diagnostics.csv"))
  stage_write(tables$raw, file.path(out, "09_house_raw_shares_cd120.csv"))
  stage_write(tables$final, file.path(out, "09_house_final_shares_cd120.csv"))
  beta_message("Saved raw and final CD120 shares in ", out, ". Fit checkpoint ", key, ".")
  invisible(tables)
}

if (sys.nframe() == 0L) run_house_cd120()
