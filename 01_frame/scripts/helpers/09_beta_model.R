# One district contributes one response at each stage where voters remain.
# The 2024 candidate-vote order is Republican, Democratic, then Other.
beta_stage_targets <- function(data) {
  votes <- house_matrix(data, c("votes_rep", "votes_dem", "votes_other"), 3L, "House votes")
  total <- rowSums(votes)
  cvap <- data$cvap
  if (length(cvap) != nrow(data) || any(!is.finite(cvap)) || any(cvap <= 0) ||
      any(votes < 0 | votes != round(votes)) || any(total > cvap) ||
      length(data$total_votes) != nrow(data) || !isTRUE(all(total == data$total_votes))) {
    stop("Check district CVAP and the three classified House candidate vote counts.")
  }
  # Sum the two remaining parties directly, so a true empty pool is exact.
  remaining <- votes[, 2L] + votes[, 3L]
  ratio <- function(numerator, denominator) {
    result <- rep(NA_real_, length(denominator))
    positive <- denominator > 0
    result[positive] <- numerator[positive] / denominator[positive]
    result
  }
  target <- cbind((cvap - total) / cvap, ratio(votes[, 1L], total),
                  ratio(votes[, 2L], remaining))
  colnames(target) <- c("none", "rep", "dem")
  target
}

# Ordered age and education effects have one parameter for each adjacent
# difference. Every difference contributes to all later bands. Subtracting
# the column mean makes the band coefficients sum to zero, without choosing
# a reference band. Multiplying district composition by this matrix gives
# the district's weight on each adjacent difference.
beta_walk_basis <- function(n_bands) {
  after_step <- outer(seq_len(n_bands), seq_len(n_bands - 1L), ">")
  sweep(after_step, 2L, colMeans(after_step))
}

beta_walk_term <- function(shares_z, label) {
  weights <- shares_z %*% beta_walk_basis(ncol(shares_z))
  steps <- seq_len(ncol(weights))
  members <- sprintf("%sStep%02d", label, steps)
  weight_names <- sprintf("%sWeight%02d", label, steps)
  colnames(weights) <- weight_names
  frame <- as.data.frame(weights)
  # Each level is an independent normal increment, sharing one SD per walk.
  # All districts use the same named steps with their own signed weights.
  for (j in steps) frame[[members[j]]] <- members[j]
  term <- sprintf("(1 | mm(%s, weights = cbind(%s), scale = FALSE))",
                  paste(members, collapse = ", "), paste(weight_names, collapse = ", "))
  list(frame = frame, term = term)
}

beta_stage_design <- function(data, choice, scaling = NULL) {
  stopifnot(choice %in% c("none", "rep", "dem"))
  age <- house_columns$age
  education <- c("educ_no_hs", "educ_hs", "educ_some_college", "educ_two_year",
                 "educ_four_year", "educ_postgrad")
  fixed <- c("sex_female", "race_black", "race_native", "race_asian",
             "race_other_multi", "eth_hispanic")
  columns <- c(fixed, paste0("pres_", choice), age, education)
  shares <- house_matrix(data, columns, length(columns), "district predictors")
  if (any(shares < 0 | shares > 1) ||
      any(abs(rowSums(shares[, age, drop = FALSE]) - 1) > 1e-8) ||
      any(abs(rowSums(shares[, education, drop = FALSE]) - 1) > 1e-8)) {
    stop("Invalid district or presidential shares. Age and education must each sum to one.")
  }
  raw <- as.data.frame(shares)
  names(raw)[names(raw) == paste0("pres_", choice)] <- "presidentialShare"

  # Raw zeros denote D-v-R and no incumbent. After centering, those same
  # reference ballots are represented by their transformed predictor values.
  if (choice != "none") {
    nominees <- house_matrix(data, c("n_dem", "n_rep", "n_other"), 3L, "nominees")
    lineup <- house_ballot_design(house_ballot_groups(nominees))
    incumbent <- house_matrix(data, paste0("incumbent_", choice), 1L, "focal incumbency")[, 1L]
    if (any(!incumbent %in% c(0, 1)) ||
        any(incumbent == 1 & nominees[, paste0("n_", choice)] == 0)) {
      stop("A focal incumbent must be a nominee of that party.")
    }
    raw <- cbind(raw, lineup, focalIncumbent = incumbent)
    fixed <- c(fixed, names(lineup), "focalIncumbent")
  }

  # Fit means and sample SDs on eligible districts from THIS training stage.
  # A fixed indicator with no training variation contributes no estimable slope.
  if (is.null(scaling)) {
    deviations <- vapply(raw, stats::sd, numeric(1))
    if (any(!is.finite(deviations))) stop("Too few districts to estimate predictor scales.")
    if (any(deviations[c(age, education)] == 0)) stop("An ordered share has zero training SD.")
    if (length(unique(raw$presidentialShare)) < 5L) {
      stop("The presidential spline requires five distinct training shares.")
    }
    omitted <- names(deviations)[deviations == 0]
    keep <- setdiff(names(raw), omitted)
    scaling <- list(mean = colMeans(raw[keep]), sd = deviations[keep], omitted = omitted)
  }
  keep <- names(scaling$mean)
  z <- sweep(sweep(as.matrix(raw[keep]), 2L, scaling$mean), 2L, scaling$sd, "/")
  fixed <- setdiff(fixed, scaling$omitted)
  age_walk <- beta_walk_term(z[, age, drop = FALSE], "age")
  education_walk <- beta_walk_term(z[, education, drop = FALSE], "education")
  frame <- data.frame(state_id = as.character(data$STATEFP),
                      z[, c(fixed, "presidentialShare"), drop = FALSE],
                      age_walk$frame, education_walk$frame)
  if (anyNA(frame) || any(!nzchar(frame$state_id))) stop("Missing state or model predictor.")
  terms <- c(fixed, "s(presidentialShare, bs = 'cr', k = 5)", "(1 | state_id)",
             age_walk$term, education_walk$term)
  formula <- stats::reformulate(terms, response = "response", env = globalenv())
  list(frame = frame, formula = formula, scaling = scaling)
}

beta_stage_priors <- function() {
  c(brms::set_prior("student_t(4, 0, 2.5)", class = "b"),
    brms::set_prior("student_t(4, 0, 3)", class = "Intercept"),
    brms::set_prior("student_t(4, 0, 1)", class = "sd"),
    brms::set_prior("student_t(4, 0, 1)", class = "sds"),
    brms::set_prior("lognormal(3, 1.5)", class = "phi"))
}

# Extend the common sampler checks to the presidential spline. Its curvature
# scale and basis coefficients are separate from the state and walk effects.
beta_sampler_diagnostics <- function(model) {
  audit <- house_sampler_diagnostics(list(model = model))
  smooth <- posterior::as_draws_array(model, variable = "^(sds_|s_)", regex = TRUE)
  variables <- posterior::variables(smooth)
  if (!any(startsWith(variables, "sds_")) || !any(startsWith(variables, "s_"))) {
    stop("Missing presidential spline parameters in the saved fit.")
  }
  stats <- posterior::summarise_draws(smooth, "rhat", "ess_bulk", "ess_tail")
  audit$parameters <- audit$parameters + nrow(stats)
  audit$max_rhat <- max(audit$max_rhat, stats$rhat)
  audit$min_bulk_ess <- min(audit$min_bulk_ess, stats$ess_bulk)
  audit$min_tail_ess <- min(audit$min_tail_ess, stats$ess_tail)
  audit$passed <- isTRUE(audit$passed && audit$max_rhat < 1.01 &&
                         audit$min_bulk_ess >= 100 * audit$chains &&
                         audit$min_tail_ess >= 100 * audit$chains)
  audit
}

fit_beta_sequence <- function(training, seed, cache_dir = NULL, chains = 4L, iter = 2000L,
                              cores = min(chains, 2L), warmup = iter %/% 2L, retry = FALSE) {
  raw <- beta_stage_targets(training)
  replacement <- 1 / mean(training$total_votes)
  if (!is.finite(replacement) || replacement <= 0 || replacement >= 0.5) {
    stop("The one-vote endpoint correction must lie strictly between zero and one half.")
  }
  prior <- beta_stage_priors()
  previous <- NULL
  if (!is.null(cache_dir)) dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  stages <- vector("list", 3L)
  diagnostics <- vector("list", 3L)

  for (j in seq_len(3L)) {
    choice <- colnames(raw)[j]
    y <- raw[, j]
    keep <- !is.na(y)
    design <- beta_stage_design(training[keep, , drop = FALSE], choice)
    y <- y[keep]
    message("Stage ", choice, ": ", length(y), " eligible training districts.")
    y[y == 0] <- replacement
    y[y == 1] <- 1 - replacement
    design$frame$response <- y

    path <- if (!is.null(cache_dir)) file.path(cache_dir, sprintf("stage_%d.rds", j))
    args <- list(seed = seed + j, chains = chains, iter = iter, warmup = warmup,
                 cores = cores, refresh = 0, control = list(adapt_delta = 0.99, max_treedepth = 13L))
    if (!is.null(path) && file.exists(path)) {
      model <- readRDS(path)
    } else {
      if (is.null(previous)) {
        model <- do.call(brms::brm, c(list(formula = design$formula, data = design$frame,
                         family = brms::Beta(link = "logit"), prior = prior, backend = "rstan"), args))
      } else {
        model <- do.call(stats::update, c(list(object = previous, formula. = design$formula,
                         newdata = design$frame, prior = prior), args))
      }
      if (!is.null(path)) stage_write(model, path, rds = TRUE)
    }
    audit <- beta_sampler_diagnostics(model)
    if (retry && !audit$passed && model$fit@sim$iter <= iter) {
      message("Retrying stage ", choice, " with longer warmup and sampling.")
      model <- stats::update(model, seed = seed + j + 1000L, iter = 2L * iter,
                    warmup = 2L * warmup, chains = chains, cores = cores, refresh = 0,
                    control = list(adapt_delta = 0.995, max_treedepth = 13L))
      if (!is.null(path)) stage_write(model, path, rds = TRUE)
      audit <- beta_sampler_diagnostics(model)
    }
    previous <- model
    stages[[j]] <- list(choice = choice, scaling = design$scaling,
                        model = model)
    diagnostics[[j]] <- data.frame(stage = choice, districts = sum(keep),
                                   omitted_empty_pool = sum(!keep), zero_share = replacement,
                                   adjusted_zeros = sum(raw[keep, j] == 0),
                                   adjusted_ones = sum(raw[keep, j] == 1),
                                   iterations = model$fit@sim$iter, audit)
  }
  list(stages = stages, diagnostics = do.call(rbind, diagnostics))
}

# Convert a draw of the three conditional fractions into four unconditional
# shares of all citizen adults. The final party gets exactly the remainder.
beta_unconditional_draws <- function(conditional) {
  home <- conditional[[1L]]
  voters <- 1 - home
  republican <- voters * conditional[[2L]]
  nonrepublican_voters <- voters * (1 - conditional[[2L]])
  democratic <- nonrepublican_voters * conditional[[3L]]
  other <- nonrepublican_voters * (1 - conditional[[3L]])
  list(dem = democratic, rep = republican, other = other, none = home)
}

predict_beta_sequence <- function(fit, newdata, seed, ndraws = 800L) {
  epred <- list()
  predictive <- list()
  for (j in seq_along(fit$stages)) {
    stage <- fit$stages[[j]]
    frame <- beta_stage_design(newdata, stage$choice, stage$scaling)$frame
    # Stage posteriors are independent. Pair independently sampled draws
    # across stages and share each unseen state's effect across its districts.
    set.seed(seed + j)
    draw_ids <- sample.int(posterior::ndraws(stage$model), ndraws, replace = FALSE)
    prep <- brms::prepare_predictions(stage$model, newdata = frame, draw_ids = draw_ids,
              allow_new_levels = TRUE, sample_new_levels = "gaussian", check_response = FALSE)
    epred[[j]] <- brms::posterior_epred(prep, dpar = NULL, nlpar = NULL)
    predictive[[j]] <- brms::posterior_predict(prep)
  }
  expected <- beta_unconditional_draws(epred)
  outcomes <- beta_unconditional_draws(predictive)
  collapse <- function(draws, statistic) {
    result <- do.call(cbind, lapply(draws, function(x) apply(x, 2L, statistic)))
    stopifnot(nrow(result) == nrow(newdata), all(is.finite(result) & result >= 0 & result <= 1))
    result
  }
  point <- collapse(expected, mean)
  stopifnot(all(abs(rowSums(point) - 1) < 1e-9))
  # Beta predictive quantiles are strictly interior. The RNG can round a
  # boundary-adjacent draw to 0 or 1. Keep the interval inside its support
  # so that this rounding never credits the model for covering an exact zero.
  interval <- function(p) collapse(outcomes, function(x) {
    q <- stats::quantile(x, p, names = FALSE)
    pmin(1 - .Machine$double.eps / 2, pmax(.Machine$double.xmin * .Machine$double.eps, q))
  })
  list(point = point, lower = interval(.05), upper = interval(.95))
}

# The driver keys fit_dir on model inputs, source and sampler configuration.
# Keep only the compact predictions once all three stage fits have succeeded.
beta_fit_predict <- function(training, assessment, seed, fit_dir) {
  completed <- file.path(fit_dir, "predictions.rds")
  if (file.exists(completed)) return(readRDS(completed))
  fit <- fit_beta_sequence(training, seed, fit_dir, retry = TRUE)
  stage_write(fit$diagnostics, file.path(fit_dir, "diagnostics.csv"))
  if (!all(fit$diagnostics$passed)) {
    failed <- which(!fit$diagnostics$passed)
    stop("Sampling diagnostics failed after the longer retry. Review ",
         file.path(fit_dir, "diagnostics.csv"), " before proceeding. Retained fit(s): ",
         paste(file.path(fit_dir, sprintf("stage_%d.rds", failed)), collapse = ", "))
  }
  result <- predict_beta_sequence(fit, assessment, seed = seed + 5L)
  result$diagnostics <- fit$diagnostics
  stage_write(result, completed, rds = TRUE)
  unlink(file.path(fit_dir, sprintf("stage_%d.rds", seq_len(3L))))
  result
}
