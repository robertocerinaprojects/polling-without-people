# ══════════════════════════════════════════════════════════════════════════════
# SCRIPT 21: Package area-level vote shares for MrsP delivery
#
# Purpose:
#   Package training_table_v2.rds as the deliverable area-level vote shares.
#   This is the CD-level table with predicted vote shares (from Script 19C's
#   CART imputation), demographic features, state pres features, and
#   modeling flags — the "prior" for MrsP that raking will adjust.
#
# Deliverables (in Data_Final/):
#   - area_level_vote_shares.csv
#   - area_level_vote_shares.rds
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

training_table <- readRDS(file.path(processed_dir, "training_table_v2.rds"))


cat("══ Structure ══\n")
cat("Rows:", nrow(training_table), "(expect 435)\n")
cat("Cols:", ncol(training_table), "\n\n")

cat("Column names:\n")
print(names(training_table))

cat("\n══ Sample rows ══\n")
print(head(training_table, 5))

cat("\n══ is_imputed and is_redistricted breakdown ══\n")
training_table %>% count(is_imputed, is_redistricted) %>% print()

cat("\n══ training_eligibility breakdown ══\n")
print(table(training_table$training_eligibility, useNA = "always"))

cat("\n══ contestation breakdown ══\n")
print(table(training_table$contestation, useNA = "always"))

cat("\n══ Vote share ranges ══\n")
for (col in c("dem_share", "rep_share", "other_share", "no_vote_share")) {
  vals <- training_table[[col]]
  cat(sprintf("%-14s min=%.3f  median=%.3f  max=%.3f\n",
              col, min(vals), median(vals), max(vals)))
}

cat("\n══ Simplex sum per CD (sanity check) ══\n")
share_sums <- training_table %>%
  mutate(s = dem_share + rep_share + other_share + no_vote_share) %>%
  group_by(is_imputed) %>%
  summarise(
    min_sum    = round(min(s), 4),
    median_sum = round(median(s), 4),
    max_sum    = round(max(s), 4),
    n          = n(),
    .groups    = "drop"
  )
print(share_sums)

cat("\n══ NA counts per column ══\n")
print(colSums(is.na(training_table)))


# ── 2. Save ─────────────────────────────────────────────────────────────────

write_csv(training_table, file.path(final_dir, "area_level_vote_shares.csv"))
saveRDS(training_table,  file.path(final_dir, "area_level_vote_shares.rds"))

cat("\nSaved area_level_vote_shares.csv and .rds\n")
cat("File size (CSV):",
    round(file.info(file.path(final_dir, "area_level_vote_shares.csv"))$size / 1e6, 2),
    "MB\n")
