# Compare three sequences of conditional beta regressions on the 2024 House map.
# From the repository root: Rscript 01_frame/scripts/09_compare_house_beta.R compare
# The optional 'plan' mode prepares the folds and prints the fit schedule.
source("01_frame/scripts/09_model_house_votes.R")
source("01_frame/scripts/helpers/09_beta_model.R")
source("01_frame/scripts/helpers/09_beta_report.R")

beta_settings <- function() {
  # Ridge values are prior standard deviations. Horseshoe values are prior
  # ratios of relevant to irrelevant coefficients. Each value applies to all
  # three stages. Grid order also settles an exact tie within a family.
  data.frame(
    method = c("vanilla", "ridge", "ridge", "horseshoe", "horseshoe"),
    hyper = c(NA_real_, 0.35, 1, 0.25, 1),
    setting = c("vanilla", "ridge_035", "ridge_100", "horseshoe_025", "horseshoe_100")
  )
}

beta_district_split <- function(districts) {
  # Reproduce the district IDs from the original Step 09 validation. The six
  # at-large states and DC are always held out. The other 23 are sampled.
  eligible <- eligible_house_rows(districts)
  single_states <- names(which(table(districts$STATEFP) == 1L))
  forced <- which(eligible$STATEFP %in% single_states)
  stopifnot(setequal(district_id(eligible[forced, ]),
                     c("02-00", "10-00", "11-98", "38-00", "46-00", "50-00", "56-00")))
  set.seed(20241105L, kind = "Mersenne-Twister", normal.kind = "Inversion", sample.kind = "Rejection")
  pool <- setdiff(seq_len(nrow(eligible)), forced)
  test_rows <- sort(c(forced, sample(pool, 30L - length(forced))))
  development <- eligible[-test_rows, , drop = FALSE]
  test <- eligible[test_rows, , drop = FALSE]

  # Spread each ballot lineup across all five folds. Continue the cycle where
  # the preceding lineup left off so total fold sizes also differ by at most one.
  set.seed(20241106L)
  fold <- integer(nrow(development))
  offset <- 0L
  for (seats in split(seq_len(nrow(development)), development$slate)) {
    seats <- seats[sample.int(length(seats))]
    fold[seats] <- 1L + (offset + seq_along(seats) - 1L) %% 5L
    offset <- offset + length(seats)
  }
  stopifnot(nrow(development) == 404L, nrow(test) == 30L,
            diff(range(table(fold))) <= 1L, setequal(fold, 1:5))
  reason <- ifelse(test_rows %in% forced, "at_large_state", "sampled")
  reason[test$STATEFP == "11"] <- "dc_delegate"
  list(development = development, test = test, fold = fold, reason = reason)
}

beta_validate_table <- function(d) {
  stopifnot(nrow(d) == 436L, all(d$congress == 119L), !anyDuplicated(district_id(d)),
            all(grepl("^[0-9]{2}$", d$STATEFP)), all(grepl("^[0-9]{2}$", d$CDFP)),
            all(is.finite(d$cvap) & d$cvap > 0))
  missing <- d$status == "unopposed_not_on_ballot"
  votes <- c("votes_dem", "votes_rep", "votes_other")
  stopifnot(setequal(district_id(d)[missing], c("12-20", "40-03")),
            all(d$status[!missing] == "observed"), !anyNA(d$ballot_group[!missing]),
            all(is.na(d[missing, c(votes, "total_votes", house_columns$shares)])))
  tabulated <- d[!missing, , drop = FALSE]
  counts <- as.matrix(tabulated[votes])
  stopifnot(all(is.finite(counts) & counts >= 0 & counts == round(counts)),
            all(rowSums(counts) == tabulated$total_votes),
            all(tabulated$total_votes > 0 & tabulated$total_votes <= tabulated$cvap))
  observed <- as.matrix(tabulated[house_columns$shares])
  expected <- cbind(counts, tabulated$cvap - tabulated$total_votes) / tabulated$cvap
  stopifnot(all(is.finite(observed)), max(abs(observed - expected)) < 1e-9)
}

# Keep all original shares together for scoring. The assessment rows given
# to brms have no vote counts, turnout, conditional outcomes, or raw shares.
beta_assess <- function(tr, va, order, setting, seed, fit_dir) {
  outcomes <- c("total_votes", "without_house_vote", house_columns$shares,
                "votes_dem", "votes_rep", "votes_other")
  predictors <- va[setdiff(names(va), outcomes)]
  prediction <- beta_fit_predict(tr, predictors, order, setting$method, setting$hyper, seed, fit_dir)
  for (component in c("point", "lower", "upper")) {
    x <- prediction[[component]]
    stopifnot(is.matrix(x), identical(dim(x), c(nrow(va), 4L)),
              identical(colnames(x), choice_names), all(is.finite(x) & x >= 0 & x <= 1))
  }
  stopifnot(all(abs(rowSums(prediction$point) - 1) < 1e-9),
            all(prediction$lower <= prediction$upper))
  prediction
}

beta_run_key <- function(input_file, settings) {
  # A new input, fitting rule, sampler version or grid starts a fresh cache.
  paths <- c("01_frame/scripts/09_compare_house_beta.R", "01_frame/scripts/09_model_house_votes.R",
             file.path("01_frame/scripts/helpers",
                       c("09_ballot_groups.R", "09_model.R", "09_validate.R", "09_beta_model.R",
                         "09_beta_report.R")))
  packages <- c("brms", "rstan", "StanHeaders", "posterior")
  versions <- vapply(packages, function(p) as.character(utils::packageVersion(p)), character(1L))
  signature <- list(inputs = unname(tools::md5sum(input_file)), code = tools::md5sum(paths),
                    r = R.version.string, packages = versions, settings = settings)
  if (anyNA(c(signature$inputs, signature$code))) stop("Could not fingerprint the comparison inputs.")
  substr(digest::digest(signature, algo = "sha256"), 1L, 16L)
}

run_beta_comparison <- function(mode = "compare",
    input_file = "01_frame/data/intermediate/09_house_training_cd119.csv",
    output_root = "01_frame/data/output/09_beta_comparison",
    cache_root = "01_frame/data/intermediate/09_beta_cache") {
  mode <- match.arg(mode, c("plan", "compare"))
  districts <- read_table09(input_file)
  beta_validate_table(districts)
  split <- beta_district_split(districts)
  train <- split$development
  test <- split$test
  settings <- beta_settings()
  key <- beta_run_key(input_file, settings)
  out <- file.path(output_root, key)
  cache <- file.path(cache_root, key)
  dir.create(out, showWarnings = FALSE, recursive = TRUE)

  # Fix the response order for every fold from the published 2024 national
  # counts. This ordering is part of the model specification. No fold or
  # penalty is selected by inspecting held-out district errors.
  party_order <- c("rep", "dem", "other")
  votes <- colSums(districts[paste0("votes_", party_order)], na.rm = TRUE)
  if (any(diff(votes) >= 0)) stop("The 2024 party ranking has changed. Review the specified stage order.")
  stage_write(data.frame(party = party_order, national_candidate_votes = unname(votes)),
              file.path(out, "09_beta_party_order.csv"))
  manifest <- rbind(
    data.frame(train[c("STATEFP", "CDFP")], sample = "development", fold = split$fold, selection = NA_character_),
    data.frame(test[c("STATEFP", "CDFP")], sample = "holdout", fold = NA_integer_, selection = split$reason)
  )
  stage_write(manifest, file.path(out, "09_beta_district_splits.csv"))
  stage_write(settings, file.path(out, "09_beta_prior_grid.csv"))
  message("Development: 404 districts in five folds. External holdout: 30 districts.",
          "\n25 cross-validation sequences and 3 holdout sequences; three beta fits per sequence.",
          "\nComparison directory: ", out)
  if (mode == "plan") {
    return(invisible(c(split, list(party_order = party_order, settings = settings, run_dir = out))))
  }

  # Tune on only the 404 development districts. Each district supplies one
  # raw, out-of-fold prediction for each of the four reconstructed shares.
  observed <- score_matrix(train, house_columns$shares)
  oof <- vector("list", nrow(settings))
  cv <- settings
  cv$cv_rmse_pp <- NA_real_
  for (i in seq_len(nrow(settings))) {
    setting <- settings[i, , drop = FALSE]
    estimates <- matrix(NA_real_, nrow(train), 4L, dimnames = list(NULL, choice_names))
    lower <- upper <- estimates
    for (fold in 1:5) {
      held <- split$fold == fold
      message("Cross-validation: ", setting$setting, ", fold ", fold, "/5")
      prediction <- beta_assess(train[!held, ], train[held, ], party_order, setting,
                                20242000L + fold,
                                file.path(cache, setting$setting, paste0("fold_", fold)))
      estimates[held, ] <- prediction$point
      lower[held, ] <- prediction$lower
      upper[held, ] <- prediction$upper
    }
    cv$cv_rmse_pp[i] <- 100 * sqrt(mean((estimates - observed)^2))
    oof[[i]] <- data.frame(district_id = rep(district_id(train), 4L),
                           choice = rep(choice_names, each = nrow(train)), setting = setting$setting,
                           fold = rep(split$fold, 4L), observed = as.vector(observed),
                           predicted = as.vector(estimates), lower_90 = as.vector(lower),
                           upper_90 = as.vector(upper))
  }
  stopifnot(all(is.finite(cv$cv_rmse_pp)))
  oof <- do.call(rbind, oof)
  stage_write(oof, file.path(out, "09_beta_out_of_fold_predictions.csv"))
  # Report patterns that a single pooled RMSE can hide: bias for one choice
  # and variation across the five assessment folds. Every district counts once.
  choices <- split(oof, list(oof$setting, oof$choice), drop = TRUE)
  by_choice <- do.call(rbind, lapply(choices, function(rows) {
    data.frame(setting = rows$setting[1L], choice = rows$choice[1L], house_prediction_metrics(rows))
  }))
  folds <- split(oof, list(oof$setting, oof$fold), drop = TRUE)
  by_fold <- do.call(rbind, lapply(folds, function(rows) {
    error <- 100 * (rows$predicted - rows$observed)
    data.frame(setting = rows$setting[1L], fold = rows$fold[1L],
               districts = length(unique(rows$district_id)), rmse_pp = sqrt(mean(error^2)))
  }))
  stage_write(by_choice, file.path(out, "09_beta_cv_scores_by_choice.csv"))
  stage_write(by_fold, file.path(out, "09_beta_cv_scores_by_fold.csv"))
  stage_write(cv, file.path(out, "09_beta_cv_scores.csv"))

  # Lock a tuning value for each family and the preferred family BEFORE
  # examining the outer holdout. Exact family ties follow the grid order.
  best <- vapply(unique(cv$method), function(method) {
    rows <- which(cv$method == method)
    rows[which.min(cv$cv_rmse_pp[rows])]
  }, integer(1L))
  finalists <- cv[unname(best), , drop = FALSE]
  finalists$selected_cv <- seq_len(nrow(finalists)) == which.min(finalists$cv_rmse_pp)
  stage_write(finalists, file.path(out, "09_beta_cv_finalists.csv"))

  predictions <- list()
  for (i in seq_len(nrow(finalists))) {
    setting <- finalists[i, , drop = FALSE]
    message("Holdout comparison: ", setting$setting, ", fit on 404 districts")
    predictions[[setting$method]] <- beta_assess(train, test, party_order, setting, 20243000L,
                                                 file.path(cache, setting$setting, "external"))
  }
  report <- write_beta_comparison(train, test, predictions, finalists, out)
  # Advance the pointer only after all three methods have successful reports.
  pointer <- tempfile(tmpdir = output_root)
  on.exit(unlink(pointer), add = TRUE)
  writeLines(key, pointer)
  if (!file.rename(pointer, file.path(output_root, "latest_complete.txt"))) {
    stop("Could not record the completed comparison directory: ", out)
  }
  message("Selected in cross-validation: ", finalists$method[finalists$selected_cv],
          ". Holdout plots and scores: ", out)
  report$run_dir <- out
  invisible(report)
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) > 1L) stop("Usage: Rscript 01_frame/scripts/09_compare_house_beta.R [plan|compare]")
  run_beta_comparison(if (length(args)) args[[1L]] else "compare")
}
