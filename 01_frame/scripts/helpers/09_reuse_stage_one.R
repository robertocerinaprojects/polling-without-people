# Inspect and reuse the saved November 10 no-House-vote fit after changing the
# diagnostic thresholds. Run once, from the repository root, before 'validate'.
source("01_frame/scripts/09_validate_house_beta.R")

# Recompute the old cache key with the original code but today's CSV, packages
# and CPU settings. Git supplies just the scripts; the working tree stays in place.
previous_key <- function(input_file, plan) {
  base <- "c48df55ff9356b8a96db4aa361289fcba5c622ff"
  folder <- tempfile("previous-beta-")
  dir.create(folder)
  root <- getwd()
  on.exit({ setwd(root); unlink(folder, recursive = TRUE) })
  archive <- file.path(folder, "scripts.tar")
  status <- system2("git", c("archive", "-o", shQuote(archive), base, "01_frame/scripts"))
  if (status != 0L) stop("Could not read the original scripts at ", base)
  utils::untar(archive, exdir = folder)
  setwd(folder)
  old <- new.env(parent = globalenv())
  old$source <- function(file) sys.source(file, envir = old)
  old$source("01_frame/scripts/09_validate_house_beta.R")
  old$beta_run_key(input_file, plan)
}

reuse_stage_one <- function() {
  input <- normalizePath("01_frame/data/intermediate/09_house_training_cd119.csv", mustWork = TRUE)
  plan <- beta_sampler_plan()
  new_key <- beta_run_key(input, plan)
  cache <- "01_frame/data/intermediate/09_beta_holdout_cache"
  destination <- file.path(cache, new_key)
  if (file.exists(file.path(destination, "predictions.rds"))) {
    message("This run already has predictions. Existing fits and diagnostic exports are in ", destination)
    return(invisible(destination))
  }

  old_key <- previous_key(input, plan)
  if (old_key != "049343311ac1b37106be" || new_key == old_key) {
    stop("The recorded November 10 run cannot be transferred with these sources, inputs or settings. ",
         "Use the normal 'validate' command for a fresh fit.")
  }
  original <- file.path(cache, old_key, "stage_1.rds")
  if (!file.exists(original)) stop("Missing the saved fit: ", original)
  target <- file.path(destination, "stage_1.rds")
  sha256 <- function(path) digest::digest(file = path, algo = "sha256")
  fingerprint <- sha256(original)
  if (file.exists(target) && sha256(target) != fingerprint) {
    stop("The destination already contains a different fit: ", target)
  }

  # Check the actual fit's stage, retry, rows and Stan specification before
  # accepting it. The independent check uses only this stage's training rows.
  stored <- readRDS(original)
  fit <- stored$model
  stopifnot(identical(stored$choice, "none"), identical(stored$attempt, 2L),
            identical(stored$plan, plan), inherits(fit, "brmsfit"), fit$backend == "rstan")
  # The saved second attempt used seed 20243000 + stage 1 + retry offset 1000.
  samples <- fit$fit@sim$samples
  same_sampler <- function(chain) {
    a <- attr(chain, "args")
    isTRUE(a$random_seed == "20244001" && a$iter == plan$iter && a$warmup == plan$warmup &&
           a$thin == 1L && a$control$adapt_delta == 0.995 && a$control$max_treedepth == 13L)
  }
  if (length(samples) != plan$chains || !all(vapply(samples, same_sampler, logical(1)))) {
    stop("The saved chains do not match the recorded seed, retry or sampler settings.")
  }
  districts <- read_table09(input)
  beta_validate_table(districts)
  train <- beta_district_split(districts)$train
  design <- beta_stage_design(train, "none")
  response <- beta_stage_targets(train)[, "none"]
  endpoint <- 1 / mean(train$total_votes)
  response[response == 0] <- endpoint
  response[response == 1] <- 1 - endpoint
  design$frame$response <- response
  specification <- list(formula = design$formula, data = design$frame,
                        family = brms::Beta(link = "logit"), prior = beta_stage_priors())
  # Four CPUs were available to this specific run: one thread for each chain.
  stopifnot(plan$threads_per_chain == 1L)
  specification$threads <- brms::threading(threads = 1, static = TRUE)
  expected_code <- do.call(brms::make_stancode, c(specification, backend = "rstan"))
  # RStan may strip the one terminal newline from brms's generated program.
  compiled <- as.character(rstan::get_stancode(fit$fit))
  generated <- as.character(expected_code)
  if (!identical(compiled, generated) && !identical(compiled, sub("\\n$", "", generated))) {
    stop("The stored Stan program differs from the current stage-one specification.")
  }
  expected_data <- do.call(brms::make_standata, specification)
  actual_data <- brms::standata(fit)
  same_input <- function(name) {
    a <- actual_data[[name]]
    b <- expected_data[[name]]
    identical(dim(a), dim(b)) && isTRUE(all.equal(a, b, tolerance = 1e-12, check.attributes = FALSE))
  }
  if (!setequal(names(actual_data), names(expected_data)) ||
      !all(vapply(names(expected_data), same_input, logical(1)))) {
    stop("The stored Stan response, predictors or other model data differ.")
  }

  dir.create(destination, recursive = TRUE, showWarnings = FALSE)
  audit <- beta_stage_inspection(fit, "none", 1L, destination, plan)
  stem <- file.path(destination, "stage_1_none")
  parameters <- paste0(stem, "_parameters.csv")
  message("Stan source: ", stem, ".stan\nParameter diagnostics: ", parameters)
  reference <- "01_frame/docs/stan/09_sequential_beta.stan"
  if (file.exists(reference)) {
    stan_hash <- sha256(paste0(stem, ".stan"))
    message("Fitted Stan SHA-256 ", stan_hash,
            if (stan_hash == sha256(reference)) " matches the reference."
            else " differs from the reference. View the fitted source above.")
  }
  detail <- utils::read.csv(parameters)
  # Show the spline slope missed by the previous audit, the extremes that
  # determine the stage summary and every parameter that failed a cutoff.
  review <- with(detail, unique(c(which(startsWith(parameter, "bs_")),
                                  which.max(rhat), which.min(ess_bulk), which.min(ess_tail),
                                  which(!passed))))
  print(detail[review, ], row.names = FALSE)
  print(audit, row.names = FALSE)
  if (!isTRUE(audit$passed)) stop("These draws did not pass the revised diagnostic checks.")

  # Publish just the fit, working from a private copy. Never replace another
  # process's checkpoint or import scores, diagnostics or predictions.
  if (!file.exists(target)) {
    copy <- tempfile(tmpdir = destination)
    on.exit(unlink(copy), add = TRUE)
    if (!file.copy(original, copy) || sha256(copy) != fingerprint || !file.link(copy, target)) {
      stop("Could not publish the verified checkpoint: ", target)
    }
  }
  message("Verified stage-one checkpoint ready for 'validate': ", target)
  invisible(destination)
}

if (sys.nframe() == 0L) reuse_stage_one()
