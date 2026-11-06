## Script 08
### Purpose: CES geographic audit and prep inputs for the ZCTA crosswalk

For CES respondents in the 43 states with stable boundaries, the `cdid119` column gives a 2026-valid CD assignment directly. For respondents in the 7 redistricted states (CA, FL, MO, NC, OH, TX, UT), `cdid119` reflects 2024 boundaries that no longer match 2026. This script does the prep work for fixing those assignments via a ZCTA-based crosswalk (built in Script 09).

### Why ZCTA-based assignment

Three CES geographic identifiers were considered for assigning 2026 CDs in redistricted states:

| Identifier | Coverage | Limitation |
|---|---|---|
| `cdid119` | Universal | Reflects 2024 boundaries; wrong for redistricted states |
| `countyfips` | Universal | Most large counties span multiple CDs (confirmed in diagnostics) |
| `lookupzip` | Universal (~100% in CES) | ZIP boundaries don't align with CD boundaries either, but Census's ZCTA-block file enables population-weighted disaggregation |

ZCTA-based assignment is the lowest geographical identifier available in the CES which allows us to map respondents to CDs so we used that. The crosswalk itself is built in Script 09.

### 1. CES geographic identifier audit

Diagnostics check class, sample values, distinct counts, and NA rates for four CES geographic columns: `inputstate`, `cdid119`, `inputzip`, `countyfips`. All four are essentially universally populated in the CES 2024 Common Content.

### 2. Load and combine BAFs

The same 7 BAFs used in Script 04 are reloaded inline (file formats handled per state) and combined into a single `all_bafs` table with columns `block_geoid`, `district`, `state_fips`. The combine makes the downstream ZCTA work simpler — one input instead of seven.

BAF sources are identical to those listed in the Script 04 methodology (Redistricting Data Hub and MSDIS).

### 3. County-split and ZIP availability diagnostics

#### County-split diagnostic

For each state's BAF, the script counts how many CDs each county touches. A county wholly within one CD permits clean county-based CD assignment; counties spanning multiple CDs are ambiguous.

Then for CES respondents in each redistricted state, the script tags each respondent with the split-scenario of their county:

| Scenario | Meaning |
|---|---|
| Clean (1 CD) | County wholly within one CD; county-based assignment works |
| 2 CDs | County split between two CDs |
| 3 CDs | County split between three CDs |
| 4-9 CDs | County split between 4–9 CDs (mid-size urban counties) |
| 10+ CDs (LA County) | County split across 10+ CDs (only Los Angeles County) |
| Unmatched | CES respondent's county doesn't appear in BAF |

The breakdown shows that the majority of CES respondents in redistricted states live in counties that span multiple CDs. This confirms that county-based assignment would lose significant CD-level resolution; ZCTA-based assignment is necessary, not just preferable.

#### ZIP availability

Several CES columns capture ZIP information at different stages and from different sources:

| Column | Source |
|---|---|
| `inputzip` | Respondent-entered ZIP at pre-election wave |
| `inputzip_post` | Respondent-entered ZIP at post-election wave |
| `regzip` | ZIP from voter registration record (pre-wave) |
| `regzip_post` | ZIP from voter registration record (post-wave) |
| `lookupzip` | ZIP from YouGov's geocoder validation (pre-wave) |
| `lookupzip_post` | ZIP from YouGov's geocoder validation (post-wave) |

Diagnostics on NA rates show `lookupzip` has the cleanest coverage. The crosswalk in Script 10 uses `lookupzip` for two reasons: (1) it's the most complete column, and (2) YouGov has already validated it against a ZIP→county lookup table, reducing the risk of typos or invalid ZIPs.

### 4. Load ZCTA-block relationship file and block populations

#### ZCTA-Block relationship file

A nationwide Census Bureau file mapping every 2020 Census block to its containing ZCTA. Loaded with `data.table::fread()` for speed (~8M rows nationally), with only the two needed columns selected. Blocks without a ZCTA assignment (uninhabited blocks, water-only areas) are dropped. Finally filtered to the 7 redistricted states by matching the first 2 digits of the block GEOID.

Source: U.S. Census Bureau, 2020 Census Relationship Files
URL: https://www.census.gov/geographies/reference-files/time-series/geo/relationship-files.2020.html
File: `tab20_zcta520_tabblock20_natl.txt`

#### 2020 Census block populations

Pulled via `tidycensus::get_decennial()` for each of the 7 states (variable P1_001N from the PL 94-171 redistricting file). Same data source as Script 04 Stage 2; re-pulled here for self-contained execution.

API key needed: tidycensus requires a free U.S. Census Bureau API key (set once via `census_api_key()` and persisted in `.Renviron`). Same setup as Script 04.

### Outputs

All three loaded objects are in-memory inputs to Script 09:

| Object | Description |
|---|---|
| `all_bafs` | Combined block-to-CD assignments for all 7 states |
| `zcta_block_redistricted` | ZCTA-to-block relationships filtered to 7 states |
| `all_blocks_pop` | 2020 block populations for 7 states |

No disk write at the end of Script 08 since all three feed directly into the Script 09 crosswalk build (and these scripts share a single R file for that reason).

### Inputs

From Script 08 (in-memory):

| Object | Description |
|---|---|
| `all_bafs` | Combined block-to-CD assignments for 7 redistricted states |
| `zcta_block_redistricted` | Census ZCTA-to-block relationships filtered to 7 states |
| `all_blocks_pop` | 2020 Census block populations for 7 states (via tidycensus) |

### Output

`zcta_cd_crosswalk_redistricted.rds`:

| Column | Type | Description |
|---|---|---|
| state_fips | character | 2-digit state FIPS code |
| zcta | character | 5-digit ZCTA code |
| cd_new | integer | 2026 CD code |
| pop_intersection | numeric | 2020 population in this ZCTA × CD intersection |
| zcta_pop | numeric | Total ZCTA population (sum across CDs) |
| afact | numeric | pop_intersection / zcta_pop (allocation factor) |

### Pipeline steps

1. **Join block-level data**: Inner-join the BAF (`block_geoid` → district), ZCTA file (`block_geoid` → zcta), and population file (`block_geoid` → pop). Each remaining block has all three pieces. Inner joins drop blocks not present in all three sources (mainly uninhabited blocks with no ZCTA assignment).

2. **Aggregate to ZCTA × CD level**: Group by (state_fips, zcta, cd_new) and sum block populations within each (ZCTA × CD) intersection. A ZCTA wholly within one CD has one row; a ZCTA split across N CDs has N rows.

3. **Compute afact**: Within each ZCTA, sum `pop_intersection` to get `zcta_pop`, then compute `afact = pop_intersection / zcta_pop`. afact values for a ZCTA sum to 1.0 across its CDs (validated next step).

4. **Initial validation**: Confirm afact sums per ZCTA. Initial run reveals NaN values caused by zero-pop ZCTAs (division by zero) — handled in section 6.

5. **Distribution diagnostic**: Count the number of CDs each ZCTA touches, broken down by state. This is the key diagnostic for the CES geography problem: if most ZCTAs nest cleanly in one CD, the fractional allocation is minimal and ZCTA-based assignment is nearly as good as precise individual-level assignment.

6. **Handle zero-pop ZCTAs**: Some ZCTAs exist geographically but contain only zero-population blocks. These cause `zcta_pop = 0` and NaN afact values. Drop them and re-validate. Real CES respondents shouldn't appear in these ZCTAs since YouGov validates `lookupzip` against actual residence, but a small number may from business-address registrations or stale geocoder hits (handled via cdid119 fallback in Script 10).

7. **Check CES respondents in dropped ZCTAs**: Diagnostic count of how many CES respondents in redistricted states have `lookupzip` values in dropped zero-pop ZCTAs. This is the count of respondents who'll fall back to `cdid119` in Script 10.

8. **Save**: Write the validated, zero-pop-handled crosswalk to `zcta_cd_crosswalk_redistricted.rds`.

### Validation findings

After zero-pop handling:
- afact sums to 1.0 per ZCTA (within floating-point rounding, ~10^-15)
- Zero ZCTAs with afact ≠ 1.0

### Note on the zero-pop ZCTA edge case

A ZCTA can exist as a polygon but contain only zero-population blocks. This happens for:
- ZIPs that are entirely commercial (no residences)
- PO Box-only ZIPs (no associated geographic area)
- ZIPs overlapping mainly water or industrial land

These were initially included by the aggregation logic but cause NaN values when normalizing. Section 6 drops them. The downstream CES join in Script 10 handles affected respondents via fallback to `cdid119`.

### Note on duplication with Script 04

Block populations are pulled via tidycensus in both Script 04 (Stage 2, for PUMA → CD) and Script 08 (for ZCTA → CD). Same Census data source (PL 94-171, variable P1_001N). Re-pulling makes each script section independently runnable. Within this combined file (Scripts 08-10), the data is loaded once in Script 08 and shared across all three.


## Script 10
### Purpose: Apply ZCTA crosswalk to CES and finalize geographic alignment

This script produces the geographic identifiers used downstream by every CD-level modeling step. After this script, CES and PUMS both have a `state_cat` and `cd_cat` column that can be joined or aggregated against.

### Inputs

| Object | Source |
|---|---|
| `ces` | `ces_harmonized.rds` (Script 07) |
| `pums_crosswalked` | `pums_crosswalked_harmonized.rds` (Script 07) |
| `zcta_cd_crosswalk` | `zcta_cd_crosswalk_redistricted.rds` (Script 09) |
| `zcta_block` | Census ZCTA-block file (Script 08, in-memory only) |

### Outputs

Both files overwrite the Script 07 versions:
- `ces_harmonized.rds` — with new columns: `cd_2026`, `afact`, `state_cat`, `cd_cat`
- `pums_crosswalked_harmonized.rds` — with new columns: `state_cat`, `cd_cat`

### Assignment logic

For each CES respondent:

| Respondent's state | Method | Result |
|---|---|---|
| Non-redistricted (43 states + DC) | `cd_2026 = cdid119`, `afact = 1.0` | One row per respondent |
| Redistricted, lookupzip in crosswalk | Inner join `lookupzip` to ZCTA crosswalk | 1+ rows per respondent (one per CD their ZCTA spans), with afact weights |
| Redistricted, lookupzip NOT in crosswalk | `cd_2026 = cdid119`, `afact = 1.0` | One row per respondent (fallback) |

The three subsets are bound together with `bind_rows()` into a single dataset (`ces_with_cd`).

### Pipeline steps

1. **Stable-state respondents** (Section 1): Filter CES to non-redistricted states; copy `cdid119` to `cd_2026`; set `afact = 1.0`.

2. **Redistricted-state respondents — ZCTA join** (Section 2): Filter CES to redistricted states; `inner_join()` to the ZCTA crosswalk on `lookupzip` ↔ `zcta`. Respondents whose ZCTA spans multiple CDs are duplicated across rows, one per CD, weighted by `afact`.

3. **Unmatched redistricted respondents — fallback** (Section 3): Filter CES to redistricted states; `anti_join()` against the same crosswalk to find respondents whose `lookupzip` doesn't appear; assign `cd_2026 = cdid119`, `afact = 1.0`.

4. **Combine and validate** (Section 4): Bind the three subsets. Validate that afact sums to 1.0 per respondent (i.e., the population contribution is preserved), no `cd_2026` is NA, and distinct caseids match the original CES count.

5. **Fallback respondent diagnostics** (Section 5): Examine which ZIPs the fallback respondents are using. Break down by state and ZIP. Cross-reference with the full ZCTA file to distinguish two cases:
   - ZIPs that ARE valid ZCTAs (dropped in Script 09 as zero-pop)
   - ZIPs that aren't ZCTAs at all (PO Box, business-only addresses)
   
   Most fallback respondents fall into the zero-pop ZCTA bucket. For both cases, the fallback to `cdid119` is the best available estimate since the respondent's actual residence is unknown.

6. **Create state_cat and cd_cat** (Section 6): Both datasets get standardized integer columns:
   - PUMS: `state_cat = STATEFIP`, `cd_cat = cd_2026`
   - CES: `state_cat = inputstate`, `cd_cat = cd_2026`
   
   An alignment check between PUMS and CES reveals two systematic mismatches (handled in Section 7):
   - At-large state CD codes differ (PUMS = 0, CES = 1)
   - DC encoding differs (PUMS cd = 98, CES cd = 1)

7. **Handle at-large states and DC** (Section 7): See "Encoding decisions" below. After fixes, re-validate alignment.

8. **Final summary and save** (Section 8): Confirm expected coverage (435 voting House CDs in both datasets) and save the updated files.

### Encoding decisions

**At-large states** (AK, DE, ND, SD, VT, WY — each has one CD):

| | CD code | Origin |
|---|---|---|
| PUMS | `cd = 0` | Geocorr convention |
| CES | `cd = 1` | Standard convention |

Decision: recode PUMS `cd_cat = 0 → 1` to match CES. The choice to standardize on `1` is because that's what CES uses and changing CES would be more invasive (touches the modeling side rather than just the population frame).

**DC**:

| | State + CD codes |
|---|---|
| PUMS (Geocorr) | `state = 11`, `cd = 98` (non-voting delegate) |
| CES | `state = 11`, `cd = 1` |

Decision: drop DC entirely from both datasets. DC has a non-voting House delegate, not a regular House seat, so it has no place in a 435-CD prediction frame. This affects ~110 CES respondents and a small number of PUMS rows; neither group is needed downstream.

### Validation findings

After all sections:

| Check | Result |
|---|---|
| Distinct CES respondents | ~60,000 (matches Script 07 minus DC) |
| Row inflation factor | ~1.13 (small share of respondents in split ZCTAs) |
| afact sum per respondent | 1.0 ± rounding |
| Missing `cd_2026` | 0 |
| PUMS unique state+CD combos | 435 |
| CES unique state+CD combos | 435 |
| Alignment mismatches between PUMS and CES | 0 |

The row inflation factor (~1.13x) is much lower than the PUMS inflation in Script 05 (~1.68x), because ZCTAs are smaller geographic units than PUMAs and split across CDs less often.

### Note on the row-level structure

After this script, CES respondents in split ZCTAs are represented as multiple rows. Downstream modeling needs to either:
- Use `afact` as a survey weight multiplier (i.e., `weight × afact`)
- Or collapse rows per respondent before fitting models

The same logic applies to PUMS rows that were duplicated in Script 05. The afact column is the bridge that ensures population shares are preserved across the geography assignment.

### Note on `cdid119` for stable states

For stable-boundary states, `cdid119` is used directly as `cd_2026`. This is correct because the 119th Congress CD codes are the same as the 2026 codes for these states (their boundaries didn't change between the 2024 and 2026 elections). For the 7 redistricted states, this is not true — hence the ZCTA crosswalk for those states only.

### Final outputs on disk

After Script 10, both files in `Stratification_Frame_Building/` represent the geographic-aligned versions of the harmonized data:
ces_harmonized.rds

69,020 CES respondents → ~68,920 after DC drop → ~78,000 rows after ZCTA split
All harmonized variables (age_cat, gender_cat, educ_cat, hispanic_cat, race_cat)
Geographic identifiers (state_cat, cd_cat, cd_2026, afact)

pums_crosswalked_harmonized.rds

~20.6M rows, covers all 50 states
All harmonized variables
Geographic identifiers (state_cat, cd_cat, PERWT_adj)
