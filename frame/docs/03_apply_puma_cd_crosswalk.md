# 03 — Apply the PUMA-to-district crosswalk

## Plain-language summary

We start with the citizen-adult records prepared by Script 01 and the
district allocation weights constructed by Script 02. Before applying
those weights, we check that every PUMA represented in the person file
appears in the crosswalk.

A PUMA is identified by its state and PUMA code together. The person file
stores those codes as numbers; the crosswalk stores them as text with
leading zeros. We make their formats consistent and compare the pairs.
We also check that the crosswalk weights sum to one within each PUMA.

This first section compares PUMA summaries. It does not duplicate,
allocate or remove individual records.

## Inputs and geographic compatibility

- `../data/intermediate/pums_clean.rds`
- `../data/intermediate/puma_cd_crosswalk.rds`

Script 01 establishes the reviewed extract as SAMPLE 202403, YEAR 2024,
with 2020 PUMA definitions. Section 1 checks that sample identity again.
Matching geographic codes alone would not establish that the underlying
boundary definitions agree.

## Coverage checks

Every retained PUMS PUMA must have a crosswalk entry. Unmatched PUMAs
cause the script to stop after saving the audit.

Crosswalk PUMAs with no retained PUMS records are reported separately.
Their presence alone does not imply that any person record is unmatched.

Zero allocation weights are valid. The within-PUMA weight-sum tolerance
of 1e-12 concerns numerical rounding, not statistical uncertainty.

## Output and implementation status

`../data/output/03_pums_crosswalk_coverage.csv` records coverage, person
counts, weighted population and crosswalk summaries for each state/PUMA.

Section 1 has been added; execution validation is pending.
Person-level allocation and population-conservation checks will follow
after this coverage audit has been reviewed.
