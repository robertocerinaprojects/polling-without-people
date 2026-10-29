# ══════════════════════════════════════════════════════════════════════════════
# SCRIPT 07: Harmonize demographic variables across PUMS and CES
#
# Purpose:
#   Create matching _cat columns in PUMS and CES so the same categorical
#   schemes are used in both. Required for MrsP cell construction.
#
# Inputs:
#   - pums_crosswalked.rds (from Script 05 loaded from disk)
#   - ces (loaded in Script 06 loaded from disk)
#
# Outputs:
#   - pums_crosswalked_harmonized.rds
#   - ces_harmonized.rds
#
# Variables harmonized:
#   age_cat       — 5-year bins (18-22 to 83+); 14 levels
#   gender_cat    — Male / Female; CES non-binary respondents dropped (~554)
#   educ_cat      — 6 levels (No HS to Post-grad)
#   hispanic_cat  — Hispanic / Not Hispanic
#   race_cat      — 5 levels (White, Black, Native American, Asian, Other/Multi)
#
# Key design choices:
#   - Race and Hispanic treated as INDEPENDENT dimensions (no Hispanic-first rule)
#   - Binary gender per ACS structural constraint
#   - All variables categorical; categories must match the stratification frame
# ══════════════════════════════════════════════════════════════════════════════

library(here)
library(tidyverse)

raw_dir       <- here("Data_Raw")
processed_dir <- here("Data_Processed")

# Load Inputs from Disk
pums_crosswalked <- readRDS(file.path(processed_dir, "pums_crosswalked.rds")) %>%
  select(-any_of(c("age_cat", "gender_cat", "educ_cat", "hispanic_cat", "race_cat")))

ces <- read_csv(file.path(raw_dir, "CCES24_Common_OUTPUT_vv_topost_final.csv"), show_col_types = FALSE) %>%
  select(-any_of(c("age_cat", "gender_cat", "educ_cat", "hispanic_cat", "race_cat")))


# ── 1. AGE → age_cat ─────────────────────────────────────────────────────────
#
# Raw formats:
#   pums_crosswalked$AGE  : integer years, 18+
#   ces$age               : integer years, 18+
#
# Binning scheme: 5-year bins starting at 18.
#   Each bin spans 5 ages, inclusive on both ends (e.g. "18-22" = 18, 19, 20, 21, 22).
#   The top bin is open-ended (83+) since exact age past ~80 is less informative
#   for political behavior and the upper tail has fewer respondents.
#
# Why 5-year bins:
#   - Captures meaningful age gradients in turnout and partisanship
#   - Keeping fine granularity at frame stage; we can collapse
#     to broader bins later at modeling stage if cells are too sparse
#   - Standard ccesMRPprep package offers 5-year and 10-year keys; we use 5
#
# How cut() works:
#   breaks = c(17, 22, ...) with right = TRUE means bins are (lower, upper]
#   - (17, 22] → 18, 19, 20, 21, 22 → labeled "18-22"
#   - (22, 27] → 23, 24, 25, 26, 27 → labeled "23-27"
#   - (82, Inf] → 83 and above → labeled "83+"
#   The lowest break is 17 (not 18) to cleanly exclude any stray under-18 records
#   while including 18 in the first bin.


#first, calculate age and store as column in ces
ces <- ces %>%
  mutate(age = 2024 - birthyr)

cat("Age summary:\n")
summary(ces$age)

bin_age <- function(age) {
  cut(age,
      breaks = c(17, 22, 27, 32, 37, 42, 47, 52, 57, 62, 67, 72, 77, 82, Inf),
      labels = c("18-22", "23-27", "28-32", "33-37", "38-42", "43-47",
                 "48-52", "53-57", "58-62", "63-67", "68-72", "73-77",
                 "78-82", "83+"),
      right  = TRUE)
}

# Apply to PUMS frame -- creates new column age_cat alongside raw AGE
pums_crosswalked <- pums_crosswalked %>%
  mutate(age_cat = bin_age(AGE))

# Apply to CES survey data -- same binning, same column name
ces <- ces %>%
  mutate(age_cat = bin_age(age))

# Distribution check on PUMS
# This shows the share of each age bin in the demographic frame.
# Expected: monotonically declining shares from middle-age peak toward older bins,
# with relatively even shares for working-age bins.
cat("══ PUMS age_cat distribution ══\n")
pums_crosswalked %>%
  count(age_cat) %>%
  mutate(pct = round(100 * n / sum(n), 2)) %>%
  print()

# Distribution check on CES
# This shows the share of each age bin in the survey sample.
# Expected: similar shape to PUMS but with some sampling differences --
# CES tends to slightly overrepresent middle-age engaged voters.
cat("\n══ CES age_cat distribution ══\n")
ces %>%
  count(age_cat) %>%
  mutate(pct = round(100 * n / sum(n), 2)) %>%
  print()

# Side by side comparison
pums_dist <- pums_crosswalked %>%
  count(age_cat, wt = PERWT_adj) %>%   # use weighted counts for fair comparison
  mutate(pct_pums = round(100 * n / sum(n), 2)) %>%
  select(age_cat, pct_pums)

ces_dist <- ces %>%
  count(age_cat) %>%
  mutate(pct_ces = round(100 * n / sum(n), 2)) %>%
  select(age_cat, pct_ces)

comparison <- pums_dist %>%
  left_join(ces_dist, by = "age_cat") %>%
  mutate(diff = pct_ces - pct_pums)

cat("══ PUMS vs CES age distribution comparison ══\n")
print(comparison, n = Inf)


# ── NEXT VARIABLE──────────────────────────────────────────
# Variables remaining to harmonize:
#   - gender / sex
#   - race + Hispanic (combined per Hispanic-first rule)
#   - education
#   - household income
#   - state + congressional district (geography)



# Inspect gender4 column structure
cat("══ Class and type of gender4 ══\n")
print(class(ces$gender4))
print(typeof(ces$gender4))

cat("\n══ Distribution of gender4 ══\n")
ces %>%
  count(gender4) %>%
  mutate(pct = round(100 * n / sum(n), 2)) %>%
  print()

# Check if there's a haven_labelled attribute that gives us the labels
cat("\n══ Value labels (if labelled) ══\n")
if ("haven_labelled" %in% class(ces$gender4)) {
  print(attr(ces$gender4, "labels"))
} else {
  cat("Not a labelled vector. Raw values shown above.\n")
}

# Also check gender4_t for any text responses
cat("\n══ Sample of non-empty gender4_t responses ══\n")
ces %>%
  filter(!is.na(gender4_t) & gender4_t != "") %>%
  count(gender4_t, sort = TRUE) %>%
  head(20) %>%
  print()


# ── 2. GENDER → harmonize CES gender4 to PUMS binary gender ──────────────────
#
# Raw formats:
#   pums_crosswalked$gender : "Male" / "Female" (binary, from ACS SEX)
#   ces$gender4             : 1=Man, 2=Woman, 3=Non-binary, 4=Other
#
# Harmonized column: gender_cat
#   Both datasets get a new gender_cat column with values "Male" / "Female".
#   This keeps the harmonized cell-defining variables consistently named
#   (age_cat, gender_cat, ...) and distinct from the raw source columns.
#
# ACS only collects binary sex (Male/Female). Non-binary and Other CES 
# respondents cannot be matched to PUMS poststratification cells under this 
# structural constraint. We drop these 554 respondents (~0.93% of CES) since
# they cannot contribute to MrP estimation regardless.


# PUMS: just copy existing gender column into gender_cat
pums_crosswalked <- pums_crosswalked %>%
  mutate(gender_cat = gender)

# CES: filter out non-binary/Other, then create gender_cat
ces <- ces %>%
  filter(gender4 %in% c(1, 2)) %>%
  mutate(gender_cat = case_when(
    gender4 == 1 ~ "Male",
    gender4 == 2 ~ "Female"
  ))

# Verify distributions match between PUMS and CES
cat("══ PUMS gender_cat distribution (weighted) ══\n")
pums_crosswalked %>%
  count(gender_cat, wt = PERWT_adj) %>%
  mutate(pct = round(100 * n / sum(n), 2)) %>%
  print()

cat("\n══ CES gender_cat distribution ══\n")
ces %>%
  count(gender_cat) %>%
  mutate(pct = round(100 * n / sum(n), 2)) %>%
  print()

cat("\nCES rows after dropping non-binary/Other:", nrow(ces), "\n")


# ── 3. EDUCATION → harmonize PUMS EDUCD to CES 6-category scheme ─────────────

# Define a single helper to label educ values consistently across both datasets
label_educ <- function(code) {
  factor(code,
         levels = 1:6,
         labels = c("No HS",
                    "HS grad",
                    "Some college",
                    "2-year",
                    "4-year",
                    "Post-grad"))
}

# Apply to PUMS -- use zap_labels to strip haven_labelled before mapping
pums_crosswalked <- pums_crosswalked %>%
  mutate(EDUCD_num = haven::zap_labels(EDUCD)) %>%
  mutate(educ_cat = case_when(
    EDUCD_num %in% c(2, 11, 12, 14, 15, 16, 17, 22, 23, 25, 26, 
                     30, 40, 50, 61)                  ~ 1L,
    EDUCD_num %in% c(63, 64)                          ~ 2L,
    EDUCD_num %in% c(65, 71)                          ~ 3L,
    EDUCD_num == 81                                   ~ 4L,
    EDUCD_num == 101                                  ~ 5L,
    EDUCD_num %in% c(114, 115, 116)                   ~ 6L,
    TRUE                                              ~ NA_integer_
  )) %>%
  mutate(educ_cat = label_educ(educ_cat)) %>%
  select(-EDUCD_num)

# Apply to CES -- educ is already 1-6 numeric, just label it
ces <- ces %>%
  mutate(educ_cat = label_educ(as.integer(educ)))

# Verify distributions
cat("══ PUMS educ_cat distribution (weighted) ══\n")
pums_crosswalked %>%
  count(educ_cat, wt = PERWT_adj) %>%
  mutate(pct = round(100 * n / sum(n), 2)) %>%
  print()

cat("\n══ CES educ_cat distribution ══\n")
ces %>%
  count(educ_cat) %>%
  mutate(pct = round(100 * n / sum(n), 2)) %>%
  print()



# ── 4. HISPANIC → harmonize CES hispanic to PUMS hispanic_flag ───────────────
#
# Raw formats:
#   pums_crosswalked$hispanic_flag : 0 = Not Hispanic, 1 = Hispanic
#   ces$hispanic                   : 1 = Yes (Hispanic), 2 = No (Not Hispanic)
#
# Harmonized column: hispanic_cat ("Hispanic" / "Not Hispanic" as factor)

# Helper to label
label_hispanic <- function(code) {
  factor(code,
         levels = c(1L, 0L),
         labels = c("Hispanic", "Not Hispanic"))
}

# Apply to PUMS
pums_crosswalked <- pums_crosswalked %>%
  mutate(hispanic_cat = label_hispanic(hispanic_flag))

# Apply to CES -- map 1->1, 2->0, NA stays NA
ces <- ces %>%
  mutate(hispanic_cat = case_when(
    hispanic == 1 ~ 1L,
    hispanic == 2 ~ 0L,
    TRUE          ~ NA_integer_
  )) %>%
  mutate(hispanic_cat = label_hispanic(hispanic_cat))

# Verify distributions
cat("══ PUMS hispanic_cat distribution (weighted) ══\n")
pums_crosswalked %>%
  count(hispanic_cat, wt = PERWT_adj) %>%
  mutate(pct = round(100 * n / sum(n), 2)) %>%
  print()

cat("\n══ CES hispanic_cat distribution ══\n")
ces %>%
  count(hispanic_cat) %>%
  mutate(pct = round(100 * n / sum(n), 2)) %>%
  print()


cat("══ Does hispanic_cat exist in ces? ══\n")
"hispanic_cat" %in% names(ces)

cat("\n══ First few rows of ces$hispanic_cat ══\n")
head(ces$hispanic_cat, 10)

cat("\n══ Class of ces$hispanic_cat ══\n")
class(ces$hispanic_cat)


###----------- 5. Race -------------------##

# Check what's in race == 8
cat("══ Sample of race == 8 ══\n")
ces %>%
  filter(race == 8) %>%
  count(race_other, sort = TRUE) %>%
  head(20) %>%
  print()

# And check if multrace is populated for race == 8
cat("\n══ multrace columns when race == 8 ══\n")
ces %>%
  filter(race == 8) %>%
  summarise(across(starts_with("multrace_"), ~sum(!is.na(.) & . != 0))) %>%
  pivot_longer(everything()) %>%
  arrange(desc(value)) %>%
  print(n = Inf)


# Helper to label race_cat consistently
label_race <- function(code) {
  factor(code,
         levels = 1:6,
         labels = c("White", "Black", "Native American", "Asian", 
                    "Two or more races", "Other"))
}

# ── Apply to PUMS ────────────────────────────────────────────────────────────
# IPUMS RACE codes:
#   1 = White, 2 = Black, 3 = AI/AN, 4 = Chinese, 5 = Japanese,
#   6 = Other Asian/PI, 7 = Other race, 8 = Two major races, 9 = Three or more

pums_crosswalked <- pums_crosswalked %>%
  mutate(RACE_num = haven::zap_labels(RACE)) %>%
  mutate(race_cat = case_when(
    RACE_num == 1                ~ 1L,  # White
    RACE_num == 2                ~ 2L,  # Black
    RACE_num == 3                ~ 3L,  # Native American (AI/AN)
    RACE_num %in% c(4, 5, 6)     ~ 4L,  # Asian (Chinese, Japanese, Other Asian/PI)
    RACE_num %in% c(8, 9)        ~ 5L,  # Two or more (incl. three+)
    RACE_num == 7                ~ 6L,  # Other
    TRUE                         ~ NA_integer_
  )) %>%
  mutate(race_cat = label_race(race_cat)) %>%
  select(-RACE_num)

# ── Apply to CES ─────────────────────────────────────────────────────────────
# CES race codes:
#   1 = White, 2 = Black, 3 = Hispanic, 4 = Asian, 5 = Native American,
#   6 = Two or more, 7 = Other, 8 = Middle Eastern

ces <- ces %>%
  mutate(race_cat = case_when(
    race == 1                    ~ 1L,  # White
    race == 2                    ~ 2L,  # Black
    race == 5                    ~ 3L,  # Native American
    race == 4                    ~ 4L,  # Asian
    race == 6                    ~ 5L,  # Two or more
    race %in% c(3, 7, 8)         ~ 6L,  # Other (Hispanic-as-race, Other, Middle Eastern)
    TRUE                         ~ NA_integer_
  )) %>%
  mutate(race_cat = label_race(race_cat))


# ── Verify distributions ─────────────────────────────────────────────────────
cat("══ PUMS race_cat distribution (weighted) ══\n")
pums_crosswalked %>%
  count(race_cat, wt = PERWT_adj) %>%
  mutate(pct = round(100 * n / sum(n), 2)) %>%
  print()

cat("\n══ CES race_cat distribution ══\n")
ces %>%
  count(race_cat) %>%
  mutate(pct = round(100 * n / sum(n), 2)) %>%
  print()

# Cross-tab race_cat × hispanic_cat to verify they're independent
cat("\n══ PUMS race_cat × hispanic_cat (weighted) ══\n")
pums_crosswalked %>%
  count(race_cat, hispanic_cat, wt = PERWT_adj) %>%
  pivot_wider(names_from = hispanic_cat, values_from = n) %>%
  print()

cat("\n══ CES race_cat × hispanic_cat ══\n")
ces %>%
  count(race_cat, hispanic_cat) %>%
  pivot_wider(names_from = hispanic_cat, values_from = n) %>%
  print()

# Collapse Two or more races and Other into a single category for cleaner alignment (since hispanics go into either)
pums_crosswalked <- pums_crosswalked %>%
  mutate(race_cat = fct_collapse(race_cat, 
                                 "Other/Multi" = c("Two or more races", "Other")))

ces <- ces %>%
  mutate(race_cat = fct_collapse(race_cat, 
                                 "Other/Multi" = c("Two or more races", "Other")))

# Verify
cat("══ PUMS race_cat distribution (weighted) ══\n")
pums_crosswalked %>%
  count(race_cat, wt = PERWT_adj) %>%
  mutate(pct = round(100 * n / sum(n), 2)) %>%
  print()

cat("\n══ CES race_cat distribution ══\n")
ces %>%
  count(race_cat) %>%
  mutate(pct = round(100 * n / sum(n), 2)) %>%
  print()

# ── 6. Save harmonized datasets ──────────────────────────────────────────────
saveRDS(pums_crosswalked, file.path(processed_dir, "pums_crosswalked_harmonized.rds"))
saveRDS(ces, file.path(processed_dir, "ces_harmonized.rds"))

cat("Harmonization complete. Saved harmonized datasets.\n")
