## Script 04: Build unified PUMA-to-2026 CD crosswalk

### Purpose

Build a single PUMA × CD crosswalk that maps every U.S. Public Use Microdata Area (PUMA) to its overlapping 2026 congressional districts, with population-weighted allocation factors. This crosswalk is the bridge between ACS PUMS data (which reports respondents at PUMA resolution) and the CD-level analysis needed for the MrsP pipeline.

For each PUMA × CD intersection, the crosswalk reports `afact` — the fraction of the PUMA's population that resides in that CD. This is the same definition Geocorr uses, allowing the two data sources used here (Geocorr 2022 and custom state-specific crosswalks) to be combined into a single interchangeable file.

### Why two sources are needed

Geocorr 2022 publishes a national PUMA × CD crosswalk for the 119th Congress (2024) boundaries. For 43 of 50 states + DC, 2024 and 2026 boundaries are identical, so Geocorr's mapping can be used directly. The remaining 7 states underwent substantial 2025 redistricting, so their 2024 boundaries no longer reflect 2026 CDs.

Redistricted States: Texas, California, Missouri, North Carolina, Ohio, Utah, Florida 

For these 7 states, state-specific crosswalks are built from official Block Assignment Files using a population-weighted methodology (described in Stage 2).

#### Note on Virginia

Virginia's redistricting efforts were blocked due to legal challenges. Hence, as of now, we are assuming that VA will not be redistricted.

### Pipeline overview

The script proceeds in 3 sequential stages:

**Stage 1** — Load the Geocorr 2022 crosswalk and prepare it for use (column renaming, type coercion, validation). Covers 43 stable states + DC.

**Stage 2** — Build PUMA × CD crosswalks for the 7 redistricted states. For each state:
1. Read the official BAF (block-to-CD mapping)
2. Pull 2020 Census block populations via tidycensus
3. Aggregate up the geographic hierarchy: blocks → tracts → PUMAs
4. Compute afact = (population in PUMA × CD intersection) / (total PUMA population)
5. Save state-specific crosswalk

The geographic chain is:
Block (has population, has CD)

↓ aggregate by tract × CD

Tract × CD intersection (has population, has CD)

↓ join via Census Tract-to-PUMA file (clean lookup, tracts nest within PUMAs)

PUMA × CD intersection (has population, has CD)

↓ aggregate per PUMA

PUMA-level afact (CD-allocated population shares within PUMA)

A reusable helper function `build_state_puma_cd_crosswalk()` executes this pipeline for each state, with arguments configuring the BAF file format.

**Stage 3** — Merge: drop the 7 redistricted-state rows from Geocorr, append the new state crosswalks, drop Puerto Rico, and save the unified file. The result is a single canonical PUMA × CD crosswalk covering all 50 states + DC.

### Inputs

| File | Source | Purpose |
|---|---|---|
| geocorr2022_2610104623.csv | Missouri Census Data Center (MCDC). https://mcdc.missouri.edu/applications/geocorr2022.html | National PUMA × CD crosswalk for 119th Congress (Stage 1) |
| 2020_Census_Tract_to_2020_PUMA.txt | U.S. Census Bureau, 2020 Relationship Files. https://www.census.gov/geographies/reference-files/time-series/geo/relationship-files.2020.html | Maps Census tracts to 2020 PUMAs; used in Stage 2 block-tract-PUMA aggregation |
| 2020 Census block populations | tidycensus::get_decennial(), variable P1_001N, PL 94-171 file | Population weights for Stage 2 aggregation |
| PLANC2333.csv (TX BAF) | Redistricting Data Hub. https://redistrictingdatahub.org/data/download-data/ | Block-to-2026 CD mapping for Texas |
| ab604.csv (CA BAF) | Redistricting Data Hub | Block-to-2026 CD mapping for California |
| HB1_Missouri_Congressional_Districts_2025_BEF.xlsx (MO BEF) | Missouri Spatial Data Information Service (MSDIS). https://data-msdis.opendata.arcgis.com/search?tags=hb1 | Block-to-2026 CD mapping for Missouri |
| NCGA_CCM-2.csv (NC BAF) | Redistricting Data Hub | Block-to-2026 CD mapping for North Carolina |
| October 31 2025 CD BAF.xlsx (OH BAF) | Redistricting Data Hub | Block-to-2026 CD mapping for Ohio |
| ut_cong_adopted_2025_baf.csv (UT BAF) | Redistricting Data Hub | Block-to-2026 CD mapping for Utah |
| EOGPCRP2026.csv (FL BAF) | Redistricting Data Hub | Block-to-2026 CD mapping for Florida |

API key needed: tidycensus requires a free U.S. Census Bureau API key (https://api.census.gov/data/key_signup.html), set once via `census_api_key()` and persisted in `.Renviron`.

R package dependencies: tidyverse, tidycensus, readxl (for Excel BAFs), readr.

### Outputs

**Intermediate (per state, from Stage 2)**: 7 state-specific RDS files
- `tx_puma_cd_crosswalk.rds`, `ca_puma_cd_crosswalk.rds`, `mo_puma_cd_crosswalk.rds`, `nc_puma_cd_crosswalk.rds`, `oh_puma_cd_crosswalk.rds`, `ut_puma_cd_crosswalk.rds`, `fl_puma_cd_crosswalk.rds`

Each contains columns: state (chr FIPS), puma (chr), cd_new (int), pop_intersection (num), puma_pop (num), afact (num).

**Final**: `unified_crosswalk_2026.rds`

| Column | Type | Description |
|---|---|---|
| state | integer | State FIPS code |
| puma22 | integer | 2022 PUMA code (unique within state) |
| cd_2026 | integer | 2026 CD code |
| afact | numeric | Fraction of PUMA population in this CD |

~4,144 rows covering 51 jurisdictions (50 states + DC), 436 state+CD combinations (435 voting House districts + DC delegate).

This is the file used by Script 05 to assign each ACS PUMS record to a 2026 CD.

### Coding conventions for special CDs

The unified crosswalk uses the following code conventions (inherited from Geocorr):

| Code | Meaning | Treatment |
|---|---|---|
| 1-52 | Regular CD number within state | Used directly |
| 0 | At-large district (AK, DE, MT, ND, SD, VT, WY) | Recoded to "1" in a later script |
| 98 | Non-voting delegate (DC) | Retained for now; DC may be filtered at the stratification frame stage |

### Stage 1 — Load Geocorr 2022 (for 43 stable states)

**Source**: Geocorr 2022 PUMA × CD crosswalk from the Missouri Census Data Center (MCDC), accessible at https://mcdc.missouri.edu/applications/geocorr2022.html.

**File structure**: The Geocorr CSV has 2 header rows — a column-name row followed by a column-description row. The description row is loaded separately for documentation, then the data is re-read skipping that row.

**Column mapping**:

| Geocorr column | Renamed to | Type | Description |
|---|---|---|---|
| State code | state | int | FIPS code |
| PUMA (2022) | puma22 | int | 2022 PUMA, unique within state |
| Congressional district code (119th Congress) | cd119 | int | 2024 CD code |
| State abbr. | stab | chr | 2-letter state |
| PUMA22 name | puma_name | chr | Human-readable label |
| Total population (2020 Census) | pop20 | num | Population in PUMA × CD intersection |
| cd119-to-puma22 allocation factor | afact2 | num | (reverse direction; not used) |
| puma22-to-cd119 allocation factor | afact | num | Primary join weight |

**Why use cd119 (2024 boundaries) for 2026 modeling?**

For 43 states, congressional district boundaries are unchanged between 2024 and 2026, so the 2024 CD codes (cd119) directly represent 2026 CDs. The 7 states with substantial 2025 redistricting are handled separately in Stage 2.

### Validation findings

After loading, the following quality issues were detected and documented (not all of which require fixing here — some are simply data characteristics):

**afact sum issues** — afact values should sum to exactly 1.0 per (state, PUMA), since allocation factors represent population shares. Empirical findings:
- Most PUMAs sum exactly to 1.0
- Some sum to approximately 0.9999 or 1.0001 due to rounding artifacts in the Geocorr file
- A few rows have afact = 0.0 (no population in that PUMA × CD intersection)

These are minor data artifacts and do not require correction. Downstream joins use afact as a population-share weight; small rounding errors propagate to PERWT_adj but are negligible at population scale.

**Unusual CD codes detected**:

| Code | Meaning | Treatment |
|---|---|---|
| 0 | At-large district (7 states: AK, DE, ND, SD, VT, WY) | Geocorr's encoding; recoded to "1" in a later script |
| 98 | Non-voting delegate (DC, PR territories) | DC dropped at stratification frame stage; PR dropped in Stage 3 |
| 99 | Unassigned (rare or absent) | Filtered if found |

**Coverage**:
- Unique states: 52 (50 + DC + PR)
- Unique CD codes: includes 1-52 regular + 0 at-large + 98 delegates
- 435 House voting CDs nationally (regular districts + at-large states counted as 1 each)

### Note on column name conventions

Although the cd119 column will eventually represent 2026 boundaries (after Stage 2 substitutes the redistricted states), the name is retained for code compatibility throughout the pipeline.

### Stage 2 — Build PUMA-to-2026 CD crosswalks for 7 redistricted states

###Purpose

Geocorr 2022 reflects 2024 (119th Congress) boundaries. For 7 states with substantial 2025 redistricting (CA, FL, MO, NC, OH, TX, UT), these boundaries no longer match the 2026 reality, so the PUMA × CD crosswalk is rebuilt from scratch using the same methodology Geocorr uses internally: aggregating official block-level CD assignments up through the geographic hierarchy with population weighting.

#### The geographic chain

The build follows the natural hierarchy of Census geography:
Block  →  Tract  →  PUMA  →  CD

- **Blocks** are the smallest Census geographic unit (typically a city block) with known 2020 population
- **Tracts** are groups of blocks and nest cleanly within PUMAs
- **PUMAs** are groups of tracts (~100,000+ people each) and are the geographic resolution at which ACS PUMS data is published
- **CDs** are independent of all the above — their boundaries don't align with PUMA boundaries

The state BAF tells us which 2026 CD each block belongs to. Combined with block populations, this lets us compute the population share of each PUMA-CD intersection.

#### Pipeline (per state)

1. **Load the BAF** — Each state's official Block Assignment File lists every 2020 Census block in the state with its 2026 CD assignment
2. **Pull block populations** — Use `tidycensus::get_decennial()` to retrieve 2020 Census P1_001N (total population) for every block in the state
3. **Join BAF to populations** — Each block now has both a CD assignment and a population
4. **Aggregate to (tract × CD)** — For each tract-CD intersection, sum the block populations. This captures how a tract's population is split when CD boundaries cut through it.
5. **Join to PUMA** — Use the Census Bureau's 2020 Tract-to-PUMA relationship file. Tracts nest completely within PUMAs, so this is a deterministic one-to-one lookup.
6. **Aggregate to (PUMA × CD)** — Sum the (tract × CD) intersection populations within each PUMA × CD combination
7. **Compute afact** — For each PUMA × CD row:
afact = pop_intersection / puma_pop

This is the fraction of the PUMA's population that lives in the part overlapping with this CD.

#### The afact concept (worked example)

Suppose PUMA 4801 has a total population of 200,000, distributed as follows after the block-level aggregation:
- 140,000 people in the portion overlapping CD 7
- 60,000 people in the portion overlapping CD 8

The afact values would be:

| PUMA | CD | afact | Meaning |
|---|---|---|---|
| 4801 | 7 | 0.70 | 70% of PUMA 4801's population is in CD 7 |
| 4801 | 8 | 0.30 | 30% of PUMA 4801's population is in CD 8 |

The afact values sum to 1.0 for every PUMA — every person in the PUMA is accounted for across the CDs it overlaps.

This is the same definition Geocorr uses for its afact column, so the unified crosswalk in Stage 3 can use either source interchangeably.

#### Why this matters for the PUMS join

The ACS PUMS data identifies each person's PUMA but not their congressional district. For PUMAs that lie entirely within one CD, there's no ambiguity. For PUMAs that span multiple CDs, the afact values support probabilistic assignment: a person with PERWT = 100 in PUMA 4801 contributes 70 statistical persons to CD 7 and 30 to CD 8, reflecting where people in that PUMA actually live geographically.

(The join itself is covered in Script 05; this stage produces the lookup table the join uses.)

#### Helper function

A single function `build_state_puma_cd_crosswalk()` handles all 7 states, with auto-detection of BAF file formats. Per-state calls supply: BAF path, state abbreviation, state FIPS, BAF column names, and delimiter/header information.

#### Helper function — full pseudocode

The `build_state_puma_cd_crosswalk()` function executes the pipeline (above) for one state at a time. Inputs configure how the BAF is read; the pipeline itself is identical across states.

**Function signature**:

```r
build_state_puma_cd_crosswalk(
    baf_path,              # path to state's BAF file
    state_abb,             # 2-letter postal code (e.g., "CA")
    state_fips,            # 2-digit FIPS as character (e.g., "06")
    baf_block_col,         # name of block GEOID column in BAF
    baf_district_col,      # name of CD column in BAF
    baf_delim = ",",       # delimiter for CSV (CSVs only)
    baf_has_header = TRUE, # whether BAF has a header row
    output_dir = ".",      # where to save RDS
    log_file = NULL        # optional log file for diagnostic output
)
```

**Pipeline (executed when called)**:

**Step 1 — Read BAF**: Auto-detect format from file extension. For `.xlsx`/`.xls`, use `readxl::read_excel()` with all columns as character. For CSV, use `readr::read_delim()` with the specified delimiter and header treatment. Rename block-ID and district columns to the standardized `block_geoid` and `district`; coerce district to integer.

**Step 2 — Pull block populations**: Call `tidycensus::get_decennial()` with `geography = "block"`, `variable = "P1_001N"` (total population), `year = 2020`, `sumfile = "pl"` (PL 94-171 redistricting file), `state = state_abb`. Returns one row per block with population.

**Step 3 — Join BAF to block populations**: `inner_join()` by block GEOID. Each block now has both a 2026 CD assignment and a 2020 population.

**Step 4 — Aggregate to (tract × CD)**: For each combination of (tract_geoid, district), sum the block populations. The tract GEOID is the first 11 characters of the 15-character block GEOID. Output: one row per (tract × CD) intersection with `pop_in_intersection` and `n_blocks`.

**Step 5 — Join tract → PUMA**: `inner_join()` to `tract_to_puma_clean` (filtered to the relevant state's FIPS). Tracts nest cleanly within PUMAs, so this is one-to-one. After the join, each (tract × CD) row has a PUMA assignment.

**Step 6 — Aggregate to (PUMA × CD)**: Group by (state, puma, cd_new), sum the intersection populations. Within each (state, puma) group, sum across CDs to get total PUMA population, then compute `afact = pop_intersection / puma_pop`.

**Step 7 — Validate**: Check that afact sums to 1.0 per PUMA (within rounding). Report the range of sums and count any deviations. Print the distribution of CDs per PUMA.

**Step 8 — Save**: Write the result as `{state_abb_lowercase}_puma_cd_crosswalk.rds` in `output_dir`.

**Returns**: The PUMA × CD data frame (in addition to saving it to disk).




#### Validation per state

Each state's crosswalk passes through automated checks:

| Check | Pass criterion |
|---|---|
| Block records match | All BAF blocks join cleanly with tidycensus population data |
| State population total | Matches 2020 Decennial Census state total |
| CD count | Matches state's known House delegation size |
| afact sums to 1.0 | Per PUMA, within floating-point rounding tolerance |
| Distribution of CDs per PUMA | Reported as sanity check (most PUMAs span 1-3 CDs) |

#### Per-state validation summary

| State | FIPS | 2020 Pop | Blocks | PUMAs | CDs | Notes |
|---|---|---|---|---|---|---|
| Texas | 48 | 29,145,505 | ~290k | ~290 | 38 | Highest split rate; many urban PUMAs split across 4+ CDs |
| California | 06 | 39,538,223 | 519,723 | 281 | 52 | Highest split rate (47% across 2 CDs); 1 PUMA spans 6 CDs |
| Missouri | 29 | 6,154,913 | 253,632 | 47 | 8 | One Kansas City PUMA spans 4 CDs |
| North Carolina | 37 | 10,439,388 | 236,638 | 76 | 14 | 50% of PUMAs in single CD |
| Ohio | 39 | 11,799,448 | 276,428 | 90 | 15 | Cleanest split rate (53% single-CD) |
| Utah | 49 | 3,271,616 | 71,207 | 23 | 4 | Court-imposed map; even 50/50 split rate |
| Florida | 12 | 21,538,187 | 390,066 | 168 | 28 | Includes some 4-CD PUMAs |

#### Note on Virginia

Virginia's 2025 redistricting amendment is facing legal challenges. Will need to be create a redistricting allocation for VA if redistricting is approved, but as of now we stick to the 2024 boundaries.

#### Outputs

Seven state-specific RDS files, each with columns:

| Column | Type | Description |
|---|---|---|
| state | chr | 2-digit FIPS as character |
| puma | chr | 2020 PUMA code |
| cd_new | int | 2026 CD number |
| pop_intersection | num | 2020 population in PUMA × CD intersection |
| puma_pop | num | Total 2020 population of PUMA |
| afact | num | Fraction of PUMA's population in this CD |

These are merged with the Geocorr file in Stage 3.


### Stage 3 — Merge into a unified national crosswalk

The Stage 1 Geocorr crosswalk covers all states with 2024 (119th Congress) boundaries. The Stage 2 state-specific crosswalks cover the 7 redistricted states with 2026 boundaries. Stage 3 merges these into a single national crosswalk by replacing the Geocorr rows for the 7 redistricted states with the new BAF-derived versions.

#### Why merge to a single crosswalk

An alternative approach would have been to keep two separate crosswalks and apply them sequentially to the PUMS data — Geocorr first, then redo the join for the 7 redistricted states. The single-merged approach was chosen instead because:

1. **Single source of truth** — One unified file captures the full national PUMA→CD mapping. Easier to save, audit, share, and reuse.
2. **Cleaner validation** — Allows national-level checks (every PUMA sums to afact = 1.0, total CD count = 435 + DC) rather than partial checks across pieces.
3. **Future updates are simpler** — When boundaries change (e.g., Virginia's legal situation resolves, future states redistrict), update rows in the unified crosswalk and rejoin once.
4. **Less compute waste** — The PUMS join runs once with the final crosswalk rather than twice (old, then patched).

#### Pipeline

**Step 1: Load and standardize the 7 state-specific crosswalks**

Each state-specific file has columns: `state` (chr), `puma` (chr), `cd_new` (int), `pop_intersection` (num), `puma_pop` (num), `afact` (num).

Standardize to match Geocorr's structure:

| State files (Stage 2) | Geocorr (Stage 1) | Action |
|---|---|---|
| state (chr) | state (int) | Coerce to integer |
| puma (chr) | puma22 (int) | Coerce to integer, rename to puma22 |
| cd_new (int) | cd119 (int) | Rename to cd119 |
| afact (num) | afact (num) | Keep as-is |
| pop_intersection, puma_pop | (not present) | Drop |

This produces 1,705 rows across the 7 redistricted states.

**Step 2: Filter Geocorr to non-redistricted states**

Remove rows where `state %in% c(48, 6, 29, 37, 39, 49, 12)` (TX, CA, MO, NC, OH, UT, FL). The remaining 2,463 rows cover 43 stable states + DC + PR.

**Step 3: Append**

`bind_rows()` the trimmed Geocorr with the standardized new-state data. Result: 4,168 rows covering 52 jurisdictions.

**Step 4: Drop Puerto Rico**

PR has no voting House representation and is not present in the ACS PUMS extract. Remove `state == 72`. This eliminates 24 PR rows, leaving 4,144 rows across 51 jurisdictions.

#### Validation findings

After the merge:

| Check | Result | Pass? |
|---|---|---|
| Total rows | 4,144 | ✓ (2,439 stable + 1,705 redistricted, minus 24 PR) |
| Unique states | 51 | ✓ (50 + DC) |
| Unique state+CD combinations | 436 | ✓ (435 voting House districts + DC delegate) |
| Unique PUMAs (state+puma22) | 2,486 | ✓ Unchanged from Geocorr — redistricting doesn't change PUMAs |
| afact sum range per PUMA | 0.9999 to 1.0001 | ✓ Rounding-tolerance, identical pattern to original Geocorr |
| PUMAs with afact != 1.0 (exact) | 37 | All within rounding tolerance — floating-point artifacts |

The 37 PUMAs with afact != 1.0 are decimal-precision artifacts, not data errors. The original Geocorr file had 72 such PUMAs for the same reason. Sums in the 0.9999-1.0001 range are not meaningful deviations.

#### Note on column naming

We do a column renaming at the end to rename cd119 to cd_2026. The column contains
- For 43 stable states + DC: the 2024 (119th Congress) CD codes (which are also the 2026 codes since boundaries didn't change)
- For 7 redistricted states (TX, CA, MO, NC, OH, UT, FL): the new 2026 CD codes from the state BAFs


#### Output file

`unified_crosswalk_2026.rds` — saved to `/Users/binampoudyal/Downloads/` (file path to be standardized when the pipeline is reorganized for GitHub). Used by Script 05 as the input for the PUMS-to-CD join.
