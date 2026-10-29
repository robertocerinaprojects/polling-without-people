
# ══════════════════════════════════════════════════════════════════════════════
# SCRIPT 15: Compute CD-level demographic proportions
#
# Purpose:
#   For each of the 435 congressional districts, compute the proportion of
#   weighted population in each demographic category. This produces a
#   CD-level dataset where each row is one CD with ~29 demographic feature
#   columns, used as predictors in Roberto's CART inheritance model.
#
# Strategy:
#   For each demographic variable (age, gender, race, hispanic, educ):
#     1. Aggregate cell_pop by (state_cd, category)
#     2. Compute proportion within each state_cd (sums to 1 per CD)
#     3. Pivot wider so each category value becomes a column
#   Then join all five wide tables together on state_cd, plus CD total pop.
#
# Naming: pct_age_18_22, pct_male, pct_race_white, pct_hisp_hispanic,
#         pct_educ_post_grad, etc.
#
# Inputs:
#   - pums_demographic_cells.rds (read from disk; ~498K rows, one per
#     unique demographic × geographic combination, with cell_pop weighted
#     population and state_cd identifier)
#
# Output:
#   - cd_demographics.rds (435 rows, one per CD, with:
#       state_cd, cd_pop, and ~29 demographic proportion columns)
#
# Sections:
#   1. Load pums_demographic_cells if not in memory
#   2. Clean factor levels into column-name-friendly strings
#   3. Helper function: compute_proportions()
#   4. Compute proportions for each demographic variable
#   5. CD-level total population
#   6. Combine all proportion tables into one CD-level dataset
#   7. Verification
#   8. Save
# ══════════════════════════════════════════════════════════════════════════════

library(tidyverse)

# ── 1. Load latest stratification frame/demographic cells from disk ────────────────
# pums_demographic_cells is the canonical poststratification frame: one row
# per (state, CD, age, gender, race, hispanic, education) cell, with cell_pop
# as the weighted population in that cell. This is derived from pums_frame
# (the row-level PUMS) and is the smaller, modeling-ready version.

# Always read fresh from disk to ensure idempotency
pums_demographic_cells <- readRDS(file.path(processed_dir, "pums_demographic_cells.rds"))
cat("Loaded pums_demographic_cells fresh from disk.\n")  

cat("Rows:", nrow(pums_demographic_cells), "\n")
cat("Cols:", ncol(pums_demographic_cells), "\n")
cat("Population sum:", round(sum(pums_demographic_cells$cell_pop)), "\n")
cat("Unique state+CD combos:", 
    n_distinct(paste(pums_demographic_cells$state_cat, 
                     pums_demographic_cells$cd_cat)), "\n")



# ── 2. Clean factor levels into column-name-friendly strings ────────────────
# Factor levels contain hyphens, spaces, slashes, and "+" symbols that don't
# work cleanly as R column names. We mutate the factor variables to use
# underscored, lowercase strings that will produce valid column names when
# we pivot wider.

pums_for_aggregation <- pums_demographic_cells %>%
  mutate(
    # Age: "18-22" → "18_22", "83+" → "83_plus"
    age_cat = as.character(age_cat) %>%
      str_replace_all("-", "_") %>%
      str_replace("\\+", "_plus"),
    
    # Gender: "Male" → "male", "Female" → "female"
    gender_cat = tolower(as.character(gender_cat)),
    
    # Race: "White" → "white", "Native American" → "native_american",
    #       "Other/Multi" → "other_multi"
    race_cat = as.character(race_cat) %>%
      tolower() %>%
      str_replace_all(" ", "_") %>%
      str_replace_all("/", "_"),
    
    # Hispanic: "Hispanic" → "hispanic", "Not Hispanic" → "not_hispanic"
    hispanic_cat = tolower(as.character(hispanic_cat)) %>%
      str_replace_all(" ", "_"),
    
    # Education: "No HS" → "no_hs", "HS grad" → "hs_grad", 
    #            "Some college" → "some_college", "2-year" → "two_year",
    #            "4-year" → "four_year", "Post-grad" → "post_grad"
    educ_cat = as.character(educ_cat) %>%
      tolower() %>%
      str_replace_all(" ", "_") %>%
      str_replace_all("-", "_") %>%
      str_replace("^2_year$", "two_year") %>%
      str_replace("^4_year$", "four_year")
  )

# Quick check: confirm the new factor levels look right
cat("══ Cleaned factor levels ══\n")
cat("age_cat:     ", paste(sort(unique(pums_for_aggregation$age_cat)), collapse = ", "), "\n")
cat("gender_cat:  ", paste(sort(unique(pums_for_aggregation$gender_cat)), collapse = ", "), "\n")
cat("race_cat:    ", paste(sort(unique(pums_for_aggregation$race_cat)), collapse = ", "), "\n")
cat("hispanic_cat:", paste(sort(unique(pums_for_aggregation$hispanic_cat)), collapse = ", "), "\n")
cat("educ_cat:    ", paste(sort(unique(pums_for_aggregation$educ_cat)), collapse = ", "), "\n")


# ── 3. Helper function to compute CD-level proportions for one variable ─────
# 
# Takes a data frame, the variable name (as a string), and a column-name
# prefix. Returns a wide-format table with one row per state_cd and one
# column per category of the variable, containing the proportion of that
# CD's population in that category.
#
# The !!sym(var_name) syntax is dplyr's "tidy evaluation" -- it lets us
# pass a variable name as a string and use it inside group_by() and
# pivot_wider() as if we'd typed the name directly.

compute_proportions <- function(data, var_name, prefix) {
  data %>%
    # Group by CD and the demographic variable
    group_by(state_cd, !!sym(var_name)) %>%
    
    # Sum population in each (CD, category) combination
    summarise(cat_pop = sum(cell_pop), .groups = "drop_last") %>%
    
    # Compute proportion within each CD
    # (still grouped by state_cd from drop_last, so sum() is per-CD)
    mutate(prop = cat_pop / sum(cat_pop)) %>%
    
    # Keep only what we need
    select(state_cd, !!sym(var_name), prop) %>%
    
    # Reshape: each category becomes a column with proportion as its value
    pivot_wider(
      names_from   = !!sym(var_name),
      values_from  = prop,
      names_prefix = prefix,
      values_fill  = 0   # missing (CD, category) combos get 0
    )
}


# ── 4. Compute proportions for each demographic variable ─────────────────────

age_props <- compute_proportions(
  pums_for_aggregation, "age_cat", "pct_age_"
)

gender_props <- compute_proportions(
  pums_for_aggregation, "gender_cat", "pct_"
)

race_props <- compute_proportions(
  pums_for_aggregation, "race_cat", "pct_race_"
)

hispanic_props <- compute_proportions(
  pums_for_aggregation, "hispanic_cat", "pct_hisp_"
)

educ_props <- compute_proportions(
  pums_for_aggregation, "educ_cat", "pct_educ_"
)


# ── 5. CD-level total population (useful for diagnostics) ────────────────────
cd_pops <- pums_demographic_cells %>%
  group_by(state_cd) %>%
  summarise(cd_pop = sum(cell_pop), .groups = "drop")


# ── 6. Combine all proportion tables ─
# Ensure we start fresh by dropping any previously created proportion columns
cd_demographics <- cd_pops %>%
  select(state_cd, cd_pop) %>% # Keep only the core identifiers
  left_join(age_props,      by = "state_cd") %>%
  left_join(gender_props,   by = "state_cd") %>%
  left_join(race_props,     by = "state_cd") %>%
  left_join(hispanic_props, by = "state_cd") %>%
  left_join(educ_props,     by = "state_cd")


# ── 7. Verification ──────────────────────────────────────────────────────────

cat("\n══ cd_demographics structure ══\n")
cat("Rows (CDs):", nrow(cd_demographics), "(expect 435)\n")
cat("Columns:   ", ncol(cd_demographics), "\n")

cat("\nColumn names:\n")
print(names(cd_demographics))

cat("\n══ First few rows ══\n")
print(head(cd_demographics, 3))

# Each demographic variable's proportions should sum to 1 within each CD
cat("\n══ Proportion sum checks ══\n")

# Get column names by prefix
age_cols      <- grep("^pct_age_",  names(cd_demographics), value = TRUE)
gender_cols   <- c("pct_male", "pct_female")
race_cols     <- grep("^pct_race_", names(cd_demographics), value = TRUE)
hispanic_cols <- grep("^pct_hisp_", names(cd_demographics), value = TRUE)
educ_cols     <- grep("^pct_educ_", names(cd_demographics), value = TRUE)

cat("Age proportions (n=", length(age_cols), "), CD sums (should all be 1):\n", sep = "")
cat("  Range:", round(min(rowSums(cd_demographics[age_cols])), 4), "to",
    round(max(rowSums(cd_demographics[age_cols])), 4), "\n")

cat("Gender proportions (n=", length(gender_cols), "), CD sums (should all be 1):\n", sep = "")
cat("  Range:", round(min(rowSums(cd_demographics[gender_cols])), 4), "to",
    round(max(rowSums(cd_demographics[gender_cols])), 4), "\n")

cat("Race proportions (n=", length(race_cols), "), CD sums (should all be 1):\n", sep = "")
cat("  Range:", round(min(rowSums(cd_demographics[race_cols])), 4), "to",
    round(max(rowSums(cd_demographics[race_cols])), 4), "\n")

cat("Hispanic proportions (n=", length(hispanic_cols), "), CD sums (should all be 1):\n", sep = "")
cat("  Range:", round(min(rowSums(cd_demographics[hispanic_cols])), 4), "to",
    round(max(rowSums(cd_demographics[hispanic_cols])), 4), "\n")

cat("Education proportions (n=", length(educ_cols), "), CD sums (should all be 1):\n", sep = "")
cat("  Range:", round(min(rowSums(cd_demographics[educ_cols])), 4), "to",
    round(max(rowSums(cd_demographics[educ_cols])), 4), "\n")

cat("\nTotal feature columns:", 
    length(age_cols) + length(gender_cols) + length(race_cols) + 
      length(hispanic_cols) + length(educ_cols), "\n")


# ── 8. Save ──────────────────────────────────────────────────────────────────
saveRDS(cd_demographics,file.path(processed_dir, "cd_demographics.rds"))

cat("\nSaved cd_demographics.rds\n")
