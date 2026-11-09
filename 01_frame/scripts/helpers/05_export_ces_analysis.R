# Export the 11 analysis columns from the saved, harmonized CES.
# From the repository root: Rscript 01_frame/scripts/helpers/05_export_ces_analysis.R
# Column definitions: 01_frame/docs/05_prepare_ces.md
export_ces_analysis <- function(intermediate_dir) {
  source_path <- file.path(intermediate_dir, "ces_demographics_harmonized.rds")
  destination <- file.path(intermediate_dir, "ces_analysis.rds")
  respondents <- as.data.frame(readRDS(source_path))
  # Respondent ID and weight, the seven population-cell keys on the 2026
  # map, and the two 2024 outcomes. Selecting columns preserves factor levels
  # and keeps respondents whose vote or ethnicity is missing.
  analysis_columns <- c(
    "caseid", "commonweight",
    "STATEFP", "CDFP120",
    "age_cat", "gender_cat", "race_cat", "hispanic_cat", "educ_cat",
    "house_vote_2024", "pres_vote_2024"
  )
  missing_fields <- setdiff(analysis_columns, names(respondents))
  if (length(missing_fields)) {
    stop("Missing fields in the saved CES: ", paste(missing_fields, collapse = ", "))
  }
  stopifnot(!anyDuplicated(names(respondents)), nrow(respondents) > 0L,
            !anyNA(respondents$caseid), !anyDuplicated(respondents$caseid))
  analysis <- respondents[analysis_columns]

  temporary <- tempfile(".05-ces-analysis-", tmpdir = intermediate_dir)
  on.exit(unlink(temporary), add = TRUE)
  saveRDS(analysis, temporary)
  if (!file.rename(temporary, destination)) stop("Could not save ", destination)
  message("Saved ", nrow(analysis), " respondents and ", ncol(analysis),
          " columns to ", destination)
  invisible(analysis)
}

if (sys.nframe() == 0L) {
  analysis <- export_ces_analysis(file.path("01_frame", "data", "intermediate"))
  print(utils::head(analysis), row.names = FALSE)
}
