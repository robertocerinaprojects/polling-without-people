# 06 — Build PUMS population cells and check CES coverage

## Plain-language summary

A cell is a group of people with the same state, 2026 congressional district,
age group, sex/gender category, race, Hispanic origin and education. We give
each PUMS person the categories prepared in Step 04, then add up their Step 03
district contributions within each cell. If a person represents 20 adults and
has district shares of 70% and 30%, the two district cells receive 14 and 6.
The result, `N`, estimates the number of citizen adults in that cell. We keep
the full precision, including fractional people.

The CES stays at one row per respondent. We count how many respondents have
a matching population cell and keep a separate count for incomplete CES
profiles and for complete profiles with no positive PUMS contribution.

## Run and files

From the repository root, run `Rscript 01_frame/scripts/06_build_pums_cells.R`
after Steps 03, 04 and 05. All four inputs are existing products.

| File under `01_frame/data/` | Role |
|---|---|
| `intermediate/pums_cd_allocation.rds` | Step 03 supplies each person's state, district and `allocated_person_weight`. This weight already includes the district allocation. |
| `intermediate/pums_demographics.rds` | Step 04 supplies each person's harmonized demographics. The join uses all of `SAMPLE`, `SERIAL` and `PERNUM`. |
| `output/03_pums_allocation_by_state.csv` | Independent Step 03 totals for checking person counts, district rows and population weights. |
| `intermediate/ces_demographics_harmonized.rds` | Step 05 respondent records supply the shared category definitions and the survey keys for the coverage check. |
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
- `matched_positive_N` means the seven CES values match a row with positive
  estimated population. `no_positive_pums_cell` means the complete profile has
  zero estimated mass in this empirical frame. Real residents could still have
  that profile. `missing_ces_key` means at least one value is missing, so its
  exact-cell `N` stays missing. A coverage flag preserves the respondent.
- Check the printed counts from the production run before reporting exact CES
  overlap. A matching category vocabulary alone does not establish cell support.

[Step 04 categories](04_harmonize_pums.md) · [Step 05 CES and district method](05_prepare_ces.md)
