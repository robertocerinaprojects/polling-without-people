#!/usr/bin/env bash
set -euo pipefail

# Start from the repository root. See 01_frame/README.md for setup.
scripts=01_frame/scripts
outputs=01_frame/data/output

# Check the local inputs before any numbered script can start a download.
# The numbered scripts verify their contents against the recorded checksums.
Rscript -e '
  input <- "01_frame/data/input"
  files <- file.path(input, c(
    "cd119.zip", "cd120.zip", "2020_Census_Tract_to_2020_PUMA.txt",
    "CVAP_2020-2024_ACS_csv_files.zip",
    "Errata148_Suppressed_Geographies_for_Wyandanch.xlsx",
    "acs22_cousub22_blkgrp20_st09.txt", "tl_2024_09_bg.zip",
    "CCES24_Common_OUTPUT_vv_topost_final.csv", "119-nominations.pdf",
    "120-nominations.pdf", "05_vote_benchmark/fec2024.xlsx",
    "05_vote_benchmark/clerk2024.pdf",
    "07_area_returns/1976-2024-president.csv",
    "07_area_returns/1976-2024-house.csv"
  ))
  manifest <- read.csv("01_frame/docs/02_pl_2020_sources.csv")
  files <- c(files, manifest$path)
  store <- file.path(input, "ipums_pums")
  pointer <- file.path(store, "current_snapshot.txt")
  files <- c(files, pointer)
  if (file.exists(pointer)) {
    id <- readLines(pointer, warn = FALSE)
    if (length(id) != 1L || !grepl("^[0-9]{8}T[0-9]{6}_[0-9]+$", id)) {
      stop("Invalid IPUMS snapshot pointer: ", pointer, call. = FALSE)
    }
    snapshot <- file.path(store, id)
    receipt <- file.path(snapshot, "download_manifest.csv")
    files <- c(files, receipt, file.path(snapshot, "request.json"))
    if (file.exists(receipt)) {
      saved <- read.csv(receipt, colClasses = "character")
      if (nrow(saved) != 2L || !setequal(saved$role, c("data", "ddi_codebook")) ||
          !all(grepl("^[A-Za-z0-9_.-]+$", saved$file))) {
        stop("Invalid IPUMS download receipt: ", receipt, call. = FALSE)
      }
      files <- c(files, file.path(snapshot, "files", saved$file))
    }
  }
  missing <- files[!file.exists(files)]
  if (length(missing)) {
    writeLines(c("Offline rebuild needs these local source files:",
                 paste0("  ", missing),
                 "See 01_frame/README.md for setup."), stderr())
    quit(status = 1L)
  }
'

run() {
  printf '\nRunning %s\n' "$*"
  "$@"
}

check_sampler() {
  # Require the first two stages to pass. Keep the final split provisional
  # if Stan flags it, and show the location of the diagnostics.
  Rscript -e '
    path <- commandArgs(TRUE)[[1L]]
    audit <- read.csv(path)
    if (!identical(audit$stage, c("none", "rep", "dem")) ||
        !is.logical(audit$passed) || anyNA(audit$passed)) {
      stop("Invalid sampler audit. Review ", path, call. = FALSE)
    }
    if (!all(audit$passed[1:2])) {
      stop("Sampler checks failed. Review ", path, call. = FALSE)
    }
    if (!audit$passed[3L]) {
      warning("Democratic-versus-Other sampler checks flagged. Results are provisional. See ",
              path, call. = FALSE)
    }
  ' "$1"
}

run Rscript "$scripts/00_download_pums.R"
run Rscript "$scripts/01_prepare_pums.R"
run Rscript "$scripts/02_build_puma_cd_crosswalk.R"
run Rscript "$scripts/03_apply_puma_cd_crosswalk.R"
run Rscript "$scripts/04_harmonize_pums.R"
run Rscript "$scripts/05_prepare_ces.R"
run Rscript "$scripts/06_build_pums_cells.R"
run Rscript "$scripts/helpers/06_check_analysis_files.R"

run python3 "$scripts/07_prepare_area_returns.py"
run python3 "$scripts/helpers/05_benchmark_official.py"
run Rscript "$scripts/helpers/05_benchmark_votes.R"
run Rscript "$scripts/helpers/05_benchmark_house_districts.R"
run Rscript "$scripts/08_build_district_predictors.R"
run python3 "$scripts/08_prepare_house_slates.py"

run Rscript "$scripts/09_model_house_votes.R" prepare
run Rscript "$scripts/09_validate_house_beta.R" validate
holdout="$outputs/09_beta_holdout"
read -r latest_run < "$holdout/latest_complete.txt"
check_sampler "$holdout/$latest_run/09_beta_sampler_diagnostics.csv"
run Rscript "$scripts/09_score_adjusted_house_holdout.R"
run Rscript "$scripts/09_predict_house_cd120.R"
check_sampler "$outputs/09_house_cd120_sampler_diagnostics.csv"
run Rscript "$scripts/10_prepare_handoff.R"
