# Frame

For the district-level House model, build [the two-map PUMS predictors](docs/08_build_district_predictors.md)
and [candidate lineups](docs/08_house_slates.md), then follow the
[holdout validation and full-model predictions](docs/09_model_house_votes.md).
Step 09 fits a Dirichlet regression to the four House shares in 434 tabulated
2024 contests. Its final district-by-party file, `data/intermediate/09_house_party_covariates.csv`,
covers both maps. Read each district's four rows together for Democratic,
Republican, Other and citizens without a counted House candidate vote.
`house_share` gives the share of district citizen adults and `outcome_source`
says whether it comes from a return, a carried count or a model estimate.

This component produces the two inputs for modeling the 2024 survey and
poststratifying on the 2026 congressional map.

| File under `data/intermediate/` | What one row represents | Population or sample |
|---|---|---|
| `pums_cd_cells.rds` — mother stratification frame | One state, district and demographic profile with a positive estimated citizen-adult population `N` | 497,550 cells across 435 voting districts and DC. Summing `N` gives 240,960,972. |
| `ces_analysis.rds` — harmonized CES, 11 columns | One eligible 2024 citizen respondent with their ID, survey weight, seven matching fields and two 2024 vote outcomes | 58,627 unique respondents in the underlying harmonized sample, including DC. |

The frame represents the 2020–2024 ACS citizen-adult population on 2026
district boundaries. Use `STATEFP` and `CDFP120` for matching. To identify a
2024 House contest or audit an imputed value, link by `caseid` to the detailed
CES file, `ces_demographics_harmonized.rds`, and its documented audits. See the
[population and survey overlap](docs/06_build_pums_cells.md#production-results)
and [2024 vote benchmark](docs/05_vote_rules.md#comparison-with-2024-election-returns).

## Script status

Run individual steps from the repository root, following their companion documents.

| Order | Script | Status | Documentation |
|---|---|---|---|
| 00 | `scripts/00_download_pums.R` | validated | [IPUMS download](docs/00_download_pums.md) |
| 01 | `scripts/01_prepare_pums.R` | validated | [PUMS preparation](docs/01_prepare_pums.md) |
| 02 | `scripts/02_build_puma_cd_crosswalk.R` | validated | [PUMA-to-district crosswalk](docs/02_build_puma_cd_crosswalk.md) |
| 03 | `scripts/03_apply_puma_cd_crosswalk.R` | validated | [Crosswalk application](docs/03_apply_puma_cd_crosswalk.md) |
| 04 | `scripts/04_harmonize_pums.R` | validated | [PUMS demographics and race probabilities](docs/04_harmonize_pums.md) |
| 05 | `scripts/05_prepare_ces.R` | national demographics and vote run passed | [2024 CES preparation](docs/05_prepare_ces.md) |
| 06 | `scripts/06_build_pums_cells.R` | national cell totals and CES coverage checked | [Population cells and CES coverage](docs/06_build_pums_cells.md) |
| 07 | `scripts/07_prepare_area_returns.py` | 2024 candidate votes by state for president and by original district for House | [2024 area-level returns](docs/07_prepare_area_returns.md) |
| 08 | `scripts/08_build_district_predictors.R` | 436 districts per map, with a common state population check | [District populations and shares](docs/08_build_district_predictors.md) |
| 08 | `scripts/08_prepare_house_slates.py` | Nominee counts and party incumbency checked for all 436 districts in 2024 and 2026 | [House candidate rosters](docs/08_house_slates.md) |
| 09 | `scripts/09_model_house_votes.R` | Prepare district-by-party inputs, validate on 30 districts, refit and produce estimates | [House shares and output files](docs/09_model_house_votes.md) |

On a fresh checkout, restore the R packages at the repository root with
`Rscript -e 'renv::restore(prompt = FALSE)'`. Step 02 also needs the Census
snapshots listed in [external inputs and acquisition](docs/data_catalogue.md#external-inputs-and-acquisition).
Step 05 uses Python 3 for its Census geography helper.

Step 00 downloads the specified IPUMS USA extract, records its files and
fingerprints, and reuses verified local files on ordinary reruns. Acquisition,
24-column validation and offline reuse passed. Use `--refresh` to request
a separate snapshot.

Step 01 checks the selected download against its receipt and the tracked
[source manifest](docs/00_pums_source.json), then prepares citizens aged 18+.
The complete download-to-preparation run passed and saved 12,263,785 records
with a total person weight of 240,960,972. Step 02 passed its documented
crosswalk checks. Step 03 matched all 2,462 PUMAs and saved 20,333,303
person–district rows. The district contributions preserved the total person
weight of 240,960,972.

The input flow is Step 00 → Step 01 → `data/intermediate/pums_clean.rds`.
Step 02 independently produces `data/intermediate/puma_cd_crosswalk.rds`.
Step 03 reads both RDS files and distributes each person’s weight across
districts using their PUMA’s probabilities. Its output is
`data/intermediate/pums_cd_allocation.rds`.

Step 04 harmonizes PUMS demographics and provides national Hispanic donor
totals. Step 05 joins those categories to Step 03's fractional district
weights, retains self-reported CES citizens, converts 2024 residence geography
to 2026 districts and draws race conditionally for eligible primary-Hispanic
respondents. See the [citizenship and district decisions](docs/05_citizenship_district_decisions.md).
Step 05 retained 58,627 CES citizens and assigned a harmonized race to 4,869
primary-Hispanic respondents using the processed PUMS donors. The [before-and-after
race table and donor audit](docs/05_prepare_ces.md#production-run) record the results.

Step 06 sums Step 03's district weights within the demographic categories
from Step 04. The CES enters this step only to check which survey profiles
have population support. It supplies none of the population counts.

Step 07 groups votes credited to candidates into Democratic, Republican and
Other. For president, it divides the state totals by the state's PUMS
citizen-adult population. The remainder estimates how many citizens had no
counted vote for a presidential candidate. The House table retains votes on
the original 2024 districts, including DC's delegate. On the new map, Step 09
carries counts for 290 identical districts, predicts 144 redrawn districts
using their 2026 rosters, and treats FL-20 and OK-03 as single-candidate
races with their verified 2024 winners. The [area-level returns guide](docs/07_prepare_area_returns.md)
documents the ballot categories and denominators.

## Review of the November 8 checkpoint

The population and survey totals above come from the completed Codespace run.
The review used [checkpoint `eaad716`](https://github.com/robertocerinaprojects/polling-without-people/commit/eaad716f25b4bb9ec55d021fa41df3030fc32911).
It independently reproduced the six block-group allocation case counts from
the pinned public inputs and checked all 436 congressional geographies.
The pinned CES release reproduced the 2024 vote outcome counts. The
[election benchmark](docs/05_vote_rules.md#comparison-with-2024-election-returns)
compares weighted shares with official returns in the original ballot geography.

The review exercised the PUMS transformations with test records covering
all documented demographic codes and age boundaries, split districts,
missing inputs and donor fallback. The tests also covered overlapping IPUMS
download attempts and a failed audit write. The national PUMS cell counts
and production race assignments remain those of the recorded Codespace run.
Run the [saved-file check](docs/06_build_pums_cells.md#check-the-saved-analysis-files)
to verify the two analysis datasets in the current workspace.

## Data and documentation

- `data/input/`: external source files and local acquisition receipts.
- `data/intermediate/`: generated working datasets.
- `data/output/`: generated audits and exports.
- `docs/`: script explanations, decisions and tracked source manifests.

The [data catalogue](docs/data_catalogue.md) records source snapshots,
acquisition, file schemas, producing scripts and downstream consumers.
It covers intermediates, audits and script-generated documentation.

The [CES analysis schema](docs/05_prepare_ces.md#analysis-file) lists the 11
columns and the command to make the slim export from an existing detailed CES.
The [vote benchmark](docs/05_vote_rules.md#reproduce-the-vote-benchmark) uses
the detailed file for vote sources and original ballot geography.

See the [shared conventions](../docs/repository_structure.md).
