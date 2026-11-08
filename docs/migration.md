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
| `frame/scripts/Script11_Cell_Aggregation_PUMS.R` | `legacy/frame/scripts/Script11_Cell_Aggregation_PUMS.R` | Active successor for this task | [Step 06](../01_frame/docs/06_build_pums_cells.md) builds the seven-key district population cells |
| `frame/scripts/Script12_Renumber_fallback_CES.R` | `legacy/frame/scripts/Script12_Renumber_fallback_CES.R` | Awaiting review | Replacement or retirement not yet decided |
| `frame/scripts/Script13_CES_vote2024_waterfall.R` | `legacy/frame/scripts/Script13_CES_vote2024_waterfall.R` | Active successor for this task | [Step 05 vote rules](../01_frame/docs/05_vote_rules.md) derive 2024 House vote and record which survey wave supplied it |
| `frame/scripts/Script14_stateabv_statecd.R` | `legacy/frame/scripts/Script14_stateabv_statecd.R` | Awaiting review | Replacement or retirement not yet decided |
| `frame/scripts/Script15_CD_level_demographic_proportions_pums.R` | `legacy/frame/scripts/Script15_CD_level_demographic_proportions_pums.R` | Awaiting review | Replacement or retirement not yet decided |
| `frame/scripts/Script16_2024_House_Shares.R` | `legacy/frame/scripts/Script16_2024_House_Shares.R` | Observed returns replaced | [Step 07](../01_frame/docs/07_prepare_area_returns.md) prepares original-district House returns. Rebalancing for 2026 remains open |
| `frame/scripts/Script17_State_Pres_Shares.R` | `legacy/frame/scripts/Script17_State_Pres_Shares.R` | Active successor | [Step 07](../01_frame/docs/07_prepare_area_returns.md) keeps four categories and the CVAP denominator, includes DC, and counts all general-election voters outside the two major nominees as Other |
| `frame/scripts/Script18ABC_CD_Level_Training_Table.R` | `legacy/frame/scripts/Script18ABC_CD_Level_Training_Table.R` | Awaiting review | Replacement or retirement not yet decided |
| `frame/scripts/Script19ABC_CART_Imputation.R` | `legacy/frame/scripts/Script19ABC_CART_Imputation.R` | Awaiting review | Replacement or retirement not yet decided |
| `frame/scripts/Script20_Strat_Frame_ForMrsP_Final.R` | `legacy/frame/scripts/Script20_Strat_Frame_ForMrsP_Final.R` | Awaiting review | Replacement or retirement not yet decided |
| `frame/scripts/Script21_Area_Level_Vote_Shares_Final.R` | `legacy/frame/scripts/Script21_Area_Level_Vote_Shares_Final.R` | Awaiting review | Replacement or retirement not yet decided |
| `frame/scripts/Script22_CES_Final.R` | `legacy/frame/scripts/Script22_CES_Final.R` | Awaiting review | Replacement or retirement not yet decided |
| `frame/scripts/Script4_Build_PUMA_CD_Crosswalk.R` | `legacy/frame/scripts/Script4_Build_PUMA_CD_Crosswalk.R` | Superseded | 02_build_puma_cd_crosswalk.R; reviewed checks passed |
| `frame/scripts/Script5_ApplyPUMACDCrossWalktoPUMS.R` | `legacy/frame/scripts/Script5_ApplyPUMACDCrossWalktoPUMS.R` | Superseded | [Script 03](../01_frame/docs/03_apply_puma_cd_crosswalk.md), national allocation validated 2026-11-07 |
| `frame/scripts/Script6_Exploratory.R` | `legacy/frame/scripts/Script6_Exploratory.R` | Awaiting review | Replacement or retirement not yet decided |
| `frame/scripts/Script7_Harmonize_DemVar.R` | `legacy/frame/scripts/Script7_Harmonize_DemVar.R` | Active successor for this task | [Step 04](../01_frame/docs/04_harmonize_pums.md) and [Step 05](../01_frame/docs/05_prepare_ces.md) harmonize the five shared demographic fields |
| `frame/scripts/Script8_10_ZCTA_Crosswalk.R` | `legacy/frame/scripts/Script8_10_ZCTA_Crosswalk.R` | Awaiting review | Replacement or retirement not yet decided |
| `frame/run_all.R` | `legacy/frame/run_all.R` | Withdrawn from active execution | New runner not yet implemented |
| `frame/runner.R` | `legacy/frame/runner.R` | Withdrawn from active execution | New runner not yet implemented |
| `frame/install_packages.R` | `legacy/frame/install_packages.R` | Historical setup | Current environment uses root renv files; retain for reference |
| `frame/scripts/ReadMe_Script11_Cell_Aggregation_PUMS.md` | `legacy/frame/docs/ReadMe_Script11_Cell_Aggregation_PUMS.md` | Active successor for this task | [Step 06](../01_frame/docs/06_build_pums_cells.md) builds the seven-key district population cells |
| `frame/scripts/ReadMe_Script12.md` | `legacy/frame/docs/ReadMe_Script12.md` | Awaiting review | Replacement or retirement not yet decided |
| `frame/scripts/ReadMe_Script13_CES_vote2024_waterfall.md` | `legacy/frame/docs/ReadMe_Script13_CES_vote2024_waterfall.md` | Active successor for this task | [Step 05 vote rules](../01_frame/docs/05_vote_rules.md) derive 2024 House vote and record which survey wave supplied it |
| `frame/scripts/ReadMe_Script14.md` | `legacy/frame/docs/ReadMe_Script14.md` | Awaiting review | Replacement or retirement not yet decided |
| `frame/scripts/ReadMe_Script15_cd_lvl_demo.md` | `legacy/frame/docs/ReadMe_Script15_cd_lvl_demo.md` | Awaiting review | Replacement or retirement not yet decided |
| `frame/scripts/ReadMe_Script16AB.md` | `legacy/frame/docs/ReadMe_Script16AB.md` | Observed returns replaced | [Step 07](../01_frame/docs/07_prepare_area_returns.md) prepares original-district House returns. Rebalancing for 2026 remains open |
| `frame/scripts/ReadMe_Script17_State_Pres_Shares.md` | `legacy/frame/docs/ReadMe_Script17_State_Pres_Shares.md` | Active successor | [Step 07](../01_frame/docs/07_prepare_area_returns.md) keeps four categories and the CVAP denominator, includes DC, and counts all general-election voters outside the two major nominees as Other |
| `frame/scripts/ReadMe_Script18ABC_CD_Level_Training_Table_For_CART.md` | `legacy/frame/docs/ReadMe_Script18ABC_CD_Level_Training_Table_For_CART.md` | Awaiting review | Replacement or retirement not yet decided |
| `frame/scripts/ReadMe_Script19ABC_CART_Impute.md` | `legacy/frame/docs/ReadMe_Script19ABC_CART_Impute.md` | Awaiting review | Replacement or retirement not yet decided |
| `frame/scripts/ReadMe_Script4_PUMA_CD_Crosswalk_Build.md` | `legacy/frame/docs/ReadMe_Script4_PUMA_CD_Crosswalk_Build.md` | Superseded | 02_build_puma_cd_crosswalk.R; reviewed checks passed |
| `frame/scripts/ReadMe_Script5.md` | `legacy/frame/docs/ReadMe_Script5.md` | Superseded | [Script 03 guide and run results](../01_frame/docs/03_apply_puma_cd_crosswalk.md) |
| `frame/scripts/ReadMe_Script6.md` | `legacy/frame/docs/ReadMe_Script6.md` | Awaiting review | Replacement or retirement not yet decided |
| `frame/scripts/ReadMe_Script7_Harmonization_DemVar.md` | `legacy/frame/docs/ReadMe_Script7_Harmonization_DemVar.md` | Active successor for this task | [Step 04](../01_frame/docs/04_harmonize_pums.md) and [Step 05](../01_frame/docs/05_prepare_ces.md) harmonize the five shared demographic fields |
| `frame/scripts/ReadMe_Script8_10.md` | `legacy/frame/docs/ReadMe_Script8_10.md` | Awaiting review | Replacement or retirement not yet decided |

## Remaining repository cleanup

- Keep active data catalogues current as script interfaces develop.
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
| `frame/data_sources.md` | `legacy/frame/data_sources.md` | Historical source list; replaced by 01_frame/docs/data_catalogue.md |
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

The [frame data catalogue](../01_frame/docs/data_catalogue.md) now records
the active script reads and writes, input acquisition, generated audits,
schemas and downstream dependencies. Current scripts and their companion
documents do not depend on retired code or historical review CSVs.

Environment housekeeping completed on 2026-11-06.

The November 6 implicit renv snapshot recorded 49 packages for the active project
and its dependencies. It removed 77 unused lockfile entries. All retained
package records and other lockfile metadata are unchanged.

At that checkpoint, dependency discovery covered the three then-active scripts
and excluded legacy files. `renv::status()` reported a consistent project. Existing package
installations were left in place.

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

## Historical Connecticut review outputs

Cleanup based on code checkpoint `65b0c42` and the 2026-11-06 local inventory.
The four CSVs below moved from `01_frame/data/output/` to
`legacy/frame/data/output/`, preserving their filenames and bytes.
They remain ignored/local-only and are not included in Git pushes.

| Filename | Bytes at review | Historical role | Current evidence or distinction |
|---|---:|---|---|
| `02_ct_population_audit.csv` | 159 | Connecticut-only population pilot, grouped by district | Current national population audit includes Connecticut; it is a state summary, not an identical replacement for this district table |
| `02_ct_population_source_check.csv` | 88 | Pilot comparison of geography POP100 with segment 1/P1 | No current standalone replacement; the active reader uses geography POP100 and segment 2/P3 and does not repeat the P1 comparison |
| `02_ct_unassigned_blocks.csv` | 2212 | Connecticut-only list of unassigned blocks | Current `02_unassigned_block_population.csv`, restricted to state 09, supplies this type of evidence and also includes adult counts; exact table equivalence was not tested |
| `02_ct_cvap_zero_population_locations.csv` | 147 | One-off location review for the two positive-CVAP/zero-2020-population cases | Current identifier, intersection, readiness and contribution audits support the decision; Script 02 Sections 9-10 reproduce location and contribution checks |

The first three were produced by the earlier Connecticut development pilot;
the fourth was produced by a separate review command. None is read or written
by an active numbered script. Their contents were not rerun or revalidated
during this cleanup. The cleanup verifies unchanged bytes during relocation.

The active allocation decision note now cites current reproducible outputs.
The former historical location reference is retained only in this migration
history; deleting the historical CSV will not remove required decision evidence.

### Preserved historical pilot result

The earlier main document recorded the following Connecticut development
check on 2026-10-30, using the pinned source archive:

- All 49,926 blocks matched the district assignments.
- Block populations summed to the state total of 3,605,944.
- All 81 unassigned blocks had zero recorded population.
- POP100 and P1 totals agreed for every block.

The pilot code was replaced by the national manifest loop. The final bullet
is a historical check, not a comparison rerun by the current Script 02.
This history is not needed to execute or interpret the current pipeline.

### Standalone active workflow

Current runtime inputs are identified in the active catalogue and source
manifest. Required assumptions and exception evidence are in the current
docs and generating code. The catalogue and active companion documents no
longer refer readers to historical review CSVs or legacy instructions.

These four historical CSVs are eligible for deletion with the quarantine once
the broader legacy review is complete. Other legacy scripts still have the
replacement/retirement decisions listed above; this cleanup does not resolve
those scientific development tasks.

## Presidential vote grouping in Step 07

Script 17 summed every MEDSL row outside the two major parties as Other.
Reapplying that formula to Harvard Dataverse v10.1 for the 50 states and DC
includes 199,150 undervotes, overvotes, void or spoiled ballots reported in nine
jurisdictions. The historic script itself excluded DC and did not pin its source
version. [MEDSL dataset](https://doi.org/10.7910/DVN/42MVDX)

The active state measure uses an independent ballot-turnout total. Other equals
counted general-election turnout less Harris and Trump votes. It includes
other valid presidential choices and counted participants with no valid
presidential choice. Did not vote equals the frame CVAP less counted turnout.
The source audit preserves the candidate breakdown, turnout source and estimate
status. Published candidate returns remain available for all states and DC.
Mississippi and Texas use turnout estimates, and Missouri has missing turnout-dependent
fields pending a verified turnout total. The [Step 07 guide](../01_frame/docs/07_prepare_area_returns.md)
records the four state shares and the treatment of blank, invalid, rejected
and replacement ballots.
