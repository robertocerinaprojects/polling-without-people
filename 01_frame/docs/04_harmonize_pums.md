# 04 — Harmonize PUMS demographics

## Plain-language summary

We start with one record for each citizen aged 18 or older in the cleaned
PUMS file. We give each person categories for age, gender, education, race
and Hispanic origin that we can also use in the CES. Each person keeps the
identifier needed to attach these categories to their district contributions.

We then ask what share of Hispanic adult citizens falls into each of our
five race categories. Each PUMS record counts once with its original person
weight. [Script 05](05_prepare_ces.md) uses the national totals to check its
donor tables and joins these demographic categories to the district-weighted
PUMS records for the conditional CES draw.

## Run and review

From the repository root, run `Rscript 01_frame/scripts/04_harmonize_pums.R`.
The input is `01_frame/data/intermediate/pums_clean.rds` from Step 01.

Review `01_frame/data/output/04_pums_hispanic_race_probabilities.csv` to check
the national margin. For each race, `probability` is that category's
`donor_weight` divided by the sum of `donor_weight` across all five rows.
The denominator includes all retained PUMS people with `hispanic_flag = 1`,
including group-quarters residents and DC. `donor_records` is the unweighted
record count. [IPUMS person weights](https://usa.ipums.org/usa-action/variables/PERWT)

| Check on the reviewed Step 01 input | Expected total |
|---|---:|
| People receiving harmonized categories | 12,263,785 |
| Hispanic donor records | 1,401,620 |
| Sum of Hispanic donor person weights | 33,794,882 |
| Sum of the five probabilities | 1 |

## Categories

| PUMS field | Harmonized field | Coding |
|---|---|---|
| `AGE` at observation | `age_cat` | Five-year bands beginning 18–22, ending 78–82, followed by 83+. |
| `SEX` | `gender_cat` | Recorded sex codes 1 and 2 give Male and Female. The field name is shared with CES. |
| `hispanic_flag` | `hispanic_cat` | 1 gives Hispanic, 0 gives Not Hispanic. Unknown origin stays missing. |
| `RACE` | `race_cat` | 1 White, 2 Black, 3 Native American, 4–6 Asian, 7–9 Other/Multi. The Asian group includes the source category Other Asian or Pacific Islander. |
| `EDUCD` | `educ_cat` | The six education groups below. |

| Education | IPUMS detailed codes |
|---|---|
| No HS | 2, 11, 12, 14–17, 22, 23, 25, 26, 30, 40, 50, 61 |
| HS grad | 63, 64 |
| Some college | 65, 71 |
| 2-year | 81 |
| 4-year | 101 |
| Post-grad | 114–116 |

These category groupings are project choices. The IPUMS codebook supplies
the meanings of the source codes. The coverage audit counts any missing
harmonized values. An unmapped race in the Hispanic donor population stops
the calculation so that the national shares account for all donors.
[IPUMS race](https://usa.ipums.org/usa-action/variables/RACE) ·
[Hispanic origin](https://usa.ipums.org/usa-action/variables/HISPAN) ·
[Education](https://usa.ipums.org/usa-action/variables/EDUC)

## Outputs

- `data/intermediate/pums_demographics.rds` has one row per
  `SAMPLE + SERIAL + PERNUM`, with the five category fields. Join using all
  three keys when constructing district-level demographic cells.
- `data/output/04_pums_hispanic_race_probabilities.csv` records the national
  donor totals used to validate the conditional donor tables. Its columns are `race_cat, donor_records, donor_weight, probability`.
- `data/output/04_pums_demographic_coverage.csv` records `variable, records,
  missing` for the five category fields.

## Validation

The national run harmonized 12,263,785 citizen-adult records. All five fields
were complete. The 1,401,620 Hispanic donor records had a combined person
weight of 33,794,882.

| Harmonized race | Donor records | Weighted people | National share (rounded) |
|---|---:|---:|---:|
| White | 291,728 | 6,868,250 | 20.32% |
| Black | 21,928 | 549,769 | 1.63% |
| Native American | 34,808 | 701,338 | 2.08% |
| Asian | 9,932 | 208,554 | 0.62% |
| Other/Multi | 1,043,224 | 25,466,971 | 75.36% |

`Other/Multi` combines 10,704,572 weighted people recorded as other race
alone, 13,968,480 recorded with two races and 793,919 with three or more.
Of the two-race group, 12,821,909 were coded “White and other race write-in”
(`RACED = 826`). Step 05 checks that its district-specific donor weights sum to these
national totals for each race.

A separate 108-record test with unequal person weights matched independently
calculated shares. It also covered a distribution with four zero-count groups.

See the [data catalogue](data_catalogue.md) for file lineage and the
[frame index](../README.md) for validation status.
