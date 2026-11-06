## Scripts 19A / 19B / 19C
### Purpose: CART model fitting, hold-out validation, and prediction-set imputation

This three-script sequence handles the CART inheritance model end-to-end: fit maximal trees on the training set (19A), validate their generalization via a randomized hold-out (19B), then apply them to impute vote shares for the prediction set (19C). The three scripts share a single R file since they use the same input data and CART logic.

### Pipeline overview

| Script | Purpose | Input | Output |
|---|---|---|---|
| 19A | Fit maximal trees on training set | `training_table.rds` | `trees.rds` + in-sample plots |
| 19B | Hold-out validation | `training_table.rds` | Console report only |
| 19C | Apply trees to prediction set | `training_table.rds`, `trees.rds` | `training_table_v2.rds` |

### Model architecture (shared by all three scripts)

Four separate rpart regression trees, one per outcome share. Modeling each share independently — rather than as a joint multivariate outcome — lets each tree find its own optimal partitions without being constrained by the others. The four-way simplex constraint (Dem + Rep + Other + No Vote = 1) is not enforced during training; it's enforced downstream during MrsP raking / poststratification.

**Predictors (34 total)**:

| Group | Count | Columns |
|---|---|---|
| Demographic proportions | 29 | pct_age_* (14), pct_male / pct_female (2), pct_race_* (5), pct_hisp_* (2), pct_educ_* (6) |
| State-level presidential shares | 4 | state_pres_dem_share, state_pres_rep_share, state_pres_other_share, state_pres_no_vote_share |
| Contestation flag | 1 | contestation (TRUE / FALSE) |

**rpart control parameters** (maximal trees, no pruning):

| Parameter | Value | Meaning |
|---|---|---|
| cp | 0 | No complexity-based pruning; grow to full depth |
| minsplit | 3 | Minimum 3 observations required to consider a split |
| minbucket | 1 | Minimum 1 observation allowed per terminal node |

Maximal trees are used deliberately at this stage — they show the maximum expressive capacity of the CART approach before any regularization. Pruning (via cross-validated cp) is deferred; if hold-out performance is acceptable, no pruning is applied. If it isn't, subsequent scripts (not yet in the pipeline) would introduce it.

**Why contestation as a feature, not a filter**: In uncontested CDs (where one major party doesn't field a candidate), the missing candidate translates directly to inflated `no_vote_share` — voters have fewer real choices and undervote at higher rates. Excluding uncontested CDs from training would discard information about one-party-dominated districts. Including them with the contestation flag lets the tree partition on this variable and learn distinct demographics→vote-share mappings for contested vs. uncontested contexts.

---

## Script 19A: Fit maximal trees on the training set

Fit the four "production" trees on all ~318 training-set CDs.

### Training set

CDs where `training_eligibility == "training_set"` — approximately 318 CDs:
- All CDs in the 43 stable-boundary states (DC already excluded)
- Essentially-unchanged CDs in the 7 redistricted states (~42, from Script 18A's inheritance table)

The remaining ~117 CDs (genuinely new geography) are the prediction set and are held out from training.

### Formula construction

Each tree uses `y ~ . -` shorthand with an explicit exclusion list, keeping only actual predictors:

Excluded from all four formulas:
- Identifiers: `state_cd`, `state_abbrv`, `cd_pop`
- Modeling flags: `is_redistricted`, `training_eligibility`
- The other three outcomes (so tree N doesn't accidentally use outcome M as a predictor)

Each tree sees 34 predictor columns and 1 outcome.

### In-sample R² validation

With maximal trees on ~318 CDs, in-sample R² is very close to 1 for all four outcomes. This is expected — maximal trees memorize the training data essentially perfectly. This is not a claim about generalization; that's tested in Script 19B.

Typical values seen empirically:

| Outcome | In-sample R² |
|---|---|
| dem | ~0.998 |
| rep | ~0.999 |
| other | ~0.998 |
| no_vote | ~0.968 |

The slightly lower `no_vote` R² reflects that uncontested CDs (where `no_vote_share` is systematically high) create high-variance training targets that even a maximal tree can't perfectly memorize.

### In-sample prediction plots

For each outcome, a scatter of actual vs. predicted values is generated. Points cluster tightly around the y=x line for maximal trees, confirming in-sample fit is nearly perfect.

Axis limits are fixed at (0, 0.6). Vote shares against CVAP typically fall in this range — even in landslide races, one party rarely captures more than 60% of CVAP due to turnout being 40-60%. Plots that would exceed 0.6 are clipped (rare, mostly `no_vote_share` in extreme uncontested races).

Plots are saved to `prediction_plots/` as `dem_predictions_plot.png`, etc.

### Output

`trees.rds` — a list of 4 rpart models with elements `$dem`, `$rep`, `$other`, `$no_vote`. These are the "production" trees used in Script 19C for imputation.

---

## Script 19B: Randomized hold-out validation

Test how well the CART approach generalizes to unseen CDs.

### Approach

Rather than k-fold cross-validation, a single randomized hold-out is used per team decision. This is a simpler diagnostic suitable for evaluating the maximal-tree approach.

- **Hold-out size**: 15 CDs (~5% of the training set)
- **Random seed**: 42 (reproducible split)

### Steps

1. Split training set into 303-CD train subset + 15-CD hold-out
2. Refit 4 trees on the train subset using the same control parameters and predictor set as Script 19A
3. Predict vote shares for the held-out CDs using the newly-fit trees
4. Compute per-CD residuals and aggregate R² per outcome

### Independence from Script 19A

Script 19B does NOT reuse `trees.rds` from Script 19A. It refits its own trees on the ~303-CD subset. This is essential — if 19A's trees were reused, evaluating them on the 15 held-out CDs would still be somewhat in-sample (those CDs were in the fit). Refitting on the subset ensures the held-out CDs are truly unseen.

### Hold-out R² findings

Typical values seen empirically (with seed = 42):

| Outcome | Hold-out R² | Interpretation |
|---|---|---|
| dem | ~0.65 | Reasonable generalization |
| rep | ~0.53 | Weaker but still meaningful |
| other | ~0.28 | Low — the "other" category has high variance and small sample support |
| no_vote | ~-0.49 | Dominated by a single outlier (NY-21) — see below |

The gap between in-sample R² (near 1.0) and hold-out R² is expected — maximal trees overfit. The key question is whether the hold-out R² is high enough that predictions on the prediction set are useful. Per team assessment, the answer is yes for dem/rep and acceptable for other/no_vote.

The negative `no_vote` R² is driven almost entirely by NY-21, a single hold-out CD whose actual `no_vote_share` sits far from any nearby training CD's value. This is a sampling artifact of the 15-CD hold-out — when NY-21 lands in the hold-out set, it dominates the error metric. Empirical investigation (not included in the current script but documented separately) confirmed that removing NY-21 raises `no_vote` hold-out R² to a positive value comparable to the other outcomes.

### Diagnostic output

The script prints per-CD residuals sorted by total absolute error, plus aggregated hold-out R² per outcome. No files are written.

---

## Script 19C: Apply trees to prediction set (imputation)

Use the trees from Script 19A to predict vote shares for the ~117 prediction-set CDs, then merge back with training-set CDs to create the imputed training table.

### Design decisions

**No normalization at this stage**: The four trees are fit independently on their respective outcomes, so their raw predictions do not necessarily sum to 1 per CD. Per team guidance, no normalization is applied here. The simplex constraint is enforced downstream during MrsP raking / poststratification. Simplex-sum diagnostics are still printed for informational purposes.

**`is_imputed` flag**: A boolean column is added so downstream code (and human readers) can easily distinguish CDs whose shares come from actual 2024 results (`is_imputed = FALSE`) versus CART imputation (`is_imputed = TRUE`). Equivalent to `training_eligibility == "prediction_set"` but explicit and semantically distinct.

**Output file naming**: Saved as `training_table_v2.rds`, NOT overwriting `training_table.rds`. This preserves the pre-imputation baseline for auditing and lets downstream code choose either version.

### Steps

1. Load `training_table.rds` and `trees.rds`
2. Split into `training_rows` (`!is_redistricted`) and `prediction_rows` (`is_redistricted`)
3. Predict all four shares for prediction rows using the trees
4. Add `is_imputed` column: FALSE for training rows, TRUE for prediction rows
5. Bind back into one table
6. Validate no negative shares, report simplex sum diagnostics
7. Save as `training_table_v2.rds`

### Validation

**Negative-share check**: All four predicted shares should be non-negative. Trees fit on non-negative outcomes typically produce non-negative predictions, but the check catches any degenerate cases.

**Simplex sum diagnostic** (informational):

| Row type | Expected sum |
|---|---|
| Training rows (unchanged) | Exactly 1.0 by construction |
| Prediction rows (imputed) | Approximately 1.0 but not exactly — deviations expected |

The reported ranges typically show:
- Training rows: min = max = 1.0
- Prediction rows: min ≈ 0.85, median ≈ 0.98, max ≈ 1.15 (illustrative)

Prediction-row sums deviate from 1.0 because the four trees are independent. Downstream raking enforces the constraint.

### Output

`training_table_v2.rds` — same schema as `training_table.rds` plus:
- Four share columns overwritten for prediction-set CDs (training-set CDs unchanged)
- New column: `is_imputed` (TRUE for prediction set, FALSE otherwise)

This is the file used by the MrsP raking / poststratification pipeline (subsequent scripts).