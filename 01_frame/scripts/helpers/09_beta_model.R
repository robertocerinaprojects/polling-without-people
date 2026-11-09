# One district contributes one response at each stage where voters remain.
# party_order is the fixed national order of dem, rep and other.
beta_stage_targets <- function(data, party_order) {
  if (!identical(sort(unname(party_order)), sort(c("dem", "rep", "other")))) {
    stop("Expected the three distinct party groups dem, rep and other.")
  }
  votes <- house_matrix(data, paste0("votes_", party_order), 3L, "House votes")
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
  colnames(target) <- c("none", party_order[1:2])
  target
}

# Preprocessing parameters are learned on districts with a defined response
# for this stage. The same parameters are applied during prediction.
beta_stage_design <- function(data, choice, remaining, scaling = NULL) {
  age <- house_matrix(data, house_columns$age, 14L, "age shares")
  people <- house_matrix(data, house_columns$demographic, length(house_columns$demographic),
                         "demographic shares")
  president <- house_matrix(data, paste0("pres_", choice), 1L, "state presidential share")
  if (any(age < 0 | age > 1) || any(abs(rowSums(age) - 1) > 1e-8) ||
      any(people < 0 | people > 1) || any(president < 0 | president > 1)) {
    stop("Invalid district demographic or statewide presidential share.")
  }
  counts <- house_matrix(data, c("n_dem", "n_rep", "n_other"), 3L, "nominee counts")
  lineup <- house_ballot_design(house_ballot_groups(counts))
  incumbents <- house_incumbency_flags(data, house_columns$incumbent, counts)
  colnames(incumbents) <- c("dem", "rep", "other")
  fixed <- data.frame(people, lineup, presidentialShare = president[, 1L])
  if (choice == "none") {
    fixed$anyIncumbent <- as.integer(rowSums(incumbents) > 0)
  } else {
    fixed$focalIncumbent <- incumbents[, choice]
    fixed$remainingIncumbent <- as.integer(rowSums(incumbents[, remaining, drop = FALSE]) > 0)
  }

  if (is.null(scaling)) {
    # An indicator constant in the training districts cannot identify a slope.
    sd <- vapply(fixed, stats::sd, numeric(1))
    if (any(!is.finite(sd))) stop("Too few districts to estimate stage predictor scales.")
    keep <- names(sd)[sd > 0]
    center <- colMeans(age)
    age_scale <- sqrt(mean(rowSums(sweep(age, 2L, center)^2)))
    if (!is.finite(age_scale) || age_scale <= 0) stop("No district age variation.")
    scaling <- list(mean = colMeans(fixed[keep]), sd = sd[keep],
                    age_center = center, age_scale = age_scale,
                    omitted = setdiff(names(fixed), keep))
  }
  variables <- names(scaling$mean)
  x <- sweep(sweep(as.matrix(fixed[variables]), 2L, scaling$mean), 2L, scaling$sd, "/")
  age <- sweep(age, 2L, scaling$age_center) / scaling$age_scale
  frame <- data.frame(state = as.character(data$STATEFP), x, check.names = FALSE)
  if (anyNA(frame) || any(!nzchar(frame$state))) stop("Missing state or model predictor.")

  # The age composition supplies the weights for partially pooled age effects.
  # Every district has 14 bands, and the centered weights sum to zero.
  members <- sprintf("ageMember%02d", seq_len(ncol(age)))
  weights <- sprintf("ageWeight%02d", seq_len(ncol(age)))
  for (j in seq_along(members)) {
    frame[[members[j]]] <- house_columns$age[j]
    frame[[weights[j]]] <- age[, j]
  }
  age_effect <- paste0("(1 | mm(", paste(members, collapse = ", "), ", weights = cbind(",
                       paste(weights, collapse = ", "), "), scale = FALSE))")
  formula <- stats::reformulate(c(variables, "(1 | state)", age_effect),
                                response = "response", env = globalenv())
  list(frame = frame, formula = formula, scaling = scaling)
}

beta_stage_priors <- function(method, hyper = NULL) {
  method <- match.arg(method, c("vanilla", "ridge", "horseshoe"))
  if (method != "vanilla" &&
      (length(hyper) != 1L || !is.numeric(hyper) || !is.finite(hyper) || hyper <= 0)) {
    stop("The ridge SD and horseshoe expected active/inactive ratio must be positive.")
  }
  slopes <- switch(method,
    vanilla = "student_t(4, 0, 2.5)",
    ridge = sprintf("normal(0, %.12g)", hyper),
    horseshoe = sprintf("horseshoe(par_ratio = %.12g, scale_slab = 2, df_slab = 4)", hyper)
  )
  c(brms::set_prior(slopes, class = "b"),
    brms::set_prior("student_t(4, 0, 3)", class = "Intercept"),
    brms::set_prior("student_t(4, 0, 1)", class = "sd"),
    brms::set_prior("lognormal(3, 1.5)", class = "phi"))
}

# Reuse the last compiled program for the active prior setting. update.brmsfit
# checks the generated Stan code and recompiles if the design requires it.
beta_templates <- new.env(parent = emptyenv())

beta_sampler_diagnostics <- function(model, method) {
  audit <- house_sampler_diagnostics(list(model = model))
  if (method == "horseshoe") {
    # Track the sampled scales as well as the regression slopes they shrink.
    hs <- posterior::as_draws_array(model, variable = "^hs_", regex = TRUE)
    stats <- posterior::summarise_draws(hs, "rhat", "ess_bulk", "ess_tail")
    audit$parameters <- audit$parameters + nrow(stats)
    audit$max_rhat <- max(audit$max_rhat, stats$rhat)
    audit$min_bulk_ess <- min(audit$min_bulk_ess, stats$ess_bulk)
    audit$min_tail_ess <- min(audit$min_tail_ess, stats$ess_tail)
    audit$passed <- isTRUE(audit$passed && audit$max_rhat < 1.01 &&
                    audit$min_bulk_ess >= 100 * audit$chains &&
                    audit$min_tail_ess >= 100 * audit$chains)
  }
  audit
}

fit_beta_sequence <- function(training, order, method, hyper = NULL, seed,
                              cache_dir = NULL, chains = 4L, iter = 2000L,
                              cores = min(chains, 2L), warmup = iter %/% 2L, retry = FALSE) {
  raw <- beta_stage_targets(training, order)
  replacement <- 1 / mean(training$total_votes)
  if (replacement >= 0.5) stop("Endpoint correction is too large for a beta response.")
  prior <- beta_stage_priors(method, hyper)
  key <- if (method == "vanilla") method else paste(method, hyper)
  if (!is.null(cache_dir)) dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  stages <- vector("list", 3L)
  diagnostics <- vector("list", 3L)

  for (j in seq_len(3L)) {
    choice <- colnames(raw)[j]
    remaining <- order[seq_along(order) >= j]
    # For a candidate stage, its opponents are the parties below it in order.
    y <- raw[, j]
    keep <- !is.na(y)
    design <- beta_stage_design(training[keep, , drop = FALSE], choice, remaining)
    y <- y[keep]
    y[y == 0] <- replacement
    y[y == 1] <- 1 - replacement
    design$frame$response <- y

    path <- if (!is.null(cache_dir)) file.path(cache_dir, sprintf("stage_%d.rds", j))
    args <- list(seed = seed + j, chains = chains, iter = iter, warmup = warmup,
                 cores = cores, refresh = 0, control = list(adapt_delta = 0.99, max_treedepth = 13L))
    if (!is.null(path) && file.exists(path)) {
      model <- readRDS(path)
    } else {
      template <- if (identical(beta_templates$key, key)) beta_templates$model
      if (is.null(template)) {
        model <- do.call(brms::brm, c(list(formula = design$formula, data = design$frame,
                         family = brms::Beta(link = "logit"), prior = prior, backend = "rstan",
                         save_pars = brms::save_pars(manual = if (method == "horseshoe") "hs_local")), args))
      } else {
        model <- do.call(stats::update, c(list(object = template, formula. = design$formula,
                         newdata = design$frame, prior = prior), args))
      }
      if (!is.null(path)) stage_write(model, path, rds = TRUE)
    }
    audit <- beta_sampler_diagnostics(model, method)
    if (retry && !audit$passed && model$fit@sim$iter <= iter) {
      message("Retrying ", method, " stage ", choice, " with longer warmup and sampling.")
      model <- stats::update(model, seed = seed + j + 1000L, iter = 2L * iter,
                    warmup = 2L * warmup, chains = chains, cores = cores, refresh = 0,
                    control = list(adapt_delta = 0.995, max_treedepth = 13L))
      if (!is.null(path)) stage_write(model, path, rds = TRUE)
      audit <- beta_sampler_diagnostics(model, method)
    }
    beta_templates$key <- key
    beta_templates$model <- model
    stages[[j]] <- list(choice = choice, remaining = remaining, scaling = design$scaling,
                        model = model)
    diagnostics[[j]] <- data.frame(stage = choice, districts = sum(keep),
                                   omitted_empty_pool = sum(!keep), zero_share = replacement,
                                   adjusted_zeros = sum(raw[keep, j] == 0),
                                   adjusted_ones = sum(raw[keep, j] == 1),
                                   iterations = model$fit@sim$iter, audit)
  }
  list(order = order, stages = stages, diagnostics = do.call(rbind, diagnostics))
}

# Convert a draw of the three conditional fractions into four unconditional
# shares of all citizen adults. The final party gets exactly the remainder.
beta_unconditional_draws <- function(conditional, party_order) {
  home <- conditional[[1L]]
  voters <- 1 - home
  party1 <- voters * conditional[[2L]]
  others <- voters * (1 - conditional[[2L]])
  party2 <- others * conditional[[3L]]
  party3 <- others * (1 - conditional[[3L]])
  shares <- setNames(list(home, party1, party2, party3), c("none", party_order))
  shares[c("dem", "rep", "other", "none")]
}

predict_beta_sequence <- function(fit, newdata, seed, ndraws = 800L) {
  epred <- list()
  predictive <- list()
  for (j in seq_along(fit$stages)) {
    stage <- fit$stages[[j]]
    frame <- beta_stage_design(newdata, stage$choice, stage$remaining, stage$scaling)$frame
    # Stage posteriors are independent. Pair independently sampled draws
    # across stages and share each unseen state's effect across its districts.
    set.seed(seed + j)
    draw_ids <- sample.int(posterior::ndraws(stage$model), ndraws, replace = FALSE)
    prep <- brms::prepare_predictions(stage$model, newdata = frame, draw_ids = draw_ids,
              allow_new_levels = TRUE, sample_new_levels = "gaussian", check_response = FALSE)
    epred[[j]] <- brms::posterior_epred(prep, dpar = NULL, nlpar = NULL)
    predictive[[j]] <- brms::posterior_predict(prep)
  }
  expected <- beta_unconditional_draws(epred, fit$order)
  outcomes <- beta_unconditional_draws(predictive, fit$order)
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

# fit_dir identifies this exact split, prior setting and sampler configuration.
# Keep only the compact predictions once all three stage fits have succeeded.
beta_fit_predict <- function(training, assessment, party_order, method, hyperparameter, seed, fit_dir) {
  completed <- file.path(fit_dir, "predictions.rds")
  if (file.exists(completed)) return(readRDS(completed))
  fit <- fit_beta_sequence(training, party_order, method, hyperparameter, seed, fit_dir, retry = TRUE)
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
