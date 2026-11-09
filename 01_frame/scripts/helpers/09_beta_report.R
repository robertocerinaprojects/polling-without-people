# Compare the three sequential beta models on the same reserved districts.
# All scores and plots use the four unconditional shares of district CVAP.
write_beta_comparison <- function(training, test, predictions, cv_winners, output_dir) {
  labels <- c(vanilla = "Vanilla beta", ridge = "Ridge beta",
              horseshoe = "Regularized horseshoe beta")
  methods <- names(labels)
  stopifnot(setequal(names(predictions), methods), !anyDuplicated(names(predictions)),
            setequal(cv_winners$method, methods), !anyDuplicated(cv_winners$method),
            all(is.finite(cv_winners$cv_rmse_pp)), all(cv_winners$cv_rmse_pp >= 0))

  choices <- c("dem", "rep", "other", "none")
  share_matrix <- function(districts, prefix) {
    shares <- as.matrix(districts[paste0(prefix, choices)])
    colnames(shares) <- choices
    shares
  }
  train_actual <- share_matrix(training, "observed_")
  train_pres <- share_matrix(training, "pres_")
  test_actual <- share_matrix(test, "observed_")
  test_pres <- share_matrix(test, "pres_")
  test_ids <- paste(test$STATEFP, test$CDFP, sep = "-")

  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  scores <- list()
  details <- list()
  for (method in methods) {
    fit <- predictions[[method]]
    holdout <- score_house_holdout(train_actual, train_pres, test_actual, test_pres,
                                   fit$point, fit$lower, fit$upper, test_ids)
    plot_file <- file.path(output_dir, paste0("09_beta_holdout_", method, ".pdf"))
    house_validation_plots(plot_file, holdout$predictions, holdout$scores,
                           model_label = unname(labels[method]))

    # Each plot has its own presidential comparison. The underlying benchmark
    # is identical across fits, so the combined CSVs need only one copy.
    holdout$scores$method[holdout$scores$method == "model"] <- method
    holdout$predictions$method[holdout$predictions$method == "model"] <- method
    if (method == methods[1L]) {
      scores[["baseline"]] <- subset(holdout$scores, method == "baseline")
      details[["baseline"]] <- subset(holdout$predictions, method == "baseline")
    }
    scores[[method]] <- holdout$scores[holdout$scores$method == method, ]
    details[[method]] <- holdout$predictions[holdout$predictions$method == method, ]
  }
  scores <- do.call(rbind, scores)
  details <- do.call(rbind, details)
  row.names(scores) <- NULL
  row.names(details) <- NULL
  utils::write.csv(scores, file.path(output_dir, "09_beta_holdout_scores.csv"), row.names = FALSE)
  utils::write.csv(details, file.path(output_dir, "09_beta_holdout_predictions.csv"), row.names = FALSE)

  # Pool squared percentage-point errors over districts and outcomes. Choose
  # the family by its out-of-fold score before consulting the 30-district test.
  # In an exact tie, prefer vanilla, then ridge, then horseshoe.
  test_rmse <- tapply(details$error_pp, details$method, function(e) sqrt(mean(e^2)))
  ranking <- cv_winners[match(methods, cv_winners$method), , drop = FALSE]
  ranking$holdout_rmse_pp <- unname(test_rmse[as.character(ranking$method)])
  ranking$selected_cv <- seq_len(nrow(ranking)) == which.min(ranking$cv_rmse_pp)
  ranking <- ranking[order(ranking$cv_rmse_pp, match(ranking$method, methods)), , drop = FALSE]
  utils::write.csv(ranking, file.path(output_dir, "09_beta_recommendation.csv"), row.names = FALSE)

  selected <- as.character(ranking$method[1L])
  best_test <- methods[which.min(test_rmse[methods])]
  recommendation <- c(
    sprintf("Recommended beta model from five-fold cross-validation: %s (%.3f pp pooled RMSE).",
            labels[[selected]], ranking$cv_rmse_pp[1L]),
    sprintf("On the 30 held-out districts its RMSE was %.3f pp. The presidential baseline scored %.3f pp.",
            test_rmse[[selected]], test_rmse[["baseline"]]),
    if (selected != best_test) {
      sprintf("%s scored lowest among the fitted models on the holdout (%.3f pp). Family selection used the separate CV score.",
              labels[[best_test]], test_rmse[[best_test]])
    } else {
      "The selected family also had the lowest holdout RMSE among the fitted models."
    }
  )
  if (test_rmse[["baseline"]] < min(test_rmse[methods])) {
    recommendation <- c(recommendation,
                        "The state presidential baseline had lower holdout RMSE than all three beta models.")
  }
  writeLines(recommendation, file.path(output_dir, "09_beta_recommendation.txt"))
  cat(paste(recommendation, collapse = "\n"), "\n")
  invisible(list(scores = scores, predictions = details, ranking = ranking))
}
