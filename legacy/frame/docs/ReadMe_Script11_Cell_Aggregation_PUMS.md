## Script 11
### Purpose: Cell aggregation for poststratification

Collapse the row-level PUMS data into one row per demographic cell (state × CD × age × gender × race × hispanic × education) with the summed weighted population per cell. This is the demographic-only stratification frame; downstream scripts expand it with vote_2024 as an additional cell dimension to produce the full MrsP frame.

### Inputs
- `pums_crosswalked_harmonized.rds` (from Script 10): row-level PUMS data with each row representing a person × CD assignment, harmonized demographic variables, and `PERWT_adj` weights

### Output
- `pums_demographic_cells.rds`: one row per non-empty demographic cell

| Column | Type | Description |
|---|---|---|
| state_cat | integer | State FIPS code |
| cd_cat | integer | 2026 CD code (1-based; at-large states use 1) |
| age_cat | factor | Age group (14 levels: 18-22 through 83+) |
| gender_cat | character | Gender (2 levels: Male / Female) |
| race_cat | factor | Race (5 levels: White, Black, Native American, Asian, Other/Multi) |
| hispanic_cat | factor | Hispanic ethnicity (2 levels) |
| educ_cat | factor | Education (6 levels: No HS to Post-grad) |
| cell_pop | numeric | Sum of PERWT_adj across all PUMS rows belonging to this cell |

### Aggregation logic

Each row in `pums_crosswalked` represents a person × CD assignment with `PERWT_adj = PERWT × afact` (the ACS person weight multiplied by the PUMA-to-CD allocation factor from Script 04). A person in a split PUMA appears in multiple rows, one per overlapping CD; their `PERWT_adj` values sum to their original `PERWT`.

The aggregation:
```r
group_by(state_cat, cd_cat, age_cat, gender_cat, race_cat, hispanic_cat, educ_cat)
  summarise(cell_pop = sum(PERWT_adj))
```

This collapses ~20.6M person × CD rows into ~498K cells.

### Validation

Two key checks:

1. **Total population preservation**: `sum(cell_pop) = sum(PERWT_adj)` within floating-point tolerance. Confirms no population was lost during aggregation.

2. **Cell-size distribution**: Sparsity matters for MrP — very small cells produce unstable estimates, but partial pooling handles this. Diagnostics report min, median, mean, max, and quantiles of `cell_pop`, plus counts of cells with `cell_pop < 1`, `< 10`, and `< 100`.

### Cell count

| Quantity | Value |
|---|---|
| Theoretical max (full Cartesian product) | 435 × 14 × 2 × 5 × 2 × 6 = 730,800 |
| Actual non-empty cells | 497,836 |
| Cells filled | 68.1% |

The ~33% sparsity reflects that many demographic combinations don't exist in any single CD — for example, "83+ Native American Hispanic post-grad in rural Wyoming." This is a feature, not a bug: building only non-empty cells avoids wasting memory on cells that contribute nothing to poststratification.

### Note on stage in pipeline

This script produces the demographic-only frame. The MrsP frame requires expanding each demographic cell by `vote_2024` (the past-vote covariate), weighted by P(vote | demographics, CD) estimated from CES. That expansion happens in a later script along with the rest of the MrsP frame construction. The output of this script is one of the necessary inputs to that step.

The `state_abbrv` and `state_cd` columns documented in the deliverable README are added during the deliverable-packaging step (not in this script). The frame at this stage uses bare `state_cat` and `cd_cat` integer columns.