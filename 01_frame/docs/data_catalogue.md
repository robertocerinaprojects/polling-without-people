# Frame data catalogue

## Plain-language summary

This catalogue explains what each data file is for, where it comes from,
which script reads or creates it, and what uses it next.

There are two separate starting points. Script 01 prepares citizen-adult
person records from IPUMS microdata. Script 02 combines Census geography,
population counts and citizen-adult estimates to build district probabilities
for each PUMA. Script 03 currently checks whether the two resulting datasets
cover the same PUMAs; it does not yet assign people to districts.

Most CSV outputs are evidence for reviewing those calculations. The two RDS
files are the working datasets read by Script 03. This catalogue describes
the active workflow and its reproducible products. It does not require
retired code, historical review CSVs or old documentation.

## Scope and reading conventions

This inventory was checked against code commit `65b0c42` and the Codespace
file listing supplied during repository cleanup on 2026-11-06. The listing
confirmed filenames, file sizes and CSV headers; it was not a rerun or a
review of every data row.

All paths in backticks are relative to `01_frame/` unless stated otherwise.
Script links below point to the active implementation:

| Name used here | Script | Companion document |
|---|---|---|
| Script 01 | [01_prepare_pums.R](../scripts/01_prepare_pums.R) | [PUMS preparation](01_prepare_pums.md) |
| Script 02 | [02_build_puma_cd_crosswalk.R](../scripts/02_build_puma_cd_crosswalk.R) | [Crosswalk construction](02_build_puma_cd_crosswalk.md) |
| Script 03 | [03_apply_puma_cd_crosswalk.R](../scripts/03_apply_puma_cd_crosswalk.R) | [Coverage and application](03_apply_puma_cd_crosswalk.md) |

See the [component README](../README.md#script-status) for current execution
status. Scripts 01 and 02 have documented successful runs for their pinned
inputs. Script 03 remains a draft: its CSV exists locally, but the execution
result has not been reviewed here. Person-level allocation is not implemented.

The active inventory comprises 59 external input files, two intermediate RDS
files and 26 output CSVs: four from Script 01, 21 from Script 02 and one from
Script 03. The tracked population-source manifest and two generated Markdown
notes are additional files in `docs/`. The four historical review CSVs found
during cleanup are recorded separately in the repository migration record.

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

All 59 files below must already exist locally. **None of the three current
numbered scripts downloads source data.** Acquisition used separate development
commands. To reconstruct the inputs, obtain the specified snapshots from the
URLs below, save them at the exact paths, and verify the recorded fingerprints.
Keep archives compressed; scripts read the required members themselves.

The two IPUMS MD5 values are recorded in Script 01's `expected_md5` and its
[input table](01_prepare_pums.md#inputs). Script 02 contains the six standalone
SHA-256 constants. The 51 PL archive sizes and SHA-256 values are maintained in
the [population manifest](02_pl_2020_sources.csv), not duplicated here.
These fingerprints identify the reviewed snapshots. A changed download needs
review rather than an automatic change to the expected fingerprint.

### PUMS source pair

- **Files:** `data/input/usa_00003.xml` and `data/input/usa_00003.csv.gz`.
- **Source:** Census ACS microdata harmonized by IPUMS USA, archived in
  [Zenodo record 21285306](https://zenodo.org/records/21285306).
- **Exact downloads:** [XML codebook](https://zenodo.org/api/records/21285306/files/usa_00003.xml/content)
  and [compressed CSV](https://zenodo.org/api/records/21285306/files/usa_00003.csv.gz/content).
- **Version:** 2020-2024 ACS five-year extract; `SAMPLE = 202403`, `YEAR = 2024`,
  `MULTYEAR` in 2020-2024. The XML supplies the extract schema and labels.
- **Reader:** Script 01 input checks and import.
- **Contributes to:** `pums_clean.rds` and all four `01_pums_*.csv` audits;
  subsequently the Script 03 coverage audit through `pums_clean.rds`.
- **Units and geography:** Individual records and person/household weights;
  person geography at the state/PUMA level. Ages and weights are not projected
  to the 2026 election.

The original CSV has these 24 columns, in order:

```text
YEAR, MULTYEAR, SAMPLE, SERIAL, CBSERIAL, HHWT, CLUSTER, STATEFIP,
PUMA, CPUMA1020, STRATA, GQ, HHINCOME, PERNUM, PERWT, SEX, AGE,
RACE, RACED, HISPAN, HISPAND, CITIZEN, EDUC, EDUCD
```

### BEF: block-to-district assignments

- **File:** `data/input/cd120.zip`; only member `NationalCD120.txt` is read.
- **Source/download:** [Census 120th Congress archive](https://www2.census.gov/programs-surveys/decennial/rdo/mapping-files/2027/120-congressional-district-befs/cd120.zip).
- **Version:** Pinned archive downloaded during review on 2026-10-30; its
  2020 block identifiers are used with the stored district assignments.
- **Reader:** Script 02 Sections 1-2; fingerprint `expected_sha256`.
- **Schema:** CSV with `GEOID, STATEFP, COUNTYFP, TRACTCE, BLOCKCE, CDFP`.
  One row per unique block `GEOID`; no population measure.
- **Scope:** Source includes Puerto Rico; processing retains the 50 states
  and DC and reports the excluded jurisdiction.
- **Contributes to:** District-code/scope audits, block matching, geographic
  exceptions, CVAP intersections, PUMA containment and final crosswalk weights.

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
- **Reader:** Script 02 Section 5 uses the Section 4 reader. It reads the
  manifest, verifies each local archive and reads two members:
  `<abbr>geo2020.pl` and `<abbr>000022020.pl`.
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

The current reader does not read segment 1/P1. The earlier Connecticut
POP100-versus-P1 comparison was a development check, identified below.
Script 02 reads but never rewrites the manifest.

### CVAP: published citizen-adult estimates

- **File:** `data/input/CVAP_2020-2024_ACS_csv_files.zip`; member `BlockGr.csv`.
- **Source/download:** [Census 2020-2024 CVAP archive](https://www2.census.gov/programs-surveys/decennial/rdo/datasets/2024/2024-cvap/CVAP_2020-2024_ACS_csv_files.zip).
- **Readers:** Script 02 Section 6 for identifiers; reread in Section 8 for
  national estimates and reused in memory in Section 9.
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

### CT relationships: older block groups and newer planning regions

- **File:** `data/input/acs22_cousub22_blkgrp20_st09.txt`.
- **Source/download:** [Census Connecticut relationship file](https://www2.census.gov/geo/docs/maps-data/data/rel2022/acs22_cousub22_blkgrp20_st09.txt).
- **Reader:** Script 02 Section 8; fingerprint `ct_lookup_sha256`.
- **Relevant columns:** Pipe-delimited `GEOID_BLKGRP_20, GEOID_COUSUB_22,
  AREALAND_PART, AREAWATER_PART`.
- **Meaning:** Intersections of 2020 block groups and 2022 county subdivisions.
  Land/water areas are square metres. This is not a direct old/new block-group
  correspondence table and supplies no population counts.
- **Use:** Derive candidate planning-region prefixes from subdivision codes,
  retaining the old tract/block-group suffix; validate candidates against
  the CVAP identifiers and reviewed exceptions.
- **Contributes to:** CT identifier audit and note, identifier links,
  geographic intersections and subsequent allocation products.

### CT feature query: saved check of two candidate identifiers

- **File:** `data/input/ct_bg_2024_identifier_check.json`.
- **Source:** Census TIGERweb's `tigerWMS_ACS2024` Block Groups feature layer
  (MapServer layer 10). It is a geographic feature table queried through a
  web service; the file is the saved JSON response, not a CVAP table.
- **Exact request:** [Saved-query URL](https://tigerweb.geo.census.gov/arcgis/rest/services/TIGERweb/tigerWMS_ACS2024/MapServer/10/query?where=GEOID+IN+%28%27091403431011%27%2C%27091703431011%27%29&outFields=GEOID%2CNAME%2CSTATE%2CCOUNTY%2CTRACT%2CBLKGRP%2CAREALAND%2CAREAWATER&returnGeometry=false&orderByFields=GEOID&f=json).
- **Acquisition:** The response was saved during review. A fresh response
  may have different bytes; preserve and verify the recorded snapshot.
- **Reader:** Script 02 Section 8; reads local JSON and performs no live query.
- **Relevant content:** Error/transfer-limit indicators and returned feature
  attributes `GEOID, AREALAND, AREAWATER`.
- **Evidence:** The response contains `091403431011`, with land area
  3,606,413 square metres and no water. Candidate `091703431011` is absent.
  The reviewed decision adopts the sole supported candidate while retaining
  every original block; it does not claim the boundaries are identical.
- **Contributes to:** Validation of the CT mapping convention and the generated
  CT note. All later allocation stages require this check to pass.

## Working datasets and direct dependencies

| File | Producer and upstream inputs | Direct downstream use |
|---|---|---|
| `data/intermediate/pums_clean.rds` | Script 01; PUMS source pair | Script 03 reads this RDS. It does not feed Script 02. |
| `data/intermediate/puma_cd_crosswalk.rds` | Script 02 Section 11; BEF + PUMA lookup + PL + CVAP + reviewed CT mapping; NY suppression and CT query validate exceptions | Script 03 reads this RDS. `02_puma_cd_weights.csv` is a readable export of the same table. |

### Cleaned person schema

`pums_clean.rds` contains one retained record per `SAMPLE + SERIAL + PERNUM`.
All 24 source columns above are retained, with six additional columns:
`gender, hispanic_flag, hispanic_detailed, race_detailed, educ_detailed,
hhincome_clean`.

The population is citizens aged 18+ at observation, including institutional
residents and DC. `gender` is a compatibility name for recorded-sex labels.
`hispanic_flag` is 0 for not Hispanic, 1 for Hispanic and missing for unknown.
Income sentinel `9999999` becomes missing; negative and zero income remain.
`STATEFIP + PUMA` is the location key; `CPUMA1020` is not used for this join.

The documented preparation run retained 12,263,785 records, 30 columns and
person-weight total 240,960,972. These are observed results for the pinned
extract, not requirements for every possible input dataset.

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
CVAP totals remain unknown. These probabilities have not yet been applied
to person records by the current Script 03.

## Current CSV products: producers and upstream inputs

All filenames in the following tables are under `data/output/`. Input names
refer to the source descriptions above. These tables identify inputs that
supply values or validation evidence; a successful sequential Script 02 run
also requires all preceding input checks to pass.

### Script 01: person preparation audits

All four outputs use the PUMS source pair. They are review tables; no active
script reads these CSVs back as inputs.

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
| `02_puma_allocation_audit.csv` | Section 11 | Original block geography + contribution totals + final weight summaries | PUMA; containment, missing CVAP, chosen method and weight-sum checks |
| `02_puma_cd_weights.csv` | Section 11 | Original assigned intersections + CVAP totals + containment rule | PUMA/district; export of the final crosswalk RDS |

**Disk versus calculation flow:** Script 02 saves these CSVs for inspection,
but does not load any generated CSV to perform a later section. It uses the
corresponding R objects already in memory. Editing an audit CSV does not
change the next calculation in the script. Script 03 reads the final RDS,
not the weights CSV. No current `02_personae` or `03_mrp` script consumes
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
| `02_puma_allocation_audit.csv` | `STATEFP, PUMA5CE, source_blocks, unassigned_blocks, assigned_districts, structural_containment, known_puma_cvap_subtotal, puma_cvap, missing_block_groups, weight_method, weight_rows, weight_sum, zero_weight_rows` |
| `02_puma_cd_weights.csv` | `STATEFP, PUMA5CE, CDFP, allocation_weight, weight_method` |

The PUMA audit schema above is its final successful-run schema. The script
also writes it earlier without the final three weight-summary columns.

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

## Script 03 coverage output

- **File:** `data/output/03_pums_crosswalk_coverage.csv`.
- **Producer:** Script 03 Section 1, currently a coverage-audit draft.
- **Direct inputs:** `data/intermediate/pums_clean.rds` from Script 01 and
  `data/intermediate/puma_cd_crosswalk.rds` from Script 02.
- **One row/key:** State/PUMA, using character `STATEFP + PUMA5CE`.
- **Columns:** `STATEFP, PUMA5CE, person_records, weighted_population,
  district_rows, positive_districts, weight_sum, coverage_status`.
- **Meaning:** `person_records` counts retained microdata records;
  `weighted_population` sums their `PERWT`. `district_rows` includes
  zero-weight intersections; `positive_districts` counts positive weights.
  `coverage_status` is `matched`, `pums_only` or `crosswalk_only`.
- **Consumer:** Review of whether every PUMS PUMA has a crosswalk entry.
  No later person-allocation implementation currently consumes this CSV.
- **Evidence/status:** Present in the supplied local inventory with the
  expected header. Its values and execution result remain to be reviewed.
  It is written before the unmatched-PUMS check, so its presence alone does
  not establish that the script passed.

## Generated documentation and other tracked metadata

| File | Producer or reader | Upstream inputs / purpose |
|---|---|---|
| `docs/02_cvap_suppression_audit.md` | Script 02 Section 6 writes it; Section 7 reads it back and appends results | BEF/CVAP/NY suppression comparison, followed by BEF/PUMA/PL geographic impact. Links to the maintained decision record. |
| `docs/02_ct_cvap_identifier_audit.md` | Script 02 Section 8 writes it, then reads it back and appends reviewed-exception results | CT relationships, CVAP identifiers, mapped 2020 population and saved CT feature query. |
| `docs/02_pl_2020_sources.csv` | Manually maintained tracked input; Script 02 Section 5 reads it | Source URLs, local paths, sizes and fingerprints for all 51 population archives. |
| `docs/02_cvap_allocation_decisions.md` | Maintained by project review, not generated or parsed by the pipeline | Rationale and evidence for implemented exception rules. The executable rules are in Script 02. |

The two generated Markdown notes are tracked, but a full Script 02 run
recreates their text. Change their generating code when revising them.
They are the only generated files Script 02 reads back; that read-back
appends narrative results, not inputs to the numerical calculation.

Census technical documentation, state-code references and apportionment
tables cited in script comments explain hard-coded definitions. They are
not files fetched at runtime. The script's source URLs likewise document
provenance rather than initiate downloads.

## Independence from retired files

The active scripts read only the inputs described in this catalogue and
current generated intermediates. Their calculations and documented exception
checks do not require historical scripts, pilot CSVs or legacy documentation.

The allocation decision record cites the current identifier, geographic
intersection, readiness and contribution audits. These are recreated by
Script 02. Its Section 9 rechecks the reviewed Connecticut locations and
Section 10 verifies the retained contribution of 5. A separate historical
location CSV is not required to establish those decisions.

Retirement history is maintained in the repository
[migration record](../../docs/migration.md). It is not an input or a prerequisite
for interpreting or running the current pipeline. The active workflow should
remain usable when the historical quarantine is deleted.

## Validation, reruns and preservation

- The companion documents record the reviewed checks and results for
  Scripts 01 and 02. The present inventory confirms their named products
  exist locally; it does not rerun those checks.
- Audits can be written before a script stops. This applies to NY/CT
  exception evidence, allocation-readiness/contribution audits and the
  early PUMA audit. A failed rerun can leave early products from the new
  attempt alongside older final products.
- Script 02 writes final weights only after their crosswalk checks pass.
  The RDS files are saved through temporary files and renamed on success;
  an interrupted save may leave a temporary file.
- The current pipeline does not clear old outputs at startup or attach a
  shared run identifier to every file. Check the run result and its
  recorded inputs rather than relying solely on a filename's existence.
- Downloaded and generated data are ignored by Git. Commits and pushes
  preserve scripts, source metadata and documentation, not these local
  data files. The generated Markdown notes and population manifest are
  tracked exceptions because they reside in `docs/`.
- Numbered scripts recreate current products after their prerequisites
  are available. Source acquisition remains separate; ignored inputs
  are not distributed by cloning this repository. Mutable download URLs,
  especially the saved feature-query response, do not guarantee recovery
  of the pinned bytes. Exact reconstruction requires access to the reviewed
  snapshots. This is a source-preservation requirement, not a dependency
  on historical code or documentation.

Update this catalogue whenever a script gains or changes an input, output,
schema or consumer. Add catalogues for `02_personae` and `03_mrp` when their
actual interfaces are defined; neither has implemented data products yet.
