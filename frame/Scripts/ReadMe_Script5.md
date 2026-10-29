## ReadMe for Script 05
### Purpose: Apply unified PUMA-to-CD crosswalk to PUMS records

### Inputs
- `pums_clean.rds` (from Script 03): 12,263,785 person-level records with cleaned demographic variables
- `unified_crosswalk_2026.rds` (from Script 04): PUMA × 2026 CD mapping with population-weighted allocation factors

### Output
- `pums_crosswalked.rds`: ~20.6M rows × 29 columns, ready for cell aggregation
- File size: ~320 MB (RDS, compressed)

### The probabilistic assignment problem

ACS PUMS data identifies each respondent at PUMA resolution — a geography deliberately coarser than the congressional district to protect respondent privacy. For PUMAs that lie entirely within one CD (afact = 1), the CD assignment is unambiguous. For PUMAs that span multiple CDs, the true CD of each individual respondent cannot be determined from the public data.

This script handles the ambiguity via **probabilistic assignment**: a respondent in a split PUMA is represented in multiple rows, one per overlapping CD, with the row weight scaled by the population share of that PUMA-CD intersection (the afact value).

### Join logic

```r
pums_crosswalked %
  left_join(
    unified_crosswalk,
    by = c("STATEFIP" = "state", "PUMA" = "puma22"),
    relationship = "many-to-many"
  )
```

- **Join key**: (STATEFIP, PUMA) on the PUMS side ↔ (state, puma22) on the crosswalk side. Both columns are required because PUMA codes are only unique within a state.
- **`left_join`**: preserves all PUMS records (no respondents are dropped if their PUMA somehow lacks a crosswalk match — this would be caught in validation)
- **`relationship = "many-to-many"`**: PUMS has many people per PUMA; crosswalk has many CDs per split PUMA. The combination produces person × CD rows.

### Adjusted person weight

For each row in the joined output:
PERWT_adj = PERWT × afact

Worked example: a respondent in a PUMA with `PERWT = 100` and that PUMA splits 70/30 between CDs A and B will appear as:

| PERWT | CD | afact | PERWT_adj |
|---|---|---|---|
| 100 | A | 0.70 | 70 |
| 100 | B | 0.30 | 30 |

The respondent's total contribution is `70 + 30 = 100` (preserved). Their statistical weight is distributed across CDs according to the geographic probability of where they actually live within their PUMA. For PUMAs entirely in one CD (afact = 1), `PERWT_adj = PERWT` and no splitting occurs.

This is the same approach Geocorr's afact column is designed for and is standard in MrP literature for handling sub-PUMA geographies.

### Validation results

| Check | Result |
|---|---|
| Rows before join | 12,263,785 |
| Rows after join | 20,640,681 |
| Row increase | 8,376,896 (from split PUMAs; expected) |
| Unmatched records (cd_2026 = NA) | 0 |
| Original PERWT sum | 240,960,972 |
| PERWT_adj sum | 240,960,961 |
| Difference | -11 (floating-point rounding) |
| Unique state+CD combinations | 436 (435 voting House + DC) |

The 8.4M extra rows reflect the higher split rate in this unified crosswalk compared to a pure Geocorr crosswalk — the redistricted states (especially CA and TX) have many PUMAs that split across multiple new 2026 CDs.

The weighted population is preserved within floating-point precision (-11 out of 241 million is rounding noise).

### Output schema

`pums_crosswalked.rds` has 29 columns:
- Identifiers and geography: SERIAL, PERNUM, STATEFIP, PUMA, CPUMA1020, **cd_2026** (new)
- Weights: PERWT, HHWT, CLUSTER, STRATA, **afact** (new), **PERWT_adj** (new)
- Raw demographic variables: AGE, SEX, RACE, RACED, HISPAN, HISPAND, CITIZEN, EDUC, EDUCD, HHINCOME, GQ
- Cleaned demographic variables: gender, hispanic_flag, hispanic_detailed, race_detailed, educ_detailed, hhincome_clean

### Notes
- DC (STATEFIP = 11, cd_2026 = 98) is retained at this stage. It may be filtered out at the stratification frame construction stage since the MrsP pipeline focuses on the 50 states.
- The output is large (~320 MB RDS). For sharing with collaborators, the RDS format is preferred over CSV (which would be ~1.5–2 GB).
