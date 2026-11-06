# ══════════════════════════════════════════════════════════════════════════════
# SCRIPT 05: Apply unified PUMA-to-CD crosswalk to PUMS records
#
# Purpose:
#   Join the cleaned PUMS data (from Scripts 01-03) to the unified PUMA-to-
#   2026-CD crosswalk (from Script 04), producing a person-level dataset
#   where each record carries a 2026 CD assignment and a population-adjusted
#   weight. This is the core dataset for subsequent CD-level aggregation
#   and stratification frame construction.
#
# Inputs:
#   - pums_clean.rds (from Script 03): 12,263,785 person records × 26 cols
#   - unified_crosswalk_2026.rds (from Script 04): ~4,144 PUMA × CD rows
#
# Output:
#   - pums_crosswalked.rds: ~20.6M rows × 29 cols
#     New columns added by the join: cd_2026 (int), afact (num),
#                                    PERWT_adj (num = PERWT × afact)
#
# Join logic:
#   - left_join on (STATEFIP ↔ state, PUMA ↔ puma22)
#   - relationship = "many-to-many" because both sides may have repeats:
#       many: PUMS has multiple records per PUMA (one per person)
#       many: crosswalk may have multiple rows per PUMA (split PUMAs)
#   - Person records in PUMAs that span multiple CDs are duplicated
#     across rows, one per candidate CD, with afact as the probability
#     of CD residence
#
# Adjusted weight:
#   PERWT_adj = PERWT × afact
#   - For PUMAs entirely in one CD (afact = 1): PERWT_adj = PERWT
#   - For split PUMAs: PERWT is distributed across CDs proportionally
#   - Sum of PERWT_adj across a person's rows = original PERWT (no loss)
#
# Validations:
#   - Row count increases as expected (split PUMAs contribute extra rows)
#   - Zero unmatched records (every PUMS PUMA has a crosswalk entry)
#   - Total weighted population preserved within floating-point rounding
#   - 436 unique state+CD combinations (435 voting House + DC)
#
# Notes:
#   - DC (STATEFIP=11, cd_2026=98) is retained at this stage; may be
#     filtered at the stratification frame construction stage
#   - The output is large (~320 MB RDS); CSV would be ~1.5-2 GB
# ══════════════════════════════════════════════════════════════════════════════


library(here)
library(tidyverse)

# ── Folder paths ────────────────────────────────────────────────────────────
processed_dir <- here("Data_Processed")

# ── Load inputs ──────────────────────────────────────────────────────────────
# Read cleaned PUMS file
library(here)
library(tidyverse)

processed_dir <- here("Data_Processed")

# Load inputs (from disk if not already in memory)
if (!exists("pums_clean")) {
  pums_clean <- readRDS(file.path(processed_dir, "pums_clean.rds"))
}
if (!exists("unified_crosswalk")) {
  unified_crosswalk <- readRDS(file.path(processed_dir, "unified_crosswalk_2026.rds"))
}


# ── 1. Join pums_clean to unified crosswalk ──────────────────────────────────
# Join key: STATEFIP (pums) = state (crosswalk)
#           PUMA (pums)     = puma22 (crosswalk)

pums_crosswalked <- pums_clean %>%
  left_join(
    unified_crosswalk,
    by = c("STATEFIP" = "state", "PUMA" = "puma22"),
    relationship = "many-to-many"
  )

cat("Rows before join:", nrow(pums_clean), "\n")
cat("Rows after join: ", nrow(pums_crosswalked), "\n")
cat("Row increase:    ", nrow(pums_crosswalked) - nrow(pums_clean), "\n")
cat("(increase expected -- split PUMA persons get multiple rows)\n")


# ── 2. Create adjusted person weight ─────────────────────────────────────────
# PERWT_adj = PERWT * afact
# Effective population weight for each person-CD assignment

pums_crosswalked <- pums_crosswalked %>%
  mutate(PERWT_adj = PERWT * afact)

cat("\nPERWT_adj summary:\n")
print(summary(pums_crosswalked$PERWT_adj))


# ── 3. Check for unmatched records ───────────────────────────────────────────
cat("\nUnmatched records (cd_2026 is NA):", 
    sum(is.na(pums_crosswalked$cd_2026)), "\n")

if(sum(is.na(pums_crosswalked$cd_2026)) > 0) {
  cat("\nUnmatched PUMA codes:\n")
  pums_crosswalked %>%
    filter(is.na(cd_2026)) %>%
    distinct(STATEFIP, PUMA) %>%
    print()
}


# ── 4. Verify weighted population preservation ───────────────────────────────
cat("\nWeighted population check:\n")
cat("Original PERWT sum:    ", sum(pums_clean$PERWT), "\n")
cat("PERWT_adj sum:         ", round(sum(pums_crosswalked$PERWT_adj), 0), "\n")
cat("Difference:            ", 
    round(sum(pums_crosswalked$PERWT_adj) - sum(pums_clean$PERWT), 0), "\n")


# ── 5. Quick sanity check on CD distribution ─────────────────────────────────
cat("\nTop 10 CDs by weighted population:\n")
pums_crosswalked %>%
  group_by(STATEFIP, cd_2026) %>%
  summarise(
    n_records  = n(),
    pop_weight = round(sum(PERWT_adj), 0),
    .groups = "drop"
  ) %>%
  arrange(desc(pop_weight)) %>%
  print(n = 10)

cat("\nTotal unique state+CD combinations:", 
    n_distinct(paste(pums_crosswalked$STATEFIP, pums_crosswalked$cd_2026)), "\n")


# ── 6. Final dimensions ──────────────────────────────────────────────────────
cat("\n── Crosswalked dataset ──\n")
cat("Dimensions:", nrow(pums_crosswalked), "rows x", 
    ncol(pums_crosswalked), "cols\n")
cat("Ready for cell aggregation.\n")


# Save
saveRDS(pums_crosswalked, file.path(processed_dir, "pums_crosswalked.rds"))

cat("Saved successfully.\n")
cat("RDS File size:", 
    round(file.size(file.path(processed_dir, "pums_crosswalked.rds")) / 1e6, 1), 
    "MB\n")
