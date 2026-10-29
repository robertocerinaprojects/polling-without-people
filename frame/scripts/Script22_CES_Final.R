# ══════════════════════════════════════════════════════════════════════════════
# SCRIPT 22: Package CES 2024 for MrsP delivery
#
# Purpose:
#   Package ces_with_cd_v2.rds as the deliverable CES file. Selects only
#   the columns needed by the MrsP multinomial regression + weighting:
#   respondent id, weights, demographics, geography, and vote_2024.
#
# Deliverables (in Data_Final/):
#   - ces_2024_for_mrsp.csv
#   - ces_2024_for_mrsp.rds
# ══════════════════════════════════════════════════════════════════════════════


library(here)
library(tidyverse)

# ── Folder paths ────────────────────────────────────────────────────────────
processed_dir <- here("Data_Processed")
final_dir     <- here("Data_Final")


# ── 1. Load and select columns ──────────────────────────────────────────────

ces <- readRDS(file.path(processed_dir, "ces_with_cd_v2.rds"))


wanted_cols <- c(
  "caseid",
  "commonweight", "commonpostweight", "tookpost",
  "age_cat", "gender_cat", "race_cat", "hispanic_cat", "educ_cat",
  "state_cat", "cd_cat", "state_abbrv", "state_cd",
  "afact",
  "vote_2024"
)

# Verify all columns exist
missing <- setdiff(wanted_cols, names(ces))
if (length(missing) > 0) {
  stop("Missing columns in CES: ", paste(missing, collapse = ", "))
}

ces_clean <- ces %>% select(all_of(wanted_cols))


# ── 2. Diagnostic ───────────────────────────────────────────────────────────

cat("══ Structure ══\n")
cat("Rows:", nrow(ces_clean), "\n")
cat("Cols:", ncol(ces_clean), "\n")
cat("Unique caseids:", n_distinct(ces_clean$caseid), "\n\n")

cat("Column types:\n")
print(sapply(ces_clean, class))

cat("\n══ Sample rows ══\n")
print(head(ces_clean, 5))

cat("\n══ Weight columns ══\n")
for (col in c("commonweight", "commonpostweight")) {
  cat(sprintf("\n%s:\n", col))
  print(summary(ces_clean[[col]]))
  cat("  NAs:", sum(is.na(ces_clean[[col]])), "\n")
}

cat("\n══ tookpost distribution ══\n")
print(table(ces_clean$tookpost, useNA = "always"))

cat("\n══ Demographic distributions ══\n")
for (col in c("age_cat", "gender_cat", "race_cat", "hispanic_cat", "educ_cat")) {
  cat(sprintf("\n%s:\n", col))
  print(table(ces_clean[[col]], useNA = "always"))
}

cat("\n══ vote_2024 distribution ══\n")
print(table(ces_clean$vote_2024, useNA = "always"))

cat("\n══ afact distribution ══\n")
print(summary(ces_clean$afact))

cat("\n══ Multi-CD respondents ══\n")
multi_cd <- ces_clean %>% count(caseid) %>% filter(n > 1)
single_cd <- ces_clean %>% count(caseid) %>% filter(n == 1)
cat("Respondents with multiple rows (multi-CD):", nrow(multi_cd), "\n")
cat("Respondents with single row:", nrow(single_cd), "\n")
cat("Max rows per respondent:", max(table(ces_clean$caseid)), "\n")

cat("\n══ Geographic coverage ══\n")
cat("Unique state_abbrv:", n_distinct(ces_clean$state_abbrv), "\n")
cat("Unique state_cd:",    n_distinct(ces_clean$state_cd),    "\n")

cat("\n══ NA counts per column ══\n")
print(colSums(is.na(ces_clean)))


# ── 3. Save ─────────────────────────────────────────────────────────────────

write_csv(ces_clean, file.path(final_dir, "ces_2024_for_mrsp.csv"))
saveRDS(ces_clean,   file.path(final_dir, "ces_2024_for_mrsp.rds"))

cat("\nSaved ces_2024_for_mrsp.csv and .rds\n")
cat("File size (CSV):",
    round(file.info(file.path(final_dir, "ces_2024_for_mrsp.csv"))$size / 1e6, 2),
    "MB\n")
