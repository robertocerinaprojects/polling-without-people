# ══════════════════════════════════════════════════════════════════════════════
# SCRIPT 17: Compute state-level 2024 presidential vote shares (VAP denominator)
#
# Purpose: Aggregate 2024 presidential election results to state-level
#          4-feature vote shares. These serve as state-level covariates in
#          the CART inheritance model: for each CD, the state-level pres
#          shares are joined in and used alongside the CD's demographic
#          proportions as predictors of House vote shares.
#
# Why these 4 features:
#   State-level presidential outcomes are a strong signal of a district's
#   underlying partisan geography. Even in redistricting years, state pres
#   shares are stable and reflect the political character that maps to House
#   outcomes. Including them as CART predictors captures state-level fixed
#   effects.
#
#   The 4-feature format (dem / rep / other / no_vote against VAP) matches
#   the CD-level House share structure from Script 16B. Both target and
#   predictors are 4-simplex vote shares.
#
# Methodology:
#
#   1. State-level VAP comes from cd_demographics:
#        state_vap = sum(cd_pop) within state
#      This uses our PUMS-derived citizen voting-age population, matching
#      the denominator used in CD-level shares.
#
#   2. For each state, compute 4 shares from 2024 presidential data:
#        state_pres_dem_share      = dem_pres_votes      / state_vap
#        state_pres_rep_share      = rep_pres_votes      / state_vap
#        state_pres_other_share    = other_pres_votes    / state_vap
#        state_pres_no_vote_share  = (state_vap - total_pres_votes) / state_vap
#      These sum to 1 per state.
#
#   3. Party categorization (uses party_simplified from MIT dataset):
#        DEMOCRAT   → dem
#        REPUBLICAN → rep
#        everything else → other
#
#   4. DC excluded (no House seat, so no downstream use).
#
# Inputs:
#   - 1976-2024-president.csv (MIT Election Lab)
#   - cd_demographics.rds (used to compute state_vap)
#
# Output:
#   - state_pres_2024.rds (50 rows, 5 columns: state_abbrv + 4 shares)
#
# Sections:
#   1. Load inputs
#   2. Build state-level VAP table
#   3. Filter pres data to 2024, drop DC
#   4. Map party_simplified to 3-way category
#   5. Aggregate votes by state + party category, pivot wide
#   6. Attach state_vap and compute 4 shares
#   7. Keep only downstream-relevant columns
#   8. Verification
#   9. Save
# ══════════════════════════════════════════════════════════════════════════════

library(here)
library(tidyverse)

raw_dir       <- here("Data_Raw")
processed_dir <- here("Data_Processed")

# ── 1. Load inputs ──────────────────────────────────────────────────────────

base_path <- "/Users/binampoudyal/Downloads/Stratification_Frame_Building/"

# ── 1. Load inputs ──────────────────────────────────────────────────────────


pres_raw <- read_csv(file.path(raw_dir, "1976-2024-president.csv"),
                       show_col_types = FALSE)


cd_demographics <- readRDS(file.path(processed_dir, "cd_demographics.rds"))


cat("══ Inputs loaded ══\n")
cat("pres_raw rows:        ", nrow(pres_raw), "\n")
cat("cd_demographics rows: ", nrow(cd_demographics), "\n\n")


# ── 2. Build state-level VAP table ──────────────────────────────────────────
#
# Sum cd_pop across CDs within each state. This gives state-level citizen
# voting-age population (CVAP), matching the denominator used in CD-level
# 4-way shares. Total US VAP should be ~240M.
#
# state_abbrv is derived from state_cd (e.g. "TX-1" → "TX") since
# cd_demographics doesn't have it as a separate column.

state_vap <- cd_demographics %>%
  mutate(state_abbrv = sub("-.*", "", state_cd)) %>%
  group_by(state_abbrv) %>%
  summarise(state_vap = sum(cd_pop), .groups = "drop")

cat("══ State VAP ══\n")
cat("States:    ", nrow(state_vap), "(expect 50)\n")
cat("Total VAP: ", round(sum(state_vap$state_vap) / 1e6, 1), "M (expect ~240M)\n\n")


# ── 3. Filter pres data to 2024, drop DC ────────────────────────────────────

pres_2024 <- pres_raw %>%
  filter(year == 2024) %>%
  filter(state_po != "DC")

cat("══ 2024 presidential data ══\n")
cat("Rows:          ", nrow(pres_2024), "\n")
cat("Unique states: ", n_distinct(pres_2024$state_po), "(expect 50)\n\n")


# ── 4. Map party_simplified to 3-way category ───────────────────────────────
# DEMOCRAT / REPUBLICAN / OTHER (catches LIBERTARIAN, OTHER, NA write-ins)

pres_2024 <- pres_2024 %>%
  mutate(party_category = case_when(
    party_simplified == "DEMOCRAT"   ~ "dem",
    party_simplified == "REPUBLICAN" ~ "rep",
    TRUE                              ~ "other"
  ))


# ── 5. Aggregate votes by state + party category, then pivot wide ──────────
#
# After this step, each state has one row with three vote-count columns
# (dem, rep, other). total_pres_votes is the sum across the three.

state_pres_2024 <- pres_2024 %>%
  group_by(state_po, party_category) %>%
  summarise(votes = sum(candidatevotes, na.rm = TRUE), .groups = "drop") %>%
  pivot_wider(
    names_from   = party_category,
    values_from  = votes,
    names_prefix = "",
    values_fill  = 0
  ) %>%
  rename(
    state_abbrv      = state_po,
    dem_pres_votes   = dem,
    rep_pres_votes   = rep,
    other_pres_votes = other
  ) %>%
  mutate(total_pres_votes = dem_pres_votes + rep_pres_votes + other_pres_votes)


# ── 6. Attach state_vap and compute 4 shares ────────────────────────────────
#
# Inner_join here would have the same effect since we have 50 in both;
# left_join is safer in case state codes diverge unexpectedly.

state_pres_2024 <- state_pres_2024 %>%
  left_join(state_vap, by = "state_abbrv") %>%
  mutate(
    state_pres_dem_share      = dem_pres_votes      / state_vap,
    state_pres_rep_share      = rep_pres_votes      / state_vap,
    state_pres_other_share    = other_pres_votes    / state_vap,
    state_pres_no_vote_share  = (state_vap - total_pres_votes) / state_vap
  )


# ── 7. Keep only the columns we need for downstream ─────────────────────────

state_pres_2024 <- state_pres_2024 %>%
  select(state_abbrv,
         state_pres_dem_share,
         state_pres_rep_share,
         state_pres_other_share,
         state_pres_no_vote_share)


# ── 8. Verification ─────────────────────────────────────────────────────────

cat("══ state_pres_2024 structure ══\n")
cat("Rows:", nrow(state_pres_2024), "(expect 50)\n")
cat("Cols:", ncol(state_pres_2024), "(expect 5)\n\n")
print(head(state_pres_2024, 10))


# Share sums should all be 1 (within rounding)
cat("\n══ Share sum validation ══\n")
share_sums <- state_pres_2024 %>%
  mutate(s = state_pres_dem_share + state_pres_rep_share + 
           state_pres_other_share + state_pres_no_vote_share) %>%
  pull(s)
cat("Range:", round(min(share_sums), 6), "to", round(max(share_sums), 6), "\n")
cat("States where sum != 1.0:", 
    sum(round(share_sums, 4) != 1), "\n")


# NA check
cat("\n══ NA check ══\n")
print(state_pres_2024 %>% summarise(across(everything(), ~sum(is.na(.x)))))


# Sanity: top Dem states (presidential 2024)
cat("\n══ Top 5 most Democratic states (presidential 2024) ══\n")
state_pres_2024 %>%
  arrange(desc(state_pres_dem_share)) %>%
  head(5) %>%
  print()

# Sanity: top Rep states
cat("\n══ Top 5 most Republican states (presidential 2024) ══\n")
state_pres_2024 %>%
  arrange(desc(state_pres_rep_share)) %>%
  head(5) %>%
  print()

# Highest turnout (lowest no_vote_share)
cat("\n══ Top 5 highest-turnout states (lowest no_vote share) ══\n")
state_pres_2024 %>%
  arrange(state_pres_no_vote_share) %>%
  head(5) %>%
  print()

# Lowest turnout (highest no_vote_share)
cat("\n══ Top 5 lowest-turnout states (highest no_vote share) ══\n")
state_pres_2024 %>%
  arrange(desc(state_pres_no_vote_share)) %>%
  head(5) %>%
  print()


# ── 9. Save ─────────────────────────────────────────────────────────────────
saveRDS(state_pres_2024, file.path(processed_dir, "state_pres_2024.rds"))

cat("\nSaved state_pres_2024.rds with 4-feature shares (VAP denominator)\n")
cat("\nFinal columns:\n")
print(names(state_pres_2024))
