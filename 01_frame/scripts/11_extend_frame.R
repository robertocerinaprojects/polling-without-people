# Step 11 estimates the distribution of individual 2024 House vote choices
# within each Step 10 population cell. It then calibrates the resulting counts
# to district House returns and the original population-cell counts.
# Run from the repository root. See 01_frame/docs/11_extend_frame.md for inputs,
# command-line arguments, output paths, and the verified national run.

score_house_choices <- function(probabilities, actual) {
  # Each row is one held-out respondent and each column is an outcome in the
  # scoring set. Accuracy uses the highest-probability choice. Log loss uses
  # the probability assigned to the observed choice, with a floor for log(0).
  # Multiclass Brier score sums squared errors over choices before averaging
  # over respondents. The observed choice has target 1 and all others have 0.
  observed <- match(actual, colnames(probabilities))
  predicted <- max.col(probabilities, ties.method = "first")
  data.frame(
    n = length(observed),
    accuracy = mean(predicted == observed),
    log_loss = -mean(log(pmax(probabilities[cbind(seq_along(observed), observed)], 1e-15))),
    brier = mean(rowSums((probabilities - outer(observed, seq_len(ncol(probabilities)), "=="))^2))
  )
}

score_house_choices_by_outcome <- function(probabilities, actual) {
  choices <- colnames(probabilities)
  predicted <- choices[max.col(probabilities, ties.method = "first")]
  # Restrict recall and log loss to respondents with this observed choice.
  # Brier error uses the whole scoring set to capture false positives as well.
  do.call(rbind, lapply(choices, function(choice) {
    selected <- actual == choice
    p <- probabilities[, choice]
    data.frame(
      choice = choice, n = sum(selected),
      recall = mean(predicted[selected] == choice),
      log_loss = -mean(log(pmax(p[selected], 1e-15))),
      brier = mean((p - selected)^2)
    )
  }))
}

write_house_raking_change_plot <- function(extended, frame, partition_dir, outcome, plot_file) {
  # Use the same partitioned summary and selected margins as the SynthFrame
  # US House vignette. This helper is internal to the pinned SynthFrame 0.1.0.
  demographics <- c("age_cat", "gender_cat", "race_cat", "hispanic_cat", "educ_cat")
  groupings <- c(as.list(demographics), list(c("age_cat", "educ_cat"),
                                           c("district_id", "age_cat"),
                                           c("district_id", "educ_cat")))
  summarize <- getFromNamespace("partitioned_raking_change_summary", "synthframe")
  summary <- summarize(frame, "district_id", outcome, "No Vote", groupings)

  # Only one state's calibrated counts and paired differences are loaded at
  # a time. Verify alignment through SynthFrame's key check before each add.
  for (state in sort(unique(frame$state_fips))) {
    before <- extended[extended$state_fips == state, ]
    after <- readRDS(file.path(partition_dir, paste0(state, ".rds")))
    rownames(before) <- rownames(after) <- NULL
    summary$add(before, after, frame[frame$state_fips == state, ])
  }
  summary$plot(plot_file)
}

extend_house_frame <- function(handoff, output, n_draws = 125L, run_validation = TRUE) {
  if (!requireNamespace("synthframe", quietly = TRUE)) {
    stop("Install SynthFrame as described in 01_frame/docs/11_extend_frame.md.")
  }
  if (dir.exists(output)) stop("Choose a new output directory: ", output)
  if (length(n_draws) != 1L || !is.finite(n_draws) || n_draws < 1L ||
      n_draws != floor(n_draws) || n_draws >= .Machine$integer.max) {
    stop("Supply a positive integer draw count.")
  }
  diagnostics <- file.path(output, "diagnostics")
  dir.create(diagnostics, recursive = TRUE)
  csv <- function(x, name) {
    write.csv(x, file.path(diagnostics, paste0(name, ".csv")), row.names = FALSE)
  }

  # Step 10 supplies population cells (N is the estimated citizen-adult count),
  # harmonized individual CES responses, and a district-by-choice election table
  # aligned to the 120th Congress map. Keep FIPS codes as text for leading zeros.
  # The combined state-district ID identifies the same area in all three inputs.
  frame <- readRDS(file.path(handoff, "pums_cd_cells.rds"))
  survey <- readRDS(file.path(handoff, "ces_2024_harmonized.rds"))
  fips <- c("state_fips", "district_fips")
  election <- read.csv(file.path(handoff, "district_election_inputs_cd120.csv"),
                       colClasses = setNames(rep("character", 2L), fips))
  district_id <- function(x) paste(x$state_fips, x$district_fips, sep = "-")
  frame$district_id <- district_id(frame)
  survey$district_id <- district_id(survey)
  election$district_id <- district_id(election)
  outcome <- "vote_house_2024"
  order <- c("No Vote", "Democratic", "Republican", "Other")
  # CES supplies the dependent variable. The election table's column with the
  # same name is an aggregate share. This explicit predictor list excludes
  # respondent-level vote history. Race and Hispanic ethnicity are separate
  # predictors and both remain in the original joint calibration constraint.
  # Keep the original CES row indices so the validation split can be audited.
  predictors <- c("state_fips", "district_id", "race_cat", "gender_cat", "age_cat", "educ_cat",
                  "hispanic_cat")
  observed <- which(complete.cases(survey[c(fips, predictors, outcome)]))
  eligible <- survey[observed, c(predictors, outcome)]
  stopifnot(
    setequal(unique(election$district_id), unique(frame$district_id)),
    all(eligible$district_id %in% frame$district_id),
    setequal(unique(eligible[[outcome]]), order),
    !anyDuplicated(election[c("district_id", "vote_choice")])
  )
  # These are unconditional district shares of citizen adults, including
  # No Vote (no counted House candidate vote). Preserve Step 09's provenance
  # so users can distinguish tabulated returns from modeled district scenarios.
  targets <- data.frame(district_id = election$district_id, target = election[[outcome]])
  targets[[outcome]] <- election$vote_choice
  stopifnot(all(abs(tapply(targets$target, targets$district_id, sum) - 1) < 1e-10))
  provenance <- read.csv(file.path(dirname(handoff), "09_house_final_shares_cd120.csv"),
                         colClasses = c(STATEFP = "character", CDFP = "character"))
  sources <- match(targets$district_id, paste(provenance$STATEFP, provenance$CDFP, sep = "-"))
  stopifnot(!anyNA(sources))
  csv(cbind(targets, provenance[sources, c("prediction_source", "fit_status")]),
      "district_targets")

  # The sequential logits model No Vote versus the remaining choices, then
  # Democratic versus Republican or Other, then Republican versus Other.
  # Other receives the residual probability and has no separate regression.
  stages <- head(order, -1L)
  # Encode lineup as numeric treatment indicators so SynthFrame treats them
  # as fixed effects. The first factor level is the reference (D in Step 10).
  lineup <- factor(election$lineup)
  lineup_columns <- model.matrix(~ lineup)[, -1L, drop = FALSE]
  colnames(lineup_columns) <- make.names(colnames(lineup_columns), unique = TRUE)
  stopifnot(nrow(lineup_columns) == nrow(election))
  csv(data.frame(lineup = levels(lineup), reference = levels(lineup) == levels(lineup)[1L]),
      "lineup_levels")
  # Each stage gets one row per district, keyed by the district ID in row.names.
  # Use the House district share and the presidential state share for that
  # stage's choice, both on the citizen-adult scale. Use party-specific binary
  # incumbency in the Democratic and Republican stages. No Vote has no incumbent.
  area_covariates <- setNames(lapply(stages, function(stage) {
    rows <- which(election$vote_choice == stage)
    covariates <- data.frame(house_share = election[[outcome]][rows],
                             pres_share = election$vote_pres_2024[rows],
                             lineup_columns[rows, , drop = FALSE],
                             row.names = election$district_id[rows])
    if (stage != "No Vote") {
      covariates$incumbent <- election$incumbent[rows]
      stopifnot(all(covariates$incumbent %in% 0:1))
    }
    covariates
  }), stages)
  # Appendix B.2 adapted for frame extension. Each stage requests varying
  # intercepts for state, district, race, gender, age, education and Hispanic
  # ethnicity. Depth two allows ten crosses among the five demographic factors.
  # Limiting geography and all area covariates to main effects keeps the two
  # share smooths additive and lineup and incumbency as fixed main effects.
  fit_options <- list(
    area_variable = "district_id", predictors = predictors, area_covariates = area_covariates,
    no_vote = order[1L], outcome_order = order, splines = TRUE, depth = 2L,
    no_interactions = c("state_fips", "district_id", "house_share", "pres_share",
                        colnames(lineup_columns), "incumbent")
  )
  logged_fit <- function(label) c(fit_options, list(
    log_file = file.path(diagnostics, paste0(label, "_fit.csv")),
    interaction_support_log = file.path(diagnostics, paste0(label, "_interaction_support.csv")),
    depth_support_dir = file.path(diagnostics, paste0(label, "_depth_support"))
  ))
  # Save both formulas because SynthFrame can screen terms for support or
  # collinearity. The fitted stage's grouping_columns maps generated cross
  # labels such as .group_3_4 to their component predictors.
  save_formulas <- function(fit, label) {
    formulas <- lapply(names(fit$stages), function(stage) {
      model <- fit$stages[[stage]]
      data.frame(stage = stage, candidate = deparse1(model$candidate_formula),
                 fitted = deparse1(model$formula))
    })
    csv(do.call(rbind, formulas), paste0(label, "_formulas"))
  }

  if (run_validation) {
    # Hold out 20% within each recorded House choice using a fixed seed. Fit
    # only on the remaining CES respondents. Both sets have access to the same
    # area covariates. This measures prediction for new respondents, before
    # raking, in the same geographic setting as production.
    set.seed(20241111)
    held_out <- sort(unlist(lapply(split(seq_len(nrow(eligible)), eligible[[outcome]]),
                                 function(rows) sample(rows, floor(0.2 * length(rows))))))
    split_table <- data.frame(handoff_row = observed, choice = eligible[[outcome]],
                              held_out = seq_len(nrow(eligible)) %in% held_out)
    csv(split_table, "respondent_split")
    csv(data.frame(
      handoff_rows = nrow(survey), missing_model_data = nrow(survey) - nrow(eligible),
      training = nrow(eligible) - length(held_out), validation = length(held_out)
    ), "respondent_counts")
    training <- eligible[-held_out, , drop = FALSE]
    validation <- eligible[held_out, , drop = FALSE]
    # Predict once per distinct holdout profile. Setting N to one makes the
    # collapsed posterior mean count for each choice its probability. Join
    # those probabilities back to every respondent so repeated profiles each
    # contribute their actual number of respondents to the scores.
    validation_frame <- unique(validation[predictors])
    validation_frame$N <- 1
    validation_fit <- do.call(synthframe::fit_sequential_logit, c(
      list(auxiliary_survey = training, extension_variable = outcome, frame = validation_frame,
           solver_trace = TRUE),
      logged_fit("validation")
    ))
    save_formulas(validation_fit, "validation")
    posterior <- synthframe::predict_sequential_logit(validation_fit, validation_frame,
                                                     write_files = FALSE)
    probabilities <- synthframe::collapse_extended_frame(validation_frame, posterior)
    keys <- function(x) do.call(paste, c(x[predictors], sep = "\r"))
    matched <- match(keys(validation), keys(validation_frame))
    by_choice <- vapply(order, function(choice) {
      rows <- probabilities[probabilities[[outcome]] == choice, ]
      rows$N[match(keys(validation_frame), keys(rows))][matched]
    }, numeric(nrow(validation)))
    colnames(by_choice) <- order
    stopifnot(all(is.finite(by_choice)), all(abs(rowSums(by_choice) - 1) < 1e-8))
    actual <- match(validation[[outcome]], order)
    predicted <- max.col(by_choice, ties.method = "first")
    csv(score_house_choices(by_choice, order[actual]), "respondent_holdout_scores")
    csv(score_house_choices_by_outcome(by_choice, order[actual]),
        "respondent_holdout_scores_by_choice")
    # Turnout-conditional scoring uses only respondents with a reported House
    # vote and divides each predicted party probability by their predicted
    # probability of casting a House vote.
    voters <- actual != 1L
    party_probabilities <- by_choice[voters, -1L, drop = FALSE]
    party_probabilities <- party_probabilities / rowSums(party_probabilities)
    csv(score_house_choices(party_probabilities, order[actual[voters]]),
        "respondent_holdout_conditional_scores")
    csv(score_house_choices_by_outcome(party_probabilities, order[actual[voters]]),
        "respondent_holdout_conditional_scores_by_choice")
    csv(data.frame(handoff_row = observed[held_out], actual = order[actual],
                   predicted = order[predicted], by_choice, check.names = FALSE),
        "respondent_holdout_predictions")
    # A calibration row compares mean predicted probability with observed
    # frequency for one outcome within one nonempty probability bin.
    calibration <- lapply(seq_along(order), function(j) {
      p <- by_choice[, j]
      bins <- cut(p, seq(0, 1, by = 0.1), include.lowest = TRUE)
      groups <- split(seq_along(p), bins, drop = TRUE)
      do.call(rbind, lapply(names(groups), function(bin) {
        rows <- groups[[bin]]
        data.frame(choice = order[j], bin = bin, n = length(rows),
                   predicted = mean(p[rows]), observed = mean(actual[rows] == j))
      }))
    })
    csv(do.call(rbind, calibration), "respondent_holdout_calibration")
    saveRDS(validation_fit, file.path(output, "validation_fit.rds"))
    rm(validation_fit, posterior, probabilities)
    gc()
  }

  # Production starts with a separate seed and all eligible CES responses.
  # One MasterP call fits the extension, splits every original cell into four
  # House-choice counts, and rakes the mean and every draw. For each original
  # cell, the four counts must sum to its original N. Across cells in a district,
  # the four shares must match its House targets.
  #
  # Register population levels for prediction. Prediction batches limit the
  # number of input cells processed at once. Raking batches hold whole districts
  # together because every election constraint is district-specific. Retain
  # the national pre-rake frame and fitted objects for diagnostics and inspection.
  pre_rake_dir <- file.path(output, "pre_rake")
  set.seed(20241112)
  result <- synthframe::MasterP(
    frame,
    extensions = setNames(list(list(
      survey = eligible, fit = logged_fit("production"), register_frame = TRUE,
      predict = list(batch_size = 4000L),
      rake = list(district = list(targets = targets, by = "district_id"))
    )), outcome),
    n_draws = n_draws, keep_fits = TRUE, pre_rake_mode = "keep", pre_rake_dir = pre_rake_dir,
    area_variable = "district_id", areas_per_batch = 4L,
    log_file = file.path(diagnostics, "masterp.log")
  )
  fit <- result$fits[[outcome]]
  save_formulas(fit, "production")
  saveRDS(fit, file.path(output, "production_fit.rds"))
  # Export the full calibrated rows, including original keys and all count
  # columns. State partitions organize the output files for downstream reads.
  raked <- result$frame
  rm(result, fit)
  partition_dir <- file.path(output, "raked_frame")
  dir.create(partition_dir)
  # Sum over House choices one state at a time to verify the original joint.
  # This bounds the memory for the cell-by-draw audit to a single partition.
  # The largest absolute error includes the mean and every draw, in people.
  cells <- do.call(rbind, lapply(sort(unique(raked$state_fips)), function(state) {
    block <- raked[raked$state_fips == state, ]
    saveRDS(block, file.path(partition_dir, paste0(state, ".rds")))
    synthframe::post_rake_cell_comparison(
      block, frame[frame$state_fips == state, ], outcome, include_max_error = TRUE
    )
  }))
  csv(cells, "original_joint")
  csv(data.frame(cells = nrow(cells), max_count_error = max(cells$max_abs_error)),
      "original_joint_metrics")
  stopifnot(max(cells$max_abs_error) <= 1e-8)

  # Independently reconstruct each district's unconditional outcome shares
  # from the calibrated counts in memory. Missing district-choice rows have
  # zero mass. Check fractional share errors in the mean and every draw.
  count_columns <- c("N", grep("^N_draw_[0-9]+$", names(raked), value = TRUE))
  district_choice <- function(x) paste(x$district_id, x[[outcome]], sep = "/")
  district_counts <- function(x) {
    keys <- district_choice(x)
    counts <- rowsum(x[count_columns], keys, reorder = FALSE)
    cbind(x[!duplicated(keys), c("district_id", outcome)], counts)
  }
  after_counts <- district_counts(raked)
  counts <- after_counts[count_columns]
  totals <- rowsum(counts, after_counts$district_id)
  rows <- match(district_choice(targets), district_choice(after_counts))
  matched_counts <- counts[rows, , drop = FALSE]
  matched_counts[is.na(rows), ] <- 0
  shares <- matched_counts / totals[targets$district_id, , drop = FALSE]
  errors <- abs(shares - targets$target)
  csv(cbind(targets, mean_error = errors[, "N"],
            max_draw_error = apply(errors[, -1L, drop = FALSE], 1L, max)),
      "target_residuals")
  stopifnot(max(errors) <= 2e-12)

  groups <- c("district_id", "race_cat", "gender_cat", "age_cat", "educ_cat", "hispanic_cat")
  group_shares <- function(x) {
    setNames(lapply(groups, function(group) {
      joint <- xtabs(reformulate(c(group, outcome), response = "N"), data = x)
      as.data.frame(prop.table(joint, 1L), responseName = "share")
    }), groups)
  }
  after_shares <- group_shares(raked)
  rm(raked, cells)
  gc()

  # Load the national pre-rake frame after releasing the calibrated frame.
  # Both district benchmarks need only district-by-choice totals, with one
  # count column for the mean and each draw. Summing first retains the inputs
  # SynthFrame uses to calculate shares, intervals and errors.
  before <- readRDS(file.path(pre_rake_dir, "extended_frame.rds"))
  before_counts <- district_counts(before)
  before_shares <- group_shares(before)
  write_house_raking_change_plot(before, frame, partition_dir, outcome,
                                 file.path(diagnostics, "raking_changes.png"))
  rm(before)
  gc()
  district_frames <- list(before = before_counts, after = after_counts)
  for (scale in c("unconditional", "conditional")) {
    # The conditional view divides each party count by counted House votes
    # within each draw. The unconditional view uses all citizen adults.
    no_vote <- if (scale == "conditional") "No Vote" else NULL
    for (phase in names(district_frames)) {
      label <- paste("district", scale, phase, sep = "_")
      check <- synthframe::check_extended_frame(
        district_frames[[phase]], targets, by = "district_id", extension_variable = outcome,
        outcome_order = order, no_vote = no_vote, coverage_tolerance = 2e-12,
        plot_file = file.path(diagnostics, paste0(label, ".png"))
      )
      comparison <- check$comparison
      metrics <- data.frame(outcome = rownames(check$metrics), check$metrics)
      if (scale == "conditional") {
        # SynthFrame includes a No Vote comparison on the population scale.
        # The turnout-conditional CSVs describe the three party choices.
        comparison <- comparison[comparison[[outcome]] != "No Vote", ]
        metrics <- metrics[metrics$outcome != "No Vote", ]
      }
      csv(comparison, label)
      csv(metrics, paste0(label, "_metrics"))
    }
  }

  # Save signed changes in mean outcome shares using citizen adults as the
  # denominator. The SynthFrame plot above adds paired-draw total variation.
  for (group in groups) {
    keys <- c(group, outcome)
    changes <- merge(before_shares[[group]], after_shares[[group]], by = keys,
                     suffixes = c("_before", "_after"))
    changes$change <- changes$share_after - changes$share_before
    csv(changes, paste0("raking_changes_", group))
  }
  # Presence of the output directory alone does not indicate success. Write
  # the completion marker only after both checks and all exports have finished.
  writeLines(capture.output(sessionInfo()), file.path(output, "session_info.txt"))
  writeLines("complete", file.path(output, "status.txt"))
}

# Execute the pipeline from the command line. Sourcing the file makes its
# functions available for inspection or a production-only retry.
if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) > 2L) {
    stop("Usage: Rscript 01_frame/scripts/11_extend_frame.R [output_directory] [n_draws]")
  }
  root <- file.path("01_frame", "data", "output")
  output <- if (length(args)) args[[1L]] else file.path(root, "11_frame_extension")
  n_draws <- if (length(args) == 2L) suppressWarnings(as.numeric(args[[2L]])) else 125L
  extend_house_frame(file.path(root, "10_handoff"), output, n_draws)
}
