## Script 17
### Purpose: Compute state-level 2024 presidential vote shares (CVAP denominator)

Aggregate 2024 presidential election results to state-level 4-feature vote shares. These serve as state-level covariates in the CART inheritance model — for each CD, the state-level pres shares are joined in and used alongside the CD's demographic proportions as predictors of House vote shares.

### Why state-level presidential vote shares as covariates

State presidential outcomes are a strong signal of a district's underlying partisan geography. Even in redistricting years, state pres shares are stable and reflect the political character that maps to House outcomes. Including them as CART predictors captures state-level fixed effects that pure demographics can't fully express (e.g., regional political culture, historical partisan trends, state-level media environments).

The 4-feature format (dem / rep / other / no_vote against CVAP) matches the CD-level House share structure from Script 16B. Both target and predictors are 4-simplex vote shares against a consistent denominator.

### Inputs

| Source | File | Description |
|---|---|---|
| MIT Election Data and Science Lab | `1976-2024-president.csv` | 1976-2024 U.S. presidential election results by state |
| Script 15 | `cd_demographics.rds` | Provides `cd_pop` — summed to get state-level CVAP |

MIT presidential dataset available at: https://dataverse.harvard.edu/dataset.xhtml?persistentId=doi:10.7910/DVN/42MVDX

### Output

`state_pres_2024.rds` — 50 rows, 5 columns.

| Column | Type | Description |
|---|---|---|
| state_abbrv | character | 2-letter state code (e.g., "TX", "CA") |
| state_pres_dem_share | numeric | Democratic pres votes / state CVAP |
| state_pres_rep_share | numeric | Republican pres votes / state CVAP |
| state_pres_other_share | numeric | Other pres votes / state CVAP |
| state_pres_no_vote_share | numeric | (state CVAP − total pres votes) / state CVAP |

All four shares sum to 1.0 per state.

### Methodology

#### 1. State-level CVAP

State citizen voting-age population (CVAP) is computed as the sum of `cd_pop` across all CDs within each state. This uses the PUMS-derived CVAP from Script 15, matching the denominator used in CD-level shares.
state_cvap = sum(cd_pop) within state

Total US CVAP is approximately 240 million, consistent with the CD-level total from Script 15.

#### 2. Party categorization

The MIT presidential dataset includes a `party_simplified` column that pre-collapses minor variations. The mapping:

| party_simplified | Category |
|---|---|
| DEMOCRAT | dem |
| REPUBLICAN | rep |
| Everything else (LIBERTARIAN, OTHER, NA) | other |

This is a simpler classification than the House data required because presidential races don't have the fusion-ticket complication (each state's presidential vote is aggregated to one state total per ticket).

#### 3. DC exclusion

DC is excluded from `state_pres_2024` because DC doesn't have House seats (only a non-voting delegate). Since state pres shares are used as covariates for CD-level predictions, and there are no DC CDs downstream, DC data is dropped for consistency with earlier scripts.

#### 4. Vote share computation

For each state, compute 4 shares against CVAP:
state_pres_dem_share     = dem_pres_votes     / state_cvap
state_pres_rep_share     = rep_pres_votes     / state_cvap
state_pres_other_share   = other_pres_votes   / state_cvap
state_pres_no_vote_share = (state_cvap - total_pres_votes) / state_cvap

All four sum to 1.0 per state. `no_vote_share` represents the fraction of citizen voting-age population that didn't cast a presidential ballot — either because they didn't vote at all or voted downballot without voting for president (rare in presidential years, but nonzero).

### Validation

The script confirms:

| Check | Expected |
|---|---|
| Row count | 50 (all states) |
| Unique state_abbrv values | 50 |
| Sum of 4 shares per state | 1.0 ± floating-point rounding |
| NAs across share columns | 0 |
| Total US CVAP | ~240M (matches Script 15) |

Sanity-check diagnostics:

- **Top 5 most Democratic states**: Should include Maryland, Massachusetts, California, New York (though not DC itself).
- **Top 5 most Republican states**: Should include Wyoming, West Virginia, Oklahoma, and other historically deep-red states.
- **Highest-turnout states**: Should be Minnesota, Maine, Wisconsin, or similar high-turnout states.
- **Lowest-turnout states**: Should include Hawaii, West Virginia, and other historically low-turnout states.

### Downstream use

`state_pres_2024.rds` is joined into the CD-level training table (built in a later script) via `state_abbrv`. Each CD in a given state gets that state's four presidential shares as covariates, adding 4 features to the CART model's predictor set alongside the ~29 demographic features from Script 15.

The resulting training table structure:
- One row per CD
- ~29 demographic features (from Script 15)
- 4 state pres share features (from Script 17)
- 4 target variables: `dem_share`, `rep_share`, `other_share`, `no_vote_share` (from Script 16B)