# ══════════════════════════════════════════════════════════════════════════════
# SCRIPTS 18A / 18B / 18C: Build the CD-level training table for CART
#
# Purpose:
#   Assemble a single CD-level training table with predictors, outcomes,
#   and modeling flags, ready for the CART inheritance model in Script 20+.
#
#   Each row is one of the 435 CDs. Columns include demographic proportions,
#   state-level presidential features, 2024 House vote shares, and flags
#   distinguishing which CDs feed into training vs. prediction.
#
# Pipeline overview:
#
#   Script 18A — Build inheritance table (cd_2026_inheritance.rds)
#     For each 2026 CD in the 7 redistricted states, identify the dominant
#     2024 CD it maps to and compute population overlap. CDs with >=95%
#     overlap are flagged as "essentially unchanged" — they can inherit
#     their 2024 House result as-is.
#
#     Inputs:  all_bafs, cd119_redistricted, all_blocks_pop (in-memory or from disk)
#     Output:  cd_2026_inheritance.rds
#
#   Script 18B — Assemble base training table (training_table.rds v1)
#     Join cd_demographics, cd_house_2024, and state_pres_2024 into one
#     table per CD. Sets a coarse state-level is_redistricted flag.
#
#     Inputs:  cd_demographics.rds, cd_house_2024.rds, state_pres_2024.rds
#     Output:  training_table.rds (base)
#
#   Script 18C — Refine flags and add contestation (training_table.rds v2)
#     Uses the inheritance table from 18A to move essentially-unchanged CDs
#     from prediction_set back into training_set. Builds a contestation
#     column and sets a 2-value training_eligibility flag.
#
#     Inputs:  training_table.rds, cd_house_2024.rds, cd_2026_inheritance.rds
#     Output:  training_table.rds (final)
#
# Final training_table (from 18C) has:
#   - 435 rows (one per CD)
#   - ~29 demographic feature columns (pct_age_*, pct_male, etc.)
#   - 4 state-level presidential feature columns (state_pres_*_share)
#   - 4 outcome columns (dem_share, rep_share, other_share, no_vote_share)
#   - Modeling flags: is_redistricted, contestation, training_eligibility
#
# End-to-end row counts:
#   - training_set:   ~318 CDs (all stable-state CDs + 42 essentially-unchanged)
#   - prediction_set: ~117 CDs (genuinely new geography in redistricted states)
#
# Why these three scripts share a file:
#   18B and 18C both write to training_table.rds and depend on the same
#   inputs. Keeping them together lets us run 18A → 18B → 18C sequentially
#   in one R session without repeated disk I/O. 18A is included because
#   it produces the inheritance table that 18C needs.
# ══════════════════════════════════════════════════════════════════════════════
# ══════════════════════════════════════════════════════════════════════════════
# SCRIPT 18A: Identify essentially-unchanged 2026 CDs in redistricted states
#
# Purpose: Within each of the 7 redistricted states, identify 2026 CDs that
#          are essentially unchanged from a single 2024 (119th Congress) CD.
#          For these CDs, we can use the 2024 House results from the old CD
#          as the area-level covariate for the new CD — no CART imputation
#          needed.
#
# Why: The 7 redistricted states had legal/political changes to their CD
#      maps for 2026, but not every district was substantially redrawn. Many
#      were renumbered slightly, shifted at the margins, or left effectively
#      unchanged. Treating all 159 CDs in the 7 states as "redistricted"
#      throws away genuine information about those whose populations are
#      effectively the same as in 2024.
#
# Inputs:
#   - all_bafs           : block → cd_2026 (from state BAFs)
#   - cd119_redistricted : block → cd_119 (from Script 12)
#   - all_blocks_pop     : block → 2020 population (from tidycensus)
#
# Output:
#   - cd_2026_inheritance.rds — one row per 2026 CD in the 7 states, with:
#       state_fips, cd_2026, dominant_cd_119, overlap_pct,
#       essentially_unchanged, cd_2026_total_pop
#
# Methodology:
#   1. For each block in the 7 redistricted states: we know cd_2026 (from BAFs),
#      cd_119 (from the 119th CD BEF built in Script 12), and population
#      (from tidycensus, loaded in Script 08).
#   2. For each (state, cd_2026), compute population from each source cd_119.
#   3. Compute overlap_pct = pop from dominant cd_119 / total cd_2026 pop.
#      This is the "new-CD-side" perspective: "of the people now in this
#      new CD, what fraction came from one specific old CD?"
#   4. Flag as essentially_unchanged if overlap_pct >= 0.95.
#
# Sections:
#   1. Build block-level table (state, cd_2026, cd_119, pop)
#   2. Aggregate to (state, cd_2026, cd_119) population intersections
#   3. For each cd_2026, find dominant cd_119 and compute overlap_pct
#   4. Examine overlap_pct distribution
#   5. Symmetry validation (forward vs reverse overlap)
#   6. Save
# ══════════════════════════════════════════════════════════════════════════════


library(here)
library(tidyverse)

# ── Folder paths ────────────────────────────────────────────────────────────
raw_dir       <- here("Data_Raw")
processed_dir <- here("Data_Processed")


# ── 1. Build block-level table: state, cd_2026, cd_119, pop ─────────────────
#
# Three sources, all joined on block_geoid:
#   all_bafs              -- block → cd_2026 (and state_fips)
#   cd119_redistricted    -- block → cd_119
#   all_blocks_pop        -- block → 2020 population


# ── Fresh input loads ─────────────────────────────────────────────────────
all_bafs <- readRDS(file.path(processed_dir, "all_bafs.rds"))

cd119_redistricted <- readRDS(file.path(processed_dir, "cd119_redistricted.rds"))

all_blocks_pop <- readRDS(file.path(processed_dir, "all_blocks_pop.rds"))





# Inner joins drop blocks not in all three (very few, e.g. uninhabited
# blocks that may have CD assignments but no population, etc.)

block_full <- all_bafs %>%
  rename(cd_2026 = district) %>%
  inner_join(
    cd119_redistricted %>% select(block_geoid, cd_119),
    by = "block_geoid"
  ) %>%
  inner_join(
    all_blocks_pop %>% rename(block_geoid = GEOID, pop = value),
    by = "block_geoid"
  )

cat("══ Block-level table ══\n")
cat("Rows:", nrow(block_full), "\n")
cat("Population covered:", sum(block_full$pop), "\n")
cat("States:\n")
print(table(block_full$state_fips))


# ── 2. Aggregate to (state, cd_2026, cd_119) population intersections ───────
#
# For each combination of (state, new CD, old CD), sum block populations.
# This tells us "how many people in new CD X used to be in old CD Y."

intersection_pop <- block_full %>%
  group_by(state_fips, cd_2026, cd_119) %>%
  summarise(pop_intersection = sum(pop), .groups = "drop")


# ── 3. For each cd_2026, find dominant source cd_119 and overlap_pct ───────
#
# overlap_pct is "new-CD-side": of the population NOW in cd_2026, what
# fraction came from the largest source cd_119?
#
# Formula:
#   overlap_pct = pop in (cd_2026, dominant_cd_119) / total pop in cd_2026
#
# If overlap_pct = 1.0: 100% of the new CD's population came from one
# specific old CD. The new CD is essentially the old CD (possibly with a
# different number).
#
# If overlap_pct = 0.6: 60% came from one old CD, 40% from others. The
# new CD is substantially different from any single old CD.

cd_2026_inheritance <- intersection_pop %>%
  group_by(state_fips, cd_2026) %>%
  # Compute total pop of this 2026 CD (for the denominator)
  mutate(cd_2026_total_pop = sum(pop_intersection)) %>%
  # Find the row with the largest intersection (the dominant source cd_119)
  slice_max(pop_intersection, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  # Compute the new-CD-side overlap percentage
  mutate(
    overlap_pct           = pop_intersection / cd_2026_total_pop,
    essentially_unchanged = overlap_pct >= 0.95
  ) %>%
  rename(dominant_cd_119 = cd_119) %>%
  select(state_fips, cd_2026, dominant_cd_119, overlap_pct, 
         essentially_unchanged, cd_2026_total_pop)


cat("\n══ cd_2026_inheritance summary ══\n")
cat("Rows:", nrow(cd_2026_inheritance), "(expect ~159 across 7 states)\n")

cat("\n══ essentially_unchanged breakdown ══\n")
cd_2026_inheritance %>%
  count(essentially_unchanged) %>%
  mutate(pct = round(100 * n / sum(n), 1)) %>%
  print()

cat("\n══ Breakdown by state ══\n")
cd_2026_inheritance %>%
  count(state_fips, essentially_unchanged) %>%
  pivot_wider(names_from = essentially_unchanged, 
              values_from = n,
              values_fill = 0,
              names_prefix = "unchanged_") %>%
  rename(unchanged_TRUE_count = unchanged_TRUE, 
         unchanged_FALSE_count = unchanged_FALSE) %>%
  mutate(total = unchanged_TRUE_count + unchanged_FALSE_count) %>%
  print()


# ── 4. Examine the distribution of overlap_pct values ──────────────────────

cat("\n══ overlap_pct distribution ══\n")
cat("Min:    ", round(min(cd_2026_inheritance$overlap_pct), 4), "\n")
cat("Median: ", round(median(cd_2026_inheritance$overlap_pct), 4), "\n")
cat("Max:    ", round(max(cd_2026_inheritance$overlap_pct), 4), "\n")

cat("\nDistribution by threshold:\n")
cat("Overlap >= 0.99:", sum(cd_2026_inheritance$overlap_pct >= 0.99), "\n")
cat("Overlap >= 0.95:", sum(cd_2026_inheritance$overlap_pct >= 0.95), "\n")
cat("Overlap >= 0.90:", sum(cd_2026_inheritance$overlap_pct >= 0.90), "\n")
cat("Overlap >= 0.80:", sum(cd_2026_inheritance$overlap_pct >= 0.80), "\n")
cat("Overlap >= 0.50:", sum(cd_2026_inheritance$overlap_pct >= 0.50), "\n")


# ── 5. Symmetry validation ─────────────────────────────────────────────────
#
# For essentially-unchanged 2026 CDs (overlap_pct >= 0.95):
#   - Forward overlap: % of NEW CD's population from dominant OLD CD
#     (this is what overlap_pct in cd_2026_inheritance measures)
#   - Reverse overlap: % of dominant OLD CD's population that ended up in NEW CD
#
# Under the equal-population constraint, these should be approximately equal.
# If forward is 0.98 but reverse is 0.5, the "inheritance" is not really
# clean — old CD X spilled into multiple new CDs, of which the new one is
# just the biggest recipient.

# Compute reverse overlap (per OLD CD)
reverse_overlap <- block_full %>%
  group_by(state_fips, cd_119) %>%
  mutate(cd_119_total_pop = sum(pop)) %>%
  group_by(state_fips, cd_119, cd_2026) %>%
  summarise(
    pop_to_2026 = sum(pop),
    cd_119_total_pop = first(cd_119_total_pop),
    reverse_overlap_pct = pop_to_2026 / cd_119_total_pop,
    .groups = "drop"
  )

# Join forward + reverse for essentially-unchanged 2026 CDs
symmetry_check <- cd_2026_inheritance %>%
  filter(essentially_unchanged) %>%
  left_join(
    reverse_overlap %>%
      rename(dominant_cd_119 = cd_119, cd_2026_match = cd_2026),
    by = c("state_fips", "dominant_cd_119")
  ) %>%
  filter(cd_2026 == cd_2026_match) %>%
  select(state_fips, cd_2026, dominant_cd_119,
         forward_overlap_pct = overlap_pct,
         reverse_overlap_pct)

cat("\n══ Symmetry check (forward vs reverse overlap) ══\n")
cat("Forward overlap range:", 
    round(min(symmetry_check$forward_overlap_pct), 3), "to",
    round(max(symmetry_check$forward_overlap_pct), 3), "\n")
cat("Reverse overlap range:", 
    round(min(symmetry_check$reverse_overlap_pct), 3), "to",
    round(max(symmetry_check$reverse_overlap_pct), 3), "\n")

cat("\nAbsolute difference (forward - reverse):\n")
print(summary(abs(symmetry_check$forward_overlap_pct - symmetry_check$reverse_overlap_pct)))


# ── 6. Save ────────────────────────────────────────────────────────────────

saveRDS(cd_2026_inheritance, file.path(processed_dir, "cd_2026_inheritance.rds"))


cat("\nSaved cd_2026_inheritance.rds\n")

# ══════════════════════════════════════════════════════════════════════════════
# SCRIPT 18B: Assemble training table (base)
#
# Purpose: Combine cd_demographics, cd_house_2024, and state_pres_2024 into
#          a single CD-level training table. This is the "base" version:
#          all 435 CDs, all features and outcomes joined, and a preliminary
#          is_redistricted flag set on state basis alone.
#
# The base table doesn't yet handle inheritance (whether a redistricted CD
# is essentially unchanged from a 2024 CD) or contestation flagging. Those
# are added in Script 18C.
#
# Inputs:
#   cd_demographics.rds   (435 CDs, ~29 demographic proportions + cd_pop,
#                          from Script 15)
#   cd_house_2024.rds     (435 CDs, dem/rep/other/no_vote shares against
#                          cd_pop, from Script 16)
#   state_pres_2024.rds   (50 states, 4 shares against state CVAP,
#                          from Script 17)
#
# Output:
#   training_table.rds    (435 CDs, base version, without contestation or
#                          inheritance refinements applied)
#
# Join architecture:
#
#   cd_demographics (435 rows)
#       │
#       │ left_join by state_cd
#       ▼
#   + cd_house_2024 (435 rows, 4 outcome shares)
#       │
#       │ left_join by state_abbrv
#       ▼
#   + state_pres_2024 (50 rows, 4 state-level pres features)
#       │
#       ▼
#   training_table (435 rows)
#
# Note on cd_pop: cd_house_2024 has cd_pop already (added in Script 16B).
# cd_demographics also has cd_pop. To avoid duplicate columns (cd_pop.x /
# cd_pop.y), we drop cd_pop from cd_house_2024 before joining.
#
# Sections:
#   1. Load source tables if not in memory
#   2. Define redistricted states
#   3. Extract state_abbrv in cd_demographics if not already present
#   4. Join the three tables
#   5. Add preliminary is_redistricted flag
#   6. Keep only the columns we need for modeling
#   7. Verification
#   8. Save
# ══════════════════════════════════════════════════════════════════════════════


library(tidyverse)


# ── 1. Load source tables if not in memory ──────────────────────────────────

cd_demographics <- readRDS(file.path(processed_dir, "cd_demographics.rds")) %>%
  select(-any_of(c("state_abbrv"))) # Drop if it exists from a previous run

cd_house_2024 <- readRDS(file.path(processed_dir, "cd_house_2024.rds")) %>%
  select(-any_of(c("contestation_2024"))) # Drop if it exists

if (!exists("state_pres_2024")) {
  cat("Loading state_pres_2024 from disk...\n")
  state_pres_2024 <- readRDS(file.path(processed_dir, "state_pres_2024.rds"))
}

cat("\n══ Input tables loaded ══\n")
cat("cd_demographics:  ", nrow(cd_demographics),  "rows\n")
cat("cd_house_2024:    ", nrow(cd_house_2024),    "rows\n")
cat("state_pres_2024:  ", nrow(state_pres_2024),  "rows\n")


# ── 2. Define which states are redistricted ─────────────────────────────────

redistricted_states <- c("CA", "FL", "MO", "NC", "OH", "TX", "UT")


# ── 3. Extract state_abbrv in cd_demographics if not already present ────────

if (!"state_abbrv" %in% names(cd_demographics)) {
  cd_demographics <- cd_demographics %>%
    mutate(state_abbrv = sub("-.*", "", state_cd))
}

cat("\n══ cd_demographics: state_abbrv ══\n")
cat("Unique values:", n_distinct(cd_demographics$state_abbrv), "(expect 50)\n")


# ── 4. Join the three tables ────────────────────────────────────────────────
#
# Step A: cd_demographics + cd_house_2024 on state_cd
#   - One-to-one join (both 435 rows keyed on state_cd)
#   - Drop cd_pop from cd_house_2024 since it's already in cd_demographics.
#     Avoids cd_pop.x / cd_pop.y collision.
#
# Step B: + state_pres_2024 on state_abbrv
#   - One-to-many: each state's 4 pres features are replicated to all its CDs.

training_table <- cd_demographics %>%
  
  # Step A: bring in House outcomes
  left_join(
    cd_house_2024 %>% select(-cd_pop),
    by = "state_cd"
  ) %>%
  
  # Step B: bring in state-level presidential features
  left_join(state_pres_2024, by = "state_abbrv")

cat("\n══ After joins ══\n")
cat("Rows:", nrow(training_table), "(expect 435)\n")
cat("Cols:", ncol(training_table), "\n")


# ── 5. Add preliminary is_redistricted flag ─────────────────────────────────
#
# This is a coarse state-level flag: TRUE for all CDs in the 7 redistricted
# states. Script 18C will refine this by looking at whether each specific
# CD is essentially unchanged from a 2024 CD (in which case we can inherit
# the 2024 result). For now, all 159 redistricted-state CDs are flagged TRUE.

training_table <- training_table %>%
  select(-any_of("is_redistricted")) %>%
  mutate(is_redistricted = state_abbrv %in% redistricted_states)


# ── 6. Keep only the columns we need for modeling ──────────────────────────
#
# Identifiers and flags:
#   state_cd, state_abbrv, cd_pop, is_redistricted
# Demographic predictors (~29):
#   pct_age_*, pct_male, pct_female, pct_race_*, pct_hisp_*, pct_educ_*
# State-level pres predictors (4):
#   state_pres_dem_share, state_pres_rep_share, state_pres_other_share,
#   state_pres_no_vote_share
# Outcomes (4):
#   dem_share, rep_share, other_share, no_vote_share

training_table <- training_table %>%
  select(
    # Identifiers / flags
    state_cd, state_abbrv, cd_pop, is_redistricted,
    
    # Demographic predictors
    starts_with("pct_"),
    
    # State-level presidential predictors
    state_pres_dem_share,
    state_pres_rep_share,
    state_pres_other_share,
    state_pres_no_vote_share,
    
    # Outcomes
    dem_share,
    rep_share,
    other_share,
    no_vote_share
  )


# ── 7. Verification ─────────────────────────────────────────────────────────

cat("\n══ Final training_table (base) structure ══\n")
cat("Rows:", nrow(training_table), "(expect 435)\n")
cat("Cols:", ncol(training_table), "\n\n")

cat("Column names:\n")
print(names(training_table))

# Distribution of is_redistricted
cat("\n══ is_redistricted breakdown ══\n")
training_table %>%
  count(is_redistricted) %>%
  mutate(pct = round(100 * n / sum(n), 1)) %>%
  print()

# Sanity check: outcomes sum to 1 per CD
cat("\n══ Outcome sum check (per CD) ══\n")
share_sums <- training_table %>%
  mutate(s = dem_share + rep_share + other_share + no_vote_share) %>%
  pull(s)
cat("Range:", round(min(share_sums, na.rm = TRUE), 6), "to",
    round(max(share_sums, na.rm = TRUE), 6), "\n")
cat("NAs:", sum(is.na(share_sums)), "\n")

# Sanity check: state-level pres shares sum to 1 per CD
cat("\n══ State pres feature sum check (per CD) ══\n")
state_pres_sums <- training_table %>%
  mutate(s = state_pres_dem_share + state_pres_rep_share + 
           state_pres_other_share + state_pres_no_vote_share) %>%
  pull(s)
cat("Range:", round(min(state_pres_sums, na.rm = TRUE), 6), "to",
    round(max(state_pres_sums, na.rm = TRUE), 6), "\n")
cat("NAs:", sum(is.na(state_pres_sums)), "\n")

# NA check across all columns
cat("\n══ NA check (any column) ══\n")
na_counts <- training_table %>%
  summarise(across(everything(), ~sum(is.na(.x)))) %>%
  pivot_longer(everything(), names_to = "column", values_to = "n_na") %>%
  filter(n_na > 0)
if (nrow(na_counts) == 0) {
  cat("No NAs in any column ✓\n")
} else {
  cat("Columns with NAs:\n")
  print(na_counts)
}


# ── 8. Save ─────────────────────────────────────────────────────────────────

saveRDS(training_table, file.path(processed_dir, "training_table.rds"))


cat("\nSaved training_table.rds (base version)\n")
cat("Next: Script 18C adds contestation flag + refines is_redistricted based\n")
cat("      on the inheritance table from Script 18A.\n")

# ══════════════════════════════════════════════════════════════════════════════
# SCRIPT 18C: Refine is_redistricted, add contestation, and set
#             training_eligibility
#
# Purpose: Take the base training_table from Script 18B and add three flags:
#
#   1. Refine is_redistricted using inheritance overlap:
#      - Essentially-unchanged CDs (>=95% overlap with a single 2024 CD)
#        get is_redistricted = FALSE (they inherit the 2024 result)
#      - Genuinely new CDs keep is_redistricted = TRUE
#
#   2. Build contestation column:
#      - For known 2026-uncontested CDs (CA-14, CA-29, CA-40, FL-10): FALSE
#      - For genuinely redistricted CDs: TRUE (assume 2026 races contested;
#        don't inherit from old district since it's been substantially redrawn)
#      - For stable / essentially-unchanged CDs: inherit from 2024 contestation
#        (>10 vote threshold per major party)
#
#   3. Set training_eligibility (2-value):
#      - !is_redistricted → "training_set" (~318 CDs)
#      - is_redistricted  → "prediction_set" (~117 CDs)
#
# Note on contestation vs training_eligibility:
#   Contestation is a FEATURE in the CART model (a predictor), not a filter.
#   Uncontested CDs still enter the training set — they're just marked as
#   uncontested so the model can learn to predict their inflated no_vote_share.
#
# Inputs:
#   training_table.rds       (load from disk)
#   cd_house_2024.rds        (used to compute 2024 contestation)
#   cd_2026_inheritance.rds  (used to refine is_redistricted for the
#                             essentially-unchanged CDs)
#
# Output:
#   training_table.rds       (overwritten with refined is_redistricted,
#                             new contestation column, and 
#                             training_eligibility column)
# ══════════════════════════════════════════════════════════════════════════════


library(tidyverse)


# ── 1. Load inputs ──────────────────────────────────────────────────────────


# ── 1. Load fresh ──────────────────────────────────────────────────────────
# Reload the base training table created in 18B.
# Drop the refined columns so we can re-derive them from the base state.
training_table <- readRDS(file.path(processed_dir, "training_table.rds")) %>%
  select(-any_of(c("contestation", "training_eligibility")))

cd_house_2024       <- readRDS(file.path(processed_dir, "cd_house_2024.rds"))
cd_2026_inheritance <- readRDS(file.path(processed_dir, "cd_2026_inheritance.rds"))


cat("══ Inputs loaded ══\n")
cat("training_table:        ", nrow(training_table),       "rows\n")
cat("cd_house_2024:         ", nrow(cd_house_2024),        "rows\n")
cat("cd_2026_inheritance:   ", nrow(cd_2026_inheritance),  "rows\n\n")


# ── 2. Refine is_redistricted using inheritance ────────────────────────────
#
# The base training_table has is_redistricted = TRUE for all CDs in the 7
# redistricted states (159 CDs). We refine this: essentially-unchanged CDs
# (>=95% population overlap with a single 2024 CD) get is_redistricted = FALSE
# so they enter the training set.

state_fips_to_abb <- tibble(
  state_fips  = c("06", "12", "29", "37", "39", "48", "49"),
  state_abbrv = c("CA", "FL", "MO", "NC", "OH", "TX", "UT")
)

# Build list of state_cd values that are essentially-unchanged
essentially_unchanged_cds <- cd_2026_inheritance %>%
  filter(essentially_unchanged) %>%
  left_join(state_fips_to_abb, by = "state_fips") %>%
  mutate(state_cd = paste0(state_abbrv, "-", cd_2026)) %>%
  pull(state_cd)

cat("Essentially-unchanged CDs identified:", length(essentially_unchanged_cds),
    "(expect ~42)\n")

# Refine is_redistricted
training_table <- training_table %>%
  mutate(
    is_redistricted = if_else(
      state_cd %in% essentially_unchanged_cds,
      FALSE,
      is_redistricted
    )
  )

cat("\n══ is_redistricted breakdown after refinement ══\n")
training_table %>%
  count(is_redistricted) %>%
  mutate(pct = round(100 * n / sum(n), 1)) %>%
  print()


# ── 3. Compute 2024 contestation from raw vote counts (>10 threshold) ──────
#
# The >10 threshold defines "contested" as: no absence of the other major
# party. In 2024 uncontested races, one major party often gets 0 or a
# placeholder value; the threshold cleanly separates these from real races.

cd_house_2024_contestation <- cd_house_2024 %>%
  mutate(contestation_2024 = (dem_votes > 10 & rep_votes > 10)) %>%
  select(state_cd, contestation_2024)

cat("\n══ 2024 contestation under >10 threshold (all 435 CDs) ══\n")
print(table(cd_house_2024_contestation$contestation_2024))


# ── 4. Build the unified contestation column ───────────────────────────────
#
# Priority order:
#   (a) Known 2026-uncontested CDs (per team guidance): contestation = FALSE
#   (b) Genuinely redistricted CDs (not in (a)): contestation = TRUE
#       (Assume contested in 2026. Don't inherit from old same-named district
#        because it's been substantially redrawn.)
#   (c) Stable / essentially-unchanged CDs: use 2024 contestation

known_uncontested_2026 <- c("CA-14", "CA-29", "CA-40", "FL-10")

training_table <- training_table %>%
  left_join(cd_house_2024_contestation, by = "state_cd") %>%
  mutate(
    contestation = case_when(
      state_cd %in% known_uncontested_2026 ~ FALSE,
      is_redistricted                      ~ TRUE,
      !is.na(contestation_2024)            ~ contestation_2024,
      TRUE                                 ~ TRUE   # fallback
    )
  ) %>%
  select(-contestation_2024)


# ── 5. Set training_eligibility ────────────────────────────────────────────
#
# Simple 2-value flag based on is_redistricted:
#   - training_set: has valid 2024 shares (either stable state or inherited)
#   - prediction_set: needs CART imputation (genuinely new geography)

training_table <- training_table %>%
  mutate(
    training_eligibility = if_else(!is_redistricted, "training_set", "prediction_set")
  )


# ── 6. Verification ────────────────────────────────────────────────────────

cat("\n══ contestation breakdown ══\n")
print(table(training_table$contestation, useNA = "always"))

cat("\n══ training_eligibility breakdown ══\n")
print(table(training_table$training_eligibility, useNA = "always"))

cat("\n══ Cross-tab: is_redistricted × contestation × training_eligibility ══\n")
print(training_table %>% count(is_redistricted, contestation, training_eligibility))

cat("\n══ The 4 known 2026-uncontested CDs ══\n")
training_table %>%
  filter(state_cd %in% known_uncontested_2026) %>%
  select(state_cd, is_redistricted, contestation, training_eligibility,
         dem_share, rep_share, other_share, no_vote_share) %>%
  print()

cat("\n══ All uncontested CDs in training_set ══\n")
training_table %>%
  filter(training_eligibility == "training_set", !contestation) %>%
  arrange(state_cd) %>%
  select(state_cd, state_abbrv, contestation,
         dem_share, rep_share, other_share, no_vote_share) %>%
  print(n = Inf)

cat("\n══ Essentially-unchanged CDs (now in training_set) ══\n")
training_table %>%
  filter(state_cd %in% essentially_unchanged_cds) %>%
  count(state_abbrv, training_eligibility) %>%
  print()


# ── 7. Save ────────────────────────────────────────────────────────────────

saveRDS(training_table, file.path(processed_dir, "training_table.rds"))

cat("\nSaved training_table.rds with:\n")

