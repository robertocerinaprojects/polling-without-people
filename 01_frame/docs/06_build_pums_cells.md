# 06 — Build PUMS population cells and check CES coverage

## Plain-language summary

A cell is a group of people with the same state, 2026 congressional district,
age group, sex/gender category, race, Hispanic origin and education. We give
each PUMS person the categories prepared in Step 04, then add up their Step 03
district contributions within each cell. If a person represents 20 adults and
has district shares of 70% and 30%, the two district cells receive 14 and 6.
If another person contributes 3.5 to the first cell and these are its only
contributions, its population estimate is `N = 17.5`. Two CES respondents
with that profile would give one audit row with `ces_respondents = 2` and
`N = 17.5`.

The CES stays at one row per respondent. We count how many respondents have
a matching population cell and keep a separate count for incomplete CES
profiles and for complete profiles with no positive PUMS contribution.

## Run and files

Run the [cell builder](../scripts/06_build_pums_cells.R) from the repository root
with `Rscript 01_frame/scripts/06_build_pums_cells.R` after Steps 03, 04 and 05.

| File under `01_frame/data/` | Role |
|---|---|
| `intermediate/pums_cd_allocation.rds` | Step 03 supplies each person's state, district and `allocated_person_weight`. This weight already includes the district allocation. |
| `intermediate/pums_demographics.rds` | Step 04 supplies each person's harmonized demographics. The join uses all of `SAMPLE`, `SERIAL` and `PERNUM`. |
| `output/03_pums_allocation_by_state.csv` | Reference totals recorded by Step 03 for checking person counts, district rows and population weights. |
| `intermediate/ces_demographics_harmonized.rds` | Step 05 detailed respondent records supply the shared categories, case IDs and survey keys for the coverage check. The 11-column `ces_analysis.rds` export contains the same respondents and matching fields. |
| `intermediate/pums_cd_cells.rds` | Output with one row per positive PUMS cell, the seven shared keys and numeric `N`. |
| `output/06_ces_pums_cell_coverage.csv` | Output with one row per distinct profile present in the CES, respondent count, matched `N` and coverage status. Read `STATEFP` and `CDFP120` as character to preserve leading zeros. |

Both products use the keys `STATEFP, CDFP120, age_cat, gender_cat, race_cat,
hispanic_cat, educ_cat`. State/district pairs use two-character codes for each
part. DC is `11/98`. The population cell table includes all 436 districts and
all cells receiving positive weight, including cells with no CES respondent.
The survey coverage table includes every retained CES respondent once in its
`ces_respondents` count. Summing the survey coverage table's `N` omits
population cells that have no survey respondent. Use the population table for
population totals.

## What a match means

The CES and PUMS cell keys use the same labels. Their source measures differ.

| Key | What the shared label represents |
|---|---|
| State and district | Both use the 120th Congress plan. PUMS uses fractional district assignments within PUMAs. CES places 2024 residence on that plan and retains one reproducible district choice per person. |
| Age | The same 14 bands from 18–22 to 83+. PUMS records age at interview across 2020–2024. CES approximates age as 2024 minus birth year, which can put someone in the adjacent band near a cutoff. |
| Sex/gender | The two frame labels are Male and Female. PUMS measures recorded sex. CES uses the Man/Woman answers to its gender identity question. |
| Education | Both use No HS, HS grad, Some college, 2-year, 4-year and Post-grad. Step 04 groups detailed IPUMS attainment codes. Step 05 maps CES's six responses. |
| Race | Both use White, Black, Native American, Asian and Other/Multi. PUMS Asian includes the source group Other Asian or Pacific Islander. CES combines Two or more races, Other and Middle Eastern into Other/Multi. Primary Hispanic/Latino CES responses receive a conditional race draw. |
| Hispanic origin | Both use Hispanic and Not Hispanic. PUMS uses its origin flag. CES uses its separate origin answer and preserves its one unresolved response as missing. |

The population universe is US citizen adults, including group quarters and DC.
The CES comparison uses its adult self-reported citizens who also met Step 05’s
gender eligibility rule. The survey does not supply an independent population
total for each cell.

## Validation and interpretation

- Each district-allocation row matches one PUMS person by their full identifier.
  Every demographic record contributes, and each person appears at most once per
  district. The script processes one state's demographic rows at a time after
  matching the identifiers.
- Each state's cell weights reconcile to Step 03's original and allocated totals.
  For the reviewed inputs, the national sum is 240,960,972 and the number of PUMS
  person records is 12,263,785.

| What happens when we look up a CES profile? | `coverage_status` | `N` in the coverage audit |
|---|---|---|
| All seven fields match a population cell. | `matched_positive_N` | Sum of the PUMS district weights in that cell |
| All fields are present, but no PUMS record contributes weight to that cell. Real residents could still have that profile. | `no_positive_pums_cell` | `0` |
| A demographic answer is missing, so we cannot identify the respondent's exact cell. | `missing_ces_key` | `NA` |

## Production results

The mother stratification frame contains **497,550 positive cells**. It
preserves the weighted total of **240,960,972 citizen adults** from
12,263,785 PUMS records across 435 voting districts and DC. The reference
period for the population is 2020–2024. The district boundaries are those
used for the 2026 election. The upstream person–district file retains each
person's fractional contributions when person-level analysis is needed.

| Result for the CES respondent's seven matching fields | Respondents | Distinct CES profiles |
|---|---:|---:|
| All seven fields match a frame cell with positive `N` | 58,162 | 42,289 |
| All seven fields are present, with no positive `N` in the frame | 464 | 459 |
| Hispanic origin is missing, so the exact cell is unknown | 1 | 1 |
| Total | 58,627 | 42,749 |

The first row covers 99.21% of respondents. The other 465 remain in the
CES with their recorded answers. The frame also has 455,261 positive cells
with no exact CES respondent. Poststratification uses the full population
table, including those cells. An inner join of the two files would discard
both people and population cells.

### Check the saved analysis files

Run the [saved-file check](../scripts/helpers/06_check_analysis_files.R) from the
repository root with `Rscript 01_frame/scripts/helpers/06_check_analysis_files.R`.
The check reads the detailed CES, its 11-column export, the mother frame, the Step 03
state totals and the Step 06 coverage CSV. It compares every exported CES value and
respondent ID in order, reconciles each state's population, and verifies the count
and population of each observed CES profile. It also checks that local Hispanic race
draws have positive population in the selected district and that broader fallback
draws have an empty local profile. It prints the totals and coverage summary without
regenerating any files.

[Step 04 categories](04_harmonize_pums.md) · [Step 05 CES and district method](05_prepare_ces.md)
