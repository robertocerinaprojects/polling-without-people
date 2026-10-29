## Script 12
### Purpose: Renumber fallback CES respondents' cd_2026

In Script 09, ~59 CES respondents in redistricted states had their `lookupzip` fail to resolve to a populated ZCTA (PO Box ZIPs, business-only ZIPs, military addresses, or zero-population ZCTAs). Script 10 assigned these respondents `cd_2026 = cdid119` as a fallback. For some, this is approximately correct (the underlying area kept the same CD number under 2026 boundaries). For others, the CD got renumbered and `cdid119` is stale.

Script 12 refines these fallback assignments using a CD119 → CD2026 renumbering heuristic: assume each old CD's geographic area now lies majority in the new CD with the largest population overlap.

### Per Roberto's guidance

This is an approximate fix. The overlap is often partial (<90% in many cases), but it's better than blindly trusting `cdid119`. The approach is: *"if we don't know for a fact, assume the majority overlap."*

The fix only affects fallback respondents. Non-fallback respondents — those assigned via the ZCTA crosswalk in Script 10, or those in stable-boundary states — are unchanged.

### Two sub-scripts

**Script 12A** builds the renumbering map: for each (state, cd_119), find the cd_2026 with the largest population overlap.

**Script 12B** applies the map: for each fallback CES respondent, update their cd_2026 from `cdid119` to the remapped 2026 value.

### Inputs

| Source | Used by | Description |
|---|---|---|
| `NationalCD119.txt` | 12A | Census Bureau 119th Congress BAF: block → 2024 CD assignment |
| `all_bafs` (in-memory) | 12A | Combined state BAFs from Script 08: block → 2026 CD assignment |
| `all_blocks_pop` (in-memory) | 12A | 2020 Census block populations from Script 08 |
| `ces_with_cd` (in-memory) | 12B | CES respondents with Script 10's cd_2026 assignment |
| `zcta_cd_crosswalk` (in-memory) | 12B | ZCTA crosswalk from Script 09 (used to identify fallback respondents) |
| `pums_crosswalked` (in-memory) | 12B | PUMS data, used only for alignment check |

### Output

`ces_with_cd_v2.rds` — CES respondents with corrected `cd_2026` for fallback respondents. All other columns are unchanged. Used as the canonical CES file by all downstream scripts.

### Methodology

#### Script 12A — Build the renumbering map

**Step 1**: Load the national 119th Congress BAF (`NationalCD119.txt`) — a single file mapping every Census block to its 2024 CD.

**Step 2**: Filter to the 7 redistricted states. Drop "ZZ" entries (uninhabited blocks with no CD assignment).

**Step 3**: Inner-join three block-level datasets:
- Block → CD119 (from this script's load)
- Block → CD2026 (from `all_bafs`, originally built in Script 04 Stage 2)
- Block → 2020 population (from tidycensus, loaded in Script 08)

Inner joins drop blocks not present in all three sources.

**Step 4**: For each (state, cd_119, cd_2026) intersection, sum block populations. Then for each (state, cd_119), pick the cd_2026 with the largest overlap. This is the population-weighted majority mapping.

The result is a lookup table: for each old CD in each redistricted state, the 2026 CD that contains the largest share of its 2020 population.

**Step 5**: Diagnostics. Print the full renumbering map. Flag cases where the overlap is <90% (i.e., the old CD got split substantially). These low-overlap cases are still mapped to their majority new CD — Roberto's guidance accepts this as the best available heuristic.

#### Script 12B — Apply the renumbering map

**Step 6**: Prepare the lookup for joining to CES — coerce `state_fips` to integer and rename `cd_2026` to `cd_2026_remapped` to avoid colliding with the existing column in CES.

**Step 7**: Apply renumbering to fallback respondents:

1. **Flag fallback respondents**: A respondent is fallback if they're in a redistricted state AND their `lookupzip` doesn't appear in the ZCTA crosswalk.

2. **Left-join the lookup** on `(inputstate, cdid119)`. For non-fallback respondents, the join still runs but the result is conditionally ignored.

3. **Conditional update**: Use `if_else` to update `cd_2026` only when the row is fallback AND a remapping exists:
```r
   cd_2026 = if_else(
     is_fallback & !is.na(cd_2026_remapped),
     as.integer(cd_2026_remapped),
     as.integer(cd_2026)
   )
```
   Non-fallback respondents and fallback respondents with no remapping (which shouldn't happen but is defended against) keep their existing `cd_2026`.

4. **Cleanup**: Drop the helper columns (`is_fallback`, `cd_2026_remapped`).

**Step 8**: Verification and save.

### Validation

| Check | Expected |
|---|---|
| Total rows in `ces_with_cd` | Unchanged from Script 10 |
| Unique respondents (`caseid`) | Unchanged from Script 10 |
| afact sums per respondent | 1.0 ± rounding |
| CDs in CES but not in PUMS | 0 |
| CDs in PUMS but not in CES | 0 |

Row count and respondent count are preserved because the update only modifies cell values, never adds or removes rows. The alignment check between PUMS and CES confirms that the renumbered CD codes still match valid PUMS CDs (no orphaned codes introduced).

### Limitations

This fix uses a population-overlap heuristic to renumber a small number of respondents whose actual residence is unknown. The corrected `cd_2026` represents a best guess based on aggregate geography, not a precise individual-level assignment. The overlap is sometimes partial — in cases where the old CD was split substantially across multiple new CDs, the majority overlap may not exceed 50%. Despite this, the approach is preferable to leaving `cdid119` in place, because:

- For respondents whose CD genuinely kept the same number, the renumbering map will assign that same number (overlap close to 100%)
- For respondents whose CD got renumbered, the lookup picks the most likely new CD based on where most of the old CD's population now lives

The number of respondents affected is small (~59 of ~60,000, or <0.1%), so any uncertainty introduced is bounded.

### Why this script lives between geographic alignment and variable construction

Scripts 04, 05, 08, 09, 10, and 12 are all geographic in nature. Script 12 is the final geographic-cleanup step. Subsequent scripts assume `cd_2026` is final and move on to variable construction (e.g., `vote_2024` in Script 13). This keeps all geographic logic in one consolidated phase of the pipeline.

### Output file

`ces_with_cd_v2.rds` is saved to `Stratification_Frame_Building/`. The original `ces_harmonized.rds` from Script 10 remains on disk as a record of the pre-renumbering version. All scripts after Script 12 use `ces_with_cd_v2.rds` as their canonical CES input.