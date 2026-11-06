# runner.R
# Convenience script for running the pipeline interactively.
# Highlight each line and run one at a time, or source() them in order.
#
# Before running:
#   1. Install packages via install_packages.R
#   2. Download raw data from Zenodo into Data_Raw/

library(here)

# ── PUMS pipeline ───────────────────────────────────────────────────────────
source(here("Scripts", "Script1_3_LoadCleanPUMS.R"))
source(here("Scripts", "Script4_Build_PUMA_CD_Crosswalk.R"))
source(here("Scripts", "Script5_ApplyPUMACDCrosswalktoPUMS.R"))

# ── CES pipeline ────────────────────────────────────────────────────────────
source(here("Scripts", "Script6_Exploratory.R"))
source(here("Scripts", "Script7_Harmonize_DemVar.R"))
source(here("Scripts", "Script8_10_ZCTA_Crosswalk.R"))

# ── Cell aggregation and CD-level processing ───────────────────────────────
source(here("Scripts", "Script11_Cell_Aggregation_PUMS.R"))
source(here("Scripts", "Script12_Renumber_fallback_CES.R"))
source(here("Scripts", "Script13_CES_vote2024_waterfall.R"))
source(here("Scripts", "Script14_stateabv_statecd.R"))
source(here("Scripts", "Script15_CD_level_demographic_proportions_pums.R"))

# ── Vote share aggregation ─────────────────────────────────────────────────
source(here("Scripts", "Script16_2024_House_Shares.R"))
source(here("Scripts", "Script17_State_Pres_Shares.R"))

# ── Training table + CART ──────────────────────────────────────────────────
source(here("Scripts", "Script18ABC_CD_Level_Training_Table.R"))
source(here("Scripts", "Script19ABC_CART_Imputation.R"))

# ── Final deliverables ─────────────────────────────────────────────────────
source(here("Scripts", "Script20_Strat_Frame_ForMrsP_Final.R"))
source(here("Scripts", "Script21_Area_Level_Vote_Shares_Final.R"))
source(here("Scripts", "Script22_CES_Final.R"))
