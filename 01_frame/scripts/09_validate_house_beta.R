# Validate the sequential beta regressions on 2024 House districts (CD119).
# Use 'plan' to inspect the split, 'validate' to fit, or 'report' to redraw a completed run.
source("01_frame/scripts/09_model_house_votes.R")
source("01_frame/scripts/helpers/09_validate.R")
source("01_frame/scripts/helpers/09_beta_model.R")

# Check the contract with Step 09 preparation. In particular, two districts
# have no House return: neither supplies a zero-turnout training observation.
beta_validate_table <- function(districts) {
  id <- district_id(districts)
  missing <- districts$status == "unopposed_not_on_ballot"
  votes <- c("votes_dem", "votes_rep", "votes_other")
  outcomes <- c(votes, "total_votes", house_columns$shares)
  stopifnot(nrow(districts) == 436L, all(districts$congress == 119L),
            !anyDuplicated(id), all(grepl("^[0-9]{2}-[0-9]{2}$", id)),
            all(is.finite(districts$cvap) & districts$cvap > 0),
            !anyNA(missing), setequal(id[missing], c("12-20", "40-03")),
            all(is.na(districts[missing, outcomes])))

  observed <- districts[!missing, , drop = FALSE]
  counts <- as.matrix(observed[votes])
  stopifnot(all(observed$status == "observed"), !anyNA(observed$ballot_group),
            all(is.finite(counts) & counts >= 0 & counts == round(counts)),
            all(rowSums(counts) == observed$total_votes),
            all(observed$total_votes > 0 & observed$total_votes <= observed$cvap))
  expected_shares <- cbind(counts, observed$cvap - observed$total_votes) / observed$cvap
  stopifnot(all(abs(as.matrix(observed[house_columns$shares]) - expected_shares) < 1e-9))
}

# Record the role of every CD119 district, including the two unpolled seats.
beta_district_split <- function(districts) {
  split <- house_holdout_split(districts)
  stopifnot(nrow(split$train) == 404L, nrow(split$test) == 30L)
  membership <- districts[c("STATEFP", "CDFP")]
  id <- district_id(membership)
  membership$sample <- "training"
  membership$selection <- NA_character_
  excluded <- districts$status != "observed"
  membership$sample[excluded] <- "excluded"
  membership$selection[excluded] <- "no_house_return"
  held <- match(district_id(split$selection), id)
  membership$sample[held] <- "holdout"
  membership$selection[held] <- split$selection$holdout_selection
  list(train = split$train, test = split$test, membership = membership[order(id), ])
}

# Fits and results belong to one input file, one version of the model and
# one software environment. Changes to any of them start a new run directory.
beta_run_key <- function(input_file, plan) {
  scripts <- "01_frame/scripts"
  sources <- c(file.path(scripts, c("09_validate_house_beta.R", "09_model_house_votes.R")),
               file.path(scripts, "helpers", c("09_beta_model.R", "09_ballot_groups.R",
                                               "09_projection.R", "09_party_covariates.R",
                                               "09_validate.R")))
  packages <- c("brms", "rstan", "StanHeaders", "posterior", "mgcv", "parallelly")
  versions <- vapply(packages, function(p) as.character(utils::packageVersion(p)), character(1))
  files <- c(training_data = input_file, setNames(sources, basename(sources)))
  hashes <- vapply(files, digest::digest, character(1), algo = "sha256", file = TRUE)
  signature <- list(files = hashes, R = R.version.string, platform = R.version$platform,
                    packages = versions, sampler = plan[c("chains", "warmup", "sampling",
                                                           "workers", "threads_per_chain")])
  substr(digest::digest(signature, algo = "sha256"), 1L, 20L)
}

# Write the same figures, scores and sampler labels for a fresh fit or a saved run.
write_beta_holdout_report <- function(out, report, audit) {
  stopifnot(is.data.frame(audit), identical(as.character(audit$stage), c("none", "rep", "dem")),
            is.logical(audit$passed), !anyNA(audit$passed))
  audit_path <- file.path(out, "09_beta_sampler_diagnostics.csv")
  if (!all(audit$passed[audit$stage %in% c("none", "rep")])) {
    stop("Required sampler checks failed. Review ", audit_path)
  }
  provisional <- if (!audit$passed[audit$stage == "dem"]) c("dem", "other") else character()
  if (length(provisional)) {
    beta_message("D-versus-Other diagnostics flagged; publishing Democratic and Other results as provisional.")
  }
  # The last stage divides only the Democratic/Other remainder. The fixed
  # presidential benchmark has no sampler and therefore has no sampler status.
  status <- function(rows) {
    value <- rep(NA_character_, nrow(rows))
    model <- rows$method == "model"
    value[model] <- "passed"
    value[model & rows$choice %in% provisional] <- "provisional"
    value
  }
  report$scores$sampler_status <- status(report$scores)
  report$predictions$sampler_status <- status(report$predictions)
  beta_message("Drawing the four-panel validation figure.")
  plot_tmp <- tempfile(tmpdir = out, fileext = ".pdf")
  on.exit(unlink(plot_tmp), add = TRUE)
  house_validation_plots(plot_tmp, report$predictions, report$scores,
                         model_label = "Sequential beta", provisional_choices = provisional)
  if (!file.rename(plot_tmp, file.path(out, "09_beta_holdout_plots.pdf"))) {
    stop("Could not publish the holdout figure in ", out)
  }

  stage_write(report$scores, file.path(out, "09_beta_holdout_scores.csv"))
  stage_write(report$predictions, file.path(out, "09_beta_holdout_predictions.csv"))
  print(report$scores, row.names = FALSE)
  beta_message("Plots: ", file.path(out, "09_beta_holdout_plots.pdf"))
  invisible(out)
}

# Read the completed run's published district predictions. Its key still
# identifies the fits that made those predictions after reporting code changes.
refresh_beta_holdout_report <- function(output_root) {
  pointer <- file.path(output_root, "latest_complete.txt")
  if (!file.exists(pointer)) stop("No completed holdout recorded in ", output_root)
  key <- readLines(pointer, warn = FALSE)
  if (length(key) != 1L || !grepl("^[0-9a-f]{20}$", key)) {
    stop("Invalid completed run identifier in ", pointer)
  }
  out <- file.path(output_root, key)
  beta_message("Refreshing reports from saved predictions in ", out)
  predictions <- read_table09(file.path(out, "09_beta_holdout_predictions.csv"))
  audit <- read_table09(file.path(out, "09_beta_sampler_diagnostics.csv"))
  write_beta_holdout_report(out, summarise_house_holdout(predictions), audit)
}

run_beta_holdout <- function(mode = "validate",
    input_file = "01_frame/data/intermediate/09_house_training_cd119.csv",
    output_root = "01_frame/data/output/09_beta_holdout",
    cache_root = "01_frame/data/intermediate/09_beta_holdout_cache") {
  mode <- match.arg(mode, c("plan", "validate", "report"))
  if (mode == "report") return(refresh_beta_holdout_report(output_root))
  started <- Sys.time()
  plan <- beta_sampler_plan()
  beta_message("CPU budget on this machine: ", plan$available, " available; ",
               plan$workers, " concurrent chain(s), ", plan$threads_per_chain, " thread(s) per chain.")
  beta_message("Per stage: ", plan$chains, " chains, each with ", plan$warmup,
               " warmup + ", plan$sampling, " sampling iterations = ", plan$draws,
               " retained draws across chains. Stan reports every ", plan$refresh, " iterations.")
  beta_message("Reading the prepared district table: ", input_file)
  if (!file.exists(input_file)) {
    stop("Missing ", input_file, ". Run Rscript 01_frame/scripts/09_model_house_votes.R prepare first.")
  }
  districts <- read_table09(input_file)
  beta_validate_table(districts)
  split <- beta_district_split(districts)
  key <- beta_run_key(input_file, plan)
  out <- file.path(output_root, key)
  fit_dir <- file.path(cache_root, key)
  dir.create(out, showWarnings = FALSE, recursive = TRUE)
  stage_write(split$membership, file.path(out, "09_beta_district_split.csv"))
  beta_message("District audit passed: 404 training, 30 held out, 2 without a return.")
  beta_message("Results: ", out, " | Checkpoints: ", fit_dir)
  if (mode == "plan") {
    beta_message("Plan complete. Run 'validate' to start sampling or resume these checkpoints.")
    return(invisible(out))
  }

  # Supply only predictors until all held-out predictions are available.
  train <- split$train
  test <- split$test
  demographics <- grep("^(age_|sex_|educ_|race_|eth_)", names(test), value = TRUE)
  predictors <- c("STATEFP", "CDFP", demographics, house_columns$president,
                  "n_dem", "n_rep", "n_other", house_columns$incumbent)
  beta_message("Starting three stages: no House vote, Republican among voters, Democratic among D + Other.")
  prediction <- beta_fit_predict(train, test[predictors], seed = 20243000L,
                                 fit_dir = fit_dir, plan = plan)
  audit <- prediction$diagnostics
  stage_write(audit, file.path(out, "09_beta_sampler_diagnostics.csv"))
  beta_message("Scoring four House choices against the state presidential baseline on 30 districts.")
  report <- score_house_holdout(
    test_observed = score_matrix(test, house_columns$shares),
    test_pres = score_matrix(test, house_columns$president),
    model_point = prediction$point, model_lower = prediction$lower,
    model_upper = prediction$upper, district_ids = district_id(test)
  )
  write_beta_holdout_report(out, report, audit)

  # "Complete" means every report was written. Its per-choice status is in both CSVs.
  pointer_tmp <- tempfile(tmpdir = output_root)
  on.exit(unlink(pointer_tmp), add = TRUE)
  writeLines(key, pointer_tmp)
  if (!file.rename(pointer_tmp, file.path(output_root, "latest_complete.txt"))) {
    stop("Could not publish the completed run identifier in ", output_root)
  }
  elapsed_minutes <- as.numeric(difftime(Sys.time(), started, units = "mins"))
  beta_message("Completed in ", round(elapsed_minutes, 1), " min. Reports: ", out)
  invisible(out)
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) > 1L || (length(args) && !args %in% c("plan", "validate", "report"))) {
    stop("Usage: Rscript 01_frame/scripts/09_validate_house_beta.R [plan|validate|report]")
  }
  run_beta_holdout(if (length(args)) args[[1L]] else "validate")
}
