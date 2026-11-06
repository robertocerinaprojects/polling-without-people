# Frame data catalogue

## Plain-language summary

This catalogue explains each data file's purpose, source, producer and
consumer. Script 00 downloads the specified IPUMS USA sample and records its
source files. Script 01 verifies those files against the approved source
manifest and prepares citizen-adult person records.

Script 02 independently combines Census geography, population counts and
citizen-adult estimates to build district probabilities for each PUMA.
Script 03 currently checks whether the two resulting datasets cover the
same PUMAs; person-level district allocation is not yet implemented.

The audit CSVs record the calculations and checks. The two intermediate RDS
files contain the working datasets read by Script 03.

## Scope and reading conventions

All paths in backticks are relative to `01_frame/` unless stated otherwise.

| Name used here | Script | Companion document |
|---|---|---|
| Script 00 | [00_download_pums.R](../scripts/00_download_pums.R) | [IPUMS download](00_download_pums.md) |
| Script 01 | [01_prepare_pums.R](../scripts/01_prepare_pums.R) | [PUMS preparation](01_prepare_pums.md) |
| Script 02 | [02_build_puma_cd_crosswalk.R](../scripts/02_build_puma_cd_crosswalk.R) | [Crosswalk construction](02_build_puma_cd_crosswalk.md) |
| Script 03 | [03_apply_puma_cd_crosswalk.R](../scripts/03_apply_puma_cd_crosswalk.R) | [Coverage and application](03_apply_puma_cd_crosswalk.md) |

Scripts 00 and 01 passed the complete download-to-preparation run, including
source checks and saving the cleaned RDS. Script 00 also passed offline reuse.
Script 02 passed its documented crosswalk checks. Script 03 remains a draft;
its coverage CSV exists locally, but its execution result remains to be
reviewed. See the [component status](../README.md#script-status).

The source-data requirement is 59 files: one selected two-file IPUMS pair
and 57 Census files. Script 00 also keeps request/receipt metadata and source
snapshots; the physical file count depends on the number of downloads.

Analysis products comprise two intermediate RDS files and 26 output CSVs:
four from Script 01, 21 from Script 02 and one from Script 03. Source manifests
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
approval checks. The Census inputs use the acquisition instructions below.
Keep source archives compressed; scripts read their required members.

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
  subsequently the Script 03 coverage audit through `pums_clean.rds`.
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
| `data/intermediate/pums_clean.rds` | Script 01; approved IPUMS pair acquired by Script 00, local pointer/receipt and tracked source approval | Script 03 reads this RDS. It does not feed Script 02. |
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
CVAP totals remain unknown. These probabilities have not yet been applied
to person records by the current Script 03.

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
| `docs/00_pums_source.json` | Maintained after source review; Script 01 reads it | Approved compressed CSV size/SHA-256, required columns, parsed-variable-metadata fingerprint and its serialization method, source provenance and codebook snapshot details. Filenames are resolved from the local receipt. |
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

## Validation, reruns and preservation

- The companion documents record successful acquisition, schema and offline
  reuse checks for Script 00, the completed Script 00 → Script 01 preparation
  run, and Script 02's crosswalk validation. Script 03 remains a draft.
- Audits can be written before a script stops. This applies to NY/CT
  exception evidence, allocation-readiness/contribution audits and the
  early PUMA audit. A failed rerun can leave early products from the new
  attempt alongside retained final products.
- Script 02 writes final weights only after their crosswalk checks pass.
  The RDS files are saved through temporary files and renamed on success;
  an interrupted save may leave a temporary file.
- The current pipeline does not clear existing outputs at startup or attach a
  shared run identifier to every file. Check the run result and its
  recorded inputs rather than relying solely on a filename's existence.
- Downloaded and generated data are ignored by Git. Commits and pushes
  preserve scripts, source metadata and documentation, not these local
  data files. The generated Markdown notes and population manifest are
  tracked exceptions because they reside in `docs/`.
- Numbered scripts recreate current products after their prerequisites
  are available. Script 00 acquires and verifies IPUMS snapshots; Script 01
  separately enforces the tracked source approval. Other source acquisition
  remains separate, and ignored inputs are not distributed by cloning this
  repository. Mutable download URLs,
  especially the saved feature-query response, do not guarantee recovery
  of the pinned bytes. Exact reconstruction requires access to the reviewed
  snapshots.

Update this catalogue whenever a script gains or changes an input, output,
schema or consumer. Add catalogues for `02_personae` and `03_mrp` when their
actual interfaces are defined; neither has implemented data products yet.
