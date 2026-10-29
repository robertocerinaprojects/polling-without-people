## Script 15
### Purpose: Compute CD-level demographic proportions

For each of the 435 congressional districts, compute the proportion of weighted population in each demographic category. Produces a CD-level feature dataset with ~29 columns (one per category), used as predictors in Roberto's CART inheritance model (Script 18+).

### Inputs and output
- Input: `pums_demographic_cells.rds` (from Script 14; ~498K rows, one per unique demographic × geographic cell)
- Output: `cd_demographics.rds` (435 rows, one per CD, with ~29 demographic proportion columns plus CD total population)

### Motivation

The CART inheritance model in Script 18 predicts CD-level vote shares from CD-level demographic characteristics. To train it, we need one row per CD with its demographic composition summarized as proportions. Each demographic dimension (age, gender, race, hispanic, education) becomes a set of proportion columns that sum to 1.0 within each CD.

For example, "TX-1" gets a row containing (approximately):
- pct_age_18_22 = 0.05, pct_age_23_27 = 0.07, ..., pct_age_83_plus = 0.03
- pct_male = 0.49, pct_female = 0.51
- pct_race_white = 0.72, pct_race_black = 0.11, ..., pct_race_other_multi = 0.02
- pct_hisp_hispanic = 0.22, pct_hisp_not_hispanic = 0.78
- pct_educ_no_hs = 0.14, pct_educ_hs_grad = 0.32, ..., pct_educ_post_grad = 0.08
- cd_pop = 542,318 (weighted CVAP)

### Column naming convention

Factor levels contain characters that don't work cleanly as R column names (hyphens, spaces, slashes, "+" symbols). The script cleans them into underscored lowercase strings:

| Original | Cleaned |
|---|---|
| "18-22" | "18_22" |
| "83+" | "83_plus" |
| "Male" | "male" |
| "Native American" | "native_american" |
| "Other/Multi" | "other_multi" |
| "Not Hispanic" | "not_hispanic" |
| "No HS" | "no_hs" |
| "2-year" | "two_year" |
| "4-year" | "four_year" |
| "Post-grad" | "post_grad" |

Column prefixes distinguish the variables:

| Variable | Prefix | Example column |
|---|---|---|
| age_cat | pct_age_ | pct_age_18_22 |
| gender_cat | pct_ | pct_male |
| race_cat | pct_race_ | pct_race_white |
| hispanic_cat | pct_hisp_ | pct_hisp_hispanic |
| educ_cat | pct_educ_ | pct_educ_post_grad |

Note the asymmetry: `gender_cat` uses just `pct_` (not `pct_gender_`) because column names like `pct_male` and `pct_female` are self-explanatory and read more naturally in output. Downstream diagnostic code hardcodes the gender column names accordingly.

### Methodology

For each demographic variable, the same three-step process is applied via the helper function `compute_proportions()`:

1. **Aggregate**: `group_by(state_cd, category)` and sum `cell_pop`. This gives the total weighted population in each (CD, category) cell.

2. **Normalize**: Compute proportion within each `state_cd`. Since `group_by(...)` uses `.groups = "drop_last"`, the summarise leaves the data still grouped by `state_cd`. The subsequent `mutate(prop = cat_pop / sum(cat_pop))` computes the proportion per-CD.

3. **Pivot wider**: Reshape so each category becomes a column with the proportion as its value. `values_fill = 0` handles the edge case of missing (CD, category) combinations (e.g., a CD with no post-graduate residents in the PUMS sample) by filling with 0 rather than NA.

The result of each per-variable pivot is a wide table with 435 rows (one per CD) and one column per category. All five per-variable tables are then joined together on `state_cd`, along with CD total population, to produce the final `cd_demographics` dataset.

### CD-level total population

`cd_pop` is included as a column alongside the proportions. It's not a feature for the CART model (which uses only proportions), but it's useful for:
- Diagnostic checks (does the CD population look reasonable?)
- Weighting CDs by size if downstream analyses need it
- Cross-referencing against other sources

The full stratification frame has ~240.45M weighted CVAP; the CD-level sum should match this within floating-point tolerance.

### Validation

For each demographic variable, the script confirms the proportion columns sum to 1.0 within each CD:
Age proportions (n=14), CD sums (should all be 1):
Range: 1.0000 to 1.0000
Gender proportions (n=2), CD sums (should all be 1):
Range: 1.0000 to 1.0000
...

Any deviation from 1.0 (beyond floating-point rounding) would indicate a bug in the aggregation or pivot logic. Total number of feature columns is also reported for confirmation.

### Note on column count

Total feature columns: 14 (age) + 2 (gender) + 5 (race) + 2 (hispanic) + 6 (educ) = **29 columns**. Plus `state_cd` and `cd_pop` = 31 total columns in `cd_demographics`.

This is the demographic feature set for the CART model. Additional features (state-level presidential vote shares, contestation) get added in later scripts before the model is fit.