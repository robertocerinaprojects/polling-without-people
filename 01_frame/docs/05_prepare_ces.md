# 05 — Prepare citizen CES respondents and assign 2026 district and race

## Plain-language summary

We download the full 2024 Cooperative Election Study and keep adults who
report US citizenship and meet the frame's existing gender eligibility rule.
We keep their original race, Hispanic origin and 2024 residence information.

We place each respondent's 2024 residence on the map used for the 2026
election. An old district, sometimes together with county, can determine the
new district exactly under the Census block map. Where the old district is
split, we draw a new district using the estimated share of citizen adults
in each overlap and keep the probabilities for later inspection.

For citizens whose primary race answer is Hispanic/Latino, we draw a
harmonized race from Hispanic PUMS citizen adults of the same sex/gender
category, age group and education within the assigned 2026 district. Someone
who selected Black as primary race and reported Hispanic origin keeps both.
The [decision record](05_citizenship_district_decisions.md) documents district
overlaps, empty donor groups, random seeds and the Texas exception.

For each respondent we also derive the party of their 2024 House and
presidential choice. We prefer a usable post-election report and flag each
use of an early vote, a preference or a turnout answer. See the
[vote questions, priorities and release checks](05_vote_rules.md).

## Run and inputs

From the repository root, run `Rscript 01_frame/scripts/05_prepare_ces.R`.
The top-level script handles the CES download, the geographic lookup, the
donor estimates and the survey harmonization. The geographic helper uses
Python 3's standard library. Run after Steps 02, 03 and 04.

| Input | Used for |
|---|---|
| `data/input/CCES24_Common_OUTPUT_vv_topost_final.csv` | Script 05 downloads Harvard Dataverse file 12050325 (V9) once, verifies MD5 `b740b9305fee50e1a34656b513f55c57` and reuses the full raw CSV. |
| `data/input/cd119.zip`, `data/input/cd120.zip` | Join the original 2020 block IDs to construct candidate district pairs. Script 05 downloads the first archive and verifies both. |
| `docs/02_pl_2020_sources.csv`, affected archives under `data/input/pl_2020/` and `data/output/02_bg_cvap_contributions.csv` | Population shares within split source areas. |
| `data/intermediate/pums_cd_allocation.rds` and `pums_demographics.rds` | Step 03 fractional person–district weights and Step 04 person-level demographics. |
| `data/output/04_pums_hispanic_race_probabilities.csv` | Reconcile the donor totals by race to the national calculation. |

The earlier national model used a 75.36% national Other/Multi probability.
The present model uses district- and demographic-specific probabilities.
The nationally observed share is recorded in the [PUMS guide](04_harmonize_pums.md).

## Respondents and variables

| CES field | Treatment |
|---|---|
| `cit1` | Retain an explicit 1 (Yes). Preserve the source answer and separately audit No and missing. |
| `gender4` | Retain 1 (Man) and 2 (Woman), using Male/Female as the shared analysis labels. PUMS records sex. |
| `birthyr` | Approximate age is 2024 minus birth year. Age bands run from 18–22 through 78–82, followed by 83+. |
| `educ` | Codes 1–6 give No HS, HS grad, Some college, 2-year, 4-year and Post-grad. |
| `race` | Codes 1, 2, 4 and 5 give White, Black, Asian and Native American respectively. Codes 6–8 give Other/Multi. Code 3 receives a conditional draw across all five categories. |
| `hispanic` | Codes 1 and 2 give Hispanic and Not Hispanic. Unresolved origin stays missing. |
| `inputstate`, `cdid119`, `countyfips` | Original CES pre-election geography, used to find the 120th-district distribution. Preserve source values. |
| `commonweight`, `caseid` | Preserve the survey weight and unique identifier for linking back to original survey answers. |

## Outputs and checks

The final `data/intermediate/ces_demographics_harmonized.rds` contains one
record per retained `caseid`. The new district is `STATEFP + CDFP120`.
`CD119` is the normalized old district. The source `cdid119` is also preserved.
`district_probability` is the probability of the chosen district.
`race_imputed` and `race_donor_level` identify a race draw and its donor pool.

| File under `data/output/` unless indicated | Unit and purpose |
|---|---|
| `05_ces_vote_sources.csv` | Unweighted counts by office, source question stage and outcome, including unresolved respondents. |
| `05_ces_sample.csv` | One row per sample stage, including citizenship responses. |
| `05_ces_district_lookup.csv` | Old district or old district plus county × possible new district. Records probabilities, method and the Texas sensitivity bounds. |
| `05_ces_unknown_origin_cvap.csv` | A separate geographic ledger of positive source CVAP with unknown old district. |
| `../intermediate/hispanic_race_by_district_profile.rds` | Five racial groups for each district, state and national sex/gender–education–age profile. Stores weights, counts, effective donor size and probabilities. |
| `05_ces_district_probabilities.csv` | One row per retained citizen and positive candidate new district, with a flag for the selected district. |
| `05_ces_race_donor_support.csv` | One row per primary-Hispanic citizen × positive candidate district. Gives all five conditional probabilities and the donor support. |
| `05_ces_race_imputation.csv` | National expected and realized assignment counts across the five categories for the retained draw recipients. |
| `05_ces_demographic_coverage.csv` | Missing values by harmonized variable in the citizen sample. |

The RDS also contains `house_vote_2024`, `pres_vote_2024`, both source
flags, the House contest type and original ballot-wave geography. The
`STATEFP + CDFP120` key still refers to the modeled residence district used
for matching to the [PUMS population cells](06_build_pums_cells.md).

## Analysis file

Use `data/intermediate/ces_analysis.rds` for respondent-level analysis. It
contains 11 columns selected from `ces_demographics_harmonized.rds` and keeps
its row order, factor levels, district codes, survey weights and missing values.
The reviewed sample has 58,627 respondents. Use `caseid` to look up raw survey
answers, candidate rosters, race imputation flags or district probabilities
in the detailed file and its audits.

| Columns | Use |
|---|---|
| `caseid`, `commonweight` | Unique respondent identifier and CES adult survey weight. |
| `STATEFP`, `CDFP120` | State and district for matching to the population frame on the 2026 map. Keep both codes as text. |
| `age_cat`, `gender_cat`, `race_cat`, `hispanic_cat`, `educ_cat` | The five harmonized demographic fields. Hispanic origin is separate from race. |
| `house_vote_2024`, `pres_vote_2024` | The cleaned 2024 House and presidential outcomes. Both keep an explicit `No Vote` distinct from a missing answer. |

For comparisons with actual 2024 House district returns, use `caseid` to
retrieve `house_vote_state_2024` and `house_vote_cd119_2024` from the detailed
file. Together they identify the contest in the survey wave that supplied the
House outcome, including the DC delegate contest. The detailed file also
records the source of each office's outcome, so a pre-election preference
can be distinguished from a post-election report. See the [vote rules](05_vote_rules.md).

Step 05 writes this export after saving the detailed file. To make it from
an existing run and print its first six rows, run from the repository root:

```sh
Rscript 01_frame/scripts/helpers/05_export_ces_analysis.R
```

## Production run

The run saved 58,627 adult, gender-eligible CES citizens. All had a harmonized
race. One had unresolved Hispanic origin. The table gives unweighted respondent
counts. The rows are the original answers to the CES primary race question.
The columns are the harmonized race after the draw.

| Original CES race | White | Black | Native American | Asian | Other/Multi | Before |
|---|---:|---:|---:|---:|---:|---:|
| White | 40,869 | 0 | 0 | 0 | 0 | 40,869 |
| Black or African-American | 0 | 7,555 | 0 | 0 | 0 | 7,555 |
| Hispanic or Latino | 984 | 79 | 99 | 37 | 3,670 | 4,869 |
| Asian or Asian-American | 0 | 0 | 0 | 1,745 | 0 | 1,745 |
| Native American | 0 | 0 | 574 | 0 | 0 | 574 |
| Two or more races | 0 | 0 | 0 | 0 | 1,871 | 1,871 |
| Other | 0 | 0 | 0 | 0 | 991 | 991 |
| Middle Eastern | 0 | 0 | 0 | 0 | 153 | 153 |
| After | 41,853 | 7,634 | 673 | 1,782 | 6,685 | 58,627 |

All 4,869 respondents in the Hispanic or Latino row also reported Hispanic
origin. A further 2,417 Hispanic-origin respondents selected another primary
race and kept its mapped category. Each person keeps one survey weight.

The run used 1,401,620 Hispanic PUMS donors with a combined person weight
of 33,794,882 across 436 district codes including DC. Of the 4,869 recipients,
2,870 had one positive district probability and 1,999 had several. In their
selected districts, 4,858 recipients had a matching district donor group,
11 used their state group and none used the national group.

The conditional model expected 3,638.48 Other/Multi assignments (74.73%),
averaging over all candidate districts. This draw produced 3,670 (75.37%).
For the effective size of each donor group used in the realized draw, filter
`05_ces_race_donor_support.csv` to `selected == TRUE` and inspect
`used_effective_donors` by `donor_level`.

See the [data catalogue](data_catalogue.md) and the [official CES release](https://doi.org/10.7910/DVN/X11EP6).
