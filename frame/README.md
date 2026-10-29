# Stratification Frame — US 2026 House Elections
 
This repository builds a demographic **stratification frame** and the associated
**area-level vote-share** and **CES respondent** files used as inputs to a
Multilevel Regression with Synthetic Poststratification (MrsP) model, which is used to build a final (demographics x votes) stratification frame for predicting voting preferences in the US 2026 House elections (2026 Midterm elections).
 
The pipeline takes public microdata (ACS PUMS, CES 2024), boundary reference
files (Census relationship files, Block Assignment Files, Geocorr), and election
returns (MEDSL), and produces three deliverables aligned to the 435 congressional
districts under their **2026** boundaries.
 
---
 
## What it produces
 
A full run writes three files (see `Final_Data_Original/` for the reference
copies produced during development):
 
| File | Rows | Contents |
|---|---|---|
| `stratification_frame_2026_preMrsP` | 497,836 | Demographic cells × 2026 CD, with weighted CVAP (`cell_pop`) |
| `area_level_vote_shares` | 435 | CD-level 2024 vote shares (observed, inherited, or CART-imputed), state presidential covariates, demographic marginals, and modeling flags |
| `ces_2024_for_mrsp` | 69,020 | CES respondents × candidate CD, with harmonized demographics, allocation factors, survey weights, and the constructed `vote_2024` outcome |
 
---
 
## Repository structure
 
```
Stratification_Frame_US2026/
├── stratification_frame_us2026.Rproj   # open this first (sets the project root)
├── README.md
├── install_packages.R                  # installs all dependencies
├── run_all.R                           # runs the full pipeline
├── runner.R                            # sources scripts one at a time (interactive/dev)
├── data_sources.md                     # provenance manifest for every raw input
├── Data_Raw/                           # raw inputs go here (from Zenodo; git-ignored)
├── Data_Processed/                     # intermediate objects (git-ignored)
├── Data_Final/                         # final deliverables (git-ignored)
├── Final_Data_Original/                # reference copies of the deliverables
├── Development_Script_Original/        # original single-file development script
└── Scripts/                            # the 18 numbered pipeline scripts + per-script docs
```
 
`Data_Raw/`, `Data_Processed/`, and `Data_Final/` are excluded from version
control (see `.gitignore`); the directory structure is preserved via `.gitkeep`.
 
---
 
## Prerequisites
 
### 1. Open the project
 
Open `stratification_frame_us2026.Rproj` in RStudio, **or** set your working
directory to the repository root before running anything. All paths are resolved
relative to the project root by the [`here`](https://here.r-lib.org/) package. If
you run from the wrong directory — or the `.Rproj` file is missing — `here()`
anchors to the wrong location and every script fails to find its inputs.
 
### 2. Download the raw data (~2.7 GB)
 
The raw inputs are archived on Zenodo and are **not** stored in this repository.
The simplest way to fetch them is the [`zenodo_get`](https://github.com/dvolgyes/zenodo_get)
command-line tool:
 
```bash
pip install zenodo_get
# from the repository root:
zenodo_get 21285306 -o Data_Raw/
```
 
The datasets sit directly inside `Data_Raw/`.
See `data_sources.md`, which can also be found in the repo root, for what each file is and where it came from.
 
### 3. Census API key
 
Several scripts query the U.S. Census Bureau API (via `tidycensus`) for 2020
Decennial block populations. Get a free key at
<https://api.census.gov/data/key_signup.html> and register it once:
 
```r
tidycensus::census_api_key("YOUR_KEY_HERE", install = TRUE)
```
 
`install = TRUE` writes the key to your `.Renviron` so it persists across
sessions. **Without a valid key, the block-population queries fail with a generic
request error, not an explicit "missing key" message** — so if a Census-querying
script errors, check this first.
 
### 4. Memory
 
The crosswalked person-level PUMS table is ~20.6 million rows, and peak memory
use during Scripts 8–11 is roughly **10–12 GB**. On macOS, R's default allocation
ceiling is 16 GB; the pipeline raises it with `mem.maxVSize()` at the top of
`run_all.R`. The code was run on a 16 GB Mac M1 RAM.
 
### 5. Install dependencies
 
```r
source("install_packages.R")
```
 
---
 
## Running the pipeline
 
Run the full suite from the project root:
 
```r
source("run_all.R")
```
 
This executes all 18 scripts in order, printing per-script progress and timing.
A complete run takes **~27 minutes** on a Mac M1, dominated by the Census
API queries and the block-level aggregation.
 
To run a contiguous subset — e.g. when re-running only a downstream stage — pass
start and end indices:
 
```bash
Rscript run_all.R 5 12    # runs scripts 5 through 12 only
```
You can also run as follows on the R console window, which will log all outputs to a run_all_log.txt file

```
con <- file(here::here("Data_Processed", "run_all_log.txt"), open = "wt")
sink(con, split = TRUE); sink(con, type = "message")
source(here::here("run_all.R"))
sink(type = "message"); sink(); close(con)
```
 
Alternatively, `runner.R` sources the scripts one at a time for interactive,
script-by-script evaluation — useful when developing or debugging, since it lets
you inspect the objects each script leaves in the environment before moving on.
Use `run_all.R` for a full automated run; use `runner.R` to step through the
pipeline during development.
 
### Reproducibility
 
`set.seed(2026)` fixes the CART hold-out split in Script 19, so repeated runs
produce identical hold-out districts and identical reported results. Population
and share totals are conserved and checked at each stage; a run that completes
without any of these checks failing has reproduced the frame.
 
---
 
## Pipeline overview
 
| Script | Purpose |
|---|---|
| `Script1_3_LoadCleanPUMS.R` | Load and clean the ACS PUMS extract; filter to CVAP; recode demographics |
| `Script4_Build_PUMA_CD_Crosswalk.R` | Build the unified PUMA → 2026 CD crosswalk (Geocorr + 7 state BAFs) |
| `Script5_...ApplyPUMACDCrossWalktoPUMS.R` | Apply the crosswalk to PUMS; compute `PERWT_adj` |
| `Script6_Exploratory.R` | Exploratory diagnostics |
| `Script7_Harmonize_DemVar.R` | Harmonize demographic variables across PUMS and CES |
| `Script8_10_ZCTA_Crosswalk.R` | Build ZCTA → 2026 CD crosswalk; assign CES respondents; reconcile geography |
| `Script11_Cell_Aggregation_PUMS.R` | Aggregate PUMS to demographic cells |
| `Script12_Renumber_fallback_CES.R` | Renumbering correction for the ZCTA-fallback CES respondents |
| `Script13_CES_vote2024_waterfall.R` | Construct the `vote_2024` outcome |
| `Script14_stateabv_statecd.R` | Attach state abbreviations and `state_cd` identifiers |
| `Script15_CD_level_demographic_proportions_pums.R` | CD-level demographic marginals |
| `Script16_2024_House_Shares.R` | 2024 House vote shares |
| `Script17_State_Pres_Shares.R` | State-level presidential shares |
| `Script18ABC_CD_Level_Training_Table.R` | Assemble the CD-level training table; inheritance and contestation flags |
| `Script19ABC_CART_Imputation.R` | Fit CART trees; hold-out validation; impute redistricted CDs |
| `Script20_Strat_Frame_ForMrsP_Final.R` | Package the final stratification frame |
| `Script21_Area_Level_Vote_Shares_Final.R` | Package the final area-level vote-share file |
| `Script22_CES_Final.R` | Package the final CES respondent file |
 
Each script has a companion `ReadMe_ScriptNN...md` in `Scripts/` documenting its
inputs, outputs, and key decisions.
 
---
 
## Troubleshooting
 
- **`cannot open the connection` / `here()` points to your home directory** —
  you are not running from the project root. Open the `.Rproj` file, or `setwd()`
  to the repository root, and restart R.
- **A Census-querying script fails with a request error** — your Census API key
  is missing or invalid. See Prerequisite 3.
- **`vector memory limit reached` (macOS)** — R's allocation ceiling. Confirm the
  `mem.maxVSize()` call at the top of `run_all.R` executed; ideally use a machine with ≥16 GB RAM.
- **A downstream script can't find an input** — run the pipeline in order from
  the start, or use `Rscript run_all.R <start> <end>` to re-run the needed range;
  intermediates live in `Data_Processed/`.
 
