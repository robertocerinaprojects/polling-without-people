# Frame

## Principal deliverables

Run Step 10 to assemble the long-format election results, mother frame, and harmonized CES
in `data/output/10_handoff/`. [Data handoff](../get_us_2024_xframe_data.md)

| Handoff file | Contents |
|---|---|
| `data/output/10_handoff/district_election_inputs_cd120.csv` | 1,744 district-by-choice rows with the 2024 House and presidential shares and district covariates. |
| `data/output/10_handoff/pums_cd_cells.rds` | 497,550 positive population cells across 435 voting districts and DC, with full state names. Estimated citizen-adult counts `N` sum to 240,960,972. |
| `data/output/10_handoff/ces_2024_harmonized.rds` | 58,627 eligible CES respondents with the shared cell keys and two 2024 vote outcomes. |

**House choices.** Democratic, Republican, Other and no counted House
candidate vote, each as a share of estimated citizen adults. The target
table marks 290 districts with an identical 2024 footprint and tabulated
returns, 144 redrawn districts with modeled scenarios, and two unopposed
2024 scenarios for FL-20 and OK-03. For the 144, the model assumes that the
same nominees who ran in 2026 would have run if those boundaries had been
in place in 2024. Incumbency is measured on November 4, 2024, including
service in a different district. [House inputs and scenario rules](docs/09_model_house_votes.md#districts-on-the-2026-map)

**Mother frame.** Step 06 sums 2020–2024 ACS PUMS weights after allocating
them to 2026 districts. Each row is a joint age, gender, race, Hispanic
ethnicity and education profile within a district. In the handoff use `state_fips` and
`district_fips` as text keys. [Build and saved-file check](docs/06_build_pums_cells.md)

**Upstream survey input.** `data/intermediate/ces_analysis.rds` has 58,627 eligible
2024 CES respondents and 11 columns. Join by `caseid` to
`ces_demographics_harmonized.rds` to inspect the original 2024 contest or
an imputed value. Step 06 uses CES profiles to check coverage. The
population counts come from PUMS. [Survey schema](docs/05_prepare_ces.md#analysis-file) ·
[Population and survey overlap](docs/06_build_pums_cells.md#production-results)

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
| 08 | `scripts/08_prepare_house_slates.py` | Build both annual slates and the 2026 slate with 2024 incumbency | [House candidate rosters](docs/08_house_slates.md) |
| 09 | `scripts/09_model_house_votes.R prepare` | Prepare observed CD119 outcomes and CD120 scenario inputs | [Source tables and outcomes](docs/09_model_house_votes.md) |
| 09 | `scripts/09_validate_house_beta.R validate` | Fit the three beta stages and score the 2024 holdout | [Model equations, predictors and outputs](docs/09_validate_house_beta.md) |
| 09 | `scripts/09_predict_house_cd120.R` | Fit all tabulated 2024 contests and export the raw and adjusted CD120 shares | [Production export](docs/09_model_house_votes.md#build-and-inspect-the-final-cd120-shares) |
| 10 | `scripts/10_prepare_handoff.R` | Assemble the three handoff files from saved pipeline outputs | [Data handoff](../get_us_2024_xframe_data.md) |

Open the [four-panel House validation figure](data/output/09_beta_holdout/3bf72b3e358bdf062b84/09_beta_holdout_plots.pdf)
or the [scores for both methods](data/output/09_beta_holdout/3bf72b3e358bdf062b84/09_beta_holdout_scores.csv).
The same directory contains the held-out district predictions, the district split and
the sampler diagnostics. Each completed validation publishes its directory name in
`data/output/09_beta_holdout/latest_complete.txt`.

The [adjusted holdout command](docs/09_validate_house_beta.md#score-the-ballot-adjusted-holdout)
applies the production ballot rule to the held-out 2024 lineups using
the saved stage fits.

On a fresh checkout, restore the R packages at the repository root with
`Rscript -e 'renv::restore(prompt = FALSE)'`. Step 02 also needs the Census
snapshots listed in [external inputs and acquisition](docs/data_catalogue.md#external-inputs-and-acquisition).
Step 05 uses Python 3 for its Census geography helper.

**Build paths.** Steps 00–01 acquire and prepare the PUMS sample. Step 02
independently builds the district crosswalk. Step 03 applies it, Step 04
harmonizes demographics, and Step 05 prepares CES. Step 06 builds the
mother frame. For House modeling, Step 07 prepares the original returns,
the two Step 08 scripts prepare maps and lineups, and Step 09 builds and
validates the model inputs. Step 10 assembles the handoff. See the [data catalogue](docs/data_catalogue.md)
for prerequisites and generated files.

## Rebuild evidence

The [November 10 rebuild receipt](../docs/validation/e393b7f2-frame-rebuild/README.md)
records hashes for a historical preparation run. The saved inputs are
needed for an exact rebuild. See [reproducibility limits](docs/data_catalogue.md#validation-reruns-and-preservation).

### November 8 checkpoint

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
