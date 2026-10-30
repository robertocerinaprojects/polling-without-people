# CVAP allocation decisions

## Plain-language summary

This document explains the choices we make when missing estimates or
differences between geographic definitions prevent a straightforward
CVAP allocation.

In the New York cases reviewed here, missing citizen-adult estimates do
not prevent allocation: each affected PUMA lies entirely within one
district. Its allocation weight can therefore be 1 without inventing
the missing population counts.

In Connecticut, we reconcile older block-group identifiers with the
newer identifiers used by the CVAP estimates. We document how to handle
ambiguous relationships and positive CVAP estimates in places with no
recorded 2020 population. Each published estimate is counted once, and
amounts excluded from district allocation remain visible in the audits.

The cases reviewed so far have documented treatments and supporting
checks. Implementing these treatments in the final allocation remains
pending. New exceptions must be reviewed explicitly.

## New York suppression — decision recorded 2026-10-30

Status: allocation rule selected; implementation in the final crosswalk pending.

### Decision

Apply a general structural allocation rule: if every mapped block of a PUMA
belongs to the same valid congressional district, assign allocation weight 1
to that district. Include zero-population blocks when checking district coverage.
Unassigned district codes do not satisfy this condition.

This rule applies to any qualifying PUMA, rather than being a hard-coded
New York exception.

### Evidence

The 39 New York block groups missing from the 2020–2024 ACS CVAP file exactly
match the Census Errata 148 suppression list.

All blocks of the two affected PUMAs belong to NY-02 under our pinned
120th Congress block-equivalency file:

| State/PUMA | District | All blocks | 2020 total population | Population in suppressed block groups |
|---|---|---:|---:|---:|
| 36/03310 | NY-02 | 1,369 | 130,712 | 62,387 |
| 36/03313 | NY-02 | 1,880 | 117,217 | 11,876 |

The suppressed block groups contain 74,263 residents in the 2020 Census.
These are all-age population counts, not CVAP estimates.

### Rationale and alternatives

Geographic containment determines the allocation without requiring the
missing citizen-adult counts. Both PUMAs receive weight 1 for NY-02.

No CVAP imputation, older-period substitution, or adult-population fallback
is needed for these allocation weights. Missing CVAP values remain missing;
they are not interpreted as zero. PUMS residents are retained.

Census Errata 148 explicitly states that PUMS files are unaffected. It also
cautions against affected 2016–2020, 2017–2021 and 2018–2022 ACS estimates,
so those releases are not automatically suitable replacements.

### Validation and limitations

The audit checks district coverage using all blocks in each affected PUMA,
including zero-population blocks, and checks population conservation during
aggregation.

The final crosswalk must implement the general rule and verify that the
two affected PUMAs each receive a single NY-02 row with weight 1.

This resolves their allocation weights under the pinned block geography.
It does not recover missing CVAP counts for block groups or PUMAs.
Connecticut mapping decisions are recorded below. Applying those decisions
and constructing the final crosswalk remain pending.

### Sources and reproducible evidence

- [Census ACS Errata 148](https://www.census.gov/programs-surveys/acs/technical-documentation/errata/148.html).
- [Source audit, fingerprints and geographic impact](02_cvap_suppression_audit.md).
- Script: `../scripts/02_build_puma_cd_crosswalk.R`, Sections 6–7.
- Generated identifier audit: `../data/output/02_cvap_ny_suppression_audit.csv`.
- Generated impact audit: `../data/output/02_cvap_ny_puma_district_impact.csv`.

## Connecticut: positive CVAP with zero 2020 population

Decision recorded 2026-10-30.
Status: treatments selected; final allocation implementation pending.

### Land block group 091902114003

Retain the published CVAP estimate of 5. Its candidate source block group,
090012114003, contains two blocks, both in PUMA 20904 and district CT-05.
Allocate the entire estimate once to that PUMA–district intersection.

This is a CVAP contribution of 5, not a final PUMA allocation weight.
Geographic containment makes a within-block-group population split unnecessary.

### Water block group 091309901000

Retain the published CVAP estimate of 5 in the source and exception audits.
Exclude it from the assigned-district allocation domain.

Its candidate source coverage consists of:
- 090079901000: six blocks in PUMA 20500, all with district code ZZ.
- 090119901000: five blocks in PUMA 20401, all with district code ZZ.

The target estimate is 5 in total, despite appearing on two candidate rows.
Do not duplicate it across source block groups or assign it to a nearby district.
PUMAs 20401 and 20500 remain in scope; no PUMS records are removed.

### General rules and reconciliation

For a validated target block group contained in one PUMA and one assigned
district, allocate its CVAP estimate directly to that intersection, including
when the 2020 population denominator is zero.

For a target whose entire candidate source coverage is unassigned to districts,
retain its estimate in the source audit and account for it separately as
excluded from district allocation.

Construct allocation numerators and denominators from the same assigned
contributions. Reconcile source CVAP into allocated, excluded and unresolved
amounts, counting each target estimate once.

For these two cases, 5 is retained for allocation and 5 is excluded.
This is not a national exclusion total.

Neither decision relies on a threshold of 5 or assumes that the estimates
are caused by privacy noise. Published source values remain unchanged.

### Remaining work and evidence

The 160-square-metre overlap involving original block group 090093431011
is addressed by the specific mapping convention recorded below.
The reviewed identifier exception checks have passed. Applying the
Connecticut mapping and validating the final allocation remain pending.

The final pipeline must reproduce the containment checks, implement the
selected treatments, and stop if new or unclassified exceptions appear.

Evidence:
- [Connecticut identifier audit](02_ct_cvap_identifier_audit.md).
- Candidate relationships: `../data/output/02_ct_cvap_identifier_audit.csv`.
- Focused location audit: `../data/output/02_ct_cvap_zero_population_locations.csv`.

## Connecticut: small boundary-overlap convention

Decision recorded 2026-10-30.
Status: mapping convention selected; final allocation implementation pending.

Map original block group `090093431011` to `091403431011`.
Retain all original block records and their 2020 population totals.

The relationship file reports 3,606,413 square metres of land in planning
region 09140 and 160 square metres in planning region 09170. Retaining the
old tract/block-group suffix produces two candidate IDs.

The official 2024 geographic catalogue returns `091403431011`, with land
area 3,606,413 square metres and no water, but does not return `091703431011`.

We adopt the sole valid candidate as a specific mapping approximation.
The unsupported overlap is approximately 0.00444% of the relationship
file's total land overlap. This is not a population-error estimate or proof
of identical boundaries. We do not adopt a general largest-area rule.

Reject the unsupported candidate relationship, not any original block or
population record. Preserve the raw relationship in the audit.

### Source snapshot

- File: `../data/input/ct_bg_2024_identifier_check.json`.
- SHA-256: `a01ecdfb5bfe0fe4119a3aab71007408f458ebc5c0c580a04402fe102a51bb87`.
- Exact query: https://tigerweb.geo.census.gov/arcgis/rest/services/TIGERweb/tigerWMS_ACS2024/MapServer/10/query?where=GEOID+IN+%28%27091403431011%27%2C%27091703431011%27%29&outFields=GEOID%2CNAME%2CSTATE%2CCOUNTY%2CTRACT%2CBLKGRP%2CAREALAND%2CAREAWATER&returnGeometry=false&orderByFields=GEOID&f=json

The script checks the reviewed absent candidate, the known water-group
collision, and the complete set of multi-region relationships. New
exceptions require review rather than automatic acceptance.
