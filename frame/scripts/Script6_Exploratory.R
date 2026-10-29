# ══════════════════════════════════════════════════════════════════════════════
# SCRIPT 6: Initial Exploration of the crosswalked PUMS and CES file
#
# ══════════════════════════════════════════════════════════════════════════════

## ══════════════════════════════════════════════════════════════════════════════
# STAGE 1: Some initial exploration of the crosswalked PUMS FILE
# ══════════════════════════════════════════════════════════════════════════════

library(here)
library(tidyverse)

processed_dir <- here("Data_Processed")

if (!exists("pums_crosswalked")) {
  pums_crosswalked <- readRDS(file.path(processed_dir, "pums_crosswalked.rds"))
}
# ── Check overlap between hispanic_flag and race_detailed ─────────────────────

# 1. Does race_detailed have explicit Hispanic categories?
cat("══ Unique values in race_detailed containing 'Hispanic' or 'Latin' ══\n")
unique(pums_crosswalked$race_detailed)[
  grepl("Hispanic|Latin|Latino|Mexican|Puerto|Cuban", 
        unique(pums_crosswalked$race_detailed), 
        ignore.case = TRUE)
]

# 2. Cross-tabulation: hispanic_flag vs race_detailed (top 20 races)
cat("\n══ Cross-tab: hispanic_flag x race_detailed (top 20 by record count) ══\n")
pums_crosswalked %>%
  count(hispanic_flag, race_detailed, sort = TRUE) %>%
  head(20) %>%
  print()

# 3. How are Hispanic-flagged people distributed across race_detailed categories?
cat("\n══ Race breakdown of Hispanic-flagged respondents ══\n")
pums_crosswalked %>%
  filter(hispanic_flag == 1) %>%
  count(race_detailed, sort = TRUE) %>%
  mutate(pct = round(100 * n / sum(n), 2)) %>%
  head(20) %>%
  print()

# 4. How are non-Hispanic-flagged people distributed across race_detailed?
cat("\n══ Race breakdown of NON-Hispanic-flagged respondents ══\n")
pums_crosswalked %>%
  filter(hispanic_flag == 0) %>%
  count(race_detailed, sort = TRUE) %>%
  mutate(pct = round(100 * n / sum(n), 2)) %>%
  head(10) %>%
  print()

# value counts
table(pums_crosswalked$cd_2026)

# how many unique CDs
n_distinct(pums_crosswalked$cd_2026)

# any NAs?
sum(is.na(pums_crosswalked$cd_2026))

# range
range(pums_crosswalked$cd_2026, na.rm = TRUE)

# rows with 0 or 98
pums_crosswalked %>% filter(cd_2026 %in% c(0, 98)) %>% nrow()

# which states have cd_2026 == 0
pums_crosswalked %>% 
  filter(cd_2026 == 0) %>% 
  distinct(STATEFIP) %>% 
  arrange(STATEFIP)

# which states have cd_2026 == 98
pums_crosswalked %>% 
  filter(cd_2026 == 98) %>% 
  distinct(STATEFIP) %>% 
  arrange(STATEFIP)

n_distinct(paste(pums_crosswalked$STATEFIP, pums_crosswalked$cd_2026))


# 1. How many unique cd_2026 values overall?
n_distinct(pums_crosswalked$cd_2026)

# 2. How many unique state + cd_2026 combinations?
n_distinct(paste(pums_crosswalked$STATEFIP, pums_crosswalked$cd_2026))

# 3. Range of cd_2026 values
range(pums_crosswalked$cd_2026)

# 4. Look at one specific state to see what cd_2026 looks like for it
pums_crosswalked %>%
  filter(STATEFIP == 6) %>%      # California -- should have 1 through 52
  distinct(cd_2026) %>%
  arrange(cd_2026) %>%
  print(n = Inf)

# 5. Same check for a smaller state
pums_crosswalked %>%
  filter(STATEFIP == 36) %>%     # New York -- should have 1 through 26
  distinct(cd_2026) %>%
  arrange(cd_2026) %>%
  print(n = Inf)

# 6. CDs per state -- should match the known House seat distribution
pums_crosswalked %>%
  distinct(STATEFIP, cd_2026) %>%
  filter(!cd_2026 %in% c(0, 98)) %>%
  count(STATEFIP, name = "n_cds") %>%
  arrange(desc(n_cds)) %>%
  print(n = Inf)



# CDs per state in the UNIFIED crosswalk
unified_crosswalk %>%
  distinct(state, cd_2026) %>%
  filter(!cd_2026 %in% c(0, 98)) %>%
  count(state, name = "n_cds") %>%
  arrange(desc(n_cds)) %>%
  print(n = Inf)

# total seat count (should be 429 nationally + 6 at-large = 435)
unified_crosswalk %>%
  distinct(state, cd_2026) %>%
  filter(!cd_2026 %in% c(0, 98)) %>%
  nrow()
# plus 6 at-large = should equal 435



pums_crosswalked %>%
  distinct(STATEFIP, cd_2026) %>%
  filter(!cd_2026 %in% c(0, 98)) %>%
  count(STATEFIP, name = "n_cds") %>%
  arrange(desc(n_cds)) %>%
  print(n = Inf)


## ══════════════════════════════════════════════════════════════════════════════
# STAGE 2: Some initial exploration of the CES common post file
# Purpose: Load the CES common post file and inventory its variables,
#          types, and category distributions before deciding what to use
#          for the modeling stages.
# ══════════════════════════════════════════════════════════════════════════════

library(tidyverse)

# ── 1. Read CES file ──────────────────────────────────────────────────────────
raw_dir <- here("Data_Raw")

ces <- read_csv(file.path(raw_dir, "CCES24_Common_OUTPUT_vv_topost_final.csv"), guess_max = Inf)


# ── 2. Top-level dimensions ──────────────────────────────────────────────────
cat("══ Dimensions ══\n")
cat("Rows:   ", nrow(ces), "\n")
cat("Columns:", ncol(ces), "\n\n")


# ── 3. Column inventory ──────────────────────────────────────────────────────
cat("══ All columns and types ══\n")
ces_summary <- tibble(
  column = names(ces),
  type   = sapply(ces, function(x) class(x)[1]),
  n_unique = sapply(ces, function(x) n_distinct(x)),
  n_na     = sapply(ces, function(x) sum(is.na(x)))
)
print(ces_summary, n = Inf)


# ── 4. Sample of first rows ──────────────────────────────────────────────────
cat("\n══ First 5 rows ══\n")
print(head(ces, 5))


# ── 5. Distributions of likely-key categorical variables ─────────────────────
# Focus on low-cardinality columns since these are likely categorical
cat("\n══ Distributions for variables with ≤ 30 unique values ══\n")

low_card_cols <- ces_summary %>%
  filter(n_unique <= 30 & n_unique > 1) %>%
  pull(column)

for (col in low_card_cols) {
  cat("\n--- ", col, " ---\n", sep = "")
  ces %>%
    count(.data[[col]], sort = TRUE) %>%
    print(n = Inf)
}


# ── 6. Year coverage if a year column exists ─────────────────────────────────
cat("\n══ Year coverage ══\n")
year_cols <- names(ces)[grepl("year|YEAR|Year", names(ces))]
if (length(year_cols) > 0) {
  for (col in year_cols) {
    cat("\n--- ", col, " ---\n", sep = "")
    print(table(ces[[col]], useNA = "ifany"))
  }
}

cat("Finished running script 6 successfully")

