# 01 — Prepare PUMS

## Purpose and population

Prepare the IPUMS 2020–2024 ACS five-year person records.
Retain GQ codes 1–5, CITIZEN codes 0–2, and ages 18+.
Institutional residents and DC remain included.
Source ages and person weights are retained without projection to 2026.

## Run

From the repository root, using its renv environment:

    Rscript frame/scripts/01_prepare_pums.R

On a fresh environment, first restore the recorded packages:

    Rscript -e 'renv::restore(prompt = FALSE)'

## Inputs

Source: https://zenodo.org/records/21285306

Both files belong in `frame/data/input/`. Their MD5 checksums are
verified before loading:

| File | MD5 |
| --- | --- |
| usa_00003.xml | 0b2b19b40c0fa4e7a35f6338b85d4b8f |
| usa_00003.csv.gz | 6945d5353a48361713b49c521f5d1f5a |

## Processing

- Preserve all original columns, including sample and person identifiers.
- Calculate record and weighted-population losses at each filtering stage.
- Add labels for recorded sex, Hispanic origin, race and education.
- Treat Hispanic-origin code 900 as unknown in the binary flag.
- Convert household-income code 9999999 to NA, without imputation.
- Retain zero and negative household incomes.
- Check label mappings, person-key uniqueness and geographic code structure.

The output name `gender` is retained for compatibility; it derives from `SEX`.

## Outputs

- `frame/data/intermediate/pums_clean.rds`
- `frame/data/output/01_pums_filtering.csv`
- `frame/data/output/01_pums_recoding.csv`
- `frame/data/output/01_pums_hispanic.csv`
- `frame/data/output/01_pums_income_by_gq.csv`

Downloaded and generated data are excluded from Git.

## Verified results

- Raw records: 16,095,728.
- Retained records and unique person identifiers: 12,263,785.
- Retained person-weight total: 240,960,972.
- Columns: 30, comprising 24 source and six derived fields.
- Geographic coverage: 50 states plus DC.
- Missing cleaned incomes: 816,970, all in GQ categories 3 and 4.
- No missing values in the other five derived fields.

These results refer to the pinned inputs above.
Crosswalk coverage and subsequent stages remain to be reviewed.
