## Script 14
### Purpose: Add state abbreviations and state_cd identifier

Create human-readable state and CD identifiers for both PUMS demographic cells and CES respondents. These columns are used throughout downstream code where state FIPS integer codes would be confusing or where a single unique-per-CD identifier is needed.

### Inputs and outputs
- Inputs: `pums_demographic_cells` (from Script 11), `ces_with_cd_v2` (from Script 13)
- Outputs (both overwrite existing files):
  - `pums_demographic_cells.rds` (with `state_abbrv`, `state_cd` added)
  - `ces_with_cd_v2.rds` (with `state_abbrv`, `state_cd` added)

### New columns

| Column | Type | Example | Purpose |
|---|---|---|---|
| `state_abbrv` | character | "TX", "CA" | Human-readable state identifier |
| `state_cd` | character | "TX-1", "FL-2" | Unique national CD identifier |

### Why state_cd

CD numbers reset within each state — Texas's CD 1 is unrelated to California's CD 1. For any analysis that aggregates across states (e.g., national CD-level summaries) or filters/joins on a single key per district, `state_cd` provides an unambiguous identifier. The format `XX-N` is a common convention in U.S. political data (e.g., `TX-23`, `CA-12`).

### Methodology

A simple FIPS-to-abbreviation lookup table covers all 50 states (DC was already excluded in Script 10). The lookup is left-joined to both datasets:

```r
left_join(state_fips_to_abb, by = "state_cat") %>%
  mutate(state_cd = paste0(state_abbrv, "-", cd_cat))
```

Both files are then re-saved with the new columns.

### Conditional loading

Both `pums_demographic_cells` and `ces_with_cd_v2` may already be in memory if the pipeline is being run end-to-end. The script checks `exists()` and only loads from disk if needed, allowing the script to be run standalone or as part of a larger session.

### Validation

For each dataset, the script prints:
- Row count
- Unique `state_cd` count (expected: 435)
- Number of NAs in `state_abbrv` and `state_cd` (expected: 0)
- A sample of 10 rows showing the new columns

Zero NAs and exactly 435 unique `state_cd` values confirm that the join covered all rows correctly and that the geographic alignment from Scripts 10 and 12 is intact.