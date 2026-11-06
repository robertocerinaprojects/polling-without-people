# Migration record

Starting checkpoint: `0045a396aa1ce5455a98105a899f5bfdb5b2624f`.

Quarantine preserves files for review; it does not imply that every old
analysis step has already been replaced.

## Current script status

See the [frame overview](../01_frame/README.md#script-status).

The original PUMS preparation script and its companion document were removed
earlier when Script 01 replaced them. They remain available in Git history.

## Quarantined files

Old companion documents follow the status of their associated script.

| Previous path | Quarantined path | Status | Successor or remaining work |
|---|---|---|---|
| `frame/scripts/Script11_Cell_Aggregation_PUMS.R` | `legacy/frame/scripts/Script11_Cell_Aggregation_PUMS.R` | Awaiting review | Replacement or retirement not yet decided |
| `frame/scripts/Script12_Renumber_fallback_CES.R` | `legacy/frame/scripts/Script12_Renumber_fallback_CES.R` | Awaiting review | Replacement or retirement not yet decided |
| `frame/scripts/Script13_CES_vote2024_waterfall.R` | `legacy/frame/scripts/Script13_CES_vote2024_waterfall.R` | Awaiting review | Replacement or retirement not yet decided |
| `frame/scripts/Script14_stateabv_statecd.R` | `legacy/frame/scripts/Script14_stateabv_statecd.R` | Awaiting review | Replacement or retirement not yet decided |
| `frame/scripts/Script15_CD_level_demographic_proportions_pums.R` | `legacy/frame/scripts/Script15_CD_level_demographic_proportions_pums.R` | Awaiting review | Replacement or retirement not yet decided |
| `frame/scripts/Script16_2024_House_Shares.R` | `legacy/frame/scripts/Script16_2024_House_Shares.R` | Awaiting review | Replacement or retirement not yet decided |
| `frame/scripts/Script17_State_Pres_Shares.R` | `legacy/frame/scripts/Script17_State_Pres_Shares.R` | Awaiting review | Replacement or retirement not yet decided |
| `frame/scripts/Script18ABC_CD_Level_Training_Table.R` | `legacy/frame/scripts/Script18ABC_CD_Level_Training_Table.R` | Awaiting review | Replacement or retirement not yet decided |
| `frame/scripts/Script19ABC_CART_Imputation.R` | `legacy/frame/scripts/Script19ABC_CART_Imputation.R` | Awaiting review | Replacement or retirement not yet decided |
| `frame/scripts/Script20_Strat_Frame_ForMrsP_Final.R` | `legacy/frame/scripts/Script20_Strat_Frame_ForMrsP_Final.R` | Awaiting review | Replacement or retirement not yet decided |
| `frame/scripts/Script21_Area_Level_Vote_Shares_Final.R` | `legacy/frame/scripts/Script21_Area_Level_Vote_Shares_Final.R` | Awaiting review | Replacement or retirement not yet decided |
| `frame/scripts/Script22_CES_Final.R` | `legacy/frame/scripts/Script22_CES_Final.R` | Awaiting review | Replacement or retirement not yet decided |
| `frame/scripts/Script4_Build_PUMA_CD_Crosswalk.R` | `legacy/frame/scripts/Script4_Build_PUMA_CD_Crosswalk.R` | Superseded | 02_build_puma_cd_crosswalk.R; reviewed checks passed |
| `frame/scripts/Script5_ApplyPUMACDCrossWalktoPUMS.R` | `legacy/frame/scripts/Script5_ApplyPUMACDCrossWalktoPUMS.R` | Replacement incomplete | 03_apply_puma_cd_crosswalk.R; coverage-audit draft only |
| `frame/scripts/Script6_Exploratory.R` | `legacy/frame/scripts/Script6_Exploratory.R` | Awaiting review | Replacement or retirement not yet decided |
| `frame/scripts/Script7_Harmonize_DemVar.R` | `legacy/frame/scripts/Script7_Harmonize_DemVar.R` | Awaiting review | Replacement or retirement not yet decided |
| `frame/scripts/Script8_10_ZCTA_Crosswalk.R` | `legacy/frame/scripts/Script8_10_ZCTA_Crosswalk.R` | Awaiting review | Replacement or retirement not yet decided |
| `frame/run_all.R` | `legacy/frame/run_all.R` | Withdrawn from active execution | New runner not yet implemented |
| `frame/runner.R` | `legacy/frame/runner.R` | Withdrawn from active execution | New runner not yet implemented |
| `frame/install_packages.R` | `legacy/frame/install_packages.R` | Historical setup | Current environment uses root renv files; retain for reference |
| `frame/scripts/ReadMe_Script11_Cell_Aggregation_PUMS.md` | `legacy/frame/docs/ReadMe_Script11_Cell_Aggregation_PUMS.md` | Awaiting review | Replacement or retirement not yet decided |
| `frame/scripts/ReadMe_Script12.md` | `legacy/frame/docs/ReadMe_Script12.md` | Awaiting review | Replacement or retirement not yet decided |
| `frame/scripts/ReadMe_Script13_CES_vote2024_waterfall.md` | `legacy/frame/docs/ReadMe_Script13_CES_vote2024_waterfall.md` | Awaiting review | Replacement or retirement not yet decided |
| `frame/scripts/ReadMe_Script14.md` | `legacy/frame/docs/ReadMe_Script14.md` | Awaiting review | Replacement or retirement not yet decided |
| `frame/scripts/ReadMe_Script15_cd_lvl_demo.md` | `legacy/frame/docs/ReadMe_Script15_cd_lvl_demo.md` | Awaiting review | Replacement or retirement not yet decided |
| `frame/scripts/ReadMe_Script16AB.md` | `legacy/frame/docs/ReadMe_Script16AB.md` | Awaiting review | Replacement or retirement not yet decided |
| `frame/scripts/ReadMe_Script17_State_Pres_Shares.md` | `legacy/frame/docs/ReadMe_Script17_State_Pres_Shares.md` | Awaiting review | Replacement or retirement not yet decided |
| `frame/scripts/ReadMe_Script18ABC_CD_Level_Training_Table_For_CART.md` | `legacy/frame/docs/ReadMe_Script18ABC_CD_Level_Training_Table_For_CART.md` | Awaiting review | Replacement or retirement not yet decided |
| `frame/scripts/ReadMe_Script19ABC_CART_Impute.md` | `legacy/frame/docs/ReadMe_Script19ABC_CART_Impute.md` | Awaiting review | Replacement or retirement not yet decided |
| `frame/scripts/ReadMe_Script4_PUMA_CD_Crosswalk_Build.md` | `legacy/frame/docs/ReadMe_Script4_PUMA_CD_Crosswalk_Build.md` | Superseded | 02_build_puma_cd_crosswalk.R; reviewed checks passed |
| `frame/scripts/ReadMe_Script5.md` | `legacy/frame/docs/ReadMe_Script5.md` | Replacement incomplete | 03_apply_puma_cd_crosswalk.R; coverage-audit draft only |
| `frame/scripts/ReadMe_Script6.md` | `legacy/frame/docs/ReadMe_Script6.md` | Awaiting review | Replacement or retirement not yet decided |
| `frame/scripts/ReadMe_Script7_Harmonization_DemVar.md` | `legacy/frame/docs/ReadMe_Script7_Harmonization_DemVar.md` | Awaiting review | Replacement or retirement not yet decided |
| `frame/scripts/ReadMe_Script8_10.md` | `legacy/frame/docs/ReadMe_Script8_10.md` | Awaiting review | Replacement or retirement not yet decided |

## Remaining repository cleanup

- Document input sources, producing scripts, outputs and downstream consumers.
- Resolve all outstanding legacy decisions before deleting `legacy/`.
- Verify that active execution and dependency discovery exclude legacy files.

## Remaining historical layout quarantined

| Previous path | Quarantined path | Status |
|---|---|---|
| `frame/Data_Raw` | `legacy/frame/Data_Raw` | Retired layout; current inputs use 01_frame/data/input/ |
| `frame/Data_Processed` | `legacy/frame/Data_Processed` | Retired layout; current intermediates use 01_frame/data/intermediate/ |
| `frame/Data_Final` | `legacy/frame/Data_Final` | Retired layout; current results use 01_frame/data/output/ |
| `frame/Development_Script_Original` | `legacy/frame/Development_Script_Original` | Historical development reference; ignored/local-only |
| `frame/Final_Data_Original` | `legacy/frame/Final_Data_Original` | Historical output documentation; ignored/local-only; no datasets present |
| `frame/README.md` | `legacy/frame/README.md` | Historical overview; replaced by the new 01_frame/README.md |
| `frame/data_sources.md` | `legacy/frame/data_sources.md` | Historical source list; current data catalogue to be written |
| `frame/.gitignore` | `legacy/frame/.gitignore` | Historical ignore rules; general R/editor rules transferred to repository root |

### Local-only historical files

These files were ignored before relocation and remain ignored.
They are present in this Codespace but are not included in Git pushes.

- `legacy/frame/Data_Processed/README.md`
- `legacy/frame/Development_Script_Original/README.md`
- `legacy/frame/Development_Script_Original/Stratification_Building.R`
- `legacy/frame/Final_Data_Original/README.md`
- `legacy/frame/Final_Data_Original/README_area_level_vote_shares.md`
- `legacy/frame/Final_Data_Original/README_ces_2024_for_mrsp.md`
- `legacy/frame/Final_Data_Original/README_stratification_frame_preMrsP.md`

### Documentation progress

The component overviews and shared repository conventions are established.
Current execution order and status live in each component's README.

Next: populate the frame data catalogue from the actual script reads and writes,
including input acquisition, generated audits and downstream dependencies.

Environment housekeeping remains pending: `rpart.plot` is recorded and installed
but is no longer referenced by the active scripts after quarantine.

## Active component numbering

Starting checkpoint: `0faf7e7`.

| Previous directory | Current directory |
|---|---|
| `frame/` | `01_frame/` |
| `personae/` | `02_personae/` |
| `mrp/` | `03_mrp/` |

Active scripts, documentation and the population-source manifest use the
new paths. Existing data moved with their component directories.

The redundant script-folder README was removed. Each component's root
README provides navigation and status; companion explanations remain in docs/.

Historical source paths and archived paths under legacy/ retain their names.
