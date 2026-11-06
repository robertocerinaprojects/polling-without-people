# ══════════════════════════════════════════════════════════════════════════════
# SCRIPT 20: Package demographic stratification frame for MrsP delivery
#
# Purpose:
#   Package pums_demographic_cells.rds as the deliverable stratification
#   frame. This is the ~498K-cell demographic frame produced in Script 11
#   (with state_abbrv / state_cd added in Script 14). It's the input to
#   the MrsP poststratification step.
#
# Deliverables (in Data_Final/):
#   - stratification_frame_2026_preMrsP.csv
#   - stratification_frame_2026_preMrsP.rds
#
# Note: no data transformation happens here. Just diagnostics + save under
# a deliverable-appropriate filename.
# ══════════════════════════════════════════════════════════════════════════════


library(here)
library(tidyverse)

# ── Folder paths ────────────────────────────────────────────────────────────
processed_dir <- here("Data_Processed")
final_dir     <- here("Data_Final")


# ── 1. Load and diagnostic ──────────────────────────────────────────────────

pums_demographic_cells <- readRDS(file.path(processed_dir, "pums_demographic_cells.rds"))


cat("══ Structure ══\n")
cat("Rows:", nrow(pums_demographic_cells), "\n")
cat("Cols:", ncol(pums_demographic_cells), "\n\n")

cat("Column names and types:\n")
print(sapply(pums_demographic_cells, class))

cat("\n══ Sample rows ══\n")
print(head(pums_demographic_cells, 5))

cat("\n══ Weighted population sum ══\n")
cat("Total cell_pop:", round(sum(pums_demographic_cells$cell_pop), 0), 
    "(expect ~240.45M)\n")

cat("\n══ Geographic coverage ══\n")
cat("Unique states:  ", n_distinct(pums_demographic_cells$state_cat), "(expect 50)\n")
cat("Unique state_cd:", n_distinct(pums_demographic_cells$state_cd),   "(expect 435)\n")

cat("\n══ Cell-size distribution ══\n")
cat("Min cell_pop:    ", round(min(pums_demographic_cells$cell_pop), 2), "\n")
cat("Median cell_pop: ", round(median(pums_demographic_cells$cell_pop), 2), "\n")
cat("Mean cell_pop:   ", round(mean(pums_demographic_cells$cell_pop), 2), "\n")
cat("Max cell_pop:    ", round(max(pums_demographic_cells$cell_pop), 0), "\n")


# ── 2. Save ─────────────────────────────────────────────────────────────────

write_csv(pums_demographic_cells,
          file.path(final_dir, "stratification_frame_2026_preMrsP.csv"))
saveRDS(pums_demographic_cells,
        file.path(final_dir, "stratification_frame_2026_preMrsP.rds"))

cat("\nSaved stratification_frame_2026_preMrsP.csv and .rds\n")
cat("File size (CSV):",
    round(file.info(file.path(final_dir, "stratification_frame_2026_preMrsP.csv"))$size / 1e6, 2),
    "MB\n")
