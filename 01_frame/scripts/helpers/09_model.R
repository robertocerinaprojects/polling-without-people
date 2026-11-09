# Dirichlet regression on the four observed shares of district CVAP. Each choice has its own
# slope for the corresponding statewide presidential share. DidNotVote anchors the other effects.
# Method: 01_frame/docs/09_model_house_votes.md
house_choices <- c("D", "R", "Other", "DidNotVote")

house_matrix <- function(data, columns, n, label) {
  if (length(columns) != n || anyDuplicated(columns) || !all(columns %in% names(data))) {
    stop("Invalid ", label, " columns: ", paste(columns, collapse = ", "))
  }
  selected <- data[columns]
  if (!all(vapply(selected, function(x) is.numeric(x) || is.logical(x), logical(1)))) {
    stop(label, " columns must be numeric")
  }
  values <- as.matrix(selected)
  storage.mode(values) <- "double"
  if (any(!is.finite(values))) stop("Missing or non-finite ", label)
  values
}

# Each flag describes a candidate on this particular ballot. A sitting member
# running against another nominee of the same party still counts just once.
house_incumbency_flags <- function(data, columns, nominees) {
  flags <- house_matrix(data, columns, 3L, "party incumbency")
  if (any(!flags %in% c(0, 1)) || any(flags == 1 & nominees == 0)) {
    stop("Incumbency must be 0 or 1, and a party with no nominee must have 0.")
  }
  flags
}

# Hanretty (2021, section 3.2) uses one vote in a typical election to
# replace an exact zero. Use the mean number of classified House candidate
# votes in the districts available to this fit. Held-out returns stay unseen.
# https://doi.org/10.1016/j.ijforecast.2021.03.007
house_zero_share <- function(training) {
  votes <- training[["total_votes"]]
  if (!length(votes) || !is.numeric(votes) || any(!is.finite(votes)) ||
      any(votes <= 0 | votes != round(votes))) {
    stop("Each training district needs a positive whole number of classified House votes.")
  }
  1 / mean(votes)
}

# A continuous Dirichlet response must be strictly inside the simplex.
# Take the replacement share from the positive choices in proportion to
# their recorded shares. Rows without zeros keep their original values.
dirichlet_fit_shares <- function(observed, replacement) {
  if (!is.matrix(observed) || !is.numeric(observed) || ncol(observed) != 4L ||
      any(!is.finite(observed)) || any(observed < 0 | observed > 1) ||
      any(abs(rowSums(observed) - 1) > 1e-10)) {
    stop("Observed House shares must be four finite proportions summing to one per district.")
  }
  if (length(replacement) != 1L || !is.numeric(replacement) || !is.finite(replacement) ||
      replacement <= 0 || replacement >= 1) {
    stop("The replacement share must be one number strictly between zero and one.")
  }
  adjusted <- observed
  for (i in which(rowSums(observed == 0) > 0)) {
    zero <- observed[i, ] == 0
    remaining <- 1 - sum(zero) * replacement
    if (remaining <= 0) stop("The replacement leaves no share for recorded House choices.")
    adjusted[i, zero] <- replacement
    adjusted[i, !zero] <- observed[i, !zero] * remaining / sum(observed[i, !zero])
  }
  if (any(adjusted <= 0 | adjusted >= 1) || any(abs(rowSums(adjusted) - 1) > 1e-10)) {
    stop("Adjusted training shares fall outside the open simplex.")
  }
  adjusted
}

house_inputs <- function(data, schema, scaling = NULL) {
  if (!nrow(data)) stop("Empty district table")
  training <- is.null(scaling)
  age <- house_matrix(data, schema$age, 14L, "age shares")
  demographic <- house_matrix(data, schema$demographic, length(schema$demographic), "demographic shares")
  president <- house_matrix(data, schema$president, 4L, "state presidential shares")
  slate <- house_matrix(data, schema$slate, 3L, "ballot presence")
  incumbents <- house_incumbency_flags(data, schema$incumbent, slate)
  inputs <- c(age, demographic, president)
  if (any(inputs < 0 | inputs > 1 + 1e-9) || any(abs(rowSums(age) - 1) > 1e-8) ||
      any(abs(rowSums(president) - 1) > 1e-8)) {
    stop("Age and statewide presidential shares must each be nonnegative and sum to one.")
  }
  slate <- as.matrix(house_ballot_design(house_ballot_groups(slate)))

  # Each non-age demographic family omits one reference category upstream.
  # Covariate scaling is learned solely from the training districts.
  if (!identical(make.names(schema$demographic, unique = TRUE), schema$demographic)) {
    stop("Please use syntactic, unique names for the demographic columns")
  }
  if (training) {
    age_center <- colMeans(age)
    age_offset <- sweep(age, 2, age_center)
    age_scale <- sqrt(mean(rowSums(age_offset^2)))
    if (!is.finite(age_scale) || age_scale <= 0) stop("No age variation in training districts")
    scaling <- list(
      dem_center = colMeans(demographic),
      dem_sd = apply(demographic, 2, stats::sd),
      pres_center = colMeans(president),
      pres_sd = apply(president, 2, stats::sd),
      age_center = age_center, age_scale = age_scale,
      zero_share = house_zero_share(data),
      slate_columns = colnames(slate)[apply(slate, 2, function(x) length(unique(x)) > 1)]
    )
    sd_all <- c(scaling$dem_sd, scaling$pres_sd)
    if (any(!is.finite(sd_all)) || any(sd_all <= 0)) {
      stop("A demographic or presidential predictor is constant in the training data.")
    }
  }
  age <- sweep(age, 2, scaling$age_center) / scaling$age_scale
  demographic <- sweep(sweep(demographic, 2, scaling$dem_center), 2, scaling$dem_sd, "/")
  president <- sweep(sweep(president, 2, scaling$pres_center), 2, scaling$pres_sd, "/")
  colnames(president) <- paste0("pres", house_choices)

  cvap <- house_matrix(data, schema$cvap, 1L, "citizen-adult population")[, 1]
  if (any(cvap <= 0)) stop("Invalid district CVAP")
  if (length(schema$state) != 1L || !schema$state %in% names(data)) stop("Missing state identifier")
  state <- as.character(data[[schema$state]])
  if (anyNA(state) || any(!nzchar(state))) stop("Missing state identifier")
  frame <- data.frame(state = state, demographic, president, incumbents,
                      slate[, scaling$slate_columns, drop = FALSE],
                      check.names = FALSE)
  if (anyDuplicated(names(frame))) stop("Conflicting demographic/model column labels")
  age_members <- sprintf("ageMember%02d", seq_len(ncol(age)))
  age_weights <- sprintf("ageWeight%02d", seq_len(ncol(age)))
  for (j in seq_len(ncol(age))) {
    # Every district belongs to every age band. Its band shares supply the
    # mm() weights. A common shift of the band coefficients cancels exactly
    # because the training-centered weights sum to zero in every district.
    frame[[age_members[j]]] <- rep(schema$age[j], nrow(data))
    frame[[age_weights[j]]] <- age[, j]
  }
  if (training) {
    observed <- house_matrix(data, schema$shares, 4L, "observed House shares")
    colnames(observed) <- house_choices
    frame$houseShares <- I(dirichlet_fit_shares(observed, scaling$zero_share))
  }
  list(data = frame, scaling = scaling, age_members = age_members, age_weights = age_weights)
}

house_formula <- function(prepared, schema) {
  mm_term <- paste0("(1 | mm(", paste(prepared$age_members, collapse = ", "),
                    ", weights = cbind(", paste(prepared$age_weights, collapse = ", "),
                    "), scale = FALSE))")
  common <- c(schema$demographic, prepared$scaling$slate_columns, "(1 | state)", mm_term)
  formulas <- list(houseShares ~ 1)
  for (choice in house_choices) {
    # Common state, age, ballot and demographic effects are identified as
    # contrasts against DidNotVote. Its own statewide presidential slope stays free.
    terms <- if (choice == "DidNotVote") "0" else c(common, schema$incumbent[[choice]])
    rhs <- paste(c(terms, paste0("pres", choice)), collapse = " + ")
    formulas[[length(formulas) + 1L]] <- stats::as.formula(paste0("mu", choice, " ~ ", rhs))
  }
  do.call(brms::bf, formulas)
}

house_stanvars <- function() {
  # Estimate one slope across the three party groups. A sitting independent
  # nominee can then use the association learned from incumbents in major parties.
  brms::stanvar(scode = "real shared_incumbency;", block = "parameters") +
    brms::stanvar(scode = "lprior += student_t_lpdf(shared_incumbency | 4, 0, 2.5);",
                  block = "tparameters", position = "end")
}

house_priors <- function(schema = house_columns) {
  # Weak Student-t fixed-effect priors. The candidate incumbency coefficients
  # all point to the same sampled slope, whose single prior is declared above.
  # The group SD priors pool state effects and age bands.
  priors <- brms::set_prior("lognormal(3, 1.5)", class = "phi")
  for (choice in house_choices) {
    dpar <- paste0("mu", choice)
    priors <- c(priors, brms::set_prior("student_t(4, 0, 2.5)", class = "b", dpar = dpar))
    if (choice != "DidNotVote") {
      priors <- c(priors,
                  brms::set_prior("constant(shared_incumbency)", class = "b", dpar = dpar,
                                  coef = schema$incumbent[[choice]]),
                  brms::set_prior("student_t(4, 0, 3)", class = "Intercept", dpar = dpar),
                  brms::set_prior("student_t(4, 0, 1)", class = "sd", dpar = dpar))
    }
  }
  priors
}

fit_house_dirichlet <- function(training, schema, seed, chains = 4L, iter = 2000L,
                         warmup = iter %/% 2L, cores = min(chains, 2L), backend = "rstan") {
  if (!requireNamespace("brms", quietly = TRUE) || utils::packageVersion("brms") < "2.23.0") {
    stop("Step 09 requires brms >= 2.23.0 to fit the reviewed Dirichlet model.")
  }
  prepared <- house_inputs(training, schema)
  formula <- house_formula(prepared, schema)
  family <- brms::dirichlet(refcat = NA)
  # Verify every fixed-effect design, including the presidential slope for
  # DidNotVote. The nonvote utility anchors the other contrasts.
  design <- brms::make_standata(formula, data = prepared$data, family = family)
  for (choice in house_choices) {
    matrix_name <- paste0("X_mu", choice)
    x <- design[[matrix_name]]
    expected <- paste0("pres", choice)
    if (choice != "DidNotVote") {
      expected <- c("Intercept", schema$demographic, prepared$scaling$slate_columns,
                    schema$incumbent[[choice]], expected)
    }
    if (!identical(colnames(x), expected)) {
      stop("Unexpected fixed effects for ", choice, " in ", matrix_name)
    }
  }
  fit <- brms::brm(formula, data = prepared$data, family = family, prior = house_priors(schema),
                   stanvars = house_stanvars(),
                   backend = backend, seed = seed, chains = chains, iter = iter, warmup = warmup,
                   cores = cores, control = list(adapt_delta = 0.97, max_treedepth = 13))
  list(model = fit, schema = schema, scaling = prepared$scaling, choices = house_choices)
}

house_sampler_diagnostics <- function(fit) {
  draws <- posterior::as_draws_array(fit$model)
  parameters <- posterior::variables(draws)
  # Include the sampled regression, dispersion and district-composition
  # hierarchy terms; omit Stan's bookkeeping variables (lp__, lprior).
  parameters <- parameters[grepl("^(b_|sd_|r_|phi$|shared_incumbency$)", parameters)]
  if (!length(parameters)) stop("Could not identify posterior model parameters")
  draws <- posterior::subset_draws(draws, variable = parameters)
  chain_count <- posterior::nchains(draws)
  stats <- posterior::summarise_draws(draws, "rhat", "ess_bulk", "ess_tail")
  sampler <- brms::nuts_params(fit$model)
  divergent <- sampler$Value[sampler$Parameter == "divergent__"]
  depth <- sampler$Value[sampler$Parameter == "treedepth__"]
  if (length(divergent) != posterior::ndraws(draws) || length(depth) != length(divergent)) {
    stop("Incomplete post-warmup Stan sampler diagnostics")
  }
  audit <- data.frame(chains = chain_count, postwarmup_draws = posterior::ndraws(draws),
                      parameters = length(parameters), max_rhat = max(stats$rhat),
                      min_bulk_ess = min(stats$ess_bulk), min_tail_ess = min(stats$ess_tail),
                      divergences = sum(divergent), max_depth_hits = sum(depth >= 13))
  audit$passed <- with(audit, isTRUE(chains >= 4L && max_rhat < 1.01 &&
      min_bulk_ess >= 100L * chains && min_tail_ess >= 100L * chains &&
      divergences == 0 && max_depth_hits == 0))
  audit
}

predict_house_dirichlet <- function(fit, newdata, seed, ndraws = NULL) {
  frame <- house_inputs(newdata, fit$schema, scaling = fit$scaling)$data
  set.seed(seed)
  # Shared prediction preparation draws unseen state effects only once
  # and uses those same draws for expected shares and predictive intervals.
  prep <- brms::prepare_predictions(fit$model, newdata = frame,
                                    allow_new_levels = TRUE, sample_new_levels = "gaussian",
                                    ndraws = ndraws, check_response = FALSE)
  check_shares <- function(draws) {
    if (length(dim(draws)) != 3L || dim(draws)[2] != nrow(frame) ||
        !setequal(dimnames(draws)[[3]], house_choices)) stop("Unexpected prediction shape")
    shares <- draws[, , house_choices, drop = FALSE]
    if (any(!is.finite(shares)) || any(shares < 0) ||
        any(abs(apply(shares, c(1, 2), sum) - 1) > 1e-8)) stop("Invalid prediction shares")
    shares
  }
  list(mean_share = check_shares(brms::posterior_epred(prep, dpar = NULL, nlpar = NULL)),
       predictive_share = check_shares(brms::posterior_predict(prep)))
}
