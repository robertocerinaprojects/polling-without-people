# run_all.R
# Runs the entire Stratification Frame pipeline in sequence.
# Before running: (1) install packages via install_packages.R
#                 (2) download raw data from Zenodo into Data_Raw/
#
# Usage:
#   Rscript run_all.R           # runs all scripts
#   Rscript run_all.R 5 12      # runs only scripts 5 through 12

library(here)
mem.maxVSize(vsize = 48000)

cat("═══════════════════════════════════════════════════\n")
cat("Stratification Frame Pipeline — Full Run\n")
cat("═══════════════════════════════════════════════════\n\n")

scripts <- c(
  "Scripts/Script1_3_LoadCleanPUMS.R",
  "Scripts/Script4_Build_PUMA_CD_Crosswalk.R",
  "Scripts/Script5_ApplyPUMACDCrossWalktoPUMS.R",
  "Scripts/Script6_Exploratory.R",
  "Scripts/Script7_Harmonize_DemVar.R",
  "Scripts/Script8_10_ZCTA_Crosswalk.R",
  "Scripts/Script11_Cell_Aggregation_PUMS.R",
  "Scripts/Script12_Renumber_fallback_CES.R",
  "Scripts/Script13_CES_vote2024_waterfall.R",
  "Scripts/Script14_stateabv_statecd.R",
  "Scripts/Script15_CD_level_demographic_proportions_pums.R",
  "Scripts/Script16_2024_House_Shares.R",
  "Scripts/Script17_State_Pres_Shares.R",
  "Scripts/Script18ABC_CD_Level_Training_Table.R",
  "Scripts/Script19ABC_CART_Imputation.R",
  "Scripts/Script20_Strat_Frame_ForMrsP_Final.R",
  "Scripts/Script21_Area_Level_Vote_Shares_Final.R",
  "Scripts/Script22_CES_Final.R"
)

# Optional: run only specific scripts
# Usage: Rscript run_all.R 5 12  (runs scripts 5 through 12)
args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 2) {
  start_idx <- as.integer(args[1])
  end_idx   <- as.integer(args[2])
  scripts   <- scripts[start_idx:end_idx]
  cat(sprintf("Running scripts %d through %d only.\n\n", start_idx, end_idx))
}

total_start <- Sys.time()

for (i in seq_along(scripts)) {
  script_path <- here(scripts[i])
  script_name <- basename(scripts[i])
  
  cat(sprintf("\n[%d/%d] Running %s...\n", i, length(scripts), script_name))
  cat(strrep("─", 60), "\n", sep = "")
  
  script_start <- Sys.time()
  
  tryCatch(
    source(script_path),
    error = function(e) {
      cat(sprintf("\n✗ ERROR in %s:\n", script_name))
      cat(sprintf("  %s\n", conditionMessage(e)))
      stop(sprintf("Pipeline failed at %s", script_name))
    }
  )
  
  script_end <- Sys.time()
  elapsed <- round(as.numeric(script_end - script_start, units = "secs"), 1)
  cat(sprintf("\n✓ %s completed in %.1fs\n", script_name, elapsed))
}

total_end <- Sys.time()
total_elapsed <- round(as.numeric(total_end - total_start, units = "mins"), 1)

cat("\n═══════════════════════════════════════════════════\n")
cat(sprintf("Pipeline completed successfully in %.1f minutes\n", total_elapsed))
cat("═══════════════════════════════════════════════════\n")
