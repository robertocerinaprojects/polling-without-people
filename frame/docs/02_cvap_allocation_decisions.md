# CVAP allocation decisions

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
Connecticut geography reconciliation and the remaining crosswalk construction
are still pending.

### Sources and reproducible evidence

- [Census ACS Errata 148](https://www.census.gov/programs-surveys/acs/technical-documentation/errata/148.html).
- [Source audit, fingerprints and geographic impact](02_cvap_suppression_audit.md).
- Script: `../scripts/02_build_puma_cd_crosswalk.R`, Sections 6–7.
- Generated identifier audit: `../data/output/02_cvap_ny_suppression_audit.csv`.
- Generated impact audit: `../data/output/02_cvap_ny_puma_district_impact.csv`.
