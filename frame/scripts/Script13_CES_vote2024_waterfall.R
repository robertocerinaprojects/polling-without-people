# ══════════════════════════════════════════════════════════════════════════════
# SCRIPT 13: Construct vote_2024 column for CES respondents
#
# Purpose:
#   Create a single, clean party-level vote variable for each CES respondent,
#   drawn from the most reliable source available in the CES survey instrument.
#   This is the modeling target for the multinomial vote-choice regression.
#
# Background — the CES 2024 vote-related variables:
#
#   The CES has both pre-election and post-election waves. Vote-related
#   information is captured in multiple questions across these waves, with
#   different gating logic per question.
#
#   Pre-election (asked of all pre-wave respondents, with branching):
#
#     CC24_363 — Vote intention
#       "Do you intend to vote in the 2024 general election on November 5th?"
#       Codes: 1 = Yes, definitely
#              2 = Probably
#              3 = I already voted (early or absentee)
#              4 = I plan to vote before November 5th
#              5 = No
#              6 = Undecided
#              8/9 = Skipped / Not asked
#       Asked of all respondents.
#
#     CC24_367 — House preference
#       "In the general election for U.S. House of Representatives in your
#        area, who do you prefer?"
#       Codes: 1-5 = $HouseCand1Name through $HouseCand5Name (candidate index)
#              10  = Other
#              98  = I'm not sure
#              99  = No one
#              998/999 = Skipped / Not asked
#       Asked of respondents who hadn't already voted at pre-wave time
#       (complement of CC24_367_voted).
#
#     CC24_367_voted — House vote (early voters only)
#       "For which House candidate did you vote?"
#       Codes: 1-5 = candidate index (same mapping as CC24_367)
#              10  = Other
#              98  = Not sure
#              99  = Didn't vote
#              998/999 = Skipped / Not asked
#       ONLY asked of respondents who said CC24_363 == 3 (already voted
#       before the pre-election survey).
#
#   Post-election (only for tookpost == 2 respondents):
#
#     CC24_401 — Turnout
#       "Voted in the 2024 election? Which of the following statements best
#        describes you?"
#       Codes: 1 = I did not vote in the election this November
#              2 = I thought about voting this time – but didn't
#              3 = I usually vote, but didn't this time
#              4 = I attempted to vote but did not or could not
#              5 = I definitely voted in the November 2024 General Election
#              8/9 = Skipped / Not asked
#       Asked of all post-wave respondents.
#
#     CC24_412 — House vote (post-wave)
#       "Who did you vote in the election (House)?"
#       Codes: 1-5 = candidate index (same mapping)
#              10  = Other
#              11  = I did not vote in this race
#              12  = I did not vote
#              13  = Not sure
#              98/99 = Skipped / Not asked
#       Only shown if at least one House candidate exists for that
#       respondent's district.
#
#   Candidate party lookup:
#     HouseCand1Party, ..., HouseCand5Party hold the party affiliation of
#     each candidate. The candidate index in any of the vote questions
#     above maps directly to these columns.
#
# Waterfall logic (in order of preference):
#   (a) CC24_412   — Confirmed votes from post-wave (most reliable)
#   (b) CC24_401   — Post-wave confirmation of non-voting
#   (c) CC24_367_voted — Pre-wave reported actual votes (early voters)
#   (d) CC24_367   — Pre-wave reported vote preference
#   (e) CC24_363   — Pre-wave reported intention not to vote (No Vote only)
#   (f) NA         — No clean information available
#
# Inputs:
#   - ces_with_cd_v2.rds (from Script 12)
#
# Output:
#   - ces_with_cd_v2.rds (overwritten with vote_2024 column added)
#
# Sections:
#   1. Load CES; diagnostic on vote-related columns
#   2. Helper function: party_from_candidate()
#   3. Apply waterfall to construct vote_2024
#   4. Convert vote_2024 to factor with explicit level ordering
#   5. Verify final distribution
#   6. Collapse low-count categories (Libertarian, Green, Independent) → Other
#   7. Save
# ══════════════════════════════════════════════════════════════════════════════

library(tidyverse)
library(here)

# ── 1. Load CES and diagnostic on vote-related columns ──────────────────────


# ── Folder paths ────────────────────────────────────────────────────────────
raw_dir       <- here("Data_Raw")
processed_dir <- here("Data_Processed")

# ── Load inputs from disk ──────────────────────────

ces_with_cd_v2 <- readRDS(file.path(processed_dir, "ces_with_cd_v2.rds")) %>%
  select(-any_of("vote_2024")) #added for idempotency

cat("Loaded CES:", nrow(ces_with_cd_v2), "rows x", ncol(ces_with_cd_v2), "cols\n")
cat("Unique respondents:", n_distinct(ces_with_cd_v2$caseid), "\n\n")

# Inspect the key vote columns (per-respondent, deduplicating row inflation)
ces_per_resp <- ces_with_cd_v2 %>% distinct(caseid, .keep_all = TRUE)

cat("══ CC24_412 distribution (post-wave House vote) ══\n")
print(table(ces_per_resp$CC24_412, useNA = "always"))

cat("\n══ CC24_401 distribution (post-wave turnout) ══\n")
print(table(ces_per_resp$CC24_401, useNA = "always"))

cat("\n══ CC24_367_voted distribution (pre-wave actual vote, early voters) ══\n")
print(table(ces_per_resp$CC24_367_voted, useNA = "always"))

cat("\n══ CC24_367 distribution (pre-wave preference) ══\n")
print(table(ces_per_resp$CC24_367, useNA = "always"))

cat("\n══ CC24_363 distribution (pre-wave vote intention) ══\n")
print(table(ces_per_resp$CC24_363, useNA = "always"))


# ── 2. Helper function: party_from_candidate() ──────────────────────────────
# Takes a candidate index (1-5) and the five HouseCandNParty columns for that
# respondent. Returns a standardized party label.
#
# Standardization:
#   Democratic          → "Democratic"
#   Republican          → "Republican"
#   Libertarian         → "Libertarian"
#   Green               → "Green"
#   Independent         → "Independent"
#   No Party Preference → "Independent" (California convention)
#   Any other party     → "Other" (Unity, write-ins, fringe)
#   NA                  → NA
#
# Note on "No Party Preference": this is the official ballot designation in
# some states (notably California) for candidates running without major-party
# affiliation. Functionally equivalent to Independent; folded together.

party_from_candidate <- function(idx, p1, p2, p3, p4, p5) {
  raw_party <- case_when(
    idx == 1 ~ p1,
    idx == 2 ~ p2,
    idx == 3 ~ p3,
    idx == 4 ~ p4,
    idx == 5 ~ p5,
    TRUE     ~ NA_character_
  )
  
  case_when(
    raw_party == "Democratic"          ~ "Democratic",
    raw_party == "Republican"          ~ "Republican",
    raw_party == "Libertarian"         ~ "Libertarian",
    raw_party == "Green"               ~ "Green",
    raw_party == "Independent"         ~ "Independent",
    raw_party == "No Party Preference" ~ "Independent",
    is.na(raw_party)                   ~ NA_character_,
    TRUE                               ~ "Other"
  )
}


# ── 3. Apply waterfall to construct vote_2024 ───────────────────────────────
# Each step starts with the result of the previous step; if NA, this step
# attempts to fill it in from its own data source. The result of the final
# step is the vote_2024 column.

ces_with_cd_v2 <- ces_with_cd_v2 %>%
  mutate(
    
    # STEP 1: CC24_412 (post-wave House vote) — most reliable
    vote_step1 = case_when(
      CC24_412 %in% 1:5 ~ party_from_candidate(
        CC24_412,
        HouseCand1Party, HouseCand2Party,
        HouseCand3Party, HouseCand4Party, HouseCand5Party),
      CC24_412 == 10           ~ "Other",         # write-in
      CC24_412 %in% c(11, 12)  ~ "No Vote",       # didn't vote in race / didn't vote
      TRUE                     ~ NA_character_    # 13, 98, 99, NA — fall through
    ),
    
    # STEP 2: CC24_401 (post-wave turnout) — confirms No Vote
    vote_step2 = case_when(
      !is.na(vote_step1)  ~ vote_step1,
      CC24_401 %in% 1:4   ~ "No Vote",
      TRUE                ~ NA_character_   # 5, 8, 9, NA — fall through
    ),
    
    # STEP 3a: CC24_367_voted (pre-wave actual vote, early voters)
    vote_step3a = case_when(
      !is.na(vote_step2)       ~ vote_step2,
      CC24_367_voted %in% 1:3  ~ party_from_candidate(
        CC24_367_voted,
        HouseCand1Party, HouseCand2Party,
        HouseCand3Party, NA, NA),
      CC24_367_voted == 10     ~ "Other",
      CC24_367_voted == 99     ~ "No Vote",
      TRUE                     ~ NA_character_   # 98, 998, 999, NA — fall through
    ),
    
    # STEP 3b: CC24_367 (pre-wave preference)
    vote_step3b = case_when(
      !is.na(vote_step3a)  ~ vote_step3a,
      CC24_367 %in% 1:3    ~ party_from_candidate(
        CC24_367,
        HouseCand1Party, HouseCand2Party,
        HouseCand3Party, NA, NA),
      CC24_367 == 10       ~ "Other",
      CC24_367 == 99       ~ "No Vote",
      TRUE                 ~ NA_character_   # 98, 998, 999, NA — fall through
    ),
    
    # STEP 4: CC24_363 (pre-wave intention) — No Vote only
    # Positive vote intent without a candidate name is too weak to record.
    vote_2024 = case_when(
      !is.na(vote_step3b)  ~ vote_step3b,
      CC24_363 == 5        ~ "No Vote",
      TRUE                 ~ NA_character_   # NA = no information available
    )
  ) %>%
  
  select(-vote_step1, -vote_step2, -vote_step3a, -vote_step3b)


# ── 4. Convert vote_2024 to factor with explicit level ordering ─────────────
# Ordering matters for modeling — Democratic and Republican first so they're
# the reference categories during regression.

ces_with_cd_v2 <- ces_with_cd_v2 %>%
  mutate(vote_2024 = factor(
    vote_2024,
    levels = c("Democratic", "Republican", "Libertarian",
               "Green", "Independent", "Other", "No Vote")
  ))


# ── 5. Verify the final distribution ────────────────────────────────────────
# Use distinct(caseid) to count each respondent once, since ces_with_cd_v2
# may have row inflation from the ZCTA crosswalk.

cat("══ vote_2024 distribution (unique respondents) ══\n")
ces_with_cd_v2 %>%
  distinct(caseid, .keep_all = TRUE) %>%
  count(vote_2024) %>%
  mutate(pct = round(100 * n / sum(n), 2)) %>%
  print()

# Summary
n_unique <- n_distinct(ces_with_cd_v2$caseid)
n_with_vote <- ces_with_cd_v2 %>%
  distinct(caseid, .keep_all = TRUE) %>%
  filter(!is.na(vote_2024)) %>%
  nrow()

cat("\n══ Summary ══\n")
cat("Total unique respondents: ", n_unique, "\n")
cat("With non-NA vote_2024:    ", n_with_vote, "\n")
cat("Coverage:                  ", round(100 * n_with_vote / n_unique, 1), "%\n")


# ── 6. Collapse low-count categories ────────────────────────────────────────
# Libertarian, Green, and Independent each have very small respondent counts
# (typically <1% each) — too sparse for stable estimation in a multinomial
# regression. Collapse them with "Other" to create a single residual category.

ces_with_cd_v2 <- ces_with_cd_v2 %>%
  mutate(vote_2024 = fct_collapse(
    vote_2024,
    "Other" = c("Libertarian", "Green", "Independent", "Other")
  ))

cat("\n══ vote_2024 distribution after collapse ══\n")
ces_with_cd_v2 %>%
  distinct(caseid, .keep_all = TRUE) %>%
  count(vote_2024) %>%
  mutate(pct = round(100 * n / sum(n), 2)) %>%
  print()


# ── 7. Save ─────────────────────────────────────────────────────────────────

#Overwrite ces_with_cd_v2
saveRDS(ces_with_cd_v2, file.path(processed_dir, "ces_with_cd_v2.rds"))

cat("\nSaved ces_with_cd_v2 with vote_2024 column\n")
