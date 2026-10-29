# ══════════════════════════════════════════════════════════════════════════════
# SCRIPT 16A: Aggregate 2024 House election results to CD-level party shares
#
# Purpose: Process MIT Election Lab's 2024 House results into CD-level vote
#          counts and shares (Dem, Rep, Other) for use as the dependent
#          variable in Roberto's CART imputation model.
#
# Input:  codebook for house_raw
#         house_raw (33,805 rows, 1976-2024 House results, MIT Election Lab)
# Output: cd_house_2024 (435 rows, one per state-district combo for 2024)
#
# Required output columns:
#   state_cd          -- e.g. "TX-1", "CA-12" (matches our harmonization)
#   dem_votes         -- total Democratic votes in CD
#   rep_votes         -- total Republican votes in CD
#   other_votes       -- everything else (third party + independent + write-in)
#   total_house_votes -- dem + rep + other (total votes cast in House race)
#
# Note: The "No Vote" share is computed in a later step by joining with the
# CD's voting-age citizen population from PUMS:
#     no_vote_share = (cd_pop - total_house_votes) / cd_pop
#
# ──────────────────────────────────────────────────────────────────────────────
# Methodological decisions (documented for the methods section of the paper):
#
# 1. PARTY CATEGORIZATION (3-way: Dem / Rep / Other)
#
#    Democratic family (counted as "dem"):
#      - DEMOCRAT (main label, used in 48 states)
#      - DEMOCRATIC-FARMER-LABOR (Minnesota's Democratic Party affiliate)
#      - DEMOCRATIC-NONPARTISAN LEAGUE (North Dakota's Democratic Party affiliate)
#
#    Republican family (counted as "rep"):
#      - REPUBLICAN (sole label)
#
#    Everything else (counted as "other"):
#      - Third parties (LIBERTARIAN, GREEN, CONSTITUTION, etc.)
#      - Minor and write-in candidates (where party is NA)
#      - Independent candidates (INDEPENDENT, UNAFFILIATED, etc.)
#      - Fusion party labels (WORKING FAMILIES, CONSERVATIVE, etc.) when the
#        candidate's primary party is itself "other"
#
# 2. FUSION TICKETS (NY, CT, NJ, SC) -- candidate aggregation approach
#
#    In fusion-voting states, a single candidate can appear under multiple
#    party labels on the ballot. For example, in NY a Democratic candidate
#    might also appear under the WORKING FAMILIES party line. Each row in
#    the MIT data represents the votes received under one party line, so the
#    candidate's total votes are split across multiple rows.
#
#    Naive approach (sum by party label) would count the WORKING FAMILIES
#    votes as "Other", artificially inflating the third-party share and
#    deflating the major-party share. In NY, this can misestimate the
#    Democratic share by 2-5 percentage points per CD.
#
#    Our approach: aggregate by candidate first, identify each candidate's
#    primary party (the party label under which they received the most
#    votes), then attribute the candidate's total votes (summed across all
#    party lines) to that primary party.
#
#    Example: if Jane Smith got 80,000 votes as DEMOCRAT and 5,000 as
#    WORKING FAMILIES, we identify DEMOCRAT as her primary party and
#    attribute the full 85,000 to "dem". This recovers the meaningful
#    political alignment that fusion voters intended.
#
#    Tradeoff: "primary party" is a heuristic based on vote share. In rare
#    edge cases (e.g., a true independent who happens to win more votes
#    under a fusion party line than under the INDEPENDENT line), this could
#    misclassify. Such edge cases are rare and the heuristic produces
#    reasonable results in 99%+ of cases.
#
# 3. WRITE-INS
#
#    119 write-in rows in 2024 have candidate = "WRITEIN" and party = NA.
#    Under our candidate-aggregation approach, all write-ins in a single CD
#    get grouped together (they share the candidate name "WRITEIN"). Their
#    primary party is NA, which maps to "other". Write-in totals are
#    typically small (a handful to hundreds of votes per CD).
#
# 4. AT-LARGE DISTRICTS
#
#    The MIT dataset uses district = 0 for at-large states (AK, DE, ND, SD,
#    VT, WY, and DC's non-voting delegate). Our PUMS/CES geography uses
#    district = 1 for the same states. We recode district 0 → 1 for
#    consistency.
#
# 5. DC EXCLUSION
#
#    DC has only a non-voting delegate, not a House seat. Excluded.
#
# 6. SPECIAL ELECTIONS AND RUNOFFS
#
#    Filtered: stage == "GEN". The 2024 data has 0 special elections and
#    0 runoffs, so no additional handling needed.
# ══════════════════════════════════════════════════════════════════════════════


library(here)
library(tidyverse)
library(data.table)

raw_dir       <- here("Data_Raw")
processed_dir <- here("Data_Processed")

# ── 1. Investigate data ────────────────────────────

# Quick look at the codebook to confirm column names and codes
codebook_path <- file.path(raw_dir, "codebook-us-house-1976–2024.md")
cat("══ Codebook contents ══\n")
cat(readLines(codebook_path), sep = "\n")
cat("══ Codebook contents ══\n")
cat(readLines(codebook_path), sep = "\n")

#data containing house vote shares at the congressional district level from 1979 to 2024
house_raw <- fread(
  file.path(raw_dir, "1976-2024-house.tab"),
  sep = ","
)

cat("══ Data structure ══\n")
cat("Rows:", nrow(house_raw), "\n")
cat("Cols:", ncol(house_raw), "\n")

cat("\nColumn names:\n")
print(names(house_raw))

cat("\nFirst 5 rows:\n")
print(head(house_raw, 5))


# Convert to tibble for tidyverse-friendly printing
house_raw <- as_tibble(house_raw)

# Filter to 2024 general elections
house_2024 <- house_raw %>%
  filter(year == 2024, stage == "GEN")

cat("══ 2024 general elections ══\n")
cat("Rows:", nrow(house_2024), "\n")

# Party label distribution
cat("\n══ Party label distribution in 2024 ══\n")
house_2024 %>%
  count(party) %>%
  arrange(desc(n)) %>%
  print(n = Inf)

# Flags
cat("\n══ Flag counts in 2024 ══\n")
cat("special  TRUE:", sum(house_2024$special, na.rm = TRUE), "\n")
cat("runoff   TRUE:", sum(house_2024$runoff, na.rm = TRUE), "\n")
cat("writein  TRUE:", sum(house_2024$writein, na.rm = TRUE), "\n")
cat("fusion   TRUE:", sum(house_2024$fusion_ticket, na.rm = TRUE), "\n")

# State coverage
cat("\n══ States in 2024 ══\n")
cat("Unique states:", n_distinct(house_2024$state), "\n")
print(sort(unique(house_2024$state_po)))

# At-large districts
cat("\n══ At-large districts (district = 0) ══\n")
house_2024 %>%
  filter(district == 0) %>%
  count(state_po) %>%
  print()

# Sample
cat("\n══ Sample 2024 rows ══\n")
print(head(house_2024 %>% 
             select(state_po, district, candidate, party, candidatevotes, totalvotes, writein), 
           15))



# ── 2. Filter raw data to 2024 general elections ────────────────────────────
# Drop DC, recode at-large district encoding (0 → 1), and create state_cd
# identifier consistent with our PUMS/CES harmonization.

house_2024 <- house_raw %>%
  filter(year == 2024, stage == "GEN") %>%
  filter(state_po != "DC") %>%
  mutate(
    district = if_else(district == 0L, 1L, as.integer(district)),
    state_cd = paste0(state_po, "-", district)
  )

cat("══ After initial filtering ══\n")
cat("Rows:", nrow(house_2024), "\n")
cat("Unique state_cd:", n_distinct(house_2024$state_cd), "(expect 435)\n")


# ── 3. Aggregate votes per candidate per CD ─────────────────────────────────
# 
# This is the first key step of the candidate-aggregation approach. For each
# unique (state_cd, candidate) combination, sum the votes across all party
# lines. This collapses the fusion-ticket multi-row representation into a
# single candidate total.
#
# For example, NY's Jane Smith with rows under DEMOCRAT (80,000) and
# WORKING FAMILIES (5,000) becomes one row with total_candidate_votes = 85,000.
#
# Note: For candidates listed under different name spellings or capitalizations
# this approach could fail, but the MIT data uses consistent spellings within
# a single year.

candidate_totals <- house_2024 %>%
  group_by(state_cd, candidate) %>%
  summarise(
    total_candidate_votes = sum(candidatevotes, na.rm = TRUE),
    .groups = "drop"
  )

cat("\n══ Candidate aggregation ══\n")
cat("Rows after collapsing party lines per candidate:", nrow(candidate_totals), "\n")


# ── 4. Identify each candidate's primary party ──────────────────────────────
#
# For each (state_cd, candidate), find the party label under which they
# received the most votes. This becomes their "primary party" and represents
# the candidate's actual political alignment.
#
# Implementation: for each (state_cd, candidate), keep only the row with
# the maximum candidatevotes value (ties broken by first occurrence).
#
# Edge case: write-ins all share candidate = "WRITEIN" within a CD, but
# their party is NA. Their "primary party" is therefore NA, which we'll
# map to "other" in the next step.

candidate_primary_party <- house_2024 %>%
  group_by(state_cd, candidate) %>%
  slice_max(candidatevotes, n = 1, with_ties = FALSE) %>%
  select(state_cd, candidate, primary_party = party) %>%
  ungroup()

cat("\n══ Primary party identification ══\n")
cat("Candidates with assigned primary party:", nrow(candidate_primary_party), "\n")
cat("Candidates with NA primary party (write-ins):", 
    sum(is.na(candidate_primary_party$primary_party)), "\n")


# ── 5. Combine: candidate's full vote total + their primary party ───────────

candidates_with_party <- candidate_totals %>%
  left_join(candidate_primary_party, by = c("state_cd", "candidate"))


# ── 6. Map primary party to 3-way category (dem / rep / other) ─────────────
#
# Democratic-family parties (DEMOCRAT, DFL, DNL) → "dem"
# Republican → "rep"
# Everything else (third parties, independents, fusion parties, write-ins,
# and any NA from write-ins) → "other"

candidates_with_party <- candidates_with_party %>%
  mutate(party_category = case_when(
    primary_party == "DEMOCRAT"                      ~ "dem",
    primary_party == "DEMOCRATIC-FARMER-LABOR"       ~ "dem",
    primary_party == "DEMOCRATIC-NONPARTISAN LEAGUE" ~ "dem",
    primary_party == "REPUBLICAN"                    ~ "rep",
    TRUE                                              ~ "other"
  ))

cat("\n══ Party category breakdown ══\n")
candidates_with_party %>%
  count(party_category) %>%
  arrange(desc(n)) %>%
  print()


# ── 7. Aggregate by CD and party category ───────────────────────────────────
# Sum candidate totals within each (state_cd, party_category). This produces
# the cleaned vote counts per party group per CD.

cd_votes_long <- candidates_with_party %>%
  group_by(state_cd, party_category) %>%
  summarise(votes = sum(total_candidate_votes, na.rm = TRUE), .groups = "drop")


# ── 8. Reshape to wide: one row per CD with dem/rep/other vote columns ─────

cd_house_2024 <- cd_votes_long %>%
  pivot_wider(
    names_from   = party_category,
    values_from  = votes,
    names_prefix = "",
    values_fill  = 0   # CDs with no candidates in a category get 0
  ) %>%
  rename(
    dem_votes   = dem,
    rep_votes   = rep,
    other_votes = other
  ) %>%
  mutate(
    total_house_votes = dem_votes + rep_votes + other_votes
  )


# ── 9. Verification ─────────────────────────────────────────────────────────

cat("\n══ cd_house_2024 structure ══\n")
cat("Rows:", nrow(cd_house_2024), "(expect 435)\n")
cat("Cols:", ncol(cd_house_2024), "\n")
print(head(cd_house_2024, 5))


# CDs per state -- sanity check we have right number for each state
cat("\n══ CDs per state ══\n")
cd_house_2024 %>%
  mutate(state_po = sub("-.*", "", state_cd)) %>%
  count(state_po, name = "n_cds") %>%
  arrange(state_po) %>%
  print(n = Inf)


# Vote total sanity check
cat("\n══ Vote total sanity check ══\n")
cat("Min total_house_votes: ", min(cd_house_2024$total_house_votes), "\n")
cat("Max total_house_votes: ", max(cd_house_2024$total_house_votes), "\n")
cat("Mean total_house_votes:", round(mean(cd_house_2024$total_house_votes)), "\n")
cat("Median total_house_votes:", round(median(cd_house_2024$total_house_votes)), "\n")
cat("\nCDs with 0 votes total:", sum(cd_house_2024$total_house_votes == 0), "\n")


# Two-party Dem share -- check distribution looks sensible
cd_house_2024 <- cd_house_2024 %>%
  mutate(dem_two_party_share = dem_votes / (dem_votes + rep_votes))

cat("\n══ Two-party Dem share distribution ══\n")
print(summary(cd_house_2024$dem_two_party_share))


# Compare to expected: which CDs look heavily Dem or heavily Rep?
cat("\n══ Top 5 most Democratic CDs ══\n")
cd_house_2024 %>%
  arrange(desc(dem_two_party_share)) %>%
  head(5) %>%
  select(state_cd, dem_votes, rep_votes, dem_two_party_share) %>%
  print()

cat("\n══ Top 5 most Republican CDs ══\n")
cd_house_2024 %>%
  arrange(dem_two_party_share) %>%
  head(5) %>%
  select(state_cd, dem_votes, rep_votes, dem_two_party_share) %>%
  print()


# ── 10. Save ─────────────────────────────────────────────────────────────────

#Intermediate save
saveRDS(cd_house_2024, file.path(processed_dir, "cd_house_2024.rds"))

cat("\nSaved cd_house_2024.rds\n")


#Edge cases diagnostic
cat("══ Potential training-data issues ══\n\n")

cat("CDs with abnormally low total votes (< 50,000):\n")
cd_house_2024 %>%
  filter(total_house_votes < 50000) %>%
  arrange(total_house_votes) %>%
  select(state_cd, dem_votes, rep_votes, other_votes, total_house_votes) %>%
  print(n = Inf)

cat("\nCDs with 0 Democratic votes (no Dem on ballot or all-Rep race):\n")
cd_house_2024 %>%
  filter(dem_votes == 0) %>%
  select(state_cd, dem_votes, rep_votes, other_votes, total_house_votes) %>%
  print(n = Inf)

cat("\nCDs with 0 Republican votes (top-two Dem-vs-Dem race or no Rep on ballot):\n")
cd_house_2024 %>%
  filter(rep_votes == 0) %>%
  select(state_cd, dem_votes, rep_votes, other_votes, total_house_votes) %>%
  print(n = Inf)



# ══════════════════════════════════════════════════════════════════════════════
# SCRIPT 16B: Add 4-way vote shares to cd_house_2024 (cd_pop denominator)
#
# Purpose: Extend cd_house_2024 with four vote shares computed against the
#          citizen voting-age population (cd_pop) rather than total House
#          votes. This adds no_vote_share as a fourth outcome and changes
#          the denominator for the existing three.
#
#
#
#   With cd_pop as the denominator:
#     dem_share     = dem_votes   / cd_pop
#     rep_share     = rep_votes   / cd_pop
#     other_share   = other_votes / cd_pop
#     no_vote_share = (cd_pop - total_house_votes) / cd_pop
#   All four sum to 1 per CD.
#
#
# Input:
#   cd_house_2024.rds (from Script 16A)
#     - dem_votes, rep_votes, other_votes, total_house_votes, 
#       dem_two_party_share
#
#   cd_demographics.rds
#     - state_cd + cd_pop (used as denominator)
#
# Output:
#   cd_house_2024.rds (overwritten with 4 shares against cd_pop)
#
# ══════════════════════════════════════════════════════════════════════════════


library(tidyverse)


# ── 1. Load inputs (Strict Read for Idempotency) ─────────────────────────────# 

cd_house_2024 <- readRDS(file.path(processed_dir, "cd_house_2024.rds")) %>%
  select(-any_of(c("cd_pop", "dem_share", "rep_share", "other_share", "no_vote_share")))

cd_demographics <- readRDS(file.path(processed_dir, "cd_demographics.rds"))


cat("══ Inputs loaded ══\n")
cat("cd_house_2024 rows:  ", nrow(cd_house_2024),   "(expect 435)\n")
cat("cd_demographics rows:", nrow(cd_demographics), "(expect 435)\n")

cat("\nCurrent cd_house_2024 columns:\n")
print(names(cd_house_2024))


# ── 2. Attach cd_pop and rebuild the 4 shares ───────────────────────────────
#
# Step 2a: drop existing share columns if present (defensive — in case we
#          re-run this script). Keeps the file's state predictable.
# Step 2b: drop cd_pop if already attached (so we don't get cd_pop.x / .y
#          from a prior join).
# Step 2c: bring in cd_pop from cd_demographics.
# Step 2d: compute the 4 shares.

cd_house_2024 <- cd_house_2024 %>%
  select(-any_of("cd_pop")) %>%
  left_join(cd_demographics %>% select(state_cd, cd_pop), by = "state_cd") %>%
  mutate(
    dem_share     = dem_votes   / cd_pop,
    rep_share     = rep_votes   / cd_pop,
    other_share   = other_votes / cd_pop,
    no_vote_share = (cd_pop - total_house_votes) / cd_pop
  )


# ── 3. Verify shares sum to 1 per CD ────────────────────────────────────────

share_check <- cd_house_2024 %>%
  mutate(sum_check = dem_share + rep_share + other_share + no_vote_share) %>%
  pull(sum_check)

cat("\n══ 4-way share sum check ══\n")
cat("Range:", round(min(share_check, na.rm = TRUE), 6),
    "to", round(max(share_check, na.rm = TRUE), 6), "\n")
cat("(Should be 1.0 to 1.0)\n")
cat("NAs in sum:", sum(is.na(share_check)), "\n")


# ── 4. Inspect distribution of each share ───────────────────────────────────

cat("\n══ Distribution of 4 shares across all 435 CDs ══\n")
cd_house_2024 %>%
  select(dem_share, rep_share, other_share, no_vote_share) %>%
  pivot_longer(everything(), names_to = "share", values_to = "value") %>%
  group_by(share) %>%
  summarise(
    min    = round(min(value),    4),
    median = round(median(value), 4),
    mean   = round(mean(value),   4),
    max    = round(max(value),    4),
    .groups = "drop"
  ) %>%
  print()


# ── 5. Save updated cd_house_2024 ──────────────────────────────────────────

#Overwrite
saveRDS(cd_house_2024, file.path(processed_dir, "cd_house_2024.rds"))

cat("\nSaved cd_house_2024.rds with 4-way shares (cd_pop denominator)\n")
cat("Final columns:\n")
print(names(cd_house_2024))
