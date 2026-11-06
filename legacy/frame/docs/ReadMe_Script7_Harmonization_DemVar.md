## Script 07
### Purpose: Harmonize demographic variables across PUMS and CES

For MrsP, CES survey respondents and PUMS-derived cells must use identical category definitions for every variable used in poststratification. This script creates matching `_cat` columns in both datasets and saves the harmonized versions to disk.

### Inputs and outputs
- Inputs: `pums_crosswalked.rds` (Script 05), `ces` (Script 06)
- Outputs: `pums_crosswalked_harmonized.rds`, `ces_harmonized.rds`

### Variable mappings

#### age_cat — 5-year bins, 14 levels

Source columns:
- PUMS: `AGE` (integer years, 18+)
- CES: `age = 2024 - birthyr`

Both datasets pass through the helper `bin_age()`:
```r
cut(age, breaks = c(17, 22, 27, 32, ..., 82, Inf),
       labels = c("18-22", "23-27", ..., "83+"),
       right = TRUE)
```

Why 5-year bins:
- Captures meaningful age gradients in turnout and partisanship
- Standard in the MrP literature (e.g., ccesMRPprep uses 5-year keys)
- Fine granularity retained at the frame stage; can collapse later if cells become sparse

The breakpoint at 17 (not 18) cleanly excludes any stray under-18 records while including 18 in the first bin. Right-inclusive: "18-22" = {18, 19, 20, 21, 22}. Top bin open-ended because exact age past ~80 is less informative for political behavior.

#### gender_cat — binary

Source columns:
- PUMS `SEX`: 1 = Male, 2 = Female (already cleaned to `gender` column in Script 03)
- CES `gender4`: 1 = Man, 2 = Woman, 3 = Non-binary, 4 = Other

Mapping:
- CES gender4 == 1 → "Male"
- CES gender4 == 2 → "Female"
- CES gender4 ∈ {3, 4} → respondent dropped from CES (~554 rows, 0.93%)

Why drop non-binary/Other respondents: ACS only collects binary sex, so non-binary cells don't exist in the stratification frame. These respondents cannot contribute to MrsP estimation regardless. This is a structural constraint of the source data, not a methodological choice.

#### educ_cat — 6 levels

Levels: No HS, HS grad, Some college, 2-year, 4-year, Post-grad.

Source columns:
- PUMS: `EDUCD` (44-level detailed education code from IPUMS)
- CES: `educ` (already coded 1-6, matching the target scheme)

PUMS EDUCD → educ_cat mapping:

| educ_cat | PUMS EDUCD codes | Description |
|---|---|---|
| 1 (No HS) | 2, 11, 12, 14, 15, 16, 17, 22, 23, 25, 26, 30, 40, 50, 61 | No schooling through 12th grade (no diploma) |
| 2 (HS grad) | 63, 64 | HS diploma, GED |
| 3 (Some college) | 65, 71 | Some college without degree |
| 4 (2-year) | 81 | Associate's degree |
| 5 (4-year) | 101 | Bachelor's degree |
| 6 (Post-grad) | 114, 115, 116 | Master's, Professional, Doctorate |

PUMS uses `haven::zap_labels()` to strip the haven-labelled metadata before the numeric case_when comparisons.

Why these specific codes: EDUCD codes 2-61 cover all "less than HS grad" categories. The choice to put associate's (code 81) into its own "2-year" bin (rather than merging with "Some college") matches the CES coding and is conventional in CES-MRP work, where 2-year degrees show distinct political behavior from non-completers.

#### hispanic_cat — binary

Source columns:
- PUMS `hispanic_flag` (from Script 03): 0 = Not Hispanic, 1 = Hispanic (any HISPAND > 0)
- CES `hispanic`: 1 = Yes, 2 = No

Mapping:
- PUMS hispanic_flag == 1 → "Hispanic"
- PUMS hispanic_flag == 0 → "Not Hispanic"
- CES hispanic == 1 → "Hispanic"
- CES hispanic == 2 → "Not Hispanic"
- NA preserved as NA in both

#### race_cat — 5 levels (after collapse)

Final levels: White, Black, Native American, Asian, Other/Multi.

Source columns:
- PUMS `RACE`: 9 levels from IPUMS
- CES `race`: 8 levels

The mapping is done in two steps. **Step 1**: both datasets are mapped to an initial 6-level scheme. **Step 2**: "Two or more races" and "Other" are collapsed into "Other/Multi" to get the final 5-level scheme.

**Step 1 — initial 6-level mapping**:

PUMS RACE → initial race_cat:

| Initial cat | PUMS RACE codes | Description |
|---|---|---|
| White | 1 | White alone |
| Black | 2 | Black alone |
| Native American | 3 | American Indian / Alaska Native |
| Asian | 4, 5, 6 | Chinese, Japanese, Other Asian/Pacific Islander |
| Two or more races | 8, 9 | Two major races, Three or more races |
| Other | 7 | Other race |

PUMS uses `haven::zap_labels()` to strip metadata before the comparisons.

CES race → initial race_cat:

| Initial cat | CES race codes | Description |
|---|---|---|
| White | 1 | |
| Black | 2 | |
| Native American | 5 | (CES uses code 5 for Native American; PUMS uses 3) |
| Asian | 4 | |
| Two or more races | 6 | |
| Other | 3, 7, 8 | Hispanic-as-race (3), Other (7), Middle Eastern (8) |

**Step 2 — collapse to 5 levels**:
```r
fct_collapse(race_cat, "Other/Multi" = c("Two or more races", "Other"))
```

Applied to both datasets after the cross-tab race × Hispanic check.

Why collapse: CES has Hispanic as a race option (code 3) which gets mapped to "Other" because PUMS has no equivalent. After this mapping, the CES "Other" category contains Hispanic respondents whose primary identification is Hispanic-as-race. Folding "Other" with "Two or more races" creates a stable "Other/Multi" bucket that aligns cleanly with PUMS, since both source datasets have small populations in these "rare" categories.

### Key design decision: race and Hispanic are independent

A respondent's `race_cat` reflects their selected race regardless of Hispanic status. The Hispanic-first rule (treating Hispanic as a race category that overrides selected race) was explicitly NOT applied. This matches Census methodology, which treats race and Hispanic origin as separate questions.

The downstream stratification frame therefore has cells for every (race × Hispanic) combination — e.g., "White Hispanic" and "White Not Hispanic" exist as separate cells, as do "Black Hispanic", "Asian Hispanic", etc.

### Validation

For each variable, the script prints side-by-side PUMS-weighted vs CES distributions. For age, a comparison table shows PUMS%, CES%, and the difference. For race × Hispanic, cross-tabulations confirm the two dimensions vary independently in both datasets.

Differences between PUMS and CES distributions are expected (CES over-represents engaged voters) and are exactly what poststratification corrects for.

### Geographic identifiers

Not harmonized here. The CES-to-2026-CD assignment requires a ZCTA-to-CD crosswalk because CES respondents in the 7 redistricted states have `cdid119` reflecting 2024 boundaries that no longer match 2026. Handled in Script 08.