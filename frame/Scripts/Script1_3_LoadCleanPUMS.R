library(tidyverse)
library(data.table)
library(janitor)
library(haven)
library(here)
library(ipumsr)

# ══════════════════════════════════════════════════════════════════════════════
# SCRIPT 01: Load IPUMS PUMS extract and run initial diagnostics
#
# Purpose:
#   Load the IPUMS 2023 ACS 5-year PUMS data extract, attach DDI metadata for
#   variable labels, and run sanity checks before filtering and recoding.
#
# Inputs:
#   - usa_00003.xml          : IPUMS DDI metadata file (variable labels, codes)
#   - usa_00003.csv.gz       : IPUMS PUMS microdata extract
#   - geocorr2022_2610104623.csv : Geocorr 2022 PUMA-to-CD crosswalk
#                                  (path stored; not used until Script 04)
#
# Outputs:
#   - pums : data frame, 16,095,728 rows × 24 columns
#           (in-memory; not saved to disk at this stage)
#
# Key variables in pums:
#   Identifiers   : YEAR, MULTYEAR, SAMPLE, SERIAL, CBSERIAL, PERNUM
#   Weights       : HHWT, PERWT, CLUSTER, STRATA
#   Geography     : STATEFIP, PUMA, CPUMA1020
#   Household     : HHINCOME, GQ
#   Demographics  : SEX, AGE, RACE, RACED, HISPAN, HISPAND, CITIZEN, EDUC, EDUCD
#
# Diagnostics produced:
#   - GQ distribution (5 categories present in data)
#   - State count: 51 (50 states + DC; DC dropped at later stage)
#   - PERWT range: 1.00 to 986.00 (median 15.00); all positive
#
# Code mappings inspected (for use in later filtering/recoding):
#   - RACED (368 detailed codes; grouped at Script 03)
#   - EDUCD (44 detailed codes; grouped at Script 03)
#   - HISPAND (55 detailed codes; binary-flagged at Script 03)
#   - CITIZEN (8 codes; codes 3+ dropped at Script 02)
#   - SEX (1 = Male, 2 = Female; recoded at Script 03)
#   - GQ (7 codes; 0 = Vacant and 6 = Fragment dropped at Script 02)
#
# Notes for downstream documentation:
#   The DDI codebook reveals several variables that require grouping
#   before they're usable as cell-defining categories. See the
#   ReadMe document for details
#   on how each is collapsed in Script 03.
# ══════════════════════════════════════════════════════════════════════════════

# ── Folder paths ────────────────────────────────────────────────────────────
raw_dir       <- here("Data_Raw")
processed_dir <- here("Data_Processed")

# ── 1. File paths ────────────────────────────────────────────────────────────
ddi_path  <- file.path(raw_dir, "usa_00003.xml")
data_path <- file.path(raw_dir, "usa_00003.csv.gz")
geo_path  <- file.path(raw_dir, "geocorr2022_2610104623.csv")

# ── 2. Load IPUMS extract ────────────────────────────────────────────────────
ddi  <- read_ipums_ddi(ddi_path)
pums <- read_ipums_micro(ddi, data_file = data_path)

# ── 3. Quick sanity checks ─────────────────────────────────────────────────────
# Row and column count
cat("Rows:", nrow(pums), "\n")
cat("Cols:", ncol(pums), "\n")

# Check key variables exist
cat("\nVariable names:\n")
print(names(pums))

# Distribution of GQ (group quarters) -- we'll filter these out next
cat("\nGQ distribution:\n")
print(table(pums$GQ))

# Check STATEFIP looks right (should be 1-56, no Puerto Rico)
cat("\nUnique states:", n_distinct(pums$STATEFIP), "\n")

# Quick check on person weights -- should all be positive
cat("\nPERWT summary:\n")
print(summary(pums$PERWT))


# Check code mappings for all variables of concern
ipums_val_labels(ddi, "GQ")
ipums_val_labels(ddi, "RACED")
ipums_val_labels(ddi, "HISPAND")
ipums_val_labels(ddi, "CITIZEN")
ipums_val_labels(ddi, "EDUCD")
ipums_val_labels(ddi, "SEX")


# Print full RACED codes
ipums_val_labels(ddi, "RACED") %>% print(n = Inf)

# Print full EDUCD codes
ipums_val_labels(ddi, "EDUCD") %>% print(n = Inf)

# Print full HISPAND codes
ipums_val_labels(ddi, "HISPAND") %>% print(n = Inf)



# ══════════════════════════════════════════════════════════════════════════════
# SCRIPT 02: Filter raw PUMS extract to voting-eligible population
#
# Purpose:
#   Apply sequential filters to the raw PUMS data, retaining only records
#   that represent the citizen voting-age population (CVAP). Also runs
#   detailed diagnostic checks on category distributions before filtering.
#
# Inputs:
#   - pums : data frame from Script 01 (16,095,728 rows × 24 columns)
#   - ddi  : IPUMS DDI metadata (for label lookups in diagnostics)
#
# Outputs:
#   - pums_filtered : data frame, 12,263,785 rows × 24 columns
#                     (in-memory; not saved to disk at this stage)
#
# Filters applied (sequential):
#   1. Group Quarters (GQ): drop codes 0 (Vacant unit) and 6 (Fragment)
#      Codes 1, 2, 3 (Institutional GQ - per Roberto), 4, 5 retained.
#   2. Citizenship (CITIZEN): drop code 3 (Not a citizen)
#      Code 0 (N/A = U.S.-born citizen), 1 (Born abroad of American parents),
#      and 2 (Naturalized) retained. Codes 4, 5, 8, 9 not present in data.
#   3. Age: keep only AGE >= 18 (voting-eligible).
#
# Running totals (sample size × weighted population):
#   Filter       | Rows           | Weighted pop
#   -------------|----------------|---------------
#   Raw          | 16,095,728     | 334,922,503
#   GQ           | 16,095,728     | 334,922,503  (codes 0 and 6 had 0 rows)
#   Citizenship  | 15,244,470     | 312,371,676
#   Age 18+      | 12,263,785     | 240,960,972  ← final CVAP
#
# Diagnostics produced (before filtering):
#   - Weighted counts by code for GQ, CITIZEN, SEX, HISPAND, RACED, EDUCD
#   - HHINCOME special values (N/A code 9999999, negative, zero, valid positive)
#   - Detailed RACED/HISPAND/EDUCD distribution check (DDI labels joined)
#   - Anti-join check for any RACED/HISPAND codes in data not in DDI labels
#   - NA audit across all key variables
#
# Notes for downstream:
#   - 240.96M is approximately U.S. CVAP per 2023 ACS 5-year estimates
#   - The GQ filter is a no-op for this extract since vacant units and
#     fragments aren't included in IPUMS person-level extracts; the filter
#     is kept for safety in case the extract definition changes
# ══════════════════════════════════════════════════════════════════════════════

library(tidyverse)

# Helper function: weighted and unweighted counts for any variable
code_counts <- function(data, var) {
  data %>%
    group_by({{ var }}) %>%
    summarise(
      n_records    = n(),                    # raw sample count
      n_weighted   = sum(PERWT),             # population estimate
      pct_weighted = round(sum(PERWT) / sum(data$PERWT) * 100, 3)
    ) %>%
    arrange(desc(n_weighted))
}

# ── GQ ────────────────────────────────────────────────────────────────────────
cat("═══ GQ (Group Quarters) ═══\n")
code_counts(pums, GQ) %>% print()

# ── CITIZEN ───────────────────────────────────────────────────────────────────
cat("\n═══ CITIZEN ═══\n")
code_counts(pums, CITIZEN) %>% print()

# ── SEX ───────────────────────────────────────────────────────────────────────
cat("\n═══ SEX ═══\n")
code_counts(pums, SEX) %>% print()

# ── HISPAND ───────────────────────────────────────────────────────────────────
# Collapse to Hispanic vs Not Hispanic vs Not Reported for readability
cat("\n═══ HISPAND (collapsed) ═══\n")
pums %>%
  mutate(hisp_group = case_when(
    HISPAND == 0   ~ "Not Hispanic",
    HISPAND == 900 ~ "Not Reported",
    TRUE           ~ "Hispanic"
  )) %>%
  group_by(hisp_group) %>%
  summarise(
    n_records  = n(),
    n_weighted = sum(PERWT),
    pct        = round(sum(PERWT) / sum(pums$PERWT) * 100, 3)
  ) %>%
  arrange(desc(n_weighted)) %>%
  print()

# ── RACED (top-level groups only) ─────────────────────────────────────────────
cat("\n═══ RACED (collapsed to major groups) ═══\n")
pums %>%
  mutate(race_group = case_when(
    HISPAND > 0 & HISPAND < 900          ~ "Hispanic",
    HISPAND == 900                       ~ "Hispanic - Not Reported",
    RACED >= 100 & RACED <= 177          ~ "NH-White",
    RACED >= 200 & RACED <= 234          ~ "NH-Black",
    RACED >= 300 & RACED <= 399          ~ "NH-AIAN",
    RACED >= 400 & RACED <= 629          ~ "NH-Asian",
    RACED >= 635 & RACED <= 679          ~ "NH-Asian",
    RACED >= 630 & RACED <= 634          ~ "NH-NativeHawaiian_PI",
    RACED >= 680 & RACED <= 699          ~ "NH-NativeHawaiian_PI",
    RACED >= 700 & RACED <= 730          ~ "NH-Other",
    RACED >= 801 & RACED <= 997          ~ "NH-Multiracial",
    TRUE                                 ~ "Uncategorised"
  )) %>%
  group_by(race_group) %>%
  summarise(
    n_records  = n(),
    n_weighted = sum(PERWT),
    pct        = round(sum(PERWT) / sum(pums$PERWT) * 100, 3)
  ) %>%
  arrange(desc(n_weighted)) %>%
  print()

# ── EDUCD ─────────────────────────────────────────────────────────────────────
cat("\n═══ EDUCD (collapsed to major groups) ═══\n")
pums %>%
  mutate(educ_group = case_when(
    EDUCD >= 0   & EDUCD <= 61  ~ "No HS",
    EDUCD >= 62  & EDUCD <= 64  ~ "HS Grad",
    EDUCD >= 65  & EDUCD <= 83  ~ "Some College",
    EDUCD >= 100 & EDUCD <= 101 ~ "4-Year Degree",
    EDUCD >= 110 & EDUCD <= 116 ~ "Post-Grad",
    EDUCD == 999                ~ "Missing",
    TRUE                        ~ "Uncategorised"
  )) %>%
  group_by(educ_group) %>%
  summarise(
    n_records  = n(),
    n_weighted = sum(PERWT),
    pct        = round(sum(PERWT) / sum(pums$PERWT) * 100, 3)
  ) %>%
  arrange(desc(n_weighted)) %>%
  print()

# ── HHINCOME ──────────────────────────────────────────────────────────────────
cat("\n═══ HHINCOME special values ═══\n")
pums %>%
  mutate(inc_flag = case_when(
    HHINCOME == 9999999 ~ "N/A code",
    HHINCOME < 0        ~ "Negative income",
    HHINCOME == 0       ~ "Zero income",
    TRUE                ~ "Valid positive"
  )) %>%
  group_by(inc_flag) %>%
  summarise(
    n_records  = n(),
    n_weighted = sum(PERWT),
    pct        = round(sum(PERWT) / sum(pums$PERWT) * 100, 3)
  ) %>%
  arrange(desc(n_weighted)) %>%
  print()



# Full detailed category counts for RACED, HISPAND, EDUCD
# Purpose: Check for missing, NA, or unexpected codes before recoding

# ── RACED full distribution ───────────────────────────────────────────────────
cat("═══ RACED full distribution ═══\n")
raced_labels <- ipums_val_labels(ddi, "RACED") %>% rename(raced_label = lbl)

pums %>%
  filter(HISPAND == 0) %>%   # non-Hispanics only for RACED
  left_join(raced_labels, by = c("RACED" = "val")) %>%
  group_by(RACED, raced_label) %>%
  summarise(
    n_records  = n(),
    n_weighted = sum(PERWT),
    pct        = round(sum(PERWT) / sum(pums$PERWT) * 100, 4),
    .groups = "drop"
  ) %>%
  arrange(desc(n_weighted)) %>%
  print(n = Inf)

# ── HISPAND full distribution ─────────────────────────────────────────────────
cat("\n═══ HISPAND full distribution ═══\n")
hispand_labels <- ipums_val_labels(ddi, "HISPAND") %>% rename(hispand_label = lbl)

pums %>%
  filter(HISPAND > 0) %>%    # Hispanics only
  left_join(hispand_labels, by = c("HISPAND" = "val")) %>%
  group_by(HISPAND, hispand_label) %>%
  summarise(
    n_records  = n(),
    n_weighted = sum(PERWT),
    pct        = round(sum(PERWT) / sum(pums$PERWT) * 100, 4),
    .groups = "drop"
  ) %>%
  arrange(desc(n_weighted)) %>%
  print(n = Inf)

# ── EDUCD full distribution ───────────────────────────────────────────────────
cat("\n═══ EDUCD full distribution ═══\n")
educd_labels <- ipums_val_labels(ddi, "EDUCD") %>% rename(educd_label = lbl)

pums  %>%
  left_join(educd_labels, by = c("EDUCD" = "val")) %>%
  group_by(EDUCD, educd_label) %>%
  summarise(
    n_records  = n(),
    n_weighted = sum(PERWT),
    pct        = round(sum(PERWT) / sum(pums$PERWT) * 100, 4),
    .groups = "drop"
  ) %>%
  arrange(desc(n_weighted)) %>%
  print(n = Inf)

# ── Check for any RACED codes in data not in DDI labels ──────────────────────
cat("\n═══ RACED codes in data with no matching DDI label ═══\n")
pums %>%
  filter(HISPAND == 0) %>%
  anti_join(raced_labels, by = c("RACED" = "val")) %>%
  group_by(RACED) %>%
  summarise(
    n_records  = n(),
    n_weighted = sum(PERWT)
  ) %>%
  print()

# ── Check for any HISPAND codes in data not in DDI labels ────────────────────
cat("\n═══ HISPAND codes in data with no matching DDI label ═══\n")
pums %>%
  filter(HISPAND > 0) %>%
  anti_join(hispand_labels, by = c("HISPAND" = "val")) %>%
  group_by(HISPAND) %>%
  summarise(
    n_records  = n(),
    n_weighted = sum(PERWT)
  ) %>%
  print()


# DIAGNOSTIC: NA audit across all key variables
cat("\n═══ NA audit across all key variables ═══\n")
pums %>%
  summarise(
    across(
      c(GQ, CITIZEN, SEX, HISPAND, RACED, EDUCD, HHINCOME, AGE, PERWT, 
        STATEFIP, PUMA, CPUMA1020),
      list(
        n_na       = ~sum(is.na(.)),
        pct_na     = ~round(sum(is.na(.)) / n() * 100, 4),
        n_weighted_na = ~sum(PERWT[is.na(.)], na.rm = TRUE)
      )
    )
  ) %>%
  pivot_longer(
    everything(),
    names_to  = c("variable", "stat"),
    names_sep = "_(?=[^_]+$)"
  ) %>%
  pivot_wider(names_from = stat, values_from = value) %>%
  arrange(desc(na)) %>%
  print(n = Inf)

##End of Diagnostics


##----------------------------------------
##            FILTERING
##----------------------------------------

###Filtering GQ 
##-- drop 0: non vacant units -- existing data count:0
##-- drop 6: fragments  --- existing data count:0   
# Keep all valid person records
# Drop only vacant units (0) and geographic fragments (6)
# Retain institutional GQ 3 per Roberto's recommendation
pums_filtered <- pums %>%
  filter(!GQ %in% c(0, 6))

cat("Rows after GQ filter:", nrow(pums_filtered), "\n")
cat("Rows removed:", nrow(pums) - nrow(pums_filtered), "\n")
cat("Weighted pop removed:", 
    sum(pums$PERWT) - sum(pums_filtered$PERWT), "\n")
cat("Pct weighted pop removed:", 
    round((sum(pums$PERWT) - sum(pums_filtered$PERWT)) / 
            sum(pums$PERWT) * 100, 3), "%\n")

###Filtering non-citizens
# Drop non-citizens (CITIZEN == 3)
# CITIZEN == 0 (N/A) = US-born citizens, question not applicable to them -- KEEP
# CITIZEN == 1 = Born abroad of American parents -- KEEP
# CITIZEN == 2 = Naturalized citizen -- KEEP
# Codes 4, 5, 8, 9 not present in data

pums_filtered <- pums_filtered %>%
  filter(!CITIZEN %in% c(3))

cat("Rows after citizenship filter:", nrow(pums_filtered), "\n")
cat("Rows removed:", nrow(pums %>% filter(!GQ %in% c(0,6))) - nrow(pums_filtered), "\n")
cat("Weighted pop removed:",
    sum(pums$PERWT) - sum(pums_filtered$PERWT), "\n")


#Filtering by age (18+)
# Keep only voting eligible age (18+)
# AGE is exact years in IPUMS, no special codes
pums_filtered <- pums_filtered %>%
  filter(AGE >= 18)

cat("Rows after age filter:", nrow(pums_filtered), "\n")
cat("Rows removed:", 15244470 - nrow(pums_filtered), "\n")
cat("Weighted pop removed:",
    sum(pums %>% filter(!CITIZEN %in% c(3)) %>% pull(PERWT)) - 
      sum(pums_filtered$PERWT), "\n")
cat("Pct weighted pop removed:",
    round((sum(pums %>% filter(!CITIZEN %in% c(3)) %>% pull(PERWT)) - 
             sum(pums_filtered$PERWT)) /
            sum(pums %>% filter(!CITIZEN %in% c(3)) %>% pull(PERWT)) * 100, 3), "%\n")



# ══════════════════════════════════════════════════════════════════════════════
# SCRIPT 03: Recode and label PUMS demographic variables
#
# Purpose:
#   Attach human-readable labels to demographic variables in pums_filtered.
#   No binning or category aggregation at this stage — full IPUMS detail
#   retained. Aggregation to coarser categories happens in Script 08 during
#   CES-PUMS harmonization.
#
# Inputs:
#   - pums_filtered : 12,263,785 rows × 24 columns (from Script 02)
#   - ddi           : IPUMS DDI metadata (for label lookups)
#
# Outputs:
#   - pums_clean : 12,263,785 rows × 26 columns
#                  Saved to: pums_clean.rds
#
# Recoded variables (added to pums_clean):
#   - gender             : binary "Male" / "Female" from SEX (codes 1, 2)
#                          Records with SEX = 9 (Missing) → NA
#   - hispanic_flag      : binary 0/1 from HISPAND
#                          (0 = Not Hispanic; 1 = any Hispanic origin)
#   - hispanic_detailed  : 24 detailed Hispanic origin labels from HISPAND
#                          (includes "Not Hispanic" as a category)
#   - race_detailed      : 156 detailed race labels from RACED
#                          (no aggregation, no Hispanic-first rule)
#   - educ_detailed      : 24 detailed education labels from EDUCD
#   - hhincome_clean     : numeric income; HHINCOME == 9999999 → NA
#                          Zero and negative income retained as-is
#
# Raw variables retained for auditability:
#   AGE, SEX, RACE, RACED, HISPAN, HISPAND, CITIZEN, EDUC, EDUCD, HHINCOME, GQ
#
# Diagnostics produced:
#   - Distribution of each recoded variable (top categories by weighted count)
#   - NA audit across all recoded variables
#   - Final dataset summary
#
# Output file:
#   pums_clean.rds
#
# Notes:
#   - Gender coding is binary per ACS structural constraint
#     (ACS does not collect non-binary). CES non-binary respondents
#     (gender4 ∈ {3, 4}) will be dropped in Script 08.
#   - Race and Hispanic ethnicity kept as separate variables.
#     Hispanic-first rule not applied — a respondent's race_detailed
#     reflects their selected race regardless of Hispanic status.
#   - AGE kept as exact years (binning to 5-year groups in Script 08).
#   - HHINCOME already in 2024 dollars (5-year file already adjusted).
# ══════════════════════════════════════════════════════════════════════════════

library(tidyverse)
library(ipumsr)

# ── 1. Load label lookups from DDI ───────────────────────────────────────────
hispand_labels <- ipums_val_labels(ddi, "HISPAND") %>% rename(hispanic_detailed = lbl)
raced_labels   <- ipums_val_labels(ddi, "RACED")   %>% rename(race_detailed     = lbl)
educd_labels   <- ipums_val_labels(ddi, "EDUCD")   %>% rename(educ_detailed     = lbl)


# ── 2. Gender ─────────────────────────────────────────────────────────────────
# SEX codes: 1 = Male, 2 = Female
# Binary for merge integrity with CES
# Non-binary handled as post-hoc persona layer only

pums_clean <- pums_filtered %>%
  mutate(gender = case_when(
    SEX == 1 ~ "Male",
    SEX == 2 ~ "Female",
    TRUE     ~ NA_character_
  ))

cat("Gender distribution:\n")
print(table(pums_clean$gender, useNA = "always"))


# ── 3. Hispanic flag ──────────────────────────────────────────────────────────
# Binary flag: 0 = Not Hispanic, 1 = Hispanic
# Kept separate from hispanic_detailed for modeling flexibility

pums_clean <- pums_clean %>%
  mutate(hispanic_flag = case_when(
    HISPAND == 0 ~ 0L,
    HISPAND >  0 ~ 1L,
    TRUE         ~ NA_integer_
  ))

cat("\nHispanic flag distribution:\n")
print(table(pums_clean$hispanic_flag, useNA = "always"))


# ── 4. Hispanic detailed label ────────────────────────────────────────────────
# Full HISPAND label for every record -- includes "Not Hispanic"
# No aggregation -- all 24 detailed categories retained

pums_clean <- pums_clean %>%
  left_join(hispand_labels, by = c("HISPAND" = "val"))

cat("\nHispanic detailed -- top 10 by weighted count:\n")
pums_clean %>%
  group_by(hispanic_detailed) %>%
  summarise(
    n_records  = n(),
    n_weighted = sum(PERWT),
    pct        = round(sum(PERWT) / sum(pums_clean$PERWT) * 100, 3)
  ) %>%
  arrange(desc(n_weighted)) %>%
  print(n = 10)

cat("Distinct hispanic categories:", n_distinct(pums_clean$hispanic_detailed), "\n")
cat("Hispanic NAs:", sum(is.na(pums_clean$hispanic_detailed)), "\n")


# ── 5. Race detailed label ────────────────────────────────────────────────────
# Full RACED label for every record -- no aggregation, no Hispanic-first rule

pums_clean <- pums_clean %>%
  left_join(raced_labels, by = c("RACED" = "val"))

cat("\nRace detailed -- top 10 by weighted count:\n")
pums_clean %>%
  group_by(race_detailed) %>%
  summarise(
    n_records  = n(),
    n_weighted = sum(PERWT),
    pct        = round(sum(PERWT) / sum(pums_clean$PERWT) * 100, 3)
  ) %>%
  arrange(desc(n_weighted)) %>%
  print(n = 10)

cat("Distinct race categories:", n_distinct(pums_clean$race_detailed), "\n")
cat("Race NAs:", sum(is.na(pums_clean$race_detailed)), "\n")


# ── 6. Education detailed label ───────────────────────────────────────────────
# Full EDUCD label -- all 24 categories retained

pums_clean <- pums_clean %>%
  left_join(educd_labels, by = c("EDUCD" = "val"))

cat("\nEducation detailed -- top 10 by weighted count:\n")
pums_clean %>%
  group_by(educ_detailed) %>%
  summarise(
    n_records  = n(),
    n_weighted = sum(PERWT),
    pct        = round(sum(PERWT) / sum(pums_clean$PERWT) * 100, 3)
  ) %>%
  arrange(desc(n_weighted)) %>%
  print(n = 10)

cat("Distinct education categories:", n_distinct(pums_clean$educ_detailed), "\n")
cat("Education NAs:", sum(is.na(pums_clean$educ_detailed)), "\n")


# ── 7. Income ─────────────────────────────────────────────────────────────────
# HHINCOME already in 2024 dollars for this 5-year file
# Convert 9999999 (N/A placeholder) to proper R NA
# Zero and negative values are legitimate -- retained as-is
# Exact dollar amounts kept -- binning happens at modeling stage

pums_clean <- pums_clean %>%
  mutate(hhincome_clean = if_else(
    HHINCOME == 9999999, NA_real_, as.numeric(HHINCOME)
  ))

cat("\nIncome summary:\n")
print(summary(pums_clean$hhincome_clean))
cat("NA income records:      ", sum(is.na(pums_clean$hhincome_clean)), "\n")
cat("Zero income records:    ", sum(pums_clean$hhincome_clean == 0, na.rm = TRUE), "\n")
cat("Negative income records:", sum(pums_clean$hhincome_clean < 0,  na.rm = TRUE), "\n")


# ── 8. NA audit ───────────────────────────────────────────────────────────────
cat("\n── NA audit across all recoded variables ──\n")
pums_clean %>%
  select(gender, hispanic_flag, hispanic_detailed,
         race_detailed, educ_detailed, hhincome_clean) %>%
  summarise(across(everything(), ~sum(is.na(.)))) %>%
  print()


# ── 9. Select final columns ───────────────────────────────────────────────────
# Raw variables retained for auditability alongside cleaned versions
# AGE kept as exact years -- binning at modeling stage

pums_clean <- pums_clean %>%
  select(
    # Identifiers and geography
    SERIAL, PERNUM, STATEFIP, PUMA, CPUMA1020,
    # Weights and variance estimation
    PERWT, HHWT, CLUSTER, STRATA,
    # Raw variables retained for auditability
    AGE, SEX, RACE, RACED, HISPAN, HISPAND, CITIZEN, EDUC, EDUCD, HHINCOME, GQ,
    # Cleaned and labeled variables
    gender, hispanic_flag, hispanic_detailed,
    race_detailed, educ_detailed, hhincome_clean
  )


# ── 10. Final summary ─────────────────────────────────────────────────────────
cat("\n── Final dataset ──\n")
cat("Dimensions:", nrow(pums_clean), "rows x", ncol(pums_clean), "cols\n")
cat("Columns:\n")
print(names(pums_clean))
cat("\nDistinct categories:\n")
cat("Race:     ", n_distinct(pums_clean$race_detailed), "\n")
cat("Hispanic: ", n_distinct(pums_clean$hispanic_detailed), "\n")
cat("Education:", n_distinct(pums_clean$educ_detailed), "\n")
cat("\nReady for PUMA-to-CD crosswalk join.\n")


#---- 11. Save to disk --------#
saveRDS(pums_clean, file.path(processed_dir, "pums_clean.rds"))

cat("Saved successfully.\n")
