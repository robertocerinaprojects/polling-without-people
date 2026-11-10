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

# Position district labels in physical inches so the same padding works for
# a 2% Other share and a 60% Democratic share. A short leader connects any
# label that has to move away from a cluster of points.
house_district_labels <- function(model, baseline, labels, cex = 0.66) {
  usr <- graphics::par("usr")
  size <- graphics::par("pin")
  xscale <- diff(usr[1:2]) / size[1]
  yscale <- diff(usr[3:4]) / size[2]
  x <- (model$predicted - usr[1]) / xscale
  y <- (model$observed - usr[3]) / yscale
  h <- graphics::strheight("MA-08", units = "inches", cex = cex) / 2 + 0.012
  w <- graphics::strwidth(labels, units = "inches", cex = cex) / 2 + 0.015

  # Start with the circles and baseline markers as small occupied rectangles.
  point_x <- c(x, (baseline$predicted - usr[1]) / xscale)
  point_y <- c(y, (baseline$observed - usr[3]) / yscale)
  boxes <- data.frame(x = point_x, y = point_y, w = 0.028, h = 0.028)
  offsets <- expand.grid(dx = seq(-12, 12) * 0.08, dy = seq(-10, 10) * 0.092)
  label_x <- label_y <- numeric(length(labels))
  for (i in order(y, x, labels)) {
    cx <- pmax(w[i], pmin(size[1] - w[i], x[i] + offsets$dx))
    cy <- pmax(h, pmin(size[2] - h, y[i] + offsets$dy))
    # Prefer the closest free spot just above the model point.
    cost <- (cx - x[i])^2 + (cy - y[i] - 0.075)^2
    for (j in seq_len(nrow(boxes))) {
      collision <- abs(cx - boxes$x[j]) < w[i] + boxes$w[j] &
                   abs(cy - boxes$y[j]) < h + boxes$h[j]
      cost[collision] <- cost[collision] + 10
    }
    best <- which.min(cost)
    label_x[i] <- cx[best]
    label_y[i] <- cy[best]
    boxes[nrow(boxes) + 1L, ] <- c(label_x[i], label_y[i], w[i], h)
  }
  distant <- sqrt((label_x - x)^2 + (label_y - y)^2) > 0.19
  text_x <- usr[1] + xscale * label_x
  text_y <- usr[3] + yscale * label_y
  graphics::segments(model$predicted[distant], model$observed[distant],
                     text_x[distant], text_y[distant], col = "grey72", lwd = 0.45)
  graphics::text(text_x, text_y, labels, cex = cex, col = "grey32")
}

house_validation_plots <- function(path, predictions, scores, model_label = "District model",
                                   provisional_choices = character()) {
  titles <- c(dem = "Democratic", rep = "Republican", other = "Other", none = "No Vote")
  model_color <- "#FA8072"
  baseline_color <- "#406A7B"
  states <- utils::read.csv("01_frame/docs/02_pl_2020_sources.csv", colClasses = "character")
  state_names <- setNames(states$STUSAB, states$STATEFP)

  grDevices::pdf(path, width = 11.6, height = 9.6, pointsize = 10.5, family = "Helvetica",
                 useDingbats = FALSE, title = "Held-out 2024 House vote shares")
  on.exit(grDevices::dev.off(), add = TRUE)
  graphics::par(mfrow = c(2, 2), oma = c(3.3, 3.4, 5.6, 1.2),
                mar = c(1.8, 2.4, 4.15, 0.6), mgp = c(2, 0.40, 0), las = 1,
                xaxs = "i", yaxs = "i", cex = 1, family = "sans")

  for (choice in names(titles)) {
    data <- predictions[predictions$choice == choice, ]
    model <- data[data$method == "model", ]
    baseline <- data[data$method == "baseline", ]
    endpoints <- range(data$predicted, data$observed, model$lower_90, model$upper_90)
    margin <- max(diff(endpoints), 0.01) * 0.055
    limits <- endpoints + c(-margin, margin)
    ticks <- pretty(limits, n = 5)
    ticks <- ticks[ticks >= 0 & ticks <= 1 & ticks >= limits[1] & ticks <= limits[2]]
    # White panels, light major/minor grids and a dashed equality line.
    graphics::plot.new()
    graphics::plot.window(limits, limits)
    if (length(ticks) > 1L) {
      minor <- c(ticks - diff(ticks[1:2]) / 2, tail(ticks, 1) + diff(ticks[1:2]) / 2)
      graphics::abline(v = minor, h = minor, col = "grey94", lwd = 0.6)
    }
    graphics::abline(v = ticks, h = ticks, col = "grey89", lwd = 0.8)
    graphics::abline(0, 1, col = "grey50", lty = "44", lwd = 0.95)
    for (side in c(1L, 2L)) {
      graphics::axis(side, at = ticks, labels = format(ticks, trim = TRUE),
                     tick = FALSE, col.axis = "grey32", cex.axis = 0.86)
    }

    # Plot intervals only for the model. Label each district once, at its
    # model prediction; both markers have the same observed share.
    graphics::segments(model$lower_90, model$observed, model$upper_90, model$observed,
                       col = "#F4C4BE", lwd = 1.0)
    graphics::points(baseline$predicted, baseline$observed, pch = 5,
                     cex = 0.84, col = baseline_color, lwd = 1.05)
    graphics::points(model$predicted, model$observed, pch = 16, cex = 0.83, col = model_color)
    state <- unname(state_names[substr(model$district_id, 1, 2)])
    seat <- as.integer(substr(model$district_id, 4, 5))
    labels <- paste(state, ifelse(seat == 0L | state == "DC", "AL", seat), sep = "-")
    house_district_labels(model, baseline, ifelse(is.na(state), model$district_id, labels))

    # Score lines sit above the grid, so they cannot cover district labels.
    # Use the same colors as the shared legend and the same units as the CSV.
    title <- titles[[choice]]
    if (choice %in% provisional_choices) title <- paste0(title, "*")
    graphics::mtext(title, side = 3, line = 2.75, cex = 1.00)
    for (method in c("model", "baseline")) {
      score <- scores[scores$choice == choice & scores$method == method, ]
      rho <- if (is.na(score$spearman)) "undefined" else sprintf("%.2f", score$spearman)
      metrics <- sprintf("Bias %+.2f pp     RMSE %.2f pp     Spearman %s",
                         score$bias_pp, score$rmse_pp, rho)
      if (method == "model") {
        line <- paste0("Model     ", metrics, "     90% coverage ", score$covered, "/", score$districts)
        graphics::mtext(line, side = 3, line = 1.33, adj = 0, cex = 0.77, col = "grey18")
      } else {
        graphics::mtext(paste("Baseline    ", metrics), side = 3, line = 0.30, adj = 0,
                        cex = 0.77, col = baseline_color)
      }
    }
  }

  n_held <- length(unique(predictions$district_id))
  graphics::mtext(sprintf("Held-out predicted vs. actual (n = %d districts)", n_held),
                  outer = TRUE, side = 3, line = 3.6, adj = 0, font = 2, cex = 1.38)
  graphics::mtext("2024 House vote shares among citizen adults. District labels identify model predictions.",
                  outer = TRUE, side = 3, line = 2.0, adj = 0, cex = 1.00)
  graphics::mtext("Observed share", outer = TRUE, side = 2, line = 1.25, las = 0, cex = 1.04)
  graphics::mtext("Predicted share", outer = TRUE, side = 1, line = 0.35, cex = 1.04)
  if (length(provisional_choices)) {
    names_flagged <- paste(unname(titles[provisional_choices]), collapse = " and ")
    graphics::mtext(paste0("* ", names_flagged, " model results are provisional (sampler diagnostics)."),
                    outer = TRUE, side = 1, line = 2.0, adj = 0, col = "grey35", cex = 0.82)
  }
  # Add the shared key using page coordinates after drawing the four facets.
  graphics::par(fig = c(0, 1, 0, 1), oma = c(0, 0, 0, 0), mar = c(0, 0, 0, 0), new = TRUE)
  graphics::plot.new()
  graphics::plot.window(c(0, 1), c(0, 1))
  graphics::legend(0.057, 0.930, legend = c(paste0(model_label, " (90% predictive interval)"),
                     "State presidential baseline"), horiz = TRUE, bty = "n",
                   col = c(model_color, baseline_color), pch = c(16, 5),
                   lty = c(1, 0), seg.len = 1.5, cex = 0.91,
                   x.intersp = 0.55, text.col = "grey20")
}

# Score one choice across the held-out districts. A positive bias means the
# model overpredicts. An observation at either interval endpoint is covered.
house_prediction_metrics <- function(rows) {
  error <- rows$error_pp
  rho <- NA_real_
  if (length(unique(rows$observed)) > 1L && length(unique(rows$predicted)) > 1L) {
    rho <- stats::cor(rows$predicted, rows$observed, method = "spearman")
  }
  metrics <- data.frame(districts = nrow(rows), bias_pp = mean(error),
                        rmse_pp = sqrt(mean(error^2)), spearman = rho,
                        covered = NA_integer_, coverage_90 = NA_real_)
  if (rows$method[1L] == "model") {
    metrics$covered <- sum(rows$covered_90)
    metrics$coverage_90 <- metrics$covered / metrics$districts
  }
  metrics
}

score_house_holdout <- function(test_observed, test_pres,
                                model_point, model_lower, model_upper, district_ids) {
  choices <- c("dem", "rep", "other", "none")
  check_matrix <- function(x) {
    x <- as.matrix(x)
    if (!is.numeric(x) || !identical(colnames(x), choices) || nrow(x) != 30L) {
      stop("Expected 30 district rows and numeric columns in order dem, rep, other, none.")
    }
    x
  }

  if (length(district_ids) != 30L || anyNA(district_ids) || anyDuplicated(district_ids) ||
      any(!nzchar(as.character(district_ids)))) {
    stop("Validation requires 30 unique district identifiers.")
  }
  test_observed <- check_matrix(test_observed)
  test_pres <- check_matrix(test_pres)
  model_point <- check_matrix(model_point)
  model_lower <- check_matrix(model_lower)
  model_upper <- check_matrix(model_upper)

  # The state presidential benchmark supplies one point prediction per choice.
  # Only model rows have interval endpoints and an interval coverage indicator.
  detail <- function(method, point, lower = NA_real_, upper = NA_real_) {
    data.frame(district_id = rep(as.character(district_ids), times = 4L),
               choice = rep(choices, each = 30L), method = method,
               observed = as.vector(test_observed), predicted = as.vector(point),
               lower_90 = as.vector(lower), upper_90 = as.vector(upper))
  }
  predictions <- rbind(detail("model", model_point, model_lower, model_upper),
                       detail("baseline", test_pres))
  predictions$prediction_stage <- "raw"
  summarise_house_holdout(predictions)
}

# Score the same 30 observed compositions for both sets of point predictions.
# Only the beta regressions produce predictive intervals.
summarise_house_holdout <- function(predictions) {
  choices <- c("dem", "rep", "other", "none")
  methods <- c("model", "baseline")
  key <- c("district_id", "choice", "method")
  shares <- c("observed", "predicted", "lower_90", "upper_90")
  if (!all(c(key, shares) %in% names(predictions)) ||
      !all(vapply(predictions[shares], is.numeric, logical(1)))) {
    stop("Incomplete district prediction columns or nonnumeric shares.")
  }
  if (nrow(predictions) != 30L * 4L * 2L || anyNA(predictions[key]) ||
      length(unique(predictions$district_id)) != 30L || any(!nzchar(predictions$district_id)) ||
      any(!predictions$method %in% methods) || any(!predictions$choice %in% choices) ||
      anyDuplicated(predictions[key])) {
    stop("Expected one model and one baseline prediction for every choice in all 30 districts.")
  }
  model <- predictions$method == "model"
  predictions$lower_90[!model] <- NA_real_
  predictions$upper_90[!model] <- NA_real_
  values <- c(predictions$observed, predictions$predicted,
              predictions$lower_90[model], predictions$upper_90[model])
  if (any(!is.finite(values) | values < 0 | values > 1) ||
      any(predictions$lower_90[model] > predictions$upper_90[model])) {
    stop("Invalid vote shares or model interval endpoints.")
  }
  # Both methods use the same 30 observed compositions.
  district_choice <- paste(predictions$district_id, predictions$choice)
  baseline_order <- match(district_choice[model], district_choice[!model])
  if (any(predictions$observed[model] != predictions$observed[!model][baseline_order])) {
    stop("The model and baseline have different observed results for the same district and choice.")
  }
  composition <- interaction(predictions$district_id, predictions$method, drop = TRUE)
  totals <- rowsum(predictions[c("observed", "predicted")], composition)
  if (any(abs(totals - 1) > 1e-9)) stop("District observed and predicted shares must sum to one.")

  predictions$error_pp <- 100 * (predictions$predicted - predictions$observed)
  # Coverage is defined only for the fitted model, which supplies both endpoints.
  predictions$covered_90 <- NA
  predictions$covered_90[model] <- with(predictions[model, ],
                                        lower_90 <= observed & observed <= upper_90)
  groups <- split(predictions, list(predictions$choice, predictions$method), drop = TRUE)
  scores <- do.call(rbind, lapply(groups, function(group) {
    data.frame(choice = group$choice[1], method = group$method[1], house_prediction_metrics(group))
  }))
  scores$prediction_stage <- "raw"
  rownames(scores) <- NULL
  list(scores = scores, predictions = predictions)
}
