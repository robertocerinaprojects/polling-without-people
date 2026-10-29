# ══════════════════════════════════════════════════════════════════════════════
# SCRIPT 14: Add state abbreviations and state_cd identifier
#
# Purpose:
#   Create a human-readable unique identifier for each congressional district,
#   combining state abbreviation and CD number. Applied to BOTH PUMS
#   demographic cells (for the CD-level aggregation done in later scripts)
#   and CES (for consistency across both datasets).
#
# Examples: TX-1, FL-2, PA-1, CA-12
#
# Inputs:
#   - pums_demographic_cells (reloaded from disk)
#   - ces_with_cd_v2.rds (from Script 13)
#
# Outputs (both overwrite existing files):
#   - pums_demographic_cells.rds (with state_abbrv, state_cd added)
#   - ces_with_cd_v2.rds (with state_abbrv, state_cd added)
#
# Sections:
#   1. Build state FIPS → abbreviation lookup
#   2. Apply to pums_demographic_cells
#   3. Apply to ces_with_cd_v2
#   4. Save both with verification
# ══════════════════════════════════════════════════════════════════════════════


library(tidyverse)


# ── 1. Build state FIPS → abbreviation lookup ───────────────────────────────
# All 50 states (DC already excluded from our data).
# Using the standard US state FIPS codes.

state_fips_to_abb <- tibble(
  state_cat = c(
    1, 2, 4, 5, 6, 8, 9, 10, 12, 13, 15, 16, 17, 18, 19, 20,
    21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35,
    36, 37, 38, 39, 40, 41, 42, 44, 45, 46, 47, 48, 49, 50, 51,
    53, 54, 55, 56
  ),
  state_abbrv = c(
    "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA",
    "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME", "MD",
    "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ",
    "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC",
    "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY"
  )
)

cat("══ State FIPS → abbreviation lookup ══\n")
cat("States:", nrow(state_fips_to_abb), "\n")


# ── 2. Apply to pums_demographic_cells ──────────────────────────────────────




# ── 2. Apply to pums_demographic_cells ──────────────────────────────────────
pums_demographic_cells <- readRDS(file.path(processed_dir, "pums_demographic_cells.rds")) %>%
  select(-any_of(c("state_abbrv", "state_cd"))) %>% # IDEMPOTENCY FIX
  left_join(state_fips_to_abb, by = "state_cat") %>%
  mutate(state_cd = paste0(state_abbrv, "-", cd_cat))

# ── 3. Apply to ces_with_cd_v2 ──────────────────────────────────────────────
ces_with_cd_v2 <- readRDS(file.path(processed_dir, "ces_with_cd_v2.rds")) %>%
  select(-any_of(c("state_abbrv", "state_cd"))) %>% # IDEMPOTENCY FIX
  left_join(state_fips_to_abb, by = "state_cat") %>%
  mutate(state_cd = paste0(state_abbrv, "-", cd_cat))


cat("\n══ Verify pums_demographic_cells ══\n")
cat("Rows:", nrow(pums_demographic_cells), "\n")
cat("Unique state_cd values:", n_distinct(pums_demographic_cells$state_cd), "(expect 435)\n")
cat("NAs in state_abbrv:", sum(is.na(pums_demographic_cells$state_abbrv)), "\n")
cat("NAs in state_cd:   ", sum(is.na(pums_demographic_cells$state_cd)), "\n")

# Show sample of new column
cat("\nSample state_cd values:\n")
pums_demographic_cells %>%
  distinct(state_cat, cd_cat, state_abbrv, state_cd) %>%
  slice_sample(n = 10) %>%
  print()


# ── 3. Apply to ces_with_cd_v2 ──────────────────────────────────────────────
# Load if needed (using v2 which has the final renumbering applied)


ces_with_cd_v2 <- readRDS(file.path(processed_dir, "ces_with_cd_v2.rds"))
cat("Loaded.\n")


ces_with_cd_v2 <- ces_with_cd_v2 %>%
  left_join(state_fips_to_abb, by = "state_cat") %>%
  mutate(state_cd = paste0(state_abbrv, "-", cd_cat))


cat("\n══ Verify ces_with_cd_v2 ══\n")
cat("Rows:", nrow(ces_with_cd_v2), "\n")
cat("Unique respondents:", n_distinct(ces_with_cd_v2$caseid), "\n")
cat("Unique state_cd:", n_distinct(ces_with_cd_v2$state_cd), "(expect 435)\n")
cat("NAs in state_abbrv:", sum(is.na(ces_with_cd_v2$state_abbrv)), "\n")
cat("NAs in state_cd:", sum(is.na(ces_with_cd_v2$state_cd)), "\n")

cat("\nSample state_cd values:\n")
ces_with_cd_v2 %>%
  distinct(state_cat, cd_cat, state_abbrv, state_cd) %>%
  slice_sample(n = 10) %>%
  print()


# ── 4. Save both ──────────────────────────────────────────

saveRDS(pums_demographic_cells,file.path(processed_dir, "pums_demographic_cells.rds"))

saveRDS(ces_with_cd_v2, file.path(processed_dir, "ces_with_cd_v2.rds"))
