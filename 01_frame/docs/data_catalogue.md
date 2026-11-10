# Frame data catalogue

To inspect the observed House response and its predictors together, open `data/intermediate/09_house_party_inputs.csv`. The [sequential House beta regression](09_validate_house_beta.md#inspect-the-district-by-party-data) derives its three conditional responses from the counts in `data/intermediate/09_house_training_cd119.csv`. For each fitted stage it saves the Stan program and per-parameter diagnostics in `data/intermediate/09_beta_holdout_cache/<run-key>/`. The district split, stage summaries, holdout predictions, scores and four-panel figure are in `data/output/09_beta_holdout/<run-key>/`.


To find a district's House shares, use the [district-by-party products](#district-by-party-house-shares). The [Step 08 inventory](#district-populations-and-candidate-rosters) describes the two-map populations and rosters behind these products. The [holdout guide](09_validate_house_beta.md) describes the model, scoring and validation outputs.

## Plain-language summary

This catalogue explains each data file's purpose, source, producer and
consumer. Script 00 downloads the specified IPUMS USA sample and records its
source files. Script 01 verifies those files against the approved source
manifest and prepares citizen-adult person records.

Script 02 independently combines Census geography, population counts and
citizen-adult estimates to build district probabilities for each PUMA.
Script 03 matches each person's state/PUMA to the crosswalk and distributes
that person's survey weight across districts using the PUMA probabilities.
The person–district RDS stores each positive contribution, and audit CSVs
record coverage and conservation checks.

Script 04 reads one record per person from the cleaned PUMS. It harmonizes
demographic categories and estimates five national race shares among Hispanic
adult citizens. Script 05 selects self-reported U.S. citizens in the CES,
maps their 119th Congress residence districts onto the 120th Congress map,
and draws a race for people whose primary response was Hispanic or Latino.
It uses district allocations from Script 03 and harmonized PUMS demographics
from Script 04 to estimate the race shares conditional on district, age,
education and sex/gender. The national race totals check donor conservation.

Script 05 also classifies 2024 House and presidential responses from the same
CES CSV. Script 06 aggregates the district-allocated PUMS weights by all
seven shared geography and demographic fields, and checks CES cell coverage.

Script 07 groups 2024 candidate votes for president by state and for House
by original district. It divides presidential totals by the state PUMS
citizen-adult population from Script 03 and estimates how many recorded no
vote for a candidate for that office. Step 09 uses the original House counts
and district CVAP to calculate 2024 shares. Together with the match between
district boundaries, these determine which results can carry to the new map
and where Step 09 needs a prediction.

## Scope and reading conventions

All paths in backticks are relative to `01_frame/` unless stated otherwise.

| Name used here | Script | Companion document |
|---|---|---|
| Script 00 | [00_download_pums.R](../scripts/00_download_pums.R) | [IPUMS download](00_download_pums.md) |
| Script 01 | [01_prepare_pums.R](../scripts/01_prepare_pums.R) | [PUMS preparation](01_prepare_pums.md) |
| Script 02 | [02_build_puma_cd_crosswalk.R](../scripts/02_build_puma_cd_crosswalk.R) | [Crosswalk construction](02_build_puma_cd_crosswalk.md) |
| Script 03 | [03_apply_puma_cd_crosswalk.R](../scripts/03_apply_puma_cd_crosswalk.R) | [Coverage and application](03_apply_puma_cd_crosswalk.md) |
| Script 04 | [04_harmonize_pums.R](../scripts/04_harmonize_pums.R) | [PUMS demographics](04_harmonize_pums.md) |
| Script 05 | [05_prepare_ces.R](../scripts/05_prepare_ces.R) | [CES download and harmonization](05_prepare_ces.md) |
| Script 06 | [06_build_pums_cells.R](../scripts/06_build_pums_cells.R) | [PUMS cell sizes and CES coverage](06_build_pums_cells.md) |
| Script 07 | [07_prepare_area_returns.py](../scripts/07_prepare_area_returns.py) | [Area-level returns](07_prepare_area_returns.md) |
| Script 08, district populations | [08_build_district_predictors.R](../scripts/08_build_district_predictors.R) | [Two-map CVAP predictors](08_build_district_predictors.md) |
| Script 08, candidate rosters | [08_prepare_house_slates.py](../scripts/08_prepare_house_slates.py) | [House candidate lineups](08_house_slates.md) |
| Script 09 | [09_model_house_votes.R](../scripts/09_model_house_votes.R) | [District input preparation](09_model_house_votes.md) |
| Script 09 | [09_validate_house_beta.R](../scripts/09_validate_house_beta.R) | [Conditional beta models, holdout and output inventory](09_validate_house_beta.md) |

Scripts 00 and 01 passed the complete download-to-preparation run, including
source checks and saving the cleaned RDS. Script 00 also passed offline reuse.
Script 02 passed its documented crosswalk checks. Script 03 passed its
national coverage and person-level allocation checks on 2026-11-07. Steps
04–06 completed demographic harmonization, CES vote coding and the national
cell build. See the [survey-to-frame coverage totals](06_build_pums_cells.md#production-results).
See the [component status](../README.md#script-status).

Through Step 06 the inputs comprise 61 source files: one selected
two-file IPUMS pair, 58 Census files and one CES Common Content CSV. Script 00
also keeps request/receipt metadata and source snapshots.

Steps 00–06 define eight intermediate RDS files and 38 output CSVs. Script 01
produces four CSVs, Script 02 produces 21, Scripts 03 and 04 produce two each,
Script 05 produces eight and Script 06 produces one. These counts cover
the numbered production runs. Step 07 uses the two files from the
[optional election benchmark](05_vote_rules.md#reproduce-the-vote-benchmark)
to check the MIT returns. Its counts, covariates and audits are listed under
[area-level election returns](#area-level-election-returns). Source manifests
and two generated Markdown notes are additional tracked files in `docs/`.

## Geography, quantities and keys

| Term or field | Meaning in these files |
|---|---|
| PUMS | Public Use Microdata Sample. Our harmonized IPUMS records identify a person's PUMA, not their census block or block group. |
| PUMA | Public Use Microdata Area. Identify it by state plus PUMA code: numeric `STATEFIP` and `PUMA` in PUMS; character `STATEFP` and `PUMA5CE` in the crosswalk. |
| Census block | Small geographic unit identified by a 15-character `GEOID`: state 2 + county 3 + tract 6 + block 4 characters. |
| Census block group | Group of blocks. Original block-group identifiers use the first 12 block-GEOID characters. `bg_2020` is the original identifier; `bg_cvap` is the identifier used by the CVAP release after reviewed reconciliation. |
| Congressional district | Identified by state plus `CDFP`. The pinned 120th Congress BEF provides each block's district code. |
| BEF | Census **Block Equivalency File**: the block-to-district assignment table, not a population table. |
| PL | **Public Law 94-171** redistricting data. The project uses its 2020 block population counts. |
| `pop20` / `population_2020` | Total 2020 population, including children and noncitizens. Used for population-conservation, missing-geography and exception audits. |
| `vap20` | 2020 population aged 18+, including noncitizens. Used to divide CVAP estimates within block groups when a split is needed. |
| CVAP | Citizen voting-age population: citizens aged 18+. `cvap_est` is a published 2020-2024 ACS block-group estimate, not a known block-level count. |
| `PERWT` | PUMS person weight. Its sum is a weighted person total, not a count of microdata rows or the separate CVAP-tabulation total. |
| `CDFP == "ZZ"` | Block unassigned to a congressional district in the BEF. Such blocks remain in geographic audits but do not appear in the final district-weight table. |
| `00` and `98` | District codes for at-large representation and nonvoting representation, respectively. State determines their meaning; DC's `98` remains in scope. |
| Coverage | Whether expected geographic identifiers have matches, and which PUMAs/districts their mapped blocks intersect. It is not a measure of statistical representativeness. |
| `coverage_only` | Reviewed ambiguous Connecticut water-area links describe possible source geography, not an exact partition of blocks. |

Preserve leading zeros when reading geographic CSV columns. PUMA and district
codes alone are not nationally unique. State plus code is required.

Allocation uses a block group's CVAP estimate and its 2020 adult distribution.
It assumes citizen adults follow that distribution within the block group.
Direct geographic containment can determine an allocation without such a
split. The [decision record](02_cvap_allocation_decisions.md) explains missing
CVAP, Connecticut correspondence, the five reviewed zero overrides and the
separate geographic exclusion. Published estimates remain distinguishable
from adjusted allocation inputs.

## External inputs and acquisition

Script 00 acquires the PUMS pair from IPUMS USA. Script 01 resolves it through
the local snapshot pointer and receipt, then applies the tracked source
approval checks. Script 05 acquires the 119th Congress Census block archive and
the CES survey file. The acquisition instructions below cover the other Census
inputs. Keep source archives compressed; scripts read their required members.

The PUMS data and variable-metadata fingerprints are maintained in
[docs/00_pums_source.json](00_pums_source.json). Script 02 contains the six
standalone Census SHA-256 constants. The 51 PL archive sizes and SHA-256
values are maintained in the [population manifest](02_pl_2020_sources.csv).
A changed approved data or metadata fingerprint requires review; downloading
another snapshot does not update these expectations automatically.

### IPUMS source pair: Scripts 00 and 01

- **Location:** `data/input/ipums_pums/<snapshot>/files/`, preserving the
  provider's filenames. `data/input/ipums_pums/current_snapshot.txt` selects
  the local download attempt; it does not by itself approve its contents.
- **Source/acquisition:** [IPUMS USA API](https://developer.ipums.org/docs/v2/get-started/),
  implemented by [Script 00](../scripts/00_download_pums.R). A registered USA
  account and `IPUMS_API_KEY` are needed for live acquisition, not offline reuse.
- **Specification:** API sample `us2024c`, full 2020-2024 ACS five-year
  person-rectangular CSV, the 24 variables below, no case filters.
  Numeric source fields are `SAMPLE = 202403`, `YEAR = 2024`, and `MULTYEAR`
  in 2020-2024. The XML supplies variable definitions and labels.
- **Receipt:** `<snapshot>/download_manifest.csv` records the returned XML
  and compressed CSV filenames, sizes, hashes and extraction provenance.
  Script 00 checks it before reuse; Script 01 checks it before import,
  including the fingerprint of the saved `request.json`.
- **Approval:** `docs/00_pums_source.json` pins the approved compressed CSV
  size/hash and the `ipums_var_info_json_v1` variable-metadata hash. The
  [source approval document](00_download_pums.md#source-approval) specifies
  the exact JSON serialization and SHA-256 method. The reference XML hash
  is evidence; each local receipt pins its own full XML file.
- **Readers:** Script 00 validates acquisition/reuse. Script 01 reads the
  pointer, receipt, saved request, approved source manifest and selected files.
- **Contributes to:** `pums_clean.rds` and all four `01_pums_*.csv` audits;
  the Script 03 district allocation and audits, and the Script 04 demographic
  table, coverage audit and national race shares. Script 05 combines the
  district allocation and demographic table and checks the resulting donor
  weights against the Script 04 national totals.
- **Units and geography:** Individual records and person/household weights;
  person geography at the state/PUMA level. Ages and weights are not projected
  to the 2026 election.
- **Reuse and refresh:** Ordinary runs reuse verified files without API
  access. `--refresh` requests a new snapshot and retains earlier ones.
  Script 01 stops if that snapshot changes the approved data or variable
  metadata. The manifest must be reviewed before accepting such a change.
- **Validation:** Acquisition, all 24 downloaded columns, offline reuse and
  the complete preparation run passed. The cleaned RDS and audit outputs
  were saved successfully.
- **Preservation:** Source snapshots and account-specific receipts are
  ignored by Git. The approval manifest and scripts are tracked.

The approved CSV has 249,052,624 bytes and SHA-256
`adb92df6553053b846773de170852e4d1b7b557d6d6aaf9827e9a37111f70a04`.
It contains these 24 columns, in order:

```text
YEAR, MULTYEAR, SAMPLE, SERIAL, CBSERIAL, HHWT, CLUSTER, STATEFIP,
PUMA, CPUMA1020, STRATA, GQ, HHINCOME, PERNUM, PERWT, SEX, AGE,
RACE, RACED, HISPAN, HISPAND, CITIZEN, EDUC, EDUCD
```

The [download document](00_download_pums.md#stored-inputs-outputs-and-consumers)
lists each acquisition-state file and the receipt columns. Returned filenames
and account-specific extract numbers are resolved from the local receipt.

### BEF: block-to-district assignments

- **File:** `data/input/cd120.zip`; only member `NationalCD120.txt` is read.
- **Source/download:** [Census 120th Congress archive](https://www2.census.gov/programs-surveys/decennial/rdo/mapping-files/2027/120-congressional-district-befs/cd120.zip).
- **Version:** Pinned archive downloaded during review on 2026-10-30; its
  2020 block identifiers are used with the stored district assignments.
- **Readers:** Script 02 Sections 1–2 and the Script 05 geography helper verify
  the same archive fingerprint and read the national member.
- **Schema:** CSV with `GEOID, STATEFP, COUNTYFP, TRACTCE, BLOCKCE, CDFP`.
  One row per unique block `GEOID`; no population measure.
- **Scope:** Source includes Puerto Rico; processing retains the 50 states
  and DC and reports the excluded jurisdiction.
- **Contributes to:** District-code/scope audits, block matching, geographic
  exceptions, CVAP intersections, PUMA containment and final crosswalk weights.
  Script 05 also uses the block assignments to map 119th to 120th districts.

### PUMA lookup: tract-to-PUMA membership

- **File:** `data/input/2020_Census_Tract_to_2020_PUMA.txt`.
- **Source/download:** [Census 2020 tract-to-PUMA lookup](https://www2.census.gov/geo/docs/maps-data/data/rel2020/2020_Census_Tract_to_2020_PUMA.txt).
- **Reader:** Script 02 Section 3; fingerprint `puma_sha256`.
- **Schema:** Comma-delimited text with `STATEFP, COUNTYFP, TRACTCE, PUMA5CE`.
  One row per tract, keyed by the first three fields concatenated.
- **Role:** Attach a 2020 PUMA to each original block through its tract.
  Retain the 50 states and DC.
- **Contributes to:** PUMA lookup/join audits, affected-PUMA audits and all
  subsequent block-group/PUMA/district intersections and weights.

### PL archives and their source manifest

- **Tracked input:** `docs/02_pl_2020_sources.csv`.
- **Manifest columns:** `STATEFP, STUSAB, state_name, path, url, bytes, sha256`.
  Exactly one row for each of the 50 states and DC. The `path` values are
  repository-root-relative, including the `01_frame/` prefix.
- **Raw files:** 51 archives at `data/input/pl_2020/<abbr>2020.pl.zip`, where
  `<abbr>` is the lowercase postal abbreviation. Total recorded bytes:
  1,311,562,849.
- **Source/download:** Exact per-state URLs in the [manifest](02_pl_2020_sources.csv),
  under [Census 2020 PL redistricting files](https://www2.census.gov/programs-surveys/decennial/2020/data/01-Redistricting_File--PL_94-171/).
  Download each `url` to its `path`; verify its `bytes` and `sha256`.
- Script 02 Sections 4–5 read the manifest and verify each local archive.
  The [PL reader](../scripts/helpers/02_census_inputs.R) reads two members,
  `<abbr>geo2020.pl` and `<abbr>000022020.pl`. Script 05 reads the manifest
  and the same two archived members for states with split old districts.
- **Geography member:** 97 pipe-delimited fields; the reader selects
  `FILEID, STUSAB, SUMLEV, GEOVAR, GEOCOMP, CHARITER, CIFSN, LOGRECNO,
  STATE, COUNTY, TRACT, BLOCK, POP100`.
- **Segment 2 member:** Linking fields `FILEID, STUSAB, CHARITER, CIFSN,
  LOGRECNO` plus `P0030001`, the total aged 18+.
- **Keys/units:** Match members by `LOGRECNO` within state. Retain state
  (`SUMLEV = 040`) and block (`750`) rows. Construct block GEOID from state,
  county, tract and block. `POP100` supplies all-age persons; `P0030001`
  supplies adults including noncitizens.
- **Contributes to:** Population matching/conservation audits, geographic
  exception evidence, adult-proportional CVAP contributions and final weights.
  Script 05 uses the adult counts to split a block-group/CD120 contribution
  across its possible CD119 districts.

Script 02 reads but never rewrites the manifest.

### CVAP: published citizen-adult estimates

- **File:** `data/input/CVAP_2020-2024_ACS_csv_files.zip`; member `BlockGr.csv`.
- **Source/download:** [Census 2020-2024 CVAP archive](https://www2.census.gov/programs-surveys/decennial/rdo/datasets/2024/2024-cvap/CVAP_2020-2024_ACS_csv_files.zip).
- Script 02 reads the block-group identifiers and estimates together in Section 6.
  Sections 8 and 9 reuse that table for Connecticut and the national allocation.
- **Source columns:** `geoname, lntitle, geoid, lnnumber, cit_est, cit_moe,
  cvap_est, cvap_moe`. Current calculations use `geoid, lnnumber, cvap_est`.
- **Selection/key:** `lnnumber == 1` is Total. Remove `1500000US` from `geoid`
  to obtain `bg_cvap`. Retain the 50 states and DC. Connecticut identifiers
  use the newer planning-region county equivalents.
- **Units:** Estimated citizen adults aged 18+. The source's margins of error
  are not propagated by the current allocation calculations.
- **Contributes to:** Missing-ID audits, CT reconciliation, allocation-case
  audits, estimated contributions and PUMA district weights.

The archive's `CD.csv` and other geography tables are not read. The script
constructs estimates for the pinned BEF's district geography from block groups.

### NY suppression: official missing-estimate identifiers

- **File:** `data/input/Errata148_Suppressed_Geographies_for_Wyandanch.xlsx`.
- **Source/download:** [Census suppression workbook](https://www.census.gov/content/dam/Census/programs-surveys/acs/tech-doc/errata/Errata148_Suppressed_Geographies_for_Wyandanch.xlsx),
  linked from [ACS Errata 148](https://www.census.gov/programs-surveys/acs/technical-documentation/errata/148.html).
- **Reader:** Script 02 Section 6; worksheet `2020-2024 ACS 5yr`, skipping
  the first two rows and reading `GEOID, NAME` as text.
- **Key/meaning:** Select New York block-group identifiers. These are
  suppression records, not CVAP estimates or zero-population observations.
- **Contributes to:** Exact missing-ID verification, the NY suppression audit
  and generated note, and the affected-PUMA impact audit. It validates which
  estimates may remain missing in the final calculation.

### CT relationships: 2020 block groups and planning regions

- **File:** `data/input/acs22_cousub22_blkgrp20_st09.txt`.
- **Source/download:** [Census Connecticut relationship file](https://www2.census.gov/geo/docs/maps-data/data/rel2022/acs22_cousub22_blkgrp20_st09.txt).
- **Reader:** Script 02 Section 8; fingerprint `ct_lookup_sha256`.
- **Relevant columns:** Pipe-delimited `GEOID_BLKGRP_20, GEOID_COUSUB_22,
  AREALAND_PART, AREAWATER_PART`.
- **Meaning:** Intersections of 2020 block groups and 2022 county subdivisions.
  Land/water areas are square metres. This is not a direct 2020-to-current block-group
  correspondence table and supplies no population counts.
- **Use:** Derive candidate planning-region prefixes from subdivision codes,
  retaining the 2020 tract/block-group suffix; validate candidates against
  the CVAP identifiers and reviewed exceptions.
- **Contributes to:** CT identifier audit and note, identifier links,
  geographic intersections and subsequent allocation products.

### CT feature query: saved check of two candidate identifiers

- **File:** `data/input/ct_bg_2024_identifier_check.json`.
- **Source:** Census TIGERweb's `tigerWMS_ACS2024` Block Groups feature layer
  (MapServer layer 10). It is a geographic feature table queried through a
  web service; the file is the saved JSON response, not a CVAP table.
- **Exact request:** [Saved-query URL](https://tigerweb.geo.census.gov/arcgis/rest/services/TIGERweb/tigerWMS_ACS2024/MapServer/10/query?where=GEOID+IN+%28%27091403431011%27%2C%27091703431011%27%29&outFields=GEOID%2CNAME%2CSTATE%2CCOUNTY%2CTRACT%2CBLKGRP%2CAREALAND%2CAREAWATER&returnGeometry=false&orderByFields=GEOID&f=json).
- **Acquisition:** Save the HTTP response body from the exact query directly
  at the path above. Parsing and reserializing JSON can change the checksum.
  Downloading that query on 2026-11-08 reproduced the 951-byte snapshot with
  SHA-256 `a01ecdfb5bfe0fe4119a3aab71007408f458ebc5c0c580a04402fe102a51bb87`.
- **Reader:** Script 02 Section 8; reads local JSON and performs no live query.
- **Relevant content:** Error/transfer-limit indicators and returned feature
  attributes `GEOID, AREALAND, AREAWATER`.
- **Evidence:** The response contains `091403431011`, with land area
  3,606,413 square metres and no water. Candidate `091703431011` is absent.
  The reviewed decision adopts the sole supported candidate while retaining
  every original block; it does not claim the boundaries are identical.
- **Contributes to:** Validation of the CT mapping convention and the generated
  CT note. All later allocation stages require this check to pass.

### 119th Congress block assignments for CES residence geography

Script 05 downloads `data/input/cd119.zip` on first use and verifies its SHA-256
(`1433feb5178dc7b4188ee30f5f7f715851f4400740b8fe1ce606a876c6294bd6`)
before reuse. The archived `NationalCD119.txt` has character `GEOID` (2020
block) and `CDFP` (119th district). Script 05 matches these blocks by identifier
to `NationalCD120.txt` in the existing `data/input/cd120.zip`. For splits it
uses `02_bg_cvap_contributions.csv` and block voting-age counts from the affected
states' PL archives, verified against `docs/02_pl_2020_sources.csv`. The
resulting lookup and its unknown-origin audit are described below.
[Census 119th Congress file description](https://www.census.gov/geographies/mapping-files/2025/dec/rdo/119-congressional-district-bef.html) ·
[Official archive](https://www2.census.gov/programs-surveys/decennial/rdo/mapping-files/2025/119-congressional-district-befs/cd119.zip)

### 2024 Cooperative Election Study

Script 05 downloads and verifies the 2024 annual Common Content vote-validated CSV.
One row represents one respondent. It reads `caseid, birthyr, gender4, educ,
race, hispanic, commonweight, cit1, inputstate, cdid119, countyfips`
as well as the [pre- and post-election vote items, House candidate party
fields and post-wave geography](05_vote_rules.md). It preserves the complete CSV at
`data/input/CCES24_Common_OUTPUT_vv_topost_final.csv` for later linkage by
`caseid`. Release V9 file 12050325 contains 60,000 rows and 183,679,005 bytes.
Its MD5 is `b740b9305fee50e1a34656b513f55c57`. The verified file is reused
on subsequent runs. It supplies eligibility, demographics, the 2024 election
district and county for the harmonized CES RDS and respondent-level audits. [Release and questionnaires](https://doi.org/10.7910/DVN/X11EP6) ·
[Official CSV](https://dataverse.harvard.edu/api/access/datafile/12050325)

## Working datasets and direct dependencies

| File | Producer and upstream inputs | Direct downstream use |
|---|---|---|
| `data/intermediate/pums_clean.rds` | Script 01 reads the approved IPUMS pair acquired by Script 00 and checks the local receipt and tracked source specification. | Script 03 reads person weights and geography. Script 04 reads the person key, demographics, citizenship and original person weights. Script 08 uses the person key, PUMA, state and original person weights to build the 2024 district predictors. |
| `data/intermediate/puma_cd_crosswalk.rds` | Script 02 Section 11; BEF + PUMA lookup + PL + CVAP + reviewed CT mapping; NY suppression and CT query validate exceptions | Script 03 reads this RDS. `02_puma_cd_weights.csv` is a readable export of the same table. |
| `data/intermediate/pums_cd_allocation.rds` | Script 03 allocates in Section 2 and assembles the file in Section 3, using `pums_clean.rds` and `puma_cd_crosswalk.rds` | Script 05 uses `allocated_person_weight` once per person/district contribution to estimate the Hispanic donor race distribution. Step 06 joins the demographics by `SAMPLE + SERIAL + PERNUM` to estimate full cell populations. |
| `data/intermediate/pums_demographics.rds` | Script 04 using `pums_clean.rds` | One row per `SAMPLE + SERIAL + PERNUM` with `age_cat, gender_cat, educ_cat, race_cat, hispanic_cat`. Scripts 05 and 06 use the three identifiers to attach these categories to Script 03 district contributions. |
| `data/intermediate/hispanic_race_by_district_profile.rds` | Script 05 donor helper using `pums_cd_allocation.rds`, `pums_demographics.rds` and the national totals in `04_pums_hispanic_race_probabilities.csv` | Script 05 reads three tables of race counts, weights, probabilities and effective donor counts by demographic profile, with district, state and national coverage. A donor can contribute to several districts. The broader pools recombine every person's weight before counting support. |
| `data/intermediate/ces_demographics_harmonized.rds` | Script 05 using the CES CSV, district lookup and conditional donor tables | One row per eligible citizen `caseid` with source fields, harmonized demographics, original and assigned geography, imputation flags, 2024 party outcomes, source of each outcome and House contest type. Script 06 checks the seven matching keys. |
| `data/intermediate/ces_analysis.rds` | Script 05 export helper, reading `ces_demographics_harmonized.rds` | One row per retained `caseid` in the same order. Provides the survey weight, seven frame keys and two 2024 vote outcomes. See the [11-column schema and export command](05_prepare_ces.md#analysis-file). |
| `data/intermediate/pums_cd_cells.rds` | Script 06, district-weighted person rows from 03, categories from 04 and the Step 03 state conservation audit | One row per positive population cell. The seven keys are `STATEFP, CDFP120, age_cat, gender_cat, race_cat, hispanic_cat, educ_cat`. Step 08 sums `N` by district and demographic category for the 2026 map. |

### Cleaned person schema

`pums_clean.rds` contains one retained record per `SAMPLE + SERIAL + PERNUM`.
The 24 source columns are followed by six derived columns in this order:
`hispanic_flag, gender, hispanic_detailed, race_detailed, educ_detailed,
hhincome_clean`.

The population is citizens aged 18+ at observation, including institutional
residents and DC. `gender` is a compatibility name for recorded-sex labels.
`hispanic_flag` is 0 for not Hispanic, 1 for Hispanic and missing for unknown.
Income sentinel `9999999` becomes missing; negative and zero income remain.
`STATEFIP + PUMA` is the location key; `CPUMA1020` is not used for this join.

The validated preparation run read 16,095,728 source records and saved
12,263,785 retained records with 30 columns and person-weight total
240,960,972. It covered 51 states including DC, with 816,970 missing cleaned
incomes. The saved RDS was 221 MiB. These results describe the approved
source snapshot.

### Crosswalk schema

`puma_cd_crosswalk.rds` and `data/output/02_puma_cd_weights.csv` contain:

```text
STATEFP, PUMA5CE, CDFP, allocation_weight, weight_method
```

Each row is one state/PUMA/assigned-district intersection. Identifiers are
character strings. `allocation_weight` is dimensionless and sums to one
within each PUMA. `weight_method` is `structural_single_district` or `cvap_share`.
Valid zero-weight intersections remain; `ZZ` rows are excluded.

The documented run produced 2,462 PUMAs, 436 assigned districts including DC,
4,183 rows and 109 zero-weight rows. The two suppressed-CVAP NY PUMAs have
weight 1 for NY-02 because each is wholly contained there; their complete
CVAP totals remain unknown. Script 03 reads this crosswalk to allocate PUMS
person weights to districts.

### Person–district allocation schema

`pums_cd_allocation.rds` stores one row per retained person and district with
a positive allocation probability. It saves the columns in this order.

```text
SAMPLE, SERIAL, PERNUM, STATEFIP, PUMA, CDFP, PERWT, allocation_weight, allocated_person_weight
```

`STATEFIP` and `PUMA` retain the source numeric codes. `CDFP` is a
two-character district code, interpreted within state. Each person is
identified by `SAMPLE + SERIAL + PERNUM`. `allocated_person_weight` equals
`PERWT * allocation_weight` and is the field to sum for district estimates.
The original `PERWT` is repeated across that person's district rows.

## Current CSV products: producers and upstream inputs

All filenames in the following tables are under `data/output/`. Input names
refer to the source descriptions above. These tables identify inputs that
supply values or validation evidence; a successful sequential Script 02 run
also requires all preceding input checks to pass.

### Script 01: person preparation audits

All four outputs use the approved PUMS source pair acquired by Script 00;
Script 01 validates its local receipt and tracked approval before processing.
Their schemas are unchanged. They are review tables; no active script reads
these CSVs back as inputs.

| File | One row represents / purpose | Columns, in file order |
|---|---|---|
| `01_pums_filtering.csv` | Filtering stage; record and weighted-population losses | `stage, rows, weighted_population, rows_removed, weighted_removed` |
| `01_pums_recoding.csv` | Derived variable; missing-value count | `variable, missing_rows` |
| `01_pums_hispanic.csv` | Hispanic flag; records and weighted persons | `hispanic_flag, rows, weighted_population` |
| `01_pums_income_by_gq.csv` | Group-quarters code; missing household income | `GQ, rows, missing_income, weighted_missing_income` |

### Script 02: geography and population audits

| File | Writer | Upstream inputs | One row represents / purpose |
|---|---|---|---|
| `02_cd120_coverage.csv` | Section 2 | BEF | State/jurisdiction; block and district counts, including out-of-scope jurisdictions |
| `02_cd120_district_codes.csv` | Section 2 | BEF + seat/district-code references encoded in script | State/jurisdiction; expected versus observed district-code sets |
| `02_cd120_excluded_jurisdictions.csv` | Section 2 | BEF | Excluded jurisdiction, reported with its block/district counts |
| `02_puma_lookup_coverage.csv` | Section 3 | PUMA lookup | State/jurisdiction; tract/PUMA counts before geographic scope filtering |
| `02_block_puma_join.csv` | Section 3 | BEF + PUMA lookup | Retained state; matched/unmatched block and tract counts |
| `02_unmatched_tract_districts.csv` | Section 3 | BEF + PUMA lookup | Unmatched state/tract/district combination; can be a header-only CSV |
| `02_population_by_state.csv` | Section 5 | BEF + PL manifest/archives | State; source totals versus matched all-age/adult population |
| `02_unassigned_block_population.csv` | Section 5 | BEF + PUMA lookup + PL | Individual `ZZ` block, its PUMA and population counts |
| `02_cvap_ny_suppression_audit.csv` | Section 6 | BEF + CVAP identifiers + NY suppression workbook | NY block-group ID in either the missing-estimate or official suppression list |
| `02_cvap_ny_puma_district_impact.csv` | Section 7 | BEF + PUMA lookup + PL + CVAP + NY suppression | Every district intersection of the affected PUMAs, including blocks outside suppressed groups |
| `02_ct_cvap_identifier_audit.csv` | Section 8 | BEF + PL + CVAP + CT relationships | Original block group/planning-region candidate relationship; raw exceptions remain visible |

### Script 02: allocation preparation, contributions and weights

These products derive from reconciled BEF/PUMA geography, PL populations,
CVAP estimates and CT relationships. The NY suppression workbook and saved
CT query validate permitted exceptions. All seven raw input families and
the PL manifest are required for a completed Script 02 run.

| File | Writer | Immediate in-memory inputs | One row represents / purpose |
|---|---|---|---|
| `02_bg_identifier_links.csv` | Section 9 | Original block groups + reviewed CT correspondence | Original/target block-group link; `coverage_only` marks ambiguous water correspondence |
| `02_bg_district_support.csv` | Section 9 | Original block-group/PUMA/district counts + identifier links | Target block-group/PUMA/district intersection, with 2020 counts |
| `02_cvap_allocation_readiness.csv` | Section 9 | Intersection summaries + CVAP totals + reviewed rules | Target block group; published estimate, method and adjusted allocation input |
| `02_cvap_allocation_case_summary.csv` | Section 9 | Allocation readiness | Allocation case; counts, published/adjusted CVAP and adjustments |
| `02_cvap_structural_zero_audit.csv` | Section 9 | Allocation readiness + exact five-case checks + geographic sets | One reviewed structural-zero override, retaining its published estimate |
| `02_bg_cvap_contributions.csv` | Section 10 | Intersection counts + allocation readiness | Target block-group/PUMA/district intersection; estimated citizen-adult contribution |
| `02_bg_cvap_conservation.csv` | Section 10 | Contributions aggregated by block group + readiness | Target block group; contribution sum versus adjusted input |
| `02_puma_cd_cvap.csv` | Section 11 | Contributions aggregated by state/PUMA/assigned district | PUMA/district; complete CVAP contribution and separately labelled known subtotal |
| `02_puma_allocation_blocked.csv` | Section 11, on failure of the PUMA input check | Original block geography + contribution totals | One PUMA with unusable allocation inputs |
| `02_puma_allocation_audit.csv` | Section 11 | Original block geography + contribution totals + final weight summaries | PUMA; containment, missing CVAP, chosen method and weight-sum checks |
| `02_puma_cd_weights.csv` | Section 11 | Original assigned intersections + CVAP totals + containment rule | PUMA/district; export of the final crosswalk RDS |

**Disk versus calculation flow:** Script 02 saves these CSVs for inspection,
but does not load any generated CSV to perform a later section. It uses the
corresponding R objects already in memory. Editing an audit CSV does not
change the next calculation in Script 02. Script 03 reads the final crosswalk
RDS. Script 05 later reads `02_bg_cvap_contributions.csv` when estimating
overlaps between old and new districts. No current `02_personae` or `03_mrp` script consumes
these products; later interfaces have not yet been implemented.

## Script 02 CSV column reference

### Geography and population

| File | Columns, in file order |
|---|---|
| `02_cd120_coverage.csv` and `02_cd120_excluded_jurisdictions.csv` | `STATEFP, blocks, assigned_districts, unassigned_blocks, in_target` |
| `02_cd120_district_codes.csv` | `STATEFP, expected_districts, observed_districts, missing_codes, unexpected_codes, passed` |
| `02_puma_lookup_coverage.csv` | `STATEFP, tracts, pumas, in_target` |
| `02_block_puma_join.csv` | `STATEFP, blocks, matched_blocks, unmatched_blocks, unmatched_tracts, matched_pumas` |
| `02_unmatched_tract_districts.csv` | `STATEFP, tract_geoid, CDFP, blocks` |
| `02_population_by_state.csv` | `STATEFP, STUSAB, blocks, state_population, matched_population, state_vap, matched_vap, unassigned_blocks, unassigned_population, unassigned_vap` |
| `02_unassigned_block_population.csv` | `GEOID, STATEFP, CDFP, PUMA5CE, pop20, vap20` |
| `02_cvap_ny_suppression_audit.csv` | `bg_geoid, missing_from_cvap, geography_name, listed_in_errata` |
| `02_cvap_ny_puma_district_impact.csv` | `STATEFP, PUMA5CE, CDFP, blocks, population_2020, suppressed_bg_blocks, suppressed_bg_population_2020` |
| `02_ct_cvap_identifier_audit.csv` | `bg_2020, planning_region, source_rows, land_m2, water_m2, bg_cvap, population_2020, cvap_est, present_in_cvap` |

### Allocation preparation and contributions

| File | Columns, in file order |
|---|---|
| `02_bg_identifier_links.csv` | `STATEFP, bg_2020, bg_cvap, coverage_only` |
| `02_bg_district_support.csv` | `STATEFP, bg_cvap, PUMA5CE, CDFP, source_block_links, pop20, vap20, coverage_only` |
| `02_cvap_allocation_readiness.csv` | `STATEFP, bg_cvap, intersections, pumas, has_unassigned, wholly_unassigned, pop20, vap20, unassigned_vap20, coverage_only, cvap_est, allocation_case, structural_zero_override, cvap_structural_zero_adjustment, cvap_geographic_exclusion, cvap_for_allocation` |
| `02_cvap_allocation_case_summary.csv` | `allocation_case, block_groups, missing_estimates, published_cvap, allocation_cvap, structural_zero_adjustment, geographic_exclusion` |
| `02_cvap_structural_zero_audit.csv` | All readiness columns in the order above, followed by `observed_pumas, observed_districts` |
| `02_bg_cvap_contributions.csv` | `STATEFP, bg_cvap, PUMA5CE, CDFP, source_block_links, pop20, vap20, coverage_only, allocation_case, cvap_contribution` |
| `02_bg_cvap_conservation.csv` | `STATEFP, bg_cvap, cell_rows, cell_adults, unknown_cells, contributed_cvap, intersections, pumas, has_unassigned, wholly_unassigned, pop20, vap20, unassigned_vap20, coverage_only, cvap_est, allocation_case, structural_zero_override, cvap_structural_zero_adjustment, cvap_geographic_exclusion, cvap_for_allocation, cvap_difference, allocation_check_passed` |
| `02_puma_cd_cvap.csv` | `STATEFP, PUMA5CE, CDFP, known_cvap_subtotal, district_cvap` |
| `02_puma_allocation_blocked.csv` | `STATEFP, PUMA5CE, source_blocks, unassigned_blocks, assigned_districts, structural_containment, known_puma_cvap_subtotal, puma_cvap, missing_block_groups, weight_method` |
| `02_puma_allocation_audit.csv` | `STATEFP, PUMA5CE, source_blocks, unassigned_blocks, assigned_districts, structural_containment, known_puma_cvap_subtotal, puma_cvap, missing_block_groups, weight_method, weight_rows, weight_sum, zero_weight_rows` |
| `02_puma_cd_weights.csv` | `STATEFP, PUMA5CE, CDFP, allocation_weight, weight_method` |

The final PUMA audit is published after weight validation and the crosswalk
save. On a failed PUMA input check, the diagnostic lists only the blocked
PUMAs. A successful run removes any earlier diagnostic.

### Interpretation rules

- `source_block_links` counts correspondence links; reviewed water blocks
  can occur under multiple target groups. Its national sum is not a count
  of distinct original blocks.
- Source CVAP is stored once per target block group in readiness/conservation
  tables. Do not sum the repeated `cvap_est` values in the CT candidate table
  as though each link were an independent estimate.
- `cvap_contribution` is an estimated count and may be fractional. It is
  neither a person record nor a district probability.
- `district_cvap` is the complete estimated contribution for a PUMA/district
  intersection, not a total for that district across all PUMAs. If any
  contributing value is unknown, this complete sum remains missing.
- `known_cvap_subtotal` and `known_puma_cvap_subtotal` sum available values
  only. They must not be relabelled as complete totals where CVAP is missing.
- `cvap_for_allocation` retains the selected input after explicit adjustments.
  For observed estimates, the implemented identity is
  `cvap_est = cvap_for_allocation + cvap_structural_zero_adjustment + cvap_geographic_exclusion`.
- The documented run reconciled observed CVAP as
  `240785129 = 240785100 + 24 + 5`. These amounts exclude the 39 unknown NY
  estimates; they are not a complete national CVAP estimate.
- Readiness methods used by the contribution stage are `direct_containment`,
  `adult_proportions`, `zero_cvap`, `structural_zero_reviewed`,
  `exclude_unassigned` and `missing_cvap`. Unhandled cases stop execution
  for review; they are not automatically dropped or assigned zero.

## Script 03 allocation audits

Both audits use `pums_clean.rds` from Script 01 and `puma_cd_crosswalk.rds`
from Script 02. Script 03 uses its in-memory summaries for the calculations.

| File under `data/output/` | Writer and unit | Columns in saved order |
|---|---|---|
| `03_pums_crosswalk_coverage.csv` | Section 1, one row per state/PUMA across both inputs | `STATEFP, PUMA5CE, person_records, weighted_population, district_rows, positive_districts, weight_sum, coverage_status` |
| `03_pums_allocation_by_state.csv` | Section 2 calculates the audit for each state or DC. Section 3 saves it alongside the allocation. | `STATEFP, person_records, expected_rows, allocated_rows, input_weight, allocated_weight, max_person_weight_error` |

In the coverage audit, `person_records` counts retained microdata records
and `weighted_population` sums their `PERWT`. `district_rows` counts all
crosswalk intersections and `positive_districts` counts those with positive
weight. `coverage_status` takes values `matched`, `pums_only` or
`crosswalk_only`. The reviewed 2026-11-07 run matched all 2,462 PUMAs and
all 12,263,785 retained people, with total survey weight 240,960,972.

In the state allocation audit, `expected_rows` counts the person–district
rows implied by PUMA membership and positive district probabilities.
`allocated_rows` counts the result. `input_weight` and `allocated_weight`
compare the original weighted population with its district contributions.
`max_person_weight_error` is the largest absolute difference between a
person's `PERWT` and the sum of that person's allocated district weights.
The 2026-11-07 run saved the state audit and 20,333,303 person–district rows.
Expected and observed row counts agreed. The input and allocated weights
each totaled 240,960,972 at the precision reported. The largest absolute
person-weight difference across states was `1.136868e-13`.

## Demographic harmonization CSVs

The following tables are saved under `data/output/`. CES audit counts are
unweighted counts of respondents. District probabilities refer to the 2020-block
representation of residence on the 120th Congress map.

| File | Producer and direct inputs | Contents and use |
|---|---|---|
| `04_pums_hispanic_race_probabilities.csv` | 04, cleaned PUMS | One row per `race_cat` with `donor_records, donor_weight, probability`. Script 05 reconciles the conditional donor tables to these national totals by race. |
| `04_pums_demographic_coverage.csv` | 04, cleaned PUMS | One row per harmonized `variable` with `records, missing`. |
| `05_ces_sample.csv` | 05, raw CES | Three stages: all respondents, gender-eligible respondents, and respondents also reporting U.S. citizenship. Includes `citizen_yes, citizen_no, citizenship_missing` and the race/origin counts. |
| `05_ces_district_lookup.csv` | 05 geography helper, CD119 and CD120 block files, Step 02 CVAP contributions, PL manifest and split states' PL archives | By `STATEFP, CD119, county_fips, CD120`: all supported geographic intersections, including modeled zero-probability ones. The empty county key gives the entire old district. Fields include `district_probability, geography_method, blocks, overlap_cvap, possible_unresolved_cvap, probability_min, probability_max`. Script 05 uses this lookup for each citizen. |
| `05_ces_unknown_origin_cvap.csv` | 05 geography helper, same inputs as the district lookup | Separate ledger of CVAP with known destination and uncertain prior district. Includes state, county, block group, district candidates, counts of blocks, 2020 adult count and unresolved CVAP. The lookup also records the resulting probability bounds. |
| `05_ces_district_probabilities.csv` | 05, CES geographic identifiers and the district lookup | One row per citizen and positive-probability 120th district; includes the original state/district, county, location match, method, probability and a `selected` flag. Exactly one row per person is selected. |
| `05_ces_race_donor_support.csv` | 05, eligible primary-Hispanic CES respondents, district probabilities and PUMS conditional donor tables | One row per race recipient and positive-probability destination, with age/education/sex-gender profile, exact and used donor counts and effective counts, source pool, and five conditional probabilities. The selected district identifies the distribution used for the draw. |
| `05_ces_race_imputation.csv` | 05, recipient geography distributions, conditional donor probabilities and realized race draws | One row per race with `expected_respondents, expected_share, imputed_respondents, realized_share`. Expectations sum over every possible district; realized counts sum to the number of citizen recipients. |
| `05_ces_demographic_coverage.csv` | 05, eligible CES and race assignments | One row per harmonized `variable` with `records, missing`. |
| `05_ces_vote_sources.csv` | 05, linked pre/post CES items and wave-specific candidate rosters | Unweighted counts by office, source and result. Each office accounts for all retained respondents, including unresolved outcomes. |
| `06_ces_pums_cell_coverage.csv` | 06, harmonized CES records and aggregated PUMS cells | Survey-observed seven-key profiles, respondent count, frame population and match status. Incomplete CES keys are distinguished from complete profiles with no positive PUMS contribution. |

The [Script 05 decisions](05_citizenship_district_decisions.md) specify the
citizen rule, geography exceptions, donor weighting, fallback and the
interpretation of estimated individual districts.

## Generated documentation and other tracked metadata

| File | Producer or reader | Upstream inputs / purpose |
|---|---|---|
| `docs/02_cvap_suppression_audit.md` | Script 02 Section 6 writes the identifier checks and Section 7 adds the affected PUMA and district results | BEF/CVAP/NY suppression comparison, followed by BEF/PUMA/PL geographic impact. Links to the maintained decision record. |
| `docs/02_ct_cvap_identifier_audit.md` | Script 02 Section 8 writes the identifier checks and adds the reviewed exceptions | CT relationships, CVAP identifiers, mapped 2020 population and saved CT feature query. |
| `docs/00_pums_source.json` | Maintained after source review; Script 01 reads it | Approved compressed CSV size/SHA-256, required columns, parsed-variable-metadata fingerprint and its serialization method, source provenance and codebook snapshot details. Filenames are resolved from the local receipt. |
| `docs/02_pl_2020_sources.csv` | Manually maintained tracked input; read by Scripts 02, 05 and 07 | State keys, source URLs, local paths, sizes and fingerprints for all 51 population archives. |
| `docs/02_cvap_allocation_decisions.md` | Maintained by project review, not generated or parsed by the pipeline | Rationale and evidence for implemented exception rules. The executable rules are in Script 02. |
| [CES eligibility, district and race decisions](05_citizenship_district_decisions.md) | Maintained decision record for Script 05 | Rules for citizenship and gender eligibility, translating residence to 2026 districts, conditional race draws and donor fallback. |
| [CES vote rules](05_vote_rules.md) | Maintained decision record for Script 05 | Source questions, party coding by wave, priority of answers, DC delegate treatment and comparison with 2024 election returns. |

Step 02 recreates both tracked Markdown notes from the audit results held
in memory. To revise their text, edit the [audit note functions](../scripts/helpers/02_cvap_audit_notes.R).

Census technical documentation, state-code references and apportionment
tables cited in script comments explain hard-coded definitions. They are
not files fetched at runtime. The script's source URLs likewise document
provenance rather than initiate downloads.

## Area-level election returns

The [Step 07 guide](07_prepare_area_returns.md) gives the pinned releases,
candidate mapping, official-source reconciliation and residual definition.
Step 07 writes the following counts and audits. The state covariate file
additionally requires the Step 03 PUMS audit.

| Input | Source | What it contributes |
|---|---|---|
| `data/input/07_area_returns/1976-2024-president.csv` | MIT Election Data and Science Lab, U.S. President 1976–2024, v10.1. | State presidential vote lines, pooled write-ins and ballot-accounting rows. |
| `data/input/07_area_returns/1976-2024-house.csv` | MIT Election Data and Science Lab, U.S. House 1976–2024, v15.0. | Original-district House vote lines and ballot-accounting rows, including DC. |
| `data/input/05_vote_benchmark/fec2024.xlsx` | Federal Election Commission, official 2024 presidential returns. | State presidential totals for reconciliation and resolving source differences. Also used by the optional CES benchmark. |
| `data/input/05_vote_benchmark/clerk2024.pdf` | U.S. House Clerk, 2024 federal election statistics. | District House returns and tabulation notes for reconciliation. Also used by the optional CES benchmark. |
| `docs/02_pl_2020_sources.csv` | Census state manifest tracked with Step 02. | Postal abbreviations and two-digit state FIPS codes for all tables. |
| `data/output/03_pums_allocation_by_state.csv` | Step 03, cleaned PUMS and district allocation. | Weighted citizen adults by state, including DC, to calculate presidential shares. |

| Output built by Step 07 | Geographic unit and use |
|---|---|
| `data/intermediate/07_president_votes_2024.csv` | One row per state or DC. State candidate counts feed the presidential covariates. |
| `data/intermediate/07_state_presidential_covariates_2024.csv` | State candidate counts plus the Step 03 citizen-adult population. Supplies Democratic, Republican, Other and Did not vote shares. |
| `data/intermediate/07_house_votes_cd119.csv` | One row per 2024 House district, including DC. Step 09 fits the model to tabulated contests and carries observed counts to identical districts. |
| `data/output/07_mit_president_rows.csv` | One row per 2024 MIT presidential source line. Records candidate or ballot label, raw count and treatment. |
| `data/output/07_mit_house_rows.csv` | One row per 2024 MIT House source line. Records district, raw count, candidate or ballot label and treatment. |
| `data/output/07_president_source_votes_2024.csv` | State-by-selection audit of the FEC workbook. Preserves named candidates, write-ins, Nevada's explicit none option and empty source cells. |
| `data/output/07_house_source_lines_cd119.csv` | U.S. House Clerk source lines, including candidate and ballot-accounting entries. |
| `data/output/07_vote_source_comparison.csv` | One row per office and geography. Compares MIT and official totals and identifies the source or status of the selected counts. |

The 2024 House file uses `STATEFP` and `CDFP119`. District population cells
from Step 06 use `STATEFP` and `CDFP120`. A same-numbered district can
cover different voters in the two elections. Step 08 identifies exact matches
by their Census blocks. Step 09 uses each target district’s own demographics
and records the roster year and outcome source in its district-by-party file.

## District populations and candidate rosters

Step 08 has two independent entry points. One produces district population estimates from the 2020–2024 PUMS on each map. The other counts eligible named House nominees and records which parties fielded a sitting member in each election. Step 09 joins the district tables by state and district on the corresponding map. The detailed population inventory gives the Census archive names and the treatment of each geographic exception. [District population inputs and products](08_build_district_predictors.md#inputs-and-products) · [House roster sources](08_house_slates.md#sources-and-review)

| Product under `data/` | Producer and direct inputs | Use |
|---|---|---|
| `intermediate/08_puma_cd119_weights.csv` and `output/08_cd119_allocation_exceptions.csv` | The district predictors script compares the CD119 and CD120 block assignments. It reuses Step 02 weights in states with identical footprints and rebuilds weights elsewhere from Step 02 block-group tables and 2020 Census block adult counts. | The weights assign a fraction of each PUMA to each original district. The audit records exceptional block groups in the rebuilt states. |
| `output/08_district_overlap.csv` | The same script counts blocks in each assigned CD119 and CD120 intersection. | Step 09 uses the shared block counts and footprint match flag to identify districts eligible to retain observed 2024 counts. |
| `intermediate/08_pums_cd119_cells.rds` | The district predictors script joins Step 01 person weights and PUMAs to Step 04 demographics by `SAMPLE + SERIAL + PERNUM`, then applies the CD119 PUMA weights. | Population by district and demographic cell for the 2024 map. |
| `intermediate/08_district_demographics.csv` and `output/08_cd119_cvap_benchmark.csv` | The district predictors script summarizes CD119 cells and Step 06 CD120 cells. It checks state totals against Step 03 and compares CD119 totals to the Census CVAP archive’s `CD.csv`. | The first table supplies Step 09 with district CVAP and 29 demographic shares. The second records the CD119 comparison in people. |
| `intermediate/08_house_slates_2024.csv`, `intermediate/08_house_slates_2026.csv` and `output/08_house_slate_nominees.csv` | The candidate roster script reads the House Clerk’s `input/119-nominations.pdf` and `input/120-nominations.pdf`, plus the tracked state manifest and reviewed amendments. | Step 09 reads the nominee counts and the three 0/1 columns `incumbent_dem`, `incumbent_rep`, and `incumbent_other` from the same annual roster. The nominee audit gives each candidate’s inclusion, original Clerk service mark, incumbency flag and source. [Definition and examples](08_house_slates.md#which-parties-fielded-a-sitting-member) [State manifest](02_pl_2020_sources.csv) · [Roster amendments](08_house_slate_corrections.csv) |

## District-by-party House shares

Step 09 joins the Step 07 House returns and state presidential shares with the Step 08 two-map demographics, district overlap and candidate rosters. It checks the declared winners of the two unpolled contests against the nominee audit and their House membership records. [Unpolled winners and sources](09_unpolled_house_winners_2024.csv)

| Product under `data/intermediate/` | What it contains |
|---|---|
| `09_house_party_inputs.csv` | Available after `prepare`. One row per `congress, STATEFP, CDFP, party`, with four choices for each of 436 districts (including DC) on each map. The 3,488 rows include the district’s CVAP and 29 demographic shares, the matching statewide presidential share, the party’s nominee count and incumbency, the roster year and the outcome source. |
| `09_house_training_cd119.csv` | One row per district on the 2024 map. The beta models use vote counts, CVAP, demographic shares, state presidential shares, lineup and incumbency to train and evaluate the conditional shares. |
| `09_house_target_cd120.csv` | One row of predictors per district on the 2026 map, including the roster year and district-boundary match. |

Read `STATEFP` and `CDFP` as text to preserve leading zeros. The four choices
are `D`, `R`, `Other` and `DidNotVote` (no counted House candidate vote).
The observed shares sum to one in each of the 434 tabulated 2024 districts.
All four outcomes are missing for FL-20, OK-03 and the 2026 map. Count the
repeated CVAP only once per district and map. The nominee count, presence
and incumbency fields apply to the three candidate choices.
[House input preparation](09_model_house_votes.md) · [Fitted conditional shares](09_validate_house_beta.md)

Step 09 also writes `data/output/09_training_slate_counts.csv` to show how
many districts on the 2024 map had each ballot configuration, candidate structure
and election status.

## Validation, reruns and preservation

The [November 10 frame rebuild](../../docs/validation/e393b7f2-frame-rebuild/README.md)
records input and product fingerprints, including the 2024 House district
training table.

The [saved-file check](06_build_pums_cells.md#check-the-saved-analysis-files)
reads both CES files, the population frame and the Step 03 and 06 audit tables.
It prints a cross-file validation summary and writes no data products.

- The companion documents record successful acquisition, schema and offline
  reuse checks for Script 00, the completed Script 00 → Script 01 preparation
  run, Script 02's crosswalk validation and Script 03's national coverage and
  person–district allocation checks. The Step 04 guide records donor totals,
  Step 05 records the citizen sample, race draws and vote sources, and Step
  06 records population conservation and the overlap of the two saved files.
- Audits can be written before a script stops. This applies to NY/CT
  exception evidence, allocation-readiness/contribution audits and the
  diagnostic listing blocked PUMAs. A failed rerun can leave these files
  alongside final products from the last successful run.
- Script 02 writes final weights only after their crosswalk checks pass.
  The RDS files are saved through temporary files and renamed on success;
  an interrupted save may leave a temporary file.
- The current pipeline does not clear existing outputs at startup or attach a
  shared run identifier to every file. Check the run result and its
  recorded inputs rather than relying solely on a filename's existence.
- Downloaded inputs, working datasets and model fits stay local. Git records
  the source manifests, population manifest and generated Markdown notes in
  `docs/`. For the House validation, `data/output/09_beta_holdout/latest_complete.txt`
  identifies the published run. Its directory holds the PDF, district split,
  sampler diagnostics, predictions and scores included in Git.
- Numbered scripts recreate current products after their prerequisites
  are available. Script 00 acquires and verifies IPUMS snapshots; Script 01
  separately enforces the tracked source approval. Script 05 acquires and
  verifies the CES file and the 119th Congress block archive. The Script 02
  Census inputs follow their separate acquisition instructions. Ignored inputs
  are not distributed by cloning this repository. Mutable download URLs,
  especially the saved feature-query response, do not guarantee recovery
  of the pinned bytes. Exact reconstruction requires access to the reviewed
  snapshots.

Update this catalogue whenever a script gains or changes an input, output,
schema or consumer. Add catalogues for `02_personae` and `03_mrp` when their
actual interfaces are defined; neither has implemented data products yet.
