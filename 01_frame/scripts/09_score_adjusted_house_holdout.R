# Rescore the published CD119 holdout under the CD120 ballot adjustment.
source("01_frame/scripts/09_validate_house_beta.R")

score_adjusted_house_holdout <- function(
    input_file = "01_frame/data/intermediate/09_house_training_cd119.csv",
    output_root = "01_frame/data/output/09_beta_holdout",
    cache_root = "01_frame/data/intermediate/09_beta_holdout_cache") {
  key <- readLines(file.path(output_root, "latest_complete.txt"), n = 1L)
  published <- file.path(output_root, key)
  cache <- file.path(cache_root, key)
  districts <- read_table09(input_file)
  beta_validate_table(districts)
  split <- beta_district_split(districts)
  membership <- read_table09(file.path(published, "09_beta_district_split.csv"))
  stopifnot(identical(district_id(split$membership), district_id(membership)),
            identical(split$membership$sample, membership$sample))

  # Reuse the exact fitted stages. Rebuild their scaling from the frozen
  # training rows, including each stage's exclusions for undefined outcomes.
  responses <- beta_stage_targets(split$train)
  paths <- file.path(cache, sprintf("stage_%d.rds", seq_len(ncol(responses))))
  if (any(!file.exists(paths))) {
    stop("The published holdout fit draws are missing. Run the holdout validation to save fit checkpoints.")
  }
  checkpoints <- lapply(paths, readRDS)
  stages <- lapply(seq_along(checkpoints), function(j) {
    checkpoint <- checkpoints[[j]]
    choice <- colnames(responses)[j]
    stopifnot(identical(checkpoint$choice, choice))
    design <- beta_stage_design(split$train[!is.na(responses[, j]), ], choice)
    list(choice = choice, scaling = design$scaling, model = checkpoint$model)
  })

  # Treat each held-out slate as if it were a redrawn prediction. Observed
  # outcomes stay as counted, including any write-ins for absent groups.
  test <- split$test
  absent <- house_matrix(test, c("n_dem", "n_rep", "n_other"), 3L, "holdout nominees") == 0
  colnames(absent) <- c("dem", "rep", "other")
  prediction <- predict_beta_sequence(list(stages = stages), test, seed = 20243005L,
                                      ndraws = checkpoints[[1L]]$plan$draws, absent = absent)
  raw <- read_table09(file.path(published, "09_beta_holdout_predictions.csv"))
  raw <- raw[raw$method == "model", ]
  expected_order <- paste(rep(district_id(test), times = 4L), rep(choice_names, each = nrow(test)))
  raw_order <- match(expected_order, paste(raw$district_id, raw$choice))
  # Check that the reused fit and prediction seed reproduce the published means
  # before attributing any change in scores to the ballot adjustment.
  stopifnot(!anyNA(raw_order),
            all(abs(raw$predicted[raw_order] - as.vector(prediction$raw_point)) < 1e-8))

  report <- score_house_holdout(score_matrix(test, house_columns$shares),
    score_matrix(test, house_columns$president), prediction$point,
    prediction$lower, prediction$upper, district_id(test))
  report$predictions$prediction_stage[report$predictions$method == "model"] <- "ballot_adjusted"
  report$scores$prediction_stage[report$scores$method == "model"] <- "ballot_adjusted"
  audit <- read_table09(file.path(published, "09_beta_sampler_diagnostics.csv"))
  destination <- file.path(published, "ballot_adjusted")
  dir.create(destination, showWarnings = FALSE)
  write_beta_holdout_report(destination, report, audit)
  invisible(report)
}

if (sys.nframe() == 0L) score_adjusted_house_holdout()
