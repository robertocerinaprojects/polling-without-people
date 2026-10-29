# ══════════════════════════════════════════════════════════════════════════════
# SCRIPTS 19A / 19B / 19C: CART Model Fitting, Validation, and Imputation
#
# Purpose:
#   Fit the CART inheritance model that predicts CD-level vote shares from
#   demographic + state-level presidential + contestation features, validate
#   its ability to generalize to unseen CDs, then apply it to impute vote
#   shares for the prediction-set CDs (genuinely redistricted CDs with no
#   valid 2024 House shares).
#
# Pipeline overview:
#
#   Script 19A — Fit maximal trees on the full training set
#     Fits 4 unpruned rpart trees (one per outcome share) on all ~318
#     training-set CDs. Reports in-sample R² and saves the trees to disk.
#     These are the "production" trees applied by Script 19C.
#
#     Input:   training_table.rds (from Script 18C)
#     Outputs: trees.rds; 4 in-sample prediction plots
#
#   Script 19B — Randomized hold-out validation
#     Randomly holds out 15 CDs from the training set, refits 4 trees on
#     the remaining ~303 CDs, and evaluates predictions on the held-out set.
#     Reports per-CD residuals and hold-out R² per outcome.
#
#     Input:   training_table.rds (same as 19A)
#     Outputs: hold-out predictions table (printed to console/logs)
#
#   Script 19C — Apply trees to the prediction set (imputation)
#     Uses trees.rds from 19A to predict vote shares for the ~117
#     prediction-set CDs. Training-set CDs are unchanged. Adds an is_imputed
#     flag. No normalization at this stage — the simplex constraint is
#     enforced downstream during MrsP raking/poststratification.
#
#     Inputs:  training_table.rds, trees.rds
#     Output:  training_table_v2.rds
#
# Why share a file:
#   All three scripts use training_table.rds and involve the same CART model
#   logic and predictor set. Sharing a file lets us run 19A → 19B → 19C in
#   sequence without repeated I/O.
#
# Note on independence:
#   19B refits its own trees on the smaller ~303-CD training subset for
#   genuine hold-out validation — it does NOT reuse trees.rds from 19A.
#   This ensures the validation is a true test of generalization on
#   demographic patterns the model has never seen.
#
#   19C, in contrast, DOES use trees.rds from 19A — its purpose is to apply
#   the production trees to prediction-set CDs.
# ══════════════════════════════════════════════════════════════════════════════


library(here)
library(tidyverse)
library(rpart)
library(rpart.plot)


# ── Folder paths ────────────────────────────────────────────────────────────
processed_dir <- here("Data_Processed")


# Shared constants for all three scripts
control_params <- rpart.control(cp = 0, minsplit = 3, minbucket = 1, xval = 0)

non_predictors_common <- c("state_cd", "state_abbrv", "cd_pop",
                           "is_redistricted", "training_eligibility")

#-----------Load Inputs-----------#
training_table <- readRDS(file.path(processed_dir, "training_table.rds"))

# If an old 'trees.rds' exists, delete it so we don't accidentally
# load stale models from a previous session
if (file.exists(file.path(processed_dir, "trees.rds"))) {
  file.remove(file.path(processed_dir, "trees.rds"))
}

# ══════════════════════════════════════════════════════════════════════════════
# SCRIPT 19A: Fit maximal CART trees on the training set
# ══════════════════════════════════════════════════════════════════════════════
#
# Fit four separate maximal (unpruned) rpart regression trees, one per outcome
# share. These become the "production" trees applied to the prediction set.
#
# Model architecture:
#   4 trees, each predicting one outcome share (dem, rep, other, no_vote)
#   from 34 predictors:
#     - 29 demographic proportions (pct_age_*, pct_male, pct_female,
#       pct_race_*, pct_hisp_*, pct_educ_*)
#     - 4 state-level presidential shares (state_pres_*_share)
#     - 1 contestation flag (TRUE / FALSE)
#
# rpart control parameters (unpruned maximal trees):
#   cp = 0        — no complexity-based pruning
#   minsplit = 3  — minimum 3 observations to consider a split
#   minbucket = 1 — minimum 1 observation per terminal node
#
# Sections:
#   1. Filter to training set
#   2. Fit the four trees
#   3. Compute in-sample R² per outcome
#   4. Generate in-sample prediction plots
#   5. Save trees.rds
# ══════════════════════════════════════════════════════════════════════════════



# ── 1. Filter to training set ───────────────────────────────────────────────
# Training set = ~318 CDs where 2024 House shares are directly usable:
#   - Stable-state CDs (43 states)
#   - Essentially-unchanged CDs in the 7 redistricted states (95%+ overlap)

training_set <- training_table %>% filter(training_eligibility == "training_set")

cat("Training set size:", nrow(training_set), "CDs\n")

# Explicit predictor set — built once, used by 19A/19B/19C.
outcome_cols   <- c("dem_share", "rep_share", "other_share", "no_vote_share")
predictor_cols <- setdiff(names(training_table),
                          c(non_predictors_common, outcome_cols))

stopifnot(length(predictor_cols) == 34)     # must be exactly 34
stopifnot(!"state_cd" %in% predictor_cols)  # identifier must NOT be a predictor

fml <- function(outcome) reformulate(predictor_cols, response = outcome)

# ── 2. Fit the four trees ────────────────────────────────────────────────────
# Fit via the explicit 34-predictor formula (fml); identifiers and other outcomes excluded by construction


trees <- list()
trees$dem     <- rpart(fml("dem_share"),     data = training_set, method = "anova", control = control_params)
trees$rep     <- rpart(fml("rep_share"),     data = training_set, method = "anova", control = control_params)
trees$other   <- rpart(fml("other_share"),   data = training_set, method = "anova", control = control_params)
trees$no_vote <- rpart(fml("no_vote_share"), data = training_set, method = "anova", control = control_params)

cat("\n══ Trees fit ══\n")
cat("dem:     ", length(unique(trees$dem$where)),     "leaves\n")
cat("rep:     ", length(unique(trees$rep$where)),     "leaves\n")
cat("other:   ", length(unique(trees$other$where)),   "leaves\n")
cat("no_vote: ", length(unique(trees$no_vote$where)), "leaves\n")


# ── 3. Compute in-sample R² per outcome ─────────────────────────────────────
# With maximal trees on ~318 CDs, in-sample R² is close to 1 by construction.
# This is expected — the trees can memorize training data. Generalization
# is tested in Script 19B.

r2 <- function(actual, predicted) {
  1 - sum((actual - predicted)^2) / sum((actual - mean(actual))^2)
}

cat("\n══ In-sample R² per outcome ══\n")
cat("dem:    ", round(r2(training_set$dem_share,
                         predict(trees$dem, training_set)), 4), "\n")
cat("rep:    ", round(r2(training_set$rep_share,
                         predict(trees$rep, training_set)), 4), "\n")
cat("other:  ", round(r2(training_set$other_share,
                         predict(trees$other, training_set)), 4), "\n")
cat("no_vote:", round(r2(training_set$no_vote_share,
                         predict(trees$no_vote, training_set)), 4), "\n")


# ── 4. Generate in-sample prediction plots ─────────────────────────────────
# Actual vs. predicted for each outcome. Points should cluster on the y=x
# line for maximal trees.

plot_prediction <- function(model, actual, outcome_label, filename) {
  df <- tibble(
    actual = actual,
    predicted = predict(model, training_set)
  )
  
  p <- ggplot(df, aes(x = actual, y = predicted)) +
    geom_point(alpha = 0.6, color = "steelblue") +
    geom_abline(linetype = "dashed", color = "red") +
    coord_cartesian(xlim = c(0, 1), ylim = c(0, 1)) +   # no dropping; fits no_vote too
    labs(
      x = paste("Actual", outcome_label),
      y = paste("Predicted", outcome_label),
      title = paste("In-sample fit:", outcome_label)
    ) +
    theme_minimal()
  
  ggsave(filename, plot = p, width = 6, height = 6, dpi = 150)
  cat("Saved:", filename, "\n")
}

plots_dir <- file.path(processed_dir, "Prediction_Plots")
if (!dir.exists(plots_dir)) dir.create(plots_dir, recursive = TRUE)

plot_prediction(trees$dem, training_set$dem_share, "dem_share",
                file.path(plots_dir, "dem_predictions_plot.png"))
plot_prediction(trees$rep, training_set$rep_share, "rep_share",
                file.path(plots_dir, "rep_predictions_plot.png"))
plot_prediction(trees$other, training_set$other_share, "other_share",
                file.path(plots_dir, "other_predictions_plot.png"))
plot_prediction(trees$no_vote, training_set$no_vote_share, "no_vote_share",
                file.path(plots_dir, "no_vote_predictions_plot.png"))
cat("Prediction plots saved to:", plots_dir, "\n")
# ── 5. Save trees.rds ───────────────────────────────────────────────────────

saveRDS(trees, file.path(processed_dir, "trees.rds"))

cat("\nSaved trees.rds\n")
cat("Contains: dem, rep, other, no_vote (rpart models)\n")


# ══════════════════════════════════════════════════════════════════════════════
# SCRIPT 19B: Randomized hold-out validation
# ══════════════════════════════════════════════════════════════════════════════
#
# Purpose:
#   Test how well the CART approach generalizes to unseen CDs. Randomly
#   hold out 15 CDs from the training set, refit trees on the remaining
#   ~303, and evaluate predictions on the held-out set.
#
# Why hold-out over cross-validation:
#   Per team decision, a single randomized hold-out is used rather than
#   k-fold CV. This is a simpler validation strategy suitable for
#   maximal-tree diagnostics. The 15-CD hold-out size is roughly 5% of
#   the training set (317 CDs).
#
# Reproducibility:
#   set.seed(2026) is used for the random split, so the same 15 CDs are
#   held out on every run.
#
# Sections:
#   1. Random 15-CD hold-out split
#   2. Refit 4 trees on the remaining ~303 CDs
#   3. Compute per-CD residuals on the held-out set
#   4. Aggregate hold-out R² per outcome
# ══════════════════════════════════════════════════════════════════════════════


# ── 1. Random 15-CD hold-out split ──────────────────────────────────────────

set.seed(2026)
holdout_indices <- sample(1:nrow(training_set), 15)

train_subset  <- training_set[-holdout_indices, ]
holdout       <- training_set[holdout_indices, ]

cat("Train subset size:", nrow(train_subset), "CDs\n")
cat("Hold-out size:    ", nrow(holdout), "CDs\n")


# ── 2. Refit 4 trees on the remaining ~303 CDs ─────────────────────────────
# Same predictor set and control parameters as Script 19A.

trees_ho <- list()

trees_ho <- list()
trees_ho$dem     <- rpart(fml("dem_share"),     data = train_subset, method = "anova", control = control_params)
trees_ho$rep     <- rpart(fml("rep_share"),     data = train_subset, method = "anova", control = control_params)
trees_ho$other   <- rpart(fml("other_share"),   data = train_subset, method = "anova", control = control_params)
trees_ho$no_vote <- rpart(fml("no_vote_share"), data = train_subset, method = "anova", control = control_params)

cat("\n══ Hold-out trees fit ══\n")
cat("dem:     ", length(unique(trees_ho$dem$where)),     "leaves\n")
cat("rep:     ", length(unique(trees_ho$rep$where)),     "leaves\n")
cat("other:   ", length(unique(trees_ho$other$where)),   "leaves\n")
cat("no_vote: ", length(unique(trees_ho$no_vote$where)), "leaves\n")


# ── 3. Compute per-CD residuals on the hold-out set ────────────────────────

holdout_preds <- holdout %>%
  mutate(
    pred_dem     = predict(trees_ho$dem,     newdata = holdout),
    pred_rep     = predict(trees_ho$rep,     newdata = holdout),
    pred_other   = predict(trees_ho$other,   newdata = holdout),
    pred_no_vote = predict(trees_ho$no_vote, newdata = holdout),
    
    resid_dem     = dem_share      - pred_dem,
    resid_rep     = rep_share      - pred_rep,
    resid_other   = other_share    - pred_other,
    resid_no_vote = no_vote_share  - pred_no_vote,
    
    abs_err_total = abs(resid_dem) + abs(resid_rep) + 
      abs(resid_other) + abs(resid_no_vote)
  ) %>%
  select(state_cd, contestation,
         dem_share, pred_dem, resid_dem,
         rep_share, pred_rep, resid_rep,
         other_share, pred_other, resid_other,
         no_vote_share, pred_no_vote, resid_no_vote,
         abs_err_total) %>%
  arrange(desc(abs_err_total))

cat("\n══ Hold-out predictions and residuals (worst-to-best by total abs error) ══\n")
print(holdout_preds, n = Inf, width = Inf)


# ── 4. Aggregate hold-out R² per outcome ───────────────────────────────────

cat("dem:    ", round(r2(holdout_preds$dem_share,     holdout_preds$pred_dem),     4), "\n")
cat("rep:    ", round(r2(holdout_preds$rep_share,     holdout_preds$pred_rep),     4), "\n")
cat("other:  ", round(r2(holdout_preds$other_share,   holdout_preds$pred_other),   4), "\n")
cat("no_vote:", round(r2(holdout_preds$no_vote_share, holdout_preds$pred_no_vote), 4), "\n")


holdout_r2 <- tibble(
  outcome = c("dem","rep","other","no_vote"),
  r2 = c(r2(holdout_preds$dem_share,     holdout_preds$pred_dem),
         r2(holdout_preds$rep_share,     holdout_preds$pred_rep),
         r2(holdout_preds$other_share,   holdout_preds$pred_other),
         r2(holdout_preds$no_vote_share, holdout_preds$pred_no_vote)))
saveRDS(holdout_r2, file.path(processed_dir, "holdout_r2.rds"))

# ══════════════════════════════════════════════════════════════════════════════
# SCRIPT 19C: Apply CART trees to prediction set (imputation)
# ══════════════════════════════════════════════════════════════════════════════
#
# Purpose:
#   Apply the four trees from Script 19A to the prediction-set CDs (~117
#   genuinely redistricted CDs with no valid 2024 House shares) to impute
#   their vote shares. Training-set CDs are unchanged.
#
# Design decisions:
#
#   No normalization at this stage:
#     The four trees are fit independently on their respective outcomes,
#     so their raw predictions do not necessarily sum to 1 per CD. Per
#     team guidance, no normalization is applied here. The simplex
#     constraint is enforced downstream during MrsP raking / poststrat.
#
#   is_imputed flag:
#     A boolean column is added so downstream code (or human readers) can
#     easily distinguish CDs whose shares come from actual 2024 results
#     versus CART imputation. Equivalent to training_eligibility ==
#     "prediction_set", but explicit and semantically distinct.
#
#   Output file naming:
#     Saved as training_table_v2.rds (NOT overwriting training_table.rds).
#     This preserves the pre-imputation baseline for auditing.
#
# Inputs:
#   training_table.rds  (from Script 18C — the pre-imputation baseline)
#   trees.rds           (from Script 19A — 4 rpart models)
#
# Output:
#   training_table_v2.rds — same schema as training_table.rds plus:
#     - dem_share, rep_share, other_share, no_vote_share overwritten for
#       prediction-set CDs (training-set CDs unchanged)
#     - new column: is_imputed (TRUE for prediction set, FALSE otherwise)
#
# Sections:
#   1. Load inputs
#   2. Split training vs prediction rows
#   3. Predict shares for prediction rows
#   4. Merge back and add is_imputed flag
#   5. Validate: no negative shares, simplex sum diagnostics
#   6. Save training_table_v2.rds
# ══════════════════════════════════════════════════════════════════════════════


# ── 1. Load inputs ──────────────────────────────────────────────────────────

training_table <- readRDS(file.path(processed_dir, "training_table.rds")) %>%
                  select(-any_of("is_imputed"))


trees <- readRDS(file.path(processed_dir, "trees.rds"))


cat("Loaded training_table:", nrow(training_table), "rows\n")
cat("Loaded trees:", length(trees), "models (dem, rep, other, no_vote)\n\n")


# ── 2. Split training vs prediction rows ────────────────────────────────────

training_rows   <- training_table %>% filter(training_eligibility == "training_set")
prediction_rows <- training_table %>% filter(training_eligibility == "prediction_set")

cat("Training rows (kept as-is):  ", nrow(training_rows),   "\n")
cat("Prediction rows (to impute): ", nrow(prediction_rows), "\n")

# ── 3. Predict shares for prediction rows ───────────────────────────────────
# Each tree predicts one share. The 4 predictions per CD are independent —
# no normalization applied (see header for rationale).

prediction_rows <- prediction_rows %>%
  mutate(
    dem_share     = predict(trees$dem,     newdata = .),
    rep_share     = predict(trees$rep,     newdata = .),
    other_share   = predict(trees$other,   newdata = .),
    no_vote_share = predict(trees$no_vote, newdata = .)
  )


# ── 4. Merge back and add is_imputed flag ───────────────────────────────────

training_rows <- training_rows %>% mutate(is_imputed = FALSE)
prediction_rows <- prediction_rows %>% mutate(is_imputed = TRUE)

training_table_v2 <- bind_rows(training_rows, prediction_rows)

cat("\nCombined training_table_v2 rows:", nrow(training_table_v2), 
    "(expect 435)\n")
cat("Imputed rows: ", sum(training_table_v2$is_imputed), "\n")
cat("Actual rows:  ", sum(!training_table_v2$is_imputed), "\n")


# ── 5. Validate: no negative shares, simplex sum diagnostics ────────────────

cat("\n══ Negative-share check on imputed rows ══\n")
neg_check <- training_table_v2 %>%
  filter(is_imputed) %>%
  summarise(
    neg_dem     = sum(dem_share     < 0),
    neg_rep     = sum(rep_share     < 0),
    neg_other   = sum(other_share   < 0),
    neg_no_vote = sum(no_vote_share < 0)
  )
print(neg_check)

cat("\n══ Simplex sum diagnostics per CD ══\n")
cat("(For information only — no normalization at this stage;\n")
cat(" simplex constraint enforced later during MrsP raking.)\n\n")

simplex_sums <- training_table_v2 %>%
  mutate(sum_shares = dem_share + rep_share + other_share + no_vote_share) %>%
  group_by(is_imputed) %>%
  summarise(
    min_sum    = round(min(sum_shares), 4),
    median_sum = round(median(sum_shares), 4),
    max_sum    = round(max(sum_shares), 4),
    n          = n()
  )
print(simplex_sums)

saveRDS(simplex_sums, file.path(processed_dir, "simplex_sums.rds"))


# ── 6. Save training_table_v2.rds ───────────────────────────────────────────

saveRDS(training_table_v2, file.path(processed_dir, "training_table_v2.rds"))
cat("\nSaved training_table_v2.rds (", nrow(training_table_v2), "CDs)\n")
cat("Columns:", paste(names(training_table_v2), collapse = ", "), "\n")



