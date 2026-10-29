## Documentation -- Scripts 1-3 -- Loading, cleaning, filtering, and recoding PUMS file

### Purpose
Load the IPUMS 2023 ACS 5-Year PUMS extract, filter to the citizen voting-age 
population, and recode demographic variables with human-readable labels. 
Produces `pums_clean.rds`.

## Script 01 

### Purpose: Load IPUMS PUMS extract and inspect

### Data sources used
- IPUMS USA ACS 2023 5-Year PUMS
- Extract ID: usa_00003
- Years: 2020-2024 pooled
- N records: 16,095,728 individuals
- Variables retained from extract: 24
- Source: ipums.org

Full set of variables and example data:

|Column     |Value       |What it means                                                                                                 |
|-----------|------------|--------------------------------------------------------------------------------------------------------------|
|`YEAR`     |2024        |This record comes from the 2024 ACS survey wave                                                               |
|`MULTYEAR` |2020        |This person was actually surveyed in 2020 — remember the 5-year file pools 2020–2024                          |
|`SAMPLE`   |202403      |IPUMS internal sample identifier — ignore                                                                     |
|`SERIAL`   |3588050     |Unique household ID — links this person to their household                                                    |
|`CBSERIAL` |2.02e+12    |Original Census Bureau household ID — ignore                                                                  |
|`HHWT`     |84          |Household weight — this household represents 84 households in the real population                             |
|`CLUSTER`  |2.024036e+12|Variance estimation cluster — used for standard errors, ignore for now                                        |
|`STATEFIP` |28          |State FIPS code 28 = **Mississippi**                                                                          |
|`PUMA`     |400         |PUMA 00400 within Mississippi                                                                                 |
|`CPUMA1020`|846         |Consistent PUMA identifier bridging 2010 and 2020 boundaries                                                  |
|`STRATA`   |40028       |Variance estimation strata — used for standard errors, ignore for now                                         |
|`GQ`       |1           |Group quarters status = **1, a regular household** — this person stays in your frame                          |
|`HHINCOME` |91334       |Total household income = **$91,334**                                                                          |
|`PERNUM`   |1           |This is **person #1** in their household — i.e. the first person listed                                       |
|`PERWT`    |83          |**Person weight = 83** — this one record represents 83 real people in Mississippi with similar characteristics|
|`SEX`      |2           |**2 = Female** (1 = Male in IPUMS coding)                                                                     |
|`AGE`      |70          |**70 years old**                                                            |
|`RACE`     |1           |**1 = White** in IPUMS coding                                                                                 |
|`RACED`    |100         |Detailed race code — White, no further detail                                                                 |
|`HISPAN`   |0           |**0 = Not Hispanic**                                                                                          |
|`HISPAND`  |0           |Detailed Hispanic code — not Hispanic                                                                         |
|`EDUC`     |8           |**8 = Some college** in IPUMS coding                                                                          |
|`EDUCD`    |81          |Detailed education code — some college, no degree                                                             |
|'CITIZEN'  |3          | Is a naturalized citizen

### Diagnostics
- 5 categories of Group Quarters (GQ) present in data (codes 1-5; codes 0 and 6 have 0 rows even though they're valid in the DDI)
- 51 unique states (50 states + DC; DC dropped at a later stage)
- PERWT (person weight) range [1, 986], median 15, mean 20.81 — all positive

### Code mappings inspected (for use in Scripts 02 and 03)
- RACED: 368 detailed codes
- EDUCD: 44 detailed codes
- HISPAND: 55 detailed codes
- CITIZEN: 8 codes
- SEX: 3 codes (1 = Male, 2 = Female, 9 = Missing)
- GQ: 7 codes

## Full Code Mapping Information (From the ipums website)
### IPUMS code mappings

IPUMS preserves rich detail in coded variables. The following are the variables relevant to our pipeline; codes shown in full where the list is small, otherwise summarized.

**GQ — Group Quarters** (7 codes)
| Code | Label |
|---|---|
| 0 | Vacant unit |
| 1 | Households under 1970 definition |
| 2 | Additional households under 1990 definition |
| 3 | Group quarters — Institutions |
| 4 | Other group quarters |
| 5 | Additional households under 2000 definition |
| 6 | Fragment |

**CITIZEN — Citizenship status** (8 codes)
| Code | Label |
|---|---|
| 0 | N/A (U.S.-born citizen; question not asked) |
| 1 | Born abroad of American parents |
| 2 | Naturalized citizen |
| 3 | Not a citizen |
| 4 | Not a citizen, but has received first papers |
| 5 | Foreign born, citizenship status not reported |
| 8 | Illegible |
| 9 | Missing/blank |

**SEX** (3 codes)
| Code | Label |
|---|---|
| 1 | Male |
| 2 | Female |
| 9 | Missing/blank |

**AGE** — Exact age in years, integer. No special codes. Top-coded at the upper end of the distribution.

**RACED — Detailed race** (368 codes)
- Codes 100–177: White (Albanian, Armenian, Austrian, ..., other European/MENA ancestries)
- Codes 200–234: Black/African American (alone and in combination)
- Codes 300–399: American Indian / Alaska Native
- Codes 400–629: Asian (Chinese, Japanese, Indian, Korean, etc.)
- Codes 630–634, 680–699: Native Hawaiian / Pacific Islander (note: sits inside the broader Asian numerical range and must be pulled out explicitly)
- Codes 635–679: Additional Asian / South Asian groups
- Codes 700–730: Other race
- Codes 801–997: Multiracial combinations

The detail is national-origin level. Collapsed to broad racial categories in Script 03.

**HISPAND — Detailed Hispanic origin** (55 codes)
- Code 0: Not Hispanic
- Codes 100–199: Mexican origin (Mexican, Mexican American, Chicano/Chicana, etc.)
- Codes 200–299: Puerto Rican
- Codes 300–399: Cuban
- Codes 400+: Other Hispanic origins (Dominican, Central American, South American, Spaniard)
- Code 900: Not reported (treated as NA)

In Script 03, collapsed to a binary Hispanic flag.

**EDUCD — Detailed educational attainment** (44 codes)
- Codes 0–1: N/A or no schooling
- Codes 2–61: No high school diploma (specific grades completed)
- Codes 62–64: HS graduate (HS diploma, GED, alternative credentials)
- Codes 65–83: Some college (incl. associate's degree)
- Codes 100–101: 4-year college degree
- Codes 110–116: Post-graduate (master's, professional, doctorate)
- Code 999: Missing → NA

**STATEFIP — State FIPS code**
Numeric codes 1–56, with gaps. 50 states + DC (code 11). U.S. territories (codes 60–78) excluded from extract. DC dropped at a later pipeline stage.

**PUMA — Public Use Microdata Area** (2022 boundaries)
5-digit numeric code, unique within state. Each PUMA contains ~100,000+ people. PUMA boundaries are not aligned to congressional district boundaries, requiring a crosswalk (Script 04).

**HHINCOME — Household income**
Integer dollars, retrospective for prior 12 months. Special values:
- 9999999: N/A (treated as NA)
- Negative: business/farm losses, retained as-is
- 0: zero income, retained as-is

**PERWT, HHWT — Person and household weights**
Numeric, range 1–986 for PERWT. Each record represents PERWT people in the population.

**CLUSTER, STRATA** — Variance estimation variables (not used in our pipeline; retained for potential future use).

### Notes
At this stage, no filtering or recoding occurs. The script's purpose is purely to load the data and verify its structure before downstream processing.

## Script 02
### Purpose: Clean/Filter raw PUMS to voting-eligible population (CVAP)

### Filters applied (sequential)
| Filter | Action | Codes affected |
|---|---|---|
| Group Quarters (GQ) | Drop vacant units and fragments; retain institutional and other GQ | Drop GQ ∈ {0, 6}; keep {1, 2, 3, 4, 5} |
| Citizenship | Drop non-citizens | Drop CITIZEN == 3; keep {0, 1, 2} |
| Age | Keep voting-eligible adults | AGE ≥ 18 |

Key decision: We decided to retain institutional GQ (code 3) since they are part of the voting-eligible population.

### Running totals after each filter

| Stage | Rows | Weighted population |
|---|---|---|
| Raw extract | 16,095,728 | 334,922,503 |
| After GQ filter | 16,095,728 | 334,922,503 (no change; codes 0 and 6 had 0 rows) |
| After citizenship filter | 15,244,470 | 312,371,676 |
| After age filter (18+) | 12,263,785 | 240,960,972 |

The final weighted population of 240.96 million matches expected U.S. citizen voting-age population (CVAP) estimates from the 2023 ACS 5-year file.

### Diagnostic checks run before filtering
- Weighted distribution by category for: GQ, CITIZEN, SEX, HISPAND, RACED, EDUCD, HHINCOME
- Full code-level distribution for RACED, HISPAND, EDUCD with DDI labels attached
- Anti-join check for unexpected codes in data that have no matching DDI label
- NA audit across all key variables

### Notes
IPUMS person-level extracts do not include vacant units or fragments (those are housing-unit-level concerns). The filter is kept defensively in case extract parameters change in future runs.

Hispanic ethnicity is NOT filtered at this stage — both Hispanic and Not Hispanic records are retained. Hispanic flag will be added as a separate variable in Script 03.


## Script 03
### Purpose: Recode and label PUMS demographic variables (no aggregation)

### Recoding logic
| Variable | Source | Output | Logic |
|---|---|---|---|
| gender | SEX | "Male" / "Female" | SEX = 1 → Male; SEX = 2 → Female; otherwise NA |
| hispanic_flag | HISPAND | 0/1 | HISPAND = 0 → 0; HISPAND > 0 → 1; otherwise NA |
| hispanic_detailed | HISPAND | 24 labels | Direct lookup from DDI labels |
| race_detailed | RACED | 156 labels | Direct lookup from DDI labels |
| educ_detailed | EDUCD | 24 labels | Direct lookup from DDI labels |
| hhincome_clean | HHINCOME | numeric | 9999999 → NA; zero and negative retained |

### Design choices

**No aggregation at this stage**: The full IPUMS detail (156 race codes, 24 Hispanic codes, 24 education codes) is retained. Aggregation to coarser categories used in cell-level analysis happens in Script 08 during CES-PUMS harmonization. Keeping detail here preserves flexibility for future analyses with finer granularity.

**Race and Hispanic treated as independent dimensions**: A respondent's race_detailed value reflects their selected race regardless of Hispanic status. The Hispanic-first rule (treating Hispanic ethnicity as a race category that overrides selected race) was explicitly NOT applied. This matches the structure of the Census data, which treats race and Hispanic origin as separate questions.

**Gender restricted to binary**: ACS does not collect non-binary gender; only Male/Female responses are coded. This is a structural constraint of the data source. Non-binary CES respondents (CES `gender4` ∈ {3, 4}) will be filtered out in Script 08 to maintain alignment.

**Raw variables retained**: Original numeric codes (AGE, SEX, RACE, RACED, HISPAN, HISPAND, CITIZEN, EDUC, EDUCD, HHINCOME, GQ) are kept in the output for auditability. Any downstream issue can be traced back to the source code.

### Final dataset
- Dimensions: 12,263,785 rows × 26 columns
- Distinct categories preserved: 156 race, 24 Hispanic, 24 education
- Saved as: `pums_clean.rds`
- Memory footprint: see saved file size diagnostic

### Final column structure

**Identifiers and geography**: SERIAL, PERNUM, STATEFIP, PUMA, CPUMA1020 — uniquely identify each person and locate them geographically. PUMA / CPUMA1020 are used in Script 04 to assign respondents to congressional districts.

**Weights and variance estimation**: PERWT, HHWT, CLUSTER, STRATA — PERWT is the person weight used for all population estimates. CLUSTER and STRATA support standard error calculation for future uncertainty modeling.

**Raw demographic variables**: AGE, SEX, RACE, RACED, HISPAN, HISPAND, CITIZEN, EDUC, EDUCD, HHINCOME, GQ — original numeric codes retained for auditability.

**Cleaned and labeled variables**: gender, hispanic_flag, hispanic_detailed, race_detailed, educ_detailed, hhincome_clean — human-readable versions used by the stratification frame.
