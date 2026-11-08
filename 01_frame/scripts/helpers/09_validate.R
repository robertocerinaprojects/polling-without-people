# Validate the four predicted 2024 House shares on a frozen district holdout.
# Inputs are aligned district-by-choice matrices. Predictive interval endpoints
# are marginal 5th and 95th percentiles for a new district outcome.

house_validation_plots <- function(path, predictions, scores) {
  labels <- c(dem = "Democratic", rep = "Republican", other = "Other",
              none = "Did not vote for a House candidate")
  method_names <- c(model = "District model", baseline = "State presidential baseline")
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
    graphics::title(main = labels[[choice]], line = 2, adj = 0)
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

validate_house_predictions <- function(train_observed, train_pres, test_observed, test_pres,
                                       model_point, model_lower, model_upper, district_ids,
                                       output_dir) {
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
    # Spearman is undefined for constant observed or predicted shares.
    rho <- NA_real_
    if (length(unique(group$observed)) > 1L && length(unique(group$predicted)) > 1L) {
      rho <- stats::cor(group$predicted, group$observed, method = "spearman")
    }
    data.frame(choice = group$choice[1], method = group$method[1], districts = nrow(group),
               bias_pp = mean(group$error_pp), rmse_pp = sqrt(mean(group$error_pp^2)),
               spearman = rho, covered = sum(group$covered_90),
               coverage_90 = mean(group$covered_90))
  }))
  scores$prediction_stage <- "raw"
  rownames(scores) <- NULL

  dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
  utils::write.csv(predictions, file.path(output_dir, "09_holdout_predictions.csv"), row.names = FALSE)
  utils::write.csv(scores, file.path(output_dir, "09_holdout_scores.csv"), row.names = FALSE)
  house_validation_plots(file.path(output_dir, "09_holdout_plots.pdf"), predictions, scores)
  invisible(list(scores = scores, predictions = predictions))
}
