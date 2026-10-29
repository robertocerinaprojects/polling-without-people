# ══════════════════════════════════════════════════════════════════════════════
# SCRIPT 08: CES geographic identifiers + prep inputs for ZCTA crosswalk
#
# Purpose:
#   For CES respondents in the 7 redistricted states (CA, FL, MO, NC, OH, TX,
#   UT), the cdid119 column reflects 2024 boundaries that no longer match
#   2026. This script does the prep work for replacing those assignments:
#     - Audits CES geographic identifiers
#     - Diagnoses why county-based assignment would fail
#     - Loads BAFs, ZCTA-block file, and block populations
#
# Inputs:
#   - ces_harmonized.rds (from Script 07)
#   - 7 state BAFs (TX, CA, MO, NC, OH, UT, FL)
#   - 2020 ZCTA-block relationship file
#   - 2020 block populations (via tidycensus)
#
# Outputs (in-memory; passed to Script 09):
#   - all_bafs              : combined BAFs for 7 states
#   - zcta_block_redistricted : ZCTA-block relationships filtered to 7 states
#   - all_blocks_pop        : 2020 block populations for 7 states
#
# Sections:
#   1. CES geographic identifier audit
#   2. Load and combine BAFs from 7 redistricted states
#   3. County-split and ZIP availability diagnostics
#   4. Load ZCTA-block relationship file and block populations
# ══════════════════════════════════════════════════════════════════════════════


library(here)
library(tidyverse)
library(readxl)
library(readr)
library(data.table)
library(tidycensus)

#Memory intensive operations so increasing the vector memory size
mem.maxVSize(48000)

# ── Folder paths ────────────────────────────────────────────────────────────
raw_dir       <- here("Data_Raw")
processed_dir <- here("Data_Processed")

# ── Load harmonized CES ─────────────────────────────────────────────────────

ces <- readRDS(file.path(processed_dir, "ces_harmonized.rds")) %>%
  select(-any_of(c("cd_2026", "afact", "state_cat", "cd_cat", 
                   "cd_2026.x", "cd_2026.y", "afact.x", "afact.y"))) %>%
  distinct(caseid, .keep_all = TRUE) 
#The select(-any_of..) and distinct() has been added to make Script 10 idempotent (safe to run repeatedly without colliding with its own previous outputs)

# ── Census API setup ────────────────────────────────────────────────────────
readRenviron("~/.Renviron")

# ── 1. CES geographic identifier audit ──────────────────────────────────────

cat("══ inputstate ══\n")
print(class(ces$inputstate))
cat("First 10 values:\n")
print(head(ces$inputstate, 10))
cat("Unique count:", n_distinct(ces$inputstate), "\n\n")

cat("══ cdid119 ══\n")
print(class(ces$cdid119))
cat("First 10 values:\n")
print(head(ces$cdid119, 10))
cat("Unique count:", n_distinct(ces$cdid119), "\n\n")

cat("══ inputzip ══\n")
print(class(ces$inputzip))
cat("First 10 values:\n")
print(head(ces$inputzip, 10))
cat("Unique count:", n_distinct(ces$inputzip), "\n\n")

cat("══ countyfips ══\n")
print(class(ces$countyfips))
cat("First 10 values:\n")
print(head(ces$countyfips, 10))
cat("Unique count:", n_distinct(ces$countyfips), "\n\n")

cat("══ NA counts ══\n")
cat("inputstate NAs:", sum(is.na(ces$inputstate)), "\n")
cat("cdid119 NAs:   ", sum(is.na(ces$cdid119)), "\n")
cat("inputzip NAs:  ", sum(is.na(ces$inputzip)), "\n")
cat("countyfips NAs:", sum(is.na(ces$countyfips)), "\n")


# ── 2. Load and combine BAFs from 7 redistricted states ─────────────────────

# Texas
tx_baf <- read_csv(file.path(raw_dir, "PLANC2333.csv"),
                   col_types = cols(SCTBKEY = col_character(), 
                                    DISTRICT = col_integer())) %>%
  transmute(block_geoid = SCTBKEY, district = DISTRICT, state_fips = "48")

# California
ca_baf <- read_delim(file.path(raw_dir, "ab604.csv"),
                     delim = ",", col_names = c("block_geoid", "district"),
                     col_types = cols(block_geoid = col_character(),
                                      district = col_integer())) %>%
  mutate(state_fips = "06")

# Missouri
mo_baf <- read_excel(file.path(raw_dir, "HB1_Missouri_Congressional_Districts_2025_BEF.xlsx")) %>%
  transmute(block_geoid = as.character(Block), 
            district = as.integer(DistrictID),
            state_fips = "29")

# North Carolina
nc_baf <- read_csv(file.path(raw_dir, "NCGA_CCM-2 .csv"),
                   col_types = cols(Block = col_character(),
                                    District = col_integer())) %>%
  transmute(block_geoid = Block, district = District, state_fips = "37")

# Ohio
oh_baf <- read_excel(file.path(raw_dir, "October 31 2025 CD BAF.xlsx")) %>%
  transmute(block_geoid = as.character(Block), 
            district = as.integer(`DistrictID:1`),
            state_fips = "39")

# Utah
ut_baf <- read_csv(file.path(raw_dir, "ut_cong_adopted_2025_baf.csv"),
                   col_types = cols(GEOID20 = col_character(),
                                    DISTRICT = col_integer())) %>%
  transmute(block_geoid = GEOID20, district = DISTRICT, state_fips = "49")

# Florida
fl_baf <- read_delim(file.path(raw_dir, "EOGPCRP2026.csv"),
                     delim = ",", col_names = c("block_geoid", "district"),
                     col_types = cols(block_geoid = col_character(),
                                      district = col_integer())) %>%
  mutate(state_fips = "12")

# Combine all BAFs
all_bafs <- bind_rows(tx_baf, ca_baf, mo_baf, nc_baf, oh_baf, ut_baf, fl_baf)

cat("Total blocks across 7 states:", nrow(all_bafs), "\n")
cat("States:\n")
print(table(all_bafs$state_fips))


# ── 3. County-split and ZIP availability diagnostics ────────────────────────

# How often do counties split across CDs in each redistricted state?
county_split_analysis <- all_bafs %>%
  mutate(county_fips = substr(block_geoid, 1, 5)) %>%
  group_by(state_fips, county_fips) %>%
  summarise(n_cds = n_distinct(district), .groups = "drop") %>%
  group_by(state_fips, n_cds) %>%
  summarise(n_counties = n(), .groups = "drop")

cat("\n══ County splits across CDs (by state) ══\n")
print(county_split_analysis, n = Inf)

# Aggregate summary
cat("\n══ Overall county split distribution ══\n")
all_bafs %>%
  mutate(county_fips = substr(block_geoid, 1, 5)) %>%
  group_by(state_fips, county_fips) %>%
  summarise(n_cds = n_distinct(district), .groups = "drop") %>%
  count(n_cds) %>%
  print()

# Identify which counties in the 7 redistricted states split across CDs
county_cd_count <- all_bafs %>%
  mutate(county_fips = as.integer(substr(block_geoid, 1, 5))) %>%
  group_by(state_fips, county_fips) %>%
  summarise(n_cds = n_distinct(district), .groups = "drop")

# FIPS codes of the 7 redistricted states
redistricted_fips <- c(6, 12, 29, 37, 39, 48, 49)

# How many CES respondents are in each scenario?
ces_geo_breakdown <- ces %>%
  filter(inputstate %in% redistricted_fips) %>%
  mutate(countyfips = sprintf("%05d", as.integer(countyfips))) %>%
  left_join(
    county_cd_count %>%
      mutate(state_fips_int = as.integer(state_fips),
             county_fips    = sprintf("%05d", as.integer(county_fips))),
    by = c("inputstate" = "state_fips_int",
           "countyfips"  = "county_fips")
  ) %>%
  mutate(scenario = case_when(
    is.na(n_cds)   ~ "Unmatched (no county)",
    n_cds == 1     ~ "Clean (1 CD)",
    n_cds == 2     ~ "2 CDs",
    n_cds == 3     ~ "3 CDs",
    n_cds %in% 4:9 ~ "4-9 CDs",
    n_cds >= 10    ~ "10+ CDs (LA County)",
    TRUE           ~ "Unknown"
  ))

cat("══ CES respondents in redistricted states, by county scenario ══\n")
ces_geo_breakdown %>%
  count(scenario) %>%
  mutate(pct = round(100 * n / sum(n), 2)) %>%
  print()

# By state breakdown
cat("\n══ Same breakdown by state ══\n")
ces_geo_breakdown %>%
  count(inputstate, scenario) %>%
  group_by(inputstate) %>%
  mutate(pct_within_state = round(100 * n / sum(n), 1)) %>%
  ungroup() %>%
  arrange(inputstate, scenario) %>%
  print(n = Inf)

# Compare to all CES (including stable states)
cat("\n══ CES geography summary ══\n")
cat("CES total:                          ", nrow(ces), "\n")
cat("In stable states (cdid119 works):   ", 
    sum(!ces$inputstate %in% redistricted_fips), "\n")
cat("In redistricted states (need fix):  ", 
    sum(ces$inputstate %in% redistricted_fips), "\n")

# Overall ZIP availability
cat("\n══ Overall ZIP availability in CES ══\n")
ces %>%
  mutate(has_zip = !is.na(inputzip)) %>%
  count(has_zip) %>%
  mutate(pct = round(100 * n / sum(n), 1)) %>%
  print()

# ZIP availability by state (redistricted vs stable)
cat("\n══ ZIP availability: redistricted vs stable states ══\n")
ces %>%
  mutate(
    has_zip = !is.na(inputzip),
    state_type = if_else(inputstate %in% redistricted_fips, 
                         "Redistricted", "Stable")
  ) %>%
  count(state_type, has_zip) %>%
  group_by(state_type) %>%
  mutate(pct = round(100 * n / sum(n), 1)) %>%
  print()

# ZIP availability for each redistricted state
cat("\n══ ZIP availability per redistricted state ══\n")
ces %>%
  filter(inputstate %in% redistricted_fips) %>%
  mutate(has_zip = !is.na(inputzip)) %>%
  count(inputstate, has_zip) %>%
  group_by(inputstate) %>%
  mutate(pct = round(100 * n / sum(n), 1)) %>%
  print(n = Inf)

# ZIP availability by county split scenario
cat("\n══ ZIP availability by county split scenario (redistricted states) ══\n")
ces_geo_breakdown %>%
  mutate(has_zip = !is.na(inputzip)) %>%
  count(scenario, has_zip) %>%
  group_by(scenario) %>%
  mutate(pct = round(100 * n / sum(n), 1)) %>%
  print(n = Inf)

# Inspect alternative ZIP columns
cat("══ lookupzip distribution ══\n")
cat("Class:", class(ces$lookupzip), "\n")
cat("NAs:", sum(is.na(ces$lookupzip)), "of", nrow(ces), "\n")
head(ces$lookupzip, 20)

cat("\n══ regzip ══\n")
cat("Class:", class(ces$regzip), "\n")
cat("NAs:", sum(is.na(ces$regzip)), "\n")
head(ces$regzip, 20)

cat("\n══ urbancity distribution ══\n")
print(class(ces$urbancity))
ces %>% count(urbancity) %>% print()

# Compare ZIP availability across pre/post wave columns
cat("\n══ Are post-wave ZIPs more complete? ══\n")
cat("inputzip NAs:      ", sum(is.na(ces$inputzip)), "\n")
cat("inputzip_post NAs: ", sum(is.na(ces$inputzip_post)), "\n")
cat("regzip NAs:        ", sum(is.na(ces$regzip)), "\n")
cat("regzip_post NAs:   ", sum(is.na(ces$regzip_post)), "\n")
cat("lookupzip NAs:     ", sum(is.na(ces$lookupzip)), "\n")
cat("lookupzip_post NAs:", sum(is.na(ces$lookupzip_post)), "\n")

# Verify ZIP format
cat("══ lookupzip character lengths ══\n")
ces %>%
  mutate(zip_len = nchar(lookupzip)) %>%
  count(zip_len) %>%
  print()

# Sample by state to verify reasonable ZIPs
cat("\n══ Sample lookupzips by state ══\n")
ces %>%
  filter(inputstate %in% c(48, 6, 12)) %>%
  select(inputstate, lookupzip) %>%
  group_by(inputstate) %>%
  slice_sample(n = 5) %>%
  print()

# Check distinct ZIPs
cat("\n══ Unique lookupzips ══\n")
cat("Total unique:", n_distinct(ces$lookupzip), "\n")


# ── 4. Load ZCTA-block relationship file and block populations ──────────────

# Load ZCTA-block relationship file
# Read only needed columns -- much faster and less memory
zcta_block <- fread(
  file.path(raw_dir, "tab20_zcta520_tabblock20_natl.txt"),
  sep = "|",
  select = c("GEOID_ZCTA5_20", "GEOID_TABBLOCK_20"),
  colClasses = list(character = c("GEOID_ZCTA5_20", "GEOID_TABBLOCK_20"))
)

cat("Dimensions:", nrow(zcta_block), "rows x", ncol(zcta_block), "cols\n")
cat("\nFirst 5 rows:\n")
print(head(zcta_block, 5))

# Drop blocks without ZCTA assignment (uninhabited/water)
cat("\nBlocks without ZCTA:", sum(is.na(zcta_block$GEOID_ZCTA5_20) | 
                                    zcta_block$GEOID_ZCTA5_20 == ""), "\n")

zcta_block <- zcta_block[GEOID_ZCTA5_20 != "" & !is.na(GEOID_ZCTA5_20)]

cat("After dropping unassigned:", nrow(zcta_block), "rows\n")

# Filter to 7 redistricted states (state FIPS = first 2 chars of block GEOID)
redistricted_state_fips <- c("06", "12", "29", "37", "39", "48", "49")
zcta_block_redistricted <- zcta_block[substr(GEOID_TABBLOCK_20, 1, 2) %in% redistricted_state_fips]

cat("\nFiltered to 7 redistricted states:", nrow(zcta_block_redistricted), "rows\n")


# Quick verify: how many unique ZCTAs in our 7 states?
cat("Unique ZCTAs in redistricted states:", 
    length(unique(zcta_block_redistricted$GEOID_ZCTA5_20)), "\n")

# Pull 2020 block-level population for the 7 redistricted states
states_needed <- c("CA", "FL", "MO", "NC", "OH", "UT", "TX")

all_blocks_pop <- map_dfr(states_needed, function(st) {
  cat("Pulling", st, "blocks...\n")
  get_decennial(
    geography = "block",
    variables = "P1_001N",
    year      = 2020,
    sumfile   = "pl",
    state     = st
  ) %>% select(GEOID, value)
})

cat("\nDone. Total block-pop records pulled:", nrow(all_blocks_pop), "\n")
cat("Total population covered:", sum(all_blocks_pop$value), "\n")


# ── 5. Save all bafs and all block pop files ──────────────

saveRDS(all_bafs, file.path(processed_dir, "all_bafs.rds"))
saveRDS(all_blocks_pop, file.path(processed_dir, "all_blocks_pop.rds"))



# ══════════════════════════════════════════════════════════════════════════════
# SCRIPT 09: Build ZCTA-to-2026-CD crosswalk for redistricted states
#
# Purpose:
#   Build a ZCTA-level crosswalk to 2026 Congressional Districts for the 7
#   redistricted states (CA, FL, MO, NC, OH, TX, UT). Used by Script 10 to
#   assign CES survey respondents to their 2026 CD via the lookupzip field
#   (5-digit ZIP, available for all respondents).
#
# Architecture (parallels Script 04's PUMA-to-CD work):
#
#     Block GEOID
#         |---> ZCTA       (from Census ZCTA-Block relationship file)
#         |---> 2026 CD    (from state BAFs)
#         |---> Population (from 2020 Decennial via tidycensus)
#         |
#         ↓ aggregate by (ZCTA, CD)
#     ZCTA × CD intersections with summed population
#         |
#         ↓ afact = pop_intersection / zcta_pop
#     Final crosswalk: each ZCTA → list of (CD, afact) pairs
#
# Inputs (in-memory from Script 08):
#   - all_bafs
#   - zcta_block_redistricted
#   - all_blocks_pop
#
# Output:
#   - zcta_cd_crosswalk_redistricted.rds
#     Columns: state_fips, zcta, cd_new, pop_intersection, zcta_pop, afact
#
# Sections:
# Sections:
#   1. Join block-level data (BAF + ZCTA + population)
#   2. Aggregate to ZCTA × CD level
#   3. Compute afact (ZCTA → CD allocation factor)
#   4. Initial validation: afact sums to 1.0 per ZCTA
#   5. Distribution diagnostic (how many CDs per ZCTA)
#   6. Handle zero-pop ZCTAs; re-validate
#   7. Check CES respondents affected by dropped ZCTAs
#   8. Save final crosswalk
# ══════════════════════════════════════════════════════════════════════════════


# ── 1. Join block-level data: BAF (CD) + ZCTA + population ──────────────────
#
# Three inputs:
#   all_bafs                 -- block_geoid, district, state_fips (from BAFs)
#   zcta_block_redistricted  -- block_geoid, zcta (Census relationship file)
#   all_blocks_pop           -- block_geoid, pop (tidycensus 2020 Decennial)
#
# Inner joins ensure each block has all three pieces of info. The expected
# loss of a few thousand blocks is from the ~145K nationwide uninhabited
# (water/empty) blocks that have no ZCTA assignment -- those drop out here.

baf_data <- all_bafs %>%
  rename(block_geoid = block_geoid, district = district)

block_zcta <- zcta_block_redistricted %>%
  rename(block_geoid = GEOID_TABBLOCK_20,
         zcta        = GEOID_ZCTA5_20)

block_pop <- all_blocks_pop %>%
  rename(block_geoid = GEOID,
         pop         = value)

# Each block now has: state_fips, district (CD), zcta, pop
block_full <- baf_data %>%
  inner_join(block_zcta, by = "block_geoid") %>%
  inner_join(block_pop,  by = "block_geoid")

cat("══ Block-level join results ══\n")
cat("Blocks in BAFs:       ", nrow(baf_data), "\n")
cat("Blocks in ZCTA file:  ", nrow(block_zcta), "\n")
cat("Blocks in pop file:   ", nrow(block_pop), "\n")
cat("After all joins:      ", nrow(block_full), "\n")
cat("Population covered:   ", sum(block_full$pop), "\n")


# ── 2. Aggregate to ZCTA × CD level ─────────────────────────────────────────
#
# For each (state, ZCTA, CD) combination, sum block populations. This gives
# us the population of each ZCTA × CD intersection cell.
#
# A ZCTA that sits entirely within one CD will have exactly one row here.
# A ZCTA that straddles a CD boundary will have multiple rows (one per CD).

zcta_cd_crosswalk <- block_full %>%
  group_by(state_fips, zcta, cd_new = district) %>%
  summarise(
    pop_intersection = sum(pop),
    n_blocks         = n(),
    .groups = "drop"
  )

cat("\n══ ZCTA × CD intersections ══\n")
cat("Rows:", nrow(zcta_cd_crosswalk), "\n")
cat("Unique ZCTAs:", n_distinct(zcta_cd_crosswalk$zcta), "\n")


# ── 3. Compute afact (ZCTA → CD allocation factor) ──────────────────────────
#
# afact = pop in this (ZCTA × CD) intersection / total ZCTA population
#
# This is the same logic as PUMA → CD allocation: a respondent in a split
# ZCTA gets multiple rows after the join, one per CD, weighted by the
# fraction of their ZCTA's population in that CD.
#
# afact values for any given ZCTA must sum to exactly 1.0 across its CDs
# (modulo floating-point rounding) -- validated in step 4.

zcta_cd_crosswalk <- zcta_cd_crosswalk %>%
  group_by(state_fips, zcta) %>%
  mutate(
    zcta_pop = sum(pop_intersection),
    afact    = pop_intersection / zcta_pop
  ) %>%
  ungroup()


# ── 4. Validate afact sums to 1.0 per ZCTA ──────────────────────────────────
#
# Sanity check on the math: every ZCTA's afact values across all its CDs
# should sum to 1.0. If any don't, there's a data integrity issue.

afact_check <- zcta_cd_crosswalk %>%
  group_by(state_fips, zcta) %>%
  summarise(afact_sum = sum(afact), .groups = "drop")

cat("\nafact sum range:", round(min(afact_check$afact_sum), 6), 
    "to", round(max(afact_check$afact_sum), 6), "\n")
cat("ZCTAs where afact != 1:", sum(round(afact_check$afact_sum, 4) != 1), "\n")


# ── 5. Distribution: how clean is ZCTA → CD assignment? ─────────────────────
#
# This is the key diagnostic for the CES geography problem.
#
# If most ZCTAs nest cleanly within one CD, our fractional allocation has
# very few entries and the ZCTA-based geography is essentially as good as
# precise individual-level assignment.
#
# If many ZCTAs split across multiple CDs (especially in urban areas), we
# get noise in CD-level estimates because each respondent gets diluted
# across multiple CDs. We expect this to be much better than the county
# breakdown we saw earlier (where 67% of redistricted-state respondents
# were in split counties).

cat("\n══ Distribution: how many CDs per ZCTA? ══\n")
zcta_cd_crosswalk %>%
  group_by(state_fips, zcta) %>%
  summarise(n_cds = n(), .groups = "drop") %>%
  count(n_cds, name = "n_zctas") %>%
  print()

# Breakdown by state -- shows which states have cleaner ZCTA assignments
cat("\n══ Same distribution by state ══\n")
zcta_cd_crosswalk %>%
  group_by(state_fips, zcta) %>%
  summarise(n_cds = n(), .groups = "drop") %>%
  count(state_fips, n_cds, name = "n_zctas") %>%
  print(n = Inf)



# ── 6. Handle zero-pop ZCTAs (bug fix) ──────────────────────────────────────
#
# afact validation showed NaN values because some ZCTAs have zcta_pop = 0
# (division by zero). These are ZCTAs that exist geographically but contain
# only blocks with zero population (industrial zones, parks, water-only
# areas). Drop them, re-validate, and re-save.

##Post run diagnostics and bug clean up
#The bug: afact validation shows NaN
#This means some ZCTAs have zcta_pop = 0 causing division by zero. 
#These are ZCTAs that exist geographically but contain only 
#blocks with zero population. 
# Check for zero-pop ZCTAs
cat("══ ZCTAs with zero total population ══\n")
zero_pop_zctas <- zcta_cd_crosswalk %>%
  group_by(state_fips, zcta) %>%
  summarise(total_pop = sum(pop_intersection), .groups = "drop") %>%
  filter(total_pop == 0)

cat("Number of zero-pop ZCTAs:", nrow(zero_pop_zctas), "\n")
cat("\nFirst few:\n")
print(head(zero_pop_zctas, 10))

# These are ZCTAs with only empty blocks -- can't be assigned to a CD
# Drop them since no real CES respondent should be in them anyway
zcta_cd_crosswalk <- zcta_cd_crosswalk %>%
  filter(zcta_pop > 0)

# Re-validate
afact_check <- zcta_cd_crosswalk %>%
  group_by(state_fips, zcta) %>%
  summarise(afact_sum = sum(afact), .groups = "drop")

cat("\nAfter dropping zero-pop ZCTAs:\n")
cat("afact sum range:", round(min(afact_check$afact_sum), 6),
    "to", round(max(afact_check$afact_sum), 6), "\n")
cat("ZCTAs where afact != 1:", sum(round(afact_check$afact_sum, 4) != 1), "\n")


# ── 7. Check CES respondents in dropped zero-pop ZCTAs ──────────────────────
#
# Real CES respondents shouldn't appear in zero-pop ZCTAs since YouGov
# validates lookupzip against actual residence. But a small number may
# appear from business-address registrations or stale geocoder hits.
# Script 10 will handle them via cdid119 fallback.

##Check if any of the CES respondents zip belongs to these zero-pop ZCTAs
# Check if any CES respondents have lookupzip values that are zero-pop ZCTAs
redistricted_state_fips_int <- c(6, 12, 29, 37, 39, 48, 49)

zero_pop_zcta_codes <- zero_pop_zctas$zcta

ces_in_zero_pop <- ces %>%
  filter(inputstate %in% redistricted_state_fips_int) %>%
  filter(lookupzip %in% zero_pop_zcta_codes)

cat("CES respondents in zero-pop ZCTAs:", nrow(ces_in_zero_pop), "\n")
if (nrow(ces_in_zero_pop) > 0) {
  cat("\nBreakdown:\n")
  print(table(ces_in_zero_pop$lookupzip))
}

# What does cdid119 say for this respondent? And what's the population context?
ces_in_zero_pop %>%
  select(inputstate, lookupzip, cdid119, countyfips, countyname) %>%
  print()

# ── 8. Save crosswalk ───────────────────────────────────────────────────────
#
# This is the final output of this script. It will be loaded later when
# we apply it to CES lookupzip values to assign each CES respondent
# (in a redistricted state) to their 2026 CD.

saveRDS(zcta_cd_crosswalk, file.path(processed_dir, "zcta_cd_crosswalk_redistricted.rds"))
cat("\nSaved ZCTA crosswalk\n")
cat("File size:", 
    round(file.size(file.path(processed_dir, "zcta_cd_crosswalk_redistricted.rds")) / 1e6, 2), 
    "MB\n")

# -- 9. Clean Up Memory ------------------------------
#Some massive files are loaded in these last two scripts. Clearing memory here ensures
# R does not crash while running the next script (10)

# ── Clean up massive intermediate block tables before running Script 10 ──
rm(
  list = intersect(
    c("zcta_block_redistricted", "all_bafs", 
      "all_blocks_pop", "baf_data", "block_zcta", "block_pop", "block_full"),
    ls()
  )
)
gc() # Forces garbage collection to immediately reclaim several GBs of RAM



# ══════════════════════════════════════════════════════════════════════════════
# SCRIPT 10: Apply ZCTA crosswalk + finalize geographic alignment
#
# Purpose:
#   Assign a 2026 CD to every CES respondent and standardize geographic
#   identifiers (state_cat, cd_cat) across CES and PUMS. After this script,
#   both datasets can be joined on (state_cat, cd_cat) for CD-level modeling
#   and poststratification.
#
# Assignment logic:
#   IF respondent in non-redistricted state:
#     cd_2026 = cdid119 (already correct since boundaries unchanged)
#     afact = 1.0
#   IF respondent in redistricted state:
#     Look up lookupzip in zcta_cd_crosswalk
#     If matched: produce 1+ rows (one per CD ZCTA spans) with afact weights
#     If unmatched (zero-pop ZCTA or non-ZCTA ZIP): fall back to cdid119,
#       afact = 1.0
#
# Inputs (pums_crosswalked which might need to be loaded since it wasn't part of scripts 8-9, others must be in-memory already):
#   - ces (harmonized; from Script 07, also read in script 08)
#   - pums_crosswalked (harmonized; from Script 07)
#   - zcta_cd_crosswalk (from Script 09)
#   - zcta_block (full ZCTA-block file from Script 08; used for diagnostics)
#
# Outputs (overwrite Script 07 versions):
#   - ces_harmonized.rds (with cd_2026, afact, state_cat, cd_cat)
#   - pums_crosswalked_harmonized.rds (with state_cat, cd_cat)
#
# Encoding decisions:
#   - At-large states (AK, DE, ND, SD, VT, WY): PUMS uses cd=0, CES uses cd=1.
#     Standardize PUMS to use 1, matching CES.
#   - DC: dropped from both datasets (no voting House seat).
#
# Sections:
#   1. Stable-state respondents: cdid119 is correct
#   2. Redistricted-state respondents: join via ZCTA
#   3. Unmatched redistricted respondents: cdid119 fallback
#   4. Combine + validate
#   5. Fallback respondent diagnostics
#   6. Create state_cat and cd_cat; alignment check between PUMS and CES
#   7. Handle at-large states and DC; re-validate alignment
#   8. Final summary and save
# ══════════════════════════════════════════════════════════════════════════════

library(tidyverse)

# Constants used across sections
redistricted_state_fips_int <- c(6, 12, 29, 37, 39, 48, 49)
at_large_fips               <- c(2, 10, 38, 46, 50, 56)  # AK, DE, ND, SD, VT, WY


# Constants used across sections
redistricted_state_fips_int <- c(6, 12, 29, 37, 39, 48, 49)
at_large_fips               <- c(2, 10, 38, 46, 50, 56)  # AK, DE, ND, SD, VT, WY

# Input loads (only needed if not already in memory from running Scripts 08-09)
# Comment out any that are already loaded.

pums_crosswalked <- readRDS(file.path(processed_dir, "pums_crosswalked_harmonized.rds"))

# ── 1. Stable-state respondents: cdid119 is correct ─────────────────────────
# Stable-state respondents get one row per respondent with afact = 1.0.

ces_stable <- ces %>%
  filter(!inputstate %in% redistricted_state_fips_int) %>%
  mutate(
    cd_2026 = cdid119,
    afact   = 1.0
  )

cat("Stable-state respondents:", nrow(ces_stable), "\n")


# ── 2. Redistricted-state respondents: join via ZCTA ────────────────────────
# Respondents in split ZCTAs get multiple rows (one per CD their ZCTA spans),
# each with the corresponding afact weight.

# Prepare crosswalk for join: zcta as character, cd_new renamed to cd_2026
zcta_xw_for_join <- zcta_cd_crosswalk %>%
  select(zcta, cd_2026 = cd_new, afact)

ces_redistricted_matched <- ces %>%
  filter(inputstate %in% redistricted_state_fips_int) %>%
  inner_join(zcta_xw_for_join, by = c("lookupzip" = "zcta"),
            relationship = "many-to-many")
# ^ genuinely M:M — many respondents share a ZIP, many CDs per ZCTA.
#   Verified: afact sums to 1 per caseid, output = 69,020 rows.

cat("Redistricted-state respondents matched via ZCTA:", 
    nrow(ces_redistricted_matched), "\n")


# ── 3. Unmatched redistricted respondents: cdid119 fallback ─────────────────
# Respondents whose lookupzip doesn't appear in the ZCTA crosswalk
# (zero-pop ZCTAs dropped in Script 09, or non-ZCTA ZIPs entirely).
# Fall back to cdid119 with afact = 1.0.

ces_redistricted_unmatched <- ces %>%
  filter(inputstate %in% redistricted_state_fips_int) %>%
  anti_join(zcta_xw_for_join, by = c("lookupzip" = "zcta")) %>%
  mutate(
    cd_2026 = cdid119,
    afact   = 1.0
  )

cat("Redistricted-state respondents using cdid119 fallback:", 
    nrow(ces_redistricted_unmatched), "\n")


# ── 4. Combine and validate ─────────────────────────────────────────────────
ces_with_cd <- bind_rows(
  ces_stable,
  ces_redistricted_matched,
  ces_redistricted_unmatched
)

cat("\n══ Combined dataset ══\n")
cat("Total rows:", nrow(ces_with_cd), "\n")
cat("Distinct CES respondents:", n_distinct(ces_with_cd$caseid), "\n")
cat("Row inflation factor:", 
    round(nrow(ces_with_cd) / n_distinct(ces_with_cd$caseid), 3), "\n")

# Each respondent's afact values should sum to 1.0 across all their rows
afact_check <- ces_with_cd %>%
  group_by(caseid) %>%
  summarise(afact_sum = sum(afact), .groups = "drop")

cat("\nafact sum range across respondents:", 
    round(min(afact_check$afact_sum), 4), "to",
    round(max(afact_check$afact_sum), 4), "\n")
cat("Respondents where afact != 1.0:", 
    sum(round(afact_check$afact_sum, 4) != 1), "\n")
cat("Missing cd_2026:", sum(is.na(ces_with_cd$cd_2026)), "\n")


# ── 5. Fallback respondent diagnostics ──────────────────────────────────────
# Examine the redistricted-state respondents who fell back to cdid119.
# Are their lookupzip values in the Census ZCTA file (zero-pop ZCTAs dropped
# in Script 09) or non-ZCTA ZIPs entirely (PO Box, business-only)?

n_fallback <- nrow(ces_redistricted_unmatched)
cat("══ Fallback respondents (", n_fallback, ") — breakdown by state and ZIP ══\n", sep = "")
ces_redistricted_unmatched %>%
  select(inputstate, lookupzip, cdid119, countyfips, countyname) %>%
  group_by(inputstate, lookupzip) %>%
  summarise(
    n_respondents = n(),
    cdid119_values = paste(unique(cdid119), collapse = ","),
    .groups = "drop"
  ) %>%
  arrange(desc(n_respondents)) %>%
  print(n = Inf)

cat("\n══ Are these ZIPs in the full ZCTA file? ══\n")
fallback_zips <- unique(ces_redistricted_unmatched$lookupzip)
cat("Total fallback ZIPs:", length(fallback_zips), "\n")

zips_in_zcta_file <- zcta_block %>%
  as_tibble() %>%
  filter(GEOID_ZCTA5_20 %in% fallback_zips) %>%
  distinct(GEOID_ZCTA5_20)

cat("\nThese ZIPs DO appear as ZCTAs (but got dropped as zero-pop):\n")
print(zips_in_zcta_file, n = Inf)

cat("\nThese ZIPs do NOT appear as ZCTAs at all (PO Box, business-only, etc.):\n")
zips_not_in_zcta <- setdiff(fallback_zips, zips_in_zcta_file$GEOID_ZCTA5_20)
print(zips_not_in_zcta)

# Human-readable per-state breakdown
state_lookup <- tibble(
  fips = c(6, 12, 29, 37, 39, 48, 49),
  abb  = c("CA", "FL", "MO", "NC", "OH", "TX", "UT"),
  name = c("California", "Florida", "Missouri", "North Carolina", 
           "Ohio", "Texas", "Utah")
)

cat("\n══ Per-state breakdown ══\n")
ces_redistricted_unmatched %>%
  select(inputstate, lookupzip, cdid119, countyfips, countyname) %>%
  left_join(state_lookup, by = c("inputstate" = "fips")) %>%
  select(state_abb = abb, state_name = name, lookupzip, cdid119, countyfips, countyname) %>%
  group_by(state_abb, state_name, lookupzip, cdid119, countyfips, countyname) %>%
  summarise(n_respondents = n(), .groups = "drop") %>%
  arrange(state_abb, lookupzip) %>%
  print(n = Inf)


# ── 6. Create state_cat and cd_cat; alignment check ─────────────────────────
# Both datasets get standardized integer state_cat and cd_cat columns.
# PUMS: cd_2026 column already contains 2026 CD (mixed origin: 119th boundaries
#       for stable states, 2026 boundaries for redistricted states)
# CES:  cd_2026 column created in sections 1-3

pums_crosswalked <- pums_crosswalked %>%
  mutate(
    state_cat = as.integer(STATEFIP),
    cd_cat    = as.integer(cd_2026)
  )

ces_with_cd <- ces_with_cd %>%
  mutate(
    state_cat = as.integer(inputstate),
    cd_cat    = as.integer(cd_2026)
  )

# Verify column types match
cat("══ PUMS state_cat and cd_cat ══\n")
cat("state_cat class:", class(pums_crosswalked$state_cat), "\n")
cat("cd_cat class:   ", class(pums_crosswalked$cd_cat), "\n")
cat("Unique state+CD combos:", 
    n_distinct(paste(pums_crosswalked$state_cat, pums_crosswalked$cd_cat)), "\n")

cat("\n══ CES state_cat and cd_cat ══\n")
cat("state_cat class:", class(ces_with_cd$state_cat), "\n")
cat("cd_cat class:   ", class(ces_with_cd$cd_cat), "\n")
cat("Unique state+CD combos:", 
    n_distinct(paste(ces_with_cd$state_cat, ces_with_cd$cd_cat)), "\n")

# Alignment check: do both datasets reference the same set of CDs?
pums_combos <- pums_crosswalked %>% distinct(state_cat, cd_cat)
ces_combos  <- ces_with_cd      %>% distinct(state_cat, cd_cat)

cat("\n══ Combos in PUMS but not in CES (PUMS-only) ══\n")
anti_join(pums_combos, ces_combos, by = c("state_cat", "cd_cat")) %>%
  count() %>% print()

cat("\n══ Combos in CES but not in PUMS (CES-only) ══\n")
anti_join(ces_combos, pums_combos, by = c("state_cat", "cd_cat")) %>%
  print(n = Inf)

# Inspect at-large state codings to understand the mismatch
cat("\n══ cdid119 values in CES for at-large states ══\n")
ces_with_cd %>%
  filter(inputstate %in% at_large_fips) %>%
  count(inputstate, cdid119, cd_cat) %>%
  print()

cat("\n══ Distinct cdid119 values across CES ══\n")
cat("Min:", min(ces$cdid119, na.rm = TRUE), "\n")
cat("Max:", max(ces$cdid119, na.rm = TRUE), "\n")
cat("Sorted distinct values:", paste(sort(unique(ces$cdid119)), collapse = ","), "\n")

cat("\n══ CES values for DC respondents ══\n")
ces_with_cd %>%
  filter(inputstate == 11) %>%
  count(cdid119, cd_cat) %>%
  print()
cat("Total DC respondents:", sum(ces_with_cd$inputstate == 11), "\n")


# ── 7. Handle at-large states and DC; re-validate ───────────────────────────
# Two encoding issues:
#
# 1. At-large states (AK, DE, ND, SD, VT, WY):
#    PUMS (Geocorr convention): cd_cat = 0
#    CES (standard convention): cd_cat = 1
#    Standardize PUMS to use 1, matching CES.
#
# 2. DC:
#    PUMS (Geocorr): state = 11, cd = 98 (non-voting delegate)
#    CES: state = 11, cd = 1
#    Drop DC entirely from both datasets. DC has a non-voting delegate,
#    not a House seat, so it has no place in a 435-CD frame.

#-------This is a memory management step before the next runs so R does not crash---#
# Drop the 8-million row national zcta table  to free ~500MB+ RAM
rm(zcta_block)
gc()

# PUMS: drop DC, then recode at-large CDs from 0 to 1
# Note: Memory intensive operation, so we will do it in a memory efficient way
library(data.table)

# 1. Convert to data.table by reference (zero memory copy)
setDT(pums_crosswalked)

# 2. Filter out DC (allocates the subset and immediately releases the old table)
pums_crosswalked <- pums_crosswalked[state_cat != 11]

# 3. Force garbage collection to reclaim RAM from the dropped DC rows
gc()

# 4. Mutate at-large CDs IN-PLACE (zero memory copy — only modifies rows where cd_cat == 0)
pums_crosswalked[cd_cat == 0L, cd_cat := 1L]

# CES: drop DC
ces_with_cd <- ces_with_cd %>%
  filter(state_cat != 11)

# Re-validate alignment
pums_combos <- pums_crosswalked %>% distinct(state_cat, cd_cat)
ces_combos  <- ces_with_cd      %>% distinct(state_cat, cd_cat)


cat("══ Combos in PUMS but not in CES (after fixes) ══\n")
anti_join(pums_combos, ces_combos, by = c("state_cat", "cd_cat")) %>%
  as_tibble() %>%
  print(n = Inf)

cat("\n══ Combos in CES but not in PUMS (after fixes) ══\n")
anti_join(ces_combos, pums_combos, by = c("state_cat", "cd_cat")) %>%
  as_tibble() %>%
  print(n = Inf)


# ── 8. Final summary and save ───────────────────────────────────────────────

cat("\n══ Final state+CD coverage ══\n")
cat("PUMS unique state+CD combos:", 
    n_distinct(paste(pums_crosswalked$state_cat, pums_crosswalked$cd_cat)), 
    "(expect 435)\n")
cat("CES unique state+CD combos: ", 
    n_distinct(paste(ces_with_cd$state_cat, ces_with_cd$cd_cat)), 
    "(expect 435)\n")
cat("\nPUMS rows:", nrow(pums_crosswalked), "\n")
cat("CES rows: ", nrow(ces_with_cd), "\n")

saveRDS(pums_crosswalked, file.path(processed_dir, "pums_crosswalked_harmonized.rds"))
saveRDS(ces_with_cd, file.path(processed_dir, "ces_harmonized.rds"))

cat("\nSaved.\n")
