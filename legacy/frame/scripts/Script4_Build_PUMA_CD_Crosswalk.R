# ══════════════════════════════════════════════════════════════════════════════
# SCRIPT 04: Build unified PUMA-to-2026 CD crosswalk
# ══════════════════════════════════════════════════════════════════════════════

library(here)
library(tidyverse)
library(tidycensus)
library(readxl)
library(readr)

# ── Folder paths ────────────────────────────────────────────────────────────
raw_dir       <- here("Data_Raw")
processed_dir <- here("Data_Processed")

# ── File paths ──────────────────────────────────────────────────────────────
tract_to_puma_path <- file.path(raw_dir, "2020_Census_Tract_to_2020_PUMA.txt")
geo_path           <- file.path(raw_dir, "geocorr2022_2610104623.csv")

# ── Census API setup ────────────────────────────────────────────────────────
readRenviron("~/.Renviron")

# ══════════════════════════════════════════════════════════════════════════════
# STAGE 1: Load Geocorr 2022 PUMA-to-CD crosswalk
# ══════════════════════════════════════════════════════════════════════════════

cat("══ Stage 1: Loading Geocorr 2022 ══\n")
crosswalk_raw <- read_csv(geo_path, skip = 1, show_col_types = FALSE)

# Standardize types and column names immediately
crosswalk <- crosswalk_raw %>%
  transmute(
    state     = as.integer(`State code`),
    puma22    = as.integer(`PUMA (2022)`),
    cd119     = as.integer(`Congressional district code (119th Congress)`),
    stab      = as.character(`State abbr.`),
    puma_name = as.character(`PUMA22 name`),
    pop20     = as.numeric(`Total population (2020 Census)`),
    afact2    = as.numeric(`cd119-to-puma22 allocation factor`),
    afact     = as.numeric(`puma22-to-cd119 allocation factor`)
  )

cat("Dimensions:", format(nrow(crosswalk), big.mark = ","), "rows x", ncol(crosswalk), "cols\n")

# Validate afact sums to 1.0 per PUMA
afact_check <- crosswalk %>%
  group_by(state, puma22) %>%
  summarise(afact_sum = round(sum(afact), 4), .groups = "drop")

if (any(afact_check$afact_sum != 1.0)) {
  warning("Some Geocorr PUMAs do not sum to afact = 1.0!")
}

# ══════════════════════════════════════════════════════════════════════════════
# STAGE 2: Build PUMA-to-2026 CD crosswalks for 7 redistricted states
# ══════════════════════════════════════════════════════════════════════════════

cat("\n══ Stage 2: Building Custom Crosswalks for Redistricted States ══\n")

# Force zero-padded character FIPS to prevent silent join failures
tract_to_puma <- read_csv(tract_to_puma_path, show_col_types = FALSE)
tract_to_puma_clean <- tract_to_puma %>%
  mutate(
    STATEFP  = sprintf("%02d", as.integer(STATEFP)),
    COUNTYFP = sprintf("%03d", as.integer(COUNTYFP)),
    TRACTCE  = sprintf("%06d", as.integer(TRACTCE)),
    tract_geoid = paste0(STATEFP, COUNTYFP, TRACTCE)
  ) %>%
  select(tract_geoid, statefp = STATEFP, puma = PUMA5CE)

build_state_puma_cd_crosswalk <- function(
    baf_path, state_abb, state_fips,
    baf_block_col = "SCTBKEY", baf_district_col = "DISTRICT",
    baf_delim = ",", baf_has_header = TRUE, output_dir = "."
) {
  cat("Processing:", state_abb, "(FIPS", state_fips, ")...\n")
  
  # 1. Read BAF
  ext <- tools::file_ext(baf_path)
  if (ext %in% c("xlsx", "xls")) {
    baf <- readxl::read_excel(baf_path) %>% mutate(across(everything(), as.character))
  } else if (baf_has_header) {
    baf <- read_delim(baf_path, delim = baf_delim, col_types = cols(.default = col_character()), show_col_types = FALSE)
  } else {
    baf <- read_delim(baf_path, delim = baf_delim, col_names = c(baf_block_col, baf_district_col), col_types = cols(.default = col_character()), show_col_types = FALSE)
  }
  
  baf <- baf %>%
    select(block_geoid = all_of(baf_block_col), district = all_of(baf_district_col)) %>%
    mutate(district = as.integer(district))
  
  # 2. Pull Decennial Block Populations
  blocks <- get_decennial(geography = "block", variables = "P1_001N", year = 2020, sumfile = "pl", state = state_abb, progress_bar = FALSE)
  
  # 3. Join Block Pops to BAF and Aggregate to Tract
  tract_cd_pop <- baf %>%
    inner_join(blocks %>% select(GEOID, pop = value), by = c("block_geoid" = "GEOID")) %>%
    mutate(tract_geoid = substr(block_geoid, 1, 11)) %>%
    group_by(tract_geoid, cd_new = district) %>%
    summarise(pop_in_intersection = sum(pop), .groups = "drop")
  
  # 4. Join Tracts to PUMA and Aggregate to PUMA x CD
  puma_cd <- tract_cd_pop %>%
    inner_join(tract_to_puma_clean %>% filter(statefp == state_fips), by = "tract_geoid") %>%
    group_by(state = state_fips, puma, cd_new) %>%
    summarise(pop_intersection = sum(pop_in_intersection), .groups = "drop") %>%
    group_by(state, puma) %>%
    mutate(
      puma_pop = sum(pop_intersection),
      afact    = pop_intersection / puma_pop
    ) %>%
    ungroup()
  
  # 5. Save RDS
  out_path <- file.path(output_dir, paste0(tolower(state_abb), "_puma_cd_crosswalk.rds"))
  saveRDS(puma_cd, out_path)
  
  # 6. MEMORY CLEANUP: Drop heavy block tables before returning
  rm(baf, blocks, tract_cd_pop)
  gc()
  
  return(puma_cd)
}

# Execute builds for all 7 redistricted states
tx_puma_cd <- build_state_puma_cd_crosswalk(file.path(raw_dir, "PLANC2333.csv"), "TX", "48", "SCTBKEY", "DISTRICT", output_dir = processed_dir)
ca_puma_cd <- build_state_puma_cd_crosswalk(file.path(raw_dir, "ab604.csv"), "CA", "06", baf_delim = ",", baf_has_header = FALSE, output_dir = processed_dir)
mo_puma_cd <- build_state_puma_cd_crosswalk(file.path(raw_dir, "HB1_Missouri_Congressional_Districts_2025_BEF.xlsx"), "MO", "29", "Block", "DistrictID", output_dir = processed_dir)
nc_puma_cd <- build_state_puma_cd_crosswalk(file.path(raw_dir, "NCGA_CCM-2 .csv"), "NC", "37", "Block", "District", output_dir = processed_dir)
oh_puma_cd <- build_state_puma_cd_crosswalk(file.path(raw_dir, "October 31 2025 CD BAF.xlsx"), "OH", "39", "Block", "DistrictID:1", output_dir = processed_dir)
ut_puma_cd <- build_state_puma_cd_crosswalk(file.path(raw_dir, "ut_cong_adopted_2025_baf.csv"), "UT", "49", "GEOID20", "DISTRICT", output_dir = processed_dir)
fl_puma_cd <- build_state_puma_cd_crosswalk(file.path(raw_dir, "EOGPCRP2026.csv"), "FL", "12", "block_geoid", "district", baf_has_header = FALSE, output_dir = processed_dir)

# ══════════════════════════════════════════════════════════════════════════════
# STAGE 3: Merge into a unified national crosswalk
# ══════════════════════════════════════════════════════════════════════════════

cat("\n══ Stage 3: Building Unified National Crosswalk ══\n")

redistricted_fips <- c(48, 6, 29, 37, 39, 49, 12)

# Standardize new states immediately to use `cd_2026`
new_states <- bind_rows(tx_puma_cd, ca_puma_cd, mo_puma_cd, nc_puma_cd, oh_puma_cd, ut_puma_cd, fl_puma_cd) %>%
  transmute(
    state   = as.integer(state),
    puma22  = as.integer(puma),
    cd_2026 = as.integer(cd_new),
    afact   = afact
  )

# Trim Geocorr, drop PR (72), and standardize to `cd_2026` immediately
geocorr_stable <- crosswalk %>%
  filter(!state %in% c(redistricted_fips, 72)) %>%
  transmute(
    state   = state,
    puma22  = puma22,
    cd_2026 = cd119,
    afact   = afact
  )

# Combine unified frame
unified_crosswalk <- bind_rows(geocorr_stable, new_states)

cat("Unified crosswalk rows:    ", format(nrow(unified_crosswalk), big.mark = ","), "\n")
cat("Unique states covered:     ", n_distinct(unified_crosswalk$state), "(Expect 51: 50 states + DC)\n")
cat("Unique state+CD combos:    ", n_distinct(paste(unified_crosswalk$state, unified_crosswalk$cd_2026)), "(Expect 436: 435 CDs + DC)\n")

# Final save
saveRDS(unified_crosswalk, file.path(processed_dir, "unified_crosswalk_2026.rds"))
cat("\nSaved successfully to Data_Processed/unified_crosswalk_2026.rds\n")