# Validate the four predicted 2024 House shares on a frozen district holdout.
# Inputs are aligned district-by-choice matrices. Predictive interval endpoints
# are marginal 5th and 95th percentiles for a new district outcome.

# Reserve the six at-large states, DC and 23 other observed districts. Both
# models use these same districts, sorted by state and district before sampling.
house_holdout_split <- function(districts, seed = 20241105L) {
  eligible <- eligible_house_rows(districts)
  state_sizes <- table(districts$STATEFP)
  single_states <- names(state_sizes)[state_sizes == 1L]
  forced <- which(eligible$STATEFP %in% single_states)
  stopifnot(nrow(eligible) > 30L, setequal(district_id(eligible[forced, ]),
                     c("02-00", "10-00", "11-98", "38-00", "46-00", "50-00", "56-00")))

  set.seed(seed, kind = "Mersenne-Twister", normal.kind = "Inversion", sample.kind = "Rejection")
  pool <- setdiff(seq_len(nrow(eligible)), forced)
  held <- sort(c(forced, sample(pool, 30L - length(forced))))
  test <- eligible[held, , drop = FALSE]
  selection <- test[c("STATEFP", "CDFP")]
  selection$holdout_selection <- ifelse(held %in% forced, "at_large_state", "sampled")
  selection$holdout_selection[selection$STATEFP == "11"] <- "dc_delegate"
  list(eligible = eligible, train = eligible[-held, , drop = FALSE], test = test,
       selection = selection)
}

house_validation_plots <- function(path, predictions, scores, model_label = "District model",
                                   provisional_choices = character()) {
  labels <- c(dem = "Democratic", rep = "Republican", other = "Other",
              none = "Did not vote for a House candidate")
  method_names <- c(model = model_label, baseline = "State presidential baseline")
  colors <- c(model = "#116789", baseline = "#AE5217")
  symbols <- c(model = 16L, baseline = 2L)
  line_types <- c(model = 1L, baseline = 2L)

  grDevices::pdf(path, width = 8.3, height = 8.7, useDingbats = FALSE,
                 title = "Raw held-out 2024 House vote shares")
  on.exit(grDevices::dev.off(), add = TRUE)
  graphics::layout(matrix(c(1L, 1L, 2L, 3L), nrow = 2L, byrow = TRUE),
                   heights = c(5.4, 1.5))

  for (choice in names(labels)) {
    data <- predictions[predictions$choice == choice, ]
    graphics::par(mar = c(4.3, 4.7, 3.8, 1.0), pty = "s", las = 1)
    # The same limits on x and y preserve the 45-degree reference line.
    endpoints <- range(data$predicted, data$observed, data$lower_90, data$upper_90)
    if (diff(endpoints) < 0.01) {
      endpoints <- c(max(0, endpoints[1] - 0.005), min(1, endpoints[2] + 0.005))
    }
    ticks <- pretty(endpoints * 100, n = 5)
    ticks <- ticks[ticks >= 0 & ticks <= 100]
    limits <- range(endpoints, ticks / 100)
    # A small margin keeps points and intervals at exactly zero or one visible.
    limits <- limits + c(-1, 1) * diff(limits) * 0.02
    graphics::plot(NA_real_, NA_real_, xlim = limits, ylim = limits, axes = FALSE,
                   xaxs = "i", yaxs = "i", xlab = "", ylab = "")
    graphics::axis(1, at = ticks / 100, labels = paste0(ticks, "%"))
    graphics::axis(2, at = ticks / 100, labels = paste0(ticks, "%"))
    graphics::box(col = "grey75")
    graphics::mtext("Predicted share of district citizen adults", side = 1, line = 2.8)
    graphics::mtext("Observed share of district citizen adults", side = 2, line = 3.4, las = 0)
    title <- labels[[choice]]
    if (choice %in% provisional_choices) title <- paste0(title, " (model provisional)")
    graphics::title(main = title, line = 2, adj = 0)
    graphics::mtext("Raw predictions   /   30 held-out districts   /   Horizontal bars show 90% intervals",
                    side = 3, line = 0.5, adj = 0, cex = 0.8)
    graphics::abline(a = 0, b = 1, col = "grey48", lty = 3, lwd = 1.4)
    # Draw intervals underneath both sets of points at the actual observed y.
    for (method in c("baseline", "model")) {
      sel <- data$method == method
      graphics::segments(data$lower_90[sel], data$observed[sel], data$upper_90[sel],
                         data$observed[sel], col = grDevices::adjustcolor(colors[[method]], 0.60),
                         lty = line_types[[method]], lwd = 1.15)
    }
    for (method in c("baseline", "model")) {
      sel <- data$method == method
      graphics::points(data$predicted[sel], data$observed[sel],
                       pch = symbols[[method]], col = colors[[method]],
                       cex = if (method == "baseline") 1.13 else 0.79, lwd = 1.35)
    }

    for (method in names(method_names)) {
      score <- scores[scores$choice == choice & scores$method == method, ]
      graphics::par(mar = c(0, 0.9, 0.4, 0.7), pty = "m")
      graphics::plot.new()
      graphics::plot.window(xlim = c(0, 1), ylim = c(0, 1), xaxs = "i", yaxs = "i")
      color <- colors[[method]]
      graphics::segments(0.02, 0.88, 0.15, 0.88, col = color, lty = line_types[[method]], lwd = 1.4)
      graphics::points(0.085, 0.88, col = color, pch = symbols[[method]])
      graphics::text(0.19, 0.88, method_names[[method]], adj = 0, font = 2,
                     col = color, cex = 0.95)
      y <- c(0.65, 0.47, 0.29, 0.11)
      graphics::text(0.02, y, c("Bias (predicted - observed)", "RMSE", "Spearman correlation",
                                 "90% interval coverage"), adj = 0, cex = 0.81)
      rho <- if (is.na(score$spearman)) "undefined" else sprintf("%.3f", score$spearman)
      graphics::text(0.98, y, c(sprintf("%+.2f pp", score$bias_pp),
                                  sprintf("%.2f pp", score$rmse_pp), rho,
                                  sprintf("%d/%d (%.1f%%)", score$covered,
                                          score$districts, 100 * score$coverage_90)),
                     adj = 1, cex = 0.82)
    }
  }
}

# Score one choice across the held-out districts. A positive bias means the
# model overpredicts. An observation at either interval endpoint is covered.
house_prediction_metrics <- function(rows) {
  error <- 100 * (rows$predicted - rows$observed)
  covered <- with(rows, lower_90 <= observed & observed <= upper_90)
  rho <- NA_real_
  if (length(unique(rows$observed)) > 1L && length(unique(rows$predicted)) > 1L) {
    rho <- stats::cor(rows$predicted, rows$observed, method = "spearman")
  }
  data.frame(districts = nrow(rows), bias_pp = mean(error), rmse_pp = sqrt(mean(error^2)),
             spearman = rho, covered = sum(covered), coverage_90 = mean(covered))
}

score_house_holdout <- function(train_observed, train_pres, test_observed, test_pres,
                                model_point, model_lower, model_upper, district_ids) {
  choices <- c("dem", "rep", "other", "none")
  check_matrix <- function(x, n, composition = TRUE) {
    x <- as.matrix(x)
    if (!is.numeric(x) || !identical(colnames(x), choices) || nrow(x) != n ||
        any(!is.finite(x)) || any(x < 0 | x > 1)) {
      stop("Expected a finite district-by-choice matrix in order dem, rep, other, none.")
    }
    if (composition && any(abs(rowSums(x) - 1) > 1e-9)) {
      stop("Every district's observed and predicted point shares must sum to one.")
    }
    x
  }

  if (length(district_ids) != 30L || anyNA(district_ids) || anyDuplicated(district_ids) ||
      any(!nzchar(as.character(district_ids)))) {
    stop("Validation requires 30 unique district identifiers.")
  }
  n_train <- nrow(train_observed)
  if (is.null(n_train) || n_train < 9L) stop("Too few training districts for a 90% interval.")
  train_observed <- check_matrix(train_observed, n_train)
  train_pres <- check_matrix(train_pres, n_train)
  test_observed <- check_matrix(test_observed, 30L)
  test_pres <- check_matrix(test_pres, 30L)
  model_point <- check_matrix(model_point, 30L)
  model_lower <- check_matrix(model_lower, 30L, FALSE)
  model_upper <- check_matrix(model_upper, 30L, FALSE)
  if (any(model_lower > model_upper)) stop("A model prediction interval has reversed endpoints.")

  # This fixed benchmark has no fitted parameters: its prediction for each
  # district is the state's 2024 presidential share. Calibrate four marginal
  # intervals on training district errors alone. The finite-sample conformal
  # rank is ceil((n+1)*0.90), with inclusive endpoints. District exchangeability
  # gives marginal coverage; shared states and unusual slates can affect actual
  # coverage in a particular split, state or new electoral map.
  rank_90 <- ceiling((n_train + 1L) * 0.90)
  radius <- apply(abs(train_observed - train_pres), 2L,
                  function(error) sort(error, partial = rank_90)[rank_90])
  base_lower <- sweep(test_pres, 2L, radius, "-")
  base_upper <- sweep(test_pres, 2L, radius, "+")
  base_lower[base_lower < 0] <- 0
  base_upper[base_upper > 1] <- 1

  detail <- function(method, point, lower, upper) {
    data.frame(district_id = rep(as.character(district_ids), times = 4L),
               choice = rep(choices, each = 30L), method = method,
               observed = as.vector(test_observed), predicted = as.vector(point),
               lower_90 = as.vector(lower), upper_90 = as.vector(upper))
  }
  predictions <- rbind(detail("model", model_point, model_lower, model_upper),
                       detail("baseline", test_pres, base_lower, base_upper))
  predictions$prediction_stage <- "raw"
  predictions$error_pp <- 100 * (predictions$predicted - predictions$observed)
  predictions$covered_90 <- with(predictions, lower_90 <= observed & observed <= upper_90)
  groups <- split(predictions, list(predictions$choice, predictions$method), drop = TRUE)
  scores <- do.call(rbind, lapply(groups, function(group) {
    data.frame(choice = group$choice[1], method = group$method[1], house_prediction_metrics(group))
  }))
  scores$prediction_stage <- "raw"
  rownames(scores) <- NULL
  list(scores = scores, predictions = predictions)
}

validate_house_predictions <- function(train_observed, train_pres, test_observed, test_pres,
                                       model_point, model_lower, model_upper, district_ids,
                                       output_dir) {
  result <- score_house_holdout(train_observed, train_pres, test_observed, test_pres,
                                model_point, model_lower, model_upper, district_ids)
  dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
  utils::write.csv(result$predictions, file.path(output_dir, "09_holdout_predictions.csv"), row.names = FALSE)
  utils::write.csv(result$scores, file.path(output_dir, "09_holdout_scores.csv"), row.names = FALSE)
  house_validation_plots(file.path(output_dir, "09_holdout_plots.pdf"), result$predictions, result$scores)
  invisible(result)
}
