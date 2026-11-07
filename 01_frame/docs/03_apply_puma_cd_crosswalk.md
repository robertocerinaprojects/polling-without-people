# 03 — Apply the PUMA-to-district crosswalk

## Plain-language summary

For each citizen-adult record, we know the person's state and PUMA. We look
up the district probabilities for that state/PUMA and create one row for
each district with a positive probability. Each row carries the share of the
person's survey weight assigned to that district. People in the same PUMA
receive the same probabilities.

For example, suppose one person's survey weight is 20 and their PUMA has
probabilities 0.7 and 0.3 for two districts. The two rows contribute 14 and
6 weighted persons to those districts. Together they account for the original
weight of 20. A person in a PUMA with a single positive district contributes
their whole weight to that district.

## Run and status

Run the script from the repository root.

```bash
Rscript 01_frame/scripts/03_apply_puma_cd_crosswalk.R
```

Status is **validated**. The 2026-11-07 national run passed coverage and
allocation checks and saved the person–district table and both audits.

## Inputs and geographic compatibility

| Input under `data/intermediate/` | Producer | Role |
|---|---|---|
| `pums_clean.rds` | Script 01 | One row per retained person, with original person weight `PERWT` and numeric `STATEFIP` and `PUMA`. |
| `puma_cd_crosswalk.rds` | Script 02 | One row per state/PUMA/assigned-district intersection, with `allocation_weight` for the 120th Congress. |

Script 01 identifies the extract as `SAMPLE = 202403`, `YEAR = 2024`, with
2020 PUMA definitions. Script 03 checks the sample and year and matches each
state/PUMA pair to the crosswalk's two-character `STATEFP` and five-character
`PUMA5CE`. District `CDFP` is interpreted within state, including `00` for
at-large districts and `98` for DC.

## Coverage audit

Section 1 counts records and sums `PERWT` by state/PUMA. It checks that
crosswalk district rows are unique and their probabilities sum to one in
every PUMA, allowing an absolute difference of `1e-12`. The audit records
state/PUMAs found in both inputs, in PUMS only or in the crosswalk only.
A PUMS-only geography stops allocation after the audit has been written.

On 2026-11-07 all **2,462 state/PUMA pairs** appeared in both inputs. The
match covered **12,263,785 person records** across all 50 states and DC,
with total weight **240,960,972**. Both unmatched categories had zero PUMAs.

## Person-level allocation and checks

Section 2 works one state at a time. Each person receives every positive
`allocation_weight` for their PUMA. The crosswalk retains zero-probability
intersections for geographic review. The allocation output contains the
positive contributions, computed at full precision.

```
allocated_person_weight = PERWT * allocation_weight
```

District estimates use **`allocated_person_weight`**. The original `PERWT`
appears on each of a person's district rows so the calculation can be checked.
Demographics are available in `pums_clean.rds` via the person identifier
`SAMPLE + SERIAL + PERNUM`.

For each person, the number of rows must equal the number of positive
districts in their PUMA. Their probabilities must sum to one and their
allocated weights must add back to `PERWT`. State totals must have the
expected number of rows and preserve the original person-weight totals.
The national total must also agree. The probability-sum tolerance is
`1e-12`. The tolerance for comparing weighted totals scales with the
original weight or total. After validation, the script combines the state
results into a single person–district table.

### Observed allocation on 2026-11-07

The 12,263,785 people produced **20,333,303 person–district rows**, exactly
the count predicted from the positive district probabilities in their PUMAs.
The input and allocated weights both totaled **240,960,972** at the precision
reported. The largest absolute difference between any person's input weight
and the sum of their contributions was `1.136868e-13`, within the rounding
tolerance. The conservation checks passed for every state and DC.

The run printed one person from Alabama PUMA `00100` with `PERWT = 2`.
The table shows the rounded values printed by R. The allocation uses the
full-precision probabilities.

| District | Probability displayed | Person-weight contribution displayed |
|---|---:|---:|
| AL-04 | 0.904 | 1.81 |
| AL-05 | 0.0962 | 0.192 |

## Outputs

Paths are relative to `01_frame/`.

| File | Contents |
|---|---|
| `data/intermediate/pums_cd_allocation.rds` | One row per person and positive-probability district, with person ID, source state/PUMA, district, original weight, probability and allocated weight. |
| `data/output/03_pums_crosswalk_coverage.csv` | One row per state/PUMA with input population, district coverage and match status. |
| `data/output/03_pums_allocation_by_state.csv` | One row per state or DC with input person count, expected and allocated row counts, input and allocated weight, and largest absolute person-weight discrepancy. |

The [frame data catalogue](data_catalogue.md) lists the columns of each file
in saved order and records the input dependencies.
