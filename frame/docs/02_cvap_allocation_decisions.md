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

## Reviewed structural zeros for allocation (2026-10-30)

Status: decision selected and code added to Script 02, Section 9.
Execution validation passed on 2026-10-30.

The five reviewed overrides retain their published estimates and set their
allocation inputs to zero. Their adjustment totals 24. The separate
Connecticut geographic exclusion totals 5. All 39 suppressed New York
estimates remain missing, and no unresolved allocation cases remain.

The available published estimates reconcile as:
240,785,129 = 240,785,100 for allocation + 24 structural-zero adjustment
+ 5 geographic exclusion. These totals exclude the unknown New York
estimates; they are not a complete national CVAP estimate.

Final crosswalk weights remain pending.

### Plain-language explanation

We treat the five reviewed block groups below as having zero citizen-adult
population for allocation. They cover military land, an airport, coastal
parkland or open water, and all their source blocks have zero recorded
population and zero adults in the 2020 Census.

This is an explicit project assumption. Zero population in 2020 does not
prove zero population throughout 2020-2024. The CVAP release documents
confidentiality noise, but we cannot establish that noise caused each
particular positive estimate.

We preserve the published estimates and record their removal from the
allocation inputs as a separate adjustment. No geographic records or
PUMS records are removed.

### Reviewed cases

| Block group | Geographic description | State/PUMA | Districts | Published CVAP | Allocation CVAP |
|---|---|---|---|---:|---:|
| 060379800031 | Los Angeles County portion of Edwards Air Force Base | 06/03772 | 23, 27 | 5 | 0 |
| 120219900000 | Offshore waters west of Naples and Marco Island | 12/02102 | 19, 22 | 4 | 0 |
| 120719800001 | Southwest Florida International Airport area | 12/07105 | 17, 19 | 5 | 0 |
| 120869806001 | Black Point Park and Marina and surrounding coastal area | 12/08623 | 27, 28 | 5 | 0 |
| 120999900000 | Atlantic Ocean waters off Palm Beach County | 12/09902 | 21, 23, 25 | 5 | 0 |

The rule applies only to these five identifiers. It is not an automatic
rule for all small estimates, all special-use areas, or every block group
with zero 2020 population.

### Implementation and accounting

- `cvap_est` retains the published estimate.
- `structural_zero_override` identifies these five reviewed cases.
- `cvap_structural_zero_adjustment` records the removed amount: 24 in total.
- `cvap_geographic_exclusion` separately records the earlier Connecticut
  water-area exclusion: 5 in total.
- `cvap_for_allocation` is the input for subsequent allocation calculations.
- `allocation_case` is `structural_zero_reviewed` for these five cases.

For each nonmissing published estimate:

`cvap_est = cvap_for_allocation + cvap_structural_zero_adjustment + cvap_geographic_exclusion`

The 39 suppressed New York estimates remain missing. Adjustment amounts
of zero on those rows mean no numerical override was applied; they do not
mean the missing population is zero. Their previously selected PUMA
containment rule remains applicable.

Before applying the overrides, the script checks the exact identifiers,
published estimates, PUMAs, district sets, and zero 2020 population/adult
counts. Other unresolved allocation cases still stop the script.

Generated evidence:
- `../data/output/02_cvap_structural_zero_audit.csv`
- `../data/output/02_cvap_allocation_readiness.csv`
- `../data/output/02_cvap_allocation_case_summary.csv`

The previously suggested proportional fallback was not adopted.

### Sources and interpretation

The quantitative checks use the pinned CVAP, district-assignment and
2020 population inputs already documented for Script 02.

Geographic descriptions were checked against these official sources:
- [Los Angeles Census tract map, sheet 2](https://www2.census.gov/geo/maps/DC2020/PL20/st06_ca/censustract_maps/c06037_los_angeles/DC20CT_C06037.pdf).
- [Collier Census tract map](https://www2.census.gov/geo/maps/DC2020/PL20/st12_fl/censustract_maps/c12021_collier/DC20CT_C12021.pdf).
- [Lee Census tract map](https://www2.census.gov/geo/maps/DC2020/PL20/st12_fl/censustract_maps/c12071_lee/DC20CT_C12071.pdf).
- [Miami-Dade Census tract map](https://www2.census.gov/geo/maps/DC2020/PL20/st12_fl/censustract_maps/c12086_miami-dade/DC20CT_C12086.pdf).
- [Palm Beach Census tract map](https://www2.census.gov/geo/maps/DC2020/PL20/st12_fl/censustract_maps/c12099_palm_beach/DC20CT_C12099.pdf).
- [2020-2024 CVAP technical documentation, page 4](https://www2.census.gov/programs-surveys/decennial/rdo/technical-documentation/special-tabulation/CVAP_2020-2024_ACS_documentation_v1.pdf).

The maps support the geographic descriptions. The decision to use zero
for allocation is ours, not a Census Bureau correction to the release.
