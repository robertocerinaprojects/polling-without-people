## Scripts 18A / 18B / 18C
### Purpose: Build the CD-level training table for the CART inheritance model

This three-script sequence assembles the CD-level training table that feeds into the CART model. Each row is one of the 435 CDs, with demographic proportions, state-level presidential features, 2024 House vote shares, and modeling flags. The three scripts share a single R file since they operate on shared in-memory objects.

### Pipeline overview

| Script | Purpose | Input | Output |
|---|---|---|---|
| 18A | Build inheritance table | Block-level data | `cd_2026_inheritance.rds` |
| 18B | Assemble base training table | Three CD-level files | `training_table.rds` (base) |
| 18C | Refine flags + add contestation | Base training table + inheritance | `training_table.rds` (final) |

Final training_table has:
- 435 rows (one per CD)
- ~29 demographic feature columns (pct_age_*, pct_male, etc.)
- 4 state-level presidential feature columns
- 4 outcome columns (dem_share, rep_share, other_share, no_vote_share)
- Modeling flags: is_redistricted, contestation, training_eligibility

End-to-end row counts:
- **training_set**: ~318 CDs (all stable-state CDs + ~42 essentially-unchanged in redistricted states)
- **prediction_set**: ~117 CDs (genuinely new geography in redistricted states)

---

## Script 18A
### Purpose: Identify essentially-unchanged 2026 CDs in redistricted states

Not every district in the 7 redistricted states was substantially redrawn. Many were renumbered slightly, shifted at the margins, or left effectively unchanged. Treating all 159 CDs in the 7 states as "redistricted" throws away information about those whose populations are effectively the same as in 2024. This script identifies which 2026 CDs are essentially-unchanged from a single 2024 CD, so they can inherit their 2024 result and enter the training set.

### Inputs (in-memory from Script 08)
- `all_bafs`: block → cd_2026 (from state BAFs)
- `cd119_redistricted`: block → cd_119 (from Script 12)
- `all_blocks_pop`: block → 2020 population (from tidycensus)

### Output
- `cd_2026_inheritance.rds` — one row per 2026 CD in the 7 states:

| Column | Description |
|---|---|
| state_fips | State FIPS code (character) |
| cd_2026 | 2026 CD number |
| dominant_cd_119 | The 2024 CD number that contributed the largest population share |
| overlap_pct | Fraction of new CD's population from the dominant 2024 CD |
| essentially_unchanged | Boolean: `overlap_pct >= 0.95` |
| cd_2026_total_pop | Total population of the 2026 CD |

### Methodology

For each block in the 7 redistricted states, we know:
- Its 2026 CD (from state BAFs, built in Script 04)
- Its 2024 CD (from the National CD119 BAF, loaded in Script 12)
- Its 2020 population (from tidycensus, loaded in Script 08)

The pipeline aggregates this block-level data:

1. **Block-level join**: Inner-join the three sources on `block_geoid`. Each remaining block has (state_fips, cd_2026, cd_119, pop).

2. **Population intersections**: For each `(state_fips, cd_2026, cd_119)` combination, sum block populations. This gives "how many people in new CD X came from old CD Y."

3. **Dominant source per new CD**: For each `(state_fips, cd_2026)`, find the row with the largest intersection population. This is the dominant source 2024 CD.

4. **Overlap percentage** ("new-CD-side"):

overlap_pct = pop_intersection / cd_2026_total_pop

This asks: "Of the people now in this new CD, what fraction came from the dominant old CD?" A value of 0.95+ means the new CD is essentially the old CD (possibly with a different number). A value of 0.60 means it's substantially different from any single old CD.

5. **Flag**: `essentially_unchanged = overlap_pct >= 0.95`

### Threshold choice: 95%

The 0.95 threshold identifies CDs whose 2026 boundaries preserve at least 95% of a single 2024 CD's population. Below this threshold, the CD has enough new population that inheriting the old vote result would introduce meaningful noise. Above 0.95, the population overlap is high enough that the CD's demographic character is effectively unchanged.

### Symmetry validation

For essentially-unchanged CDs, forward overlap ("what fraction of the new CD came from the dominant old CD") should approximately equal reverse overlap ("what fraction of the dominant old CD ended up in the new CD"). Under equal-population constraints, these are mathematically identical.

The script computes both and reports the absolute difference. Empirically, differences are typically <0.02 percentage points (floating-point noise), confirming the inheritance mapping is well-behaved: an essentially-unchanged CD in one direction is essentially-unchanged in the reverse direction too.

### Findings

- Total 2026 CDs across 7 states: ~159
- Essentially-unchanged (overlap >= 0.95): ~42
- Substantially redrawn (overlap < 0.95): ~117

The distribution varies by state — e.g., some states redrew every CD (all 117 in one bucket), while others left many CDs largely intact.

---

## Script 18B
### Purpose: Assemble base training table

Combine `cd_demographics`, `cd_house_2024`, and `state_pres_2024` into a single CD-level table. This is the base version, before contestation and inheritance-refined flags are added in 18C.

### Inputs
- `cd_demographics.rds` (Script 15): 435 CDs with ~29 demographic proportions + cd_pop
- `cd_house_2024.rds` (Script 16): 435 CDs with 4 vote shares against cd_pop
- `state_pres_2024.rds` (Script 17): 50 states with 4 shares against CVAP

### Output
- `training_table.rds` (base version): 435 rows, ~40 columns

### Join architecture

cd_demographics (435 rows)
│
│ left_join by state_cd
▼

cd_house_2024 (435 rows, 4 outcome shares)
│
│ left_join by state_abbrv
▼
state_pres_2024 (50 rows, 4 state-level pres features)
│
▼
training_table (435 rows)

### Column selection

Final base table has these columns:

| Category | Columns |
|---|---|
| Identifiers / flags | state_cd, state_abbrv, cd_pop, is_redistricted |
| Demographic predictors (~29) | pct_age_*, pct_male, pct_female, pct_race_*, pct_hisp_*, pct_educ_* |
| State-level pres predictors (4) | state_pres_dem_share, state_pres_rep_share, state_pres_other_share, state_pres_no_vote_share |
| Outcomes (4) | dem_share, rep_share, other_share, no_vote_share |

### Preliminary is_redistricted flag

At this stage, `is_redistricted = TRUE` for all CDs in the 7 redistricted states (all 159 of them). Script 18C refines this by looking at whether each specific CD is essentially unchanged from a 2024 CD.

### Validation

Three sanity checks:
- Outcomes sum to 1 per CD (within floating-point tolerance)
- State-level pres shares sum to 1 per CD
- No NAs in any column

Any deviation from these signals a bug in earlier scripts.

---

## Script 18C
### Purpose: Refine is_redistricted, add contestation, and set training_eligibility

Take the base training table from 18B and add the final modeling flags.

### Inputs
- `training_table.rds` (from 18B): base version with preliminary is_redistricted
- `cd_house_2024.rds` (from 16): used to compute contestation
- `cd_2026_inheritance.rds` (from 18A): used to refine is_redistricted

### Output
- `training_table.rds` (final version): base + contestation + refined is_redistricted + training_eligibility

### Step 1: Refine is_redistricted using inheritance

The base `is_redistricted` is coarse — TRUE for all CDs in the 7 redistricted states. The inheritance table shows that ~42 of these are essentially-unchanged from a 2024 CD (>=95% population overlap). These CDs can inherit their 2024 vote result, so they belong in the training set.

The refinement:
```r
is_redistricted = if_else(
  state_cd %in% essentially_unchanged_cds,
  FALSE,      # was TRUE, now FALSE — enters training set
  is_redistricted
)
```

After refinement:
- `is_redistricted = TRUE`: ~117 CDs (genuinely new geography)
- `is_redistricted = FALSE`: ~318 CDs (~276 stable + ~42 essentially-unchanged)

### Step 2: Compute 2024 contestation

For each CD, contestation is defined as: both major parties received more than 10 votes in the 2024 House race.

```r
contestation_2024 = (dem_votes > 10 & rep_votes > 10)
```

**Why the >10 threshold**: The MIT dataset codes uncontested races in various ways — 0 votes, placeholder 1 vote, or actual write-in totals in the single digits. The >10 threshold cleanly separates these coding artifacts from real contested races. Real contested races have thousands of votes per major party, so the threshold is far below any legitimate contested-race minimum.

**Why relaxed from an earlier >100 threshold**: An earlier version of this pipeline used >100 to be conservative, but that excluded some CDs with real but very low turnout. The >10 threshold captures more actual contested races without introducing noise from placeholders.

### Step 3: Build unified contestation column

Contestation values are assigned in priority order:

| Priority | Case | Contestation |
|---|---|---|
| 1 | Known 2026-uncontested CDs (CA-14, CA-29, CA-40, FL-10) | FALSE |
| 2 | Genuinely redistricted CDs (is_redistricted = TRUE, not in group 1) | TRUE |
| 3 | Stable / essentially-unchanged CDs | Inherit from 2024 (>10 threshold) |
| 4 | Fallback | TRUE |

**Why the 4 hard-coded overrides**: These four CDs are known ahead of the 2026 election to be uncontested (based on candidate filings and jungle-primary results). Because they're redistricted, the pipeline defaults them to `contestation = TRUE`, so we hard-code the correction.

**Why genuinely redistricted CDs default to TRUE**: A newly-drawn CD has no direct 2024 ancestor. We assume its 2026 race will be contested unless otherwise specified. We deliberately do NOT inherit contestation from the old same-named CD — that CD has been substantially redrawn, so its 2024 contestation status is not informative about the new district.

### Step 4: Set training_eligibility

A simple 2-value flag derived from is_redistricted:

```r
training_eligibility = if_else(!is_redistricted, "training_set", "prediction_set")
```

| Category | Definition | Count |
|---|---|---|
| training_set | Stable states + essentially-unchanged CDs | ~318 |
| prediction_set | Genuinely new redistricted CDs | ~117 |

### Contestation is a feature, not a filter

Contestation is used as a **predictor** in the CART model, not as a filter for the training set. Uncontested CDs still enter the training set — they're marked as uncontested so the model can learn to predict their inflated no_vote_share.

This is a deliberate design choice: excluding uncontested CDs would discard information about the demographics-to-vote-share mapping in one-party-dominated districts. Including them with the contestation flag lets the model learn:
- In contested CDs: how demographics predict Dem/Rep/other/no_vote shares
- In uncontested CDs: how demographics predict Dem-only or Rep-only shares (with high no_vote_share)

### Validation

The script prints:
- Contestation breakdown (TRUE / FALSE counts)
- Training eligibility breakdown
- Cross-tabulation of is_redistricted × contestation × training_eligibility
- The 4 hard-coded overrides (confirms they were applied correctly)
- All uncontested CDs in the training set (typically ~20-30 stable-state CDs)
- Essentially-unchanged CDs (confirms they moved into training_set)

Expected patterns:
- Training set has both contested and uncontested CDs (contested is the majority, but uncontested is nonzero)
- Prediction set is all contested (either genuinely new + assumed contested, or one of the 4 overrides = uncontested)
- The 4 known 2026-uncontested CDs appear in prediction_set with contestation = FALSE