# Frame

## Principal deliverables

Run Step 10 to assemble the long-format election results, mother frame, and harmonized CES
in `data/output/10_handoff/`. [Data handoff](../get_us_2024_xframe_data.md)

| Handoff file | Contents |
|---|---|
| `data/output/10_handoff/district_election_inputs_cd120.csv` | 1,744 district-by-choice rows with the 2024 House and presidential shares, lineup, incumbency, and ballot presence. |
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

## Rebuild the frame

From the repository root, run the following once the R environment and the
source files under `01_frame/data/input/` are in place.

```bash
bash 01_frame/scripts/rebuild_frame.sh
```

The command starts at Step 00, runs the survey and population checks, fits and
checks the House models, and builds the three handoff files in Step 10. It
stops at the first failed command or a failed sampler check for either of
the first two House regressions. A flagged Democratic-versus-Other fit
produces a warning and its results are marked provisional. The rebuild uses
the source files on disk and stops up front with a list of any missing files.
It regenerates the intermediate datasets and audits and reuses matching saved
model fits when available.

For setup, restore the R packages with
`Rscript -e 'renv::restore(prompt = FALSE)'`. Use Bash, `gzip`, Python 3 with
`openpyxl`, Poppler's `pdftotext`, and the compiler needed by Stan. The
repository's development container supplies the system tools.
To populate a new checkout, use the individual scripts to download sources
once. Set `IPUMS_API_KEY` before running Step 00 on a machine without the
extract. Steps 02, 05, 07, and 08 download their public source files as needed.
Manually download the two MIT returns files in **Original Format** from
Harvard Dataverse. The
[Step 07 input list](docs/07_prepare_area_returns.md#source-snapshots-and-running-the-script)
gives the exact releases and paths.

Keep `01_frame/data/input/` on disk between rebuilds. For a new checkout on
the same machine, copy that directory into the same location before running
the command. IPUMS USA requires permission to redistribute the full extract.
[IPUMS USA terms of use](https://usa.ipums.org/usa/terms.shtml)

## Script status

To run individual steps, use their companion documents and run from the
repository root.

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

The [latest House holdout results](docs/09_validate_house_beta.md#latest-verified-holdout-results)
include the published figures, scores, district predictions and sampler
diagnostics. After a local validation run, read
`data/output/09_beta_holdout/latest_complete.txt` for that run's directory.

The [adjusted holdout command](docs/09_validate_house_beta.md#score-the-ballot-adjusted-holdout)
applies the production ballot rule to the held-out 2024 lineups using
the saved stage fits.

**Build paths.** Steps 00–01 acquire and prepare the PUMS sample. Step 02
independently builds the district crosswalk. Step 03 applies it, Step 04
harmonizes demographics, and Step 05 prepares CES. Step 06 builds the
mother frame. For House modeling, Step 07 prepares the original returns,
the two Step 08 scripts prepare maps and lineups, and Step 09 builds and
validates the model inputs. Step 10 assembles the handoff. See the [data catalogue](docs/data_catalogue.md)
for prerequisites and generated files.

## Latest verified rebuild

On November 22, 2026, Steps 00–10 ran in an isolated checkout starting
with a fresh IPUMS extract and the two verified MIT returns files staged
locally. A second run used the rebuild command with those source files
and the saved model fits. It made no source downloads and reproduced all
three handoff files byte for byte.

The population frame covers 436 districts with 497,550 positive cells
and a total weight of 240,960,972 citizen adults. The survey export
contains 58,627 respondents. All three production House regressions
passed the project’s sampler checks. The third holdout regression had
two divergences, so the rebuild warned and retained its provisional
results. See the [population and survey checks](docs/06_build_pums_cells.md#production-results)
and the [House holdout results](docs/09_validate_house_beta.md#latest-verified-holdout-results).

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
