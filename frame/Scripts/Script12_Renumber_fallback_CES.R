# ══════════════════════════════════════════════════════════════════════════════
# SCRIPT 12: Renumber fallback CES respondents' cd_2026
#
# Purpose:
#   For the ~59 CES respondents in redistricted states whose lookupzip
#   didn't resolve to a populated ZCTA in Script 09 (PO Box, business,
#   military, or empty ZIPs), refine their cd_2026 assignment using a
#   CD119 → CD2026 renumbering heuristic: assume the old CD's geographic
#   area now lies majority in the new CD with the largest population overlap.
#
# Background:
#   At the end of Script 10, these ~59 respondents had cd_2026 = cdid119 as
#   a fallback. For most this is approximately right (the area kept the same
#   CD number under 2026 boundaries). For some, the CD got renumbered and
#   cdid119 is stale.
#
#   Per Roberto's guidance: this is an approximate fix. The overlap is often
#   partial (<90% in many cases), but it's better than blindly trusting
#   cdid119. The approach is "if we don't know for a fact, assume the
#   majority overlap."
#
# Two sub-scripts:
#   12A — Build CD119 → CD2026 renumbering map (sections 1-5)
#   12B — Apply renumbering map to fallback respondents (sections 6-8)
#
# Inputs:
#   - NationalCD119.txt (Census Bureau, 119th Congress BAF)
#   - all_bafs (in-memory from Script 08)
#   - all_blocks_pop (in-memory from Script 08)
#   - zcta_cd_crosswalk (in-memory from Script 09)
#   - ces_with_cd (in-memory from Script 10)
#   - pums_crosswalked (in-memory from Script 10; used for alignment check)
#
# Output:
#   - cd119_to_cd2026 (Renumbering map. For each old (119th Congress / 2024) CD in the 7 redistricted states, which 2026 CD does most of its population now live in?)
#   - ces_with_cd_v2.rds (CES with corrected cd_2026 for fallback respondents)
#
# Sections (12A — build the map):
#   1. Load and inspect NationalCD119 BAF
#   2. Filter to redistricted states; standardize columns
#   3. Join block-level data (CD119 + 2026 CD + population)
#   4. Aggregate to find max-overlap CD2026 per (state, CD119)
#   5. Diagnostics
#
# Sections (12B — apply the map):
#   6. Prepare the renumbering lookup
#   7. Apply renumbering to fallback respondents
#   8. Verification and save
# ══════════════════════════════════════════════════════════════════════════════

library(tidyverse)
library(data.table)


# ══════════════════════════════════════════════════════════════════════════════
# SCRIPT 12A: Build CD119 → CD2026 renumbering map
# ══════════════════════════════════════════════════════════════════════════════

# ── 1. Load files and inspect NationalCD119 BAF ───────────────────────────────────

library(here)
library(tidyverse)
library(data.table)

# ── Folder paths ────────────────────────────────────────────────────────────
raw_dir       <- here("Data_Raw")
processed_dir <- here("Data_Processed")

# ── Load inputs from disk  ──────────────────────────

all_bafs <- readRDS(file.path(processed_dir, "all_bafs.rds"))



all_blocks_pop <- readRDS(file.path(processed_dir, "all_blocks_pop.rds"))



zcta_cd_crosswalk <- readRDS(file.path(processed_dir, "zcta_cd_crosswalk_redistricted.rds"))



ces_with_cd <- readRDS(file.path(processed_dir, "ces_harmonized.rds"))



pums_crosswalked <- readRDS(file.path(processed_dir, "pums_crosswalked_harmonized.rds"))


# ── Load NationalCD119 BAF ──────────────────────────────────────────────────
cd119_baf <- fread(
  file.path(raw_dir, "NationalCD119.txt"),
  colClasses = list(character = 1:2)
)
# Each row maps a 2020 Census block (GEOID) to its 119th Congress CD (CDFP).


cat("══ NationalCD119 BAF ══\n")
cat("Rows:", nrow(cd119_baf), "\n")
cat("Columns:", paste(names(cd119_baf), collapse = ", "), "\n")
cat("First 5 rows:\n")
print(head(cd119_baf, 5))


# ── 2. Filter to redistricted states; standardize columns and save ───────────────────
# Only the 7 redistricted states need renumbering. Drop "ZZ" entries
# (uninhabited blocks with no CD assignment).

redistricted_state_fips <- c("06", "12", "29", "37", "39", "48", "49")

cd119_redistricted <- cd119_baf %>%
  as_tibble() %>%
  filter(substr(GEOID, 1, 2) %in% redistricted_state_fips,
         CDFP != "ZZ") %>%
  rename(block_geoid = GEOID, cd_119 = CDFP) %>%
  mutate(cd_119 = as.integer(cd_119))

cat("\n══ Filtered to 7 redistricted states ══\n")
cat("Blocks:", nrow(cd119_redistricted), "\n")


# ── 3. Join block-level data (CD119 + 2026 CD + population) ─────────────────
# Each block needs three pieces of information:
#   - cd_119  (from cd119_redistricted, just built)
#   - cd_2026 (from all_bafs, built in Script 08)
#   - pop    (from all_blocks_pop, built in Script 08)
# Inner joins drop blocks not present in all three sources.

cd_renumber_map <- cd119_redistricted %>%
  mutate(state_fips = substr(block_geoid, 1, 2)) %>%
  inner_join(
    all_bafs %>% rename(cd_2026 = district),
    by = c("block_geoid", "state_fips")
  ) %>%
  inner_join(
    all_blocks_pop %>% rename(block_geoid = GEOID, pop = value),
    by = "block_geoid"
  )

cat("\n══ Block-level merged data ══\n")
cat("Rows:", nrow(cd_renumber_map), "\n")
cat("Population covered:", sum(cd_renumber_map$pop), "\n")


# ── 4. Aggregate: find max-overlap cd_2026 per (state, cd_119) ──────────────
# For each (state, cd_119, cd_2026) intersection, sum block populations.
# Then for each (state, cd_119), pick the cd_2026 with the largest overlap.

cd119_to_cd2026 <- cd_renumber_map %>%
  group_by(state_fips, cd_119, cd_2026) %>%
  summarise(overlap_pop = sum(pop), .groups = "drop") %>%
  group_by(state_fips, cd_119) %>%
  arrange(desc(overlap_pop)) %>%
  mutate(
    cd_119_total_pop  = sum(overlap_pop),
    overlap_pct       = round(100 * overlap_pop / cd_119_total_pop, 1)
  ) %>%
  slice_head(n = 1) %>%
  ungroup() %>%
  select(state_fips, cd_119, cd_2026, overlap_pct, overlap_pop, cd_119_total_pop)


# ── 5. Diagnostics and save──────────────────────────────────────────────────────────

cat("\n══ Renumbering map (CD119 -> CD2026 by max population overlap) ══\n")
print(cd119_to_cd2026, n = Inf)

cat("\n══ Cases where overlap < 90% (old CD split substantially) ══\n")
cd119_to_cd2026 %>%
  filter(overlap_pct < 90) %>%
  print(n = Inf)

#Save the block -> cd119 file for redistricted districts
saveRDS(cd119_redistricted, file.path(processed_dir, "cd119_redistricted.rds"))
#Save the renumbering map
saveRDS(cd119_to_cd2026, file.path(processed_dir, "cd119_to_cd2026.rds"))

# ══════════════════════════════════════════════════════════════════════════════
# SCRIPT 12B: Apply renumbering map to fallback respondents
#
# Uses the cd119_to_cd2026 lookup built in 12A. Updates cd_2026 for fallback
# respondents only; non-fallback respondents are unaffected.
# ══════════════════════════════════════════════════════════════════════════════

# ── 6. Prepare the renumbering lookup ───────────────────────────────────────
# cd119_to_cd2026 has columns: state_fips (chr), cd_119 (int), cd_2026 (int)
# Coerce state_fips to integer for matching ces_with_cd$inputstate.
# Rename cd_2026 → cd_2026_remapped to avoid collision with the existing
# cd_2026 column in ces_with_cd.

cd119_lookup <- cd119_to_cd2026 %>%
  mutate(state_fips_int = as.integer(state_fips)) %>%
  select(state_fips_int, cd_119, cd_2026_remapped = cd_2026)


# ── 7. Apply renumbering to fallback respondents ────────────────────────────
# Step-by-step:
#   - Flag each row as fallback (in redistricted state AND lookupzip
#     not in the ZCTA crosswalk).
#   - Left-join the renumbering lookup on (inputstate, cdid119). For non-
#     fallback respondents this still does a join but the result doesn't
#     get applied.
#   - Use if_else to update cd_2026 ONLY when the row is fallback AND a
#     remapping exists. Other rows keep their existing cd_2026 (either from
#     stable-state cdid119 or from ZCTA-based assignment).
#   - Drop the temporary helper columns to keep the dataset tidy.

zcta_codes_in_crosswalk <- unique(zcta_cd_crosswalk$zcta)

ces_with_cd <- ces_with_cd %>%
  
  # Flag fallback respondents (~59 rows total)
  mutate(
    is_fallback = inputstate %in% c(6, 12, 29, 37, 39, 48, 49) & 
      !(lookupzip %in% zcta_codes_in_crosswalk)
  ) %>%
  
  # Join the renumbering lookup on (state, old CD).
  # For fallback respondents, their current cd_2026 is their cdid119 value,
  # but we join on cdid119 explicitly to be unambiguous about semantic.
  left_join(cd119_lookup,
            by = c("inputstate" = "state_fips_int", "cdid119" = "cd_119")) %>%
  
  # Conditionally update cd_2026 for fallback respondents with a valid remapping
  mutate(
    cd_2026 = if_else(
      is_fallback & !is.na(cd_2026_remapped),
      as.integer(cd_2026_remapped),
      as.integer(cd_2026)
    )
  ) %>%
  
  # Clean up helper columns
  select(-cd_2026_remapped, -is_fallback)


# ── 8. Verification and save ────────────────────────────────────────────────
# Confirm structure is preserved: row count, unique respondent count,
# afact values still sum to 1.0 per respondent, state+CD alignment with PUMS.

cat("\n══ Verify after renumbering ══\n")
cat("Total rows in ces_with_cd:", nrow(ces_with_cd), "\n")
cat("Unique respondents:        ", n_distinct(ces_with_cd$caseid), "\n")

# afact integrity check (should sum to 1.0 per respondent)
afact_check <- ces_with_cd %>%
  group_by(caseid) %>%
  summarise(afact_sum = sum(afact), .groups = "drop")

cat("\nafact sum per respondent:",
    round(min(afact_check$afact_sum), 4), "to",
    round(max(afact_check$afact_sum), 4), "\n")
cat("Respondents where afact != 1:",
    sum(round(afact_check$afact_sum, 4) != 1), "\n")

# Check state+CD alignment with PUMS is still intact
pums_combos <- pums_crosswalked %>% distinct(state_cat, cd_cat)
ces_combos <- ces_with_cd %>%
  mutate(state_cat = as.integer(inputstate),
         cd_cat = as.integer(cd_2026)) %>%
  distinct(state_cat, cd_cat)

cat("\nCDs in CES but not in PUMS:",
    nrow(anti_join(ces_combos, pums_combos, by = c("state_cat", "cd_cat"))), "\n")
cat("CDs in PUMS but not in CES:",
    nrow(anti_join(pums_combos, ces_combos, by = c("state_cat", "cd_cat"))), "\n")


# Save ces_with_cd_v2 (the CES with corrected cd_2026 for fallback respondents)
saveRDS(ces_with_cd, file.path(processed_dir, "ces_with_cd_v2.rds"))
