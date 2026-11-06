# ══════════════════════════════════════════════════════════════════════════════
# SCRIPT 11: Cell Aggregation for Poststratification
#
# Purpose: Collapse the row-level PUMS data into one row per demographic cell
#          (state × CD × age × gender × race × hispanic × education) with the
#          summed weighted population per cell. 
#
# Note: this is the demographic-only frame. The MrsP frame requires
# expanding this with past vote (vote_2024) as an additional cell dimension,
# weighted by P(vote | demographics, CD) from the CES regression.
#
# Logic:
#   - Each row in pums_crosswalked is a person × CD assignment, with
#     PERWT_adj = ACS person weight × afact (the CD allocation fraction).
#   - Aggregate by all cell-defining variables, summing PERWT_adj within
#     each unique cell.
#   - Output: one row per cell with cell_pop = sum of PERWT_adj.
#
# Inputs:
#   - pums_crosswalked_harmonized.rds (from Script 10)
#
# Output:
#   - pums_demographic_cells.rds
#     Columns: state_cat, cd_cat, age_cat, gender_cat, race_cat,
#              hispanic_cat, educ_cat, cell_pop
#
# Sections:
#   1. Load harmonized PUMS
#   2. Aggregate to cell level
#   3. Validate population preserved
#   4. Cell-size distribution diagnostic
#   5. Save
# ══════════════════════════════════════════════════════════════════════════════

library(tidyverse)
library(data.table)
library(here)       

# ── 1. Load harmonized PUMS from disk ────────────────────────────────────────


# ── Folder paths ────────────────────────────────────────────────────────────
raw_dir       <- here("Data_Raw")
processed_dir <- here("Data_Processed")

# ── Load harmonized pums crosswalk file ─────────────────────────────────────────────────────

pums_frame <- readRDS(file.path(processed_dir, "pums_crosswalked_harmonized.rds"))

cat("══ Loaded PUMS ══\n")
cat("Rows:", nrow(pums_frame), "\n")
cat("Cols:", ncol(pums_frame), "\n")


# ── 2. Aggregate to cell level ───────────────────────────────────────────────
# Cell-defining variables (must match exactly what we'll use in modeling):
#   state_cat, cd_cat -- geography
#   age_cat -- 14 age bins
#   gender_cat -- Male / Female
#   race_cat -- 5 categories
#   hispanic_cat -- Hispanic / Not Hispanic
#   educ_cat -- 6 levels
#
# Total possible cells: 435 × 14 × 2 × 5 × 2 × 6 = 730,800
# Actual cells (after dropping empties): less because many demographic
# combinations don't exist in any geography (e.g. an 83+ Native American
# Hispanic post-grad in CD 27 might have zero population)

pums_demographic_cells <- pums_frame %>%
  group_by(state_cat, cd_cat, age_cat, gender_cat, 
           race_cat, hispanic_cat, educ_cat) %>%
  summarise(
    cell_pop = sum(PERWT_adj),
    .groups = "drop"
  )

cat("\n══ Cell aggregation results ══\n")
cat("Number of cells (non-empty):", nrow(pums_demographic_cells), "\n")
cat("Theoretical max cells:       730,800\n")
cat("Cells filled:                ", 
    round(100 * nrow(pums_demographic_cells) / 730800, 1), "%\n")

# ── 3. Validation: total population preserved ────────────────────────────────
cat("\n══ Population check ══\n")
cat("PUMS total PERWT_adj sum:    ", 
    round(sum(pums_frame$PERWT_adj), 0), "\n")
cat("Aggregated cell_pop sum:     ", 
    round(sum(pums_demographic_cells$cell_pop), 0), "\n")
cat("Difference:                  ", 
    round(sum(pums_demographic_cells$cell_pop) - sum(pums_frame$PERWT_adj), 0), "\n")


# ── 4. Cell-size distribution ────────────────────────────────────────────────
# Sparsity matters for MrP -- very small cells produce unstable estimates
# but partial pooling handles this. Worth knowing the distribution.

cat("\n══ Cell-size distribution ══\n")
cat("Min cell_pop:    ", round(min(pums_demographic_cells$cell_pop), 2), "\n")
cat("Median cell_pop: ", round(median(pums_demographic_cells$cell_pop), 2), "\n")
cat("Mean cell_pop:   ", round(mean(pums_demographic_cells$cell_pop), 2), "\n")
cat("Max cell_pop:    ", round(max(pums_demographic_cells$cell_pop), 0), "\n")

cat("\nCell-size quantiles:\n")
print(round(quantile(pums_demographic_cells$cell_pop, probs = c(0.01, 0.1, 0.25, 0.5, 0.75, 0.9, 0.99)), 2))

# How many cells have very tiny populations (< 1 person effectively)?
cat("\nCells with cell_pop < 1:    ", sum(pums_demographic_cells$cell_pop < 1), "\n")
cat("Cells with cell_pop < 10:   ", sum(pums_demographic_cells$cell_pop < 10), "\n")
cat("Cells with cell_pop < 100:  ", sum(pums_demographic_cells$cell_pop < 100), "\n")


# ── 5. Save the poststratification frame ─────────────────────────────────────
saveRDS(pums_demographic_cells, file.path(processed_dir, "pums_demographic_cells.rds"))

cat("\nSaved pums demographic cells frame\n")
