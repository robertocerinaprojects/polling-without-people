# Data handoff

Copy these three generated files from the local checkout at `/workspaces/polling-without-people` into the receiving repo.

- `01_frame/data/intermediate/09_house_training_cd119.csv` contains rebased 2024 House vote-share targets on the **2024 district map (CD119)**. The target columns are `observed_dem`, `observed_rep`, `observed_other`, and `observed_none`. Read `STATEFP` and `CDFP` as strings to preserve leading zeros if you import the CSV.
- `01_frame/data/intermediate/pums_cd_cells.rds` contains the ACS mother frame on the **2026 district map (CD120)**.
- `01_frame/data/intermediate/09_house_target_cd120.csv` contains the district-level predictors for estimating **2024 House vote shares on the 2026 district map (CD120)**. It has 436 rows with demographics, 2024 statewide presidential shares, ballot lineup and incumbency fields, and prediction flags. The 144 districts flagged `model_redrawn` use 2026 nominees with incumbency evaluated immediately before the 2024 general election. Redrawn FL-20 uses its reviewed 2024 sole nominee, Sheila Cherfilus-McCormick. Read `STATEFP` and `CDFP` as strings to preserve leading zeros.

Use this repo’s existing location for imported data. If it has no convention, use `data/input/`. Keep the filenames and file contents intact. Verify that each copy matches its source by comparing SHA-256 checksums, then report the destination paths.

These files are untracked in the source repo. If the local checkout or either file is inaccessible, report which file needs to be made available for transfer.
