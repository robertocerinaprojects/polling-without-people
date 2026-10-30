# 02 — Build PUMA-to-district crosswalk

## Plain-language summary

Our PUMS file contains individual records for which we know the PUMA,
but not the block group or block. We want to assign each individual a
probability of allocation to each congressional district equal to the
estimated share of citizen adults in their PUMA who live in that district.

To calculate this, we start with the ACS estimate of citizen adults in
each block group. The method distributes that estimate among
its constituent blocks in proportion to their 2020 adult populations.
This assumes that, within each block group, citizen adults follow the
same spatial distribution as those adult counts. Differences in
citizenship rates between blocks and population changes since 2020 can
make this approximation inaccurate.

Using the geographic mappings, we identify each block's PUMA and
assigned district. We then add up the estimated citizen-adult
contributions for each PUMA–district combination and divide by the
corresponding PUMA total. The numerator and denominator must use the
same allocation basis.

Those shares form the PUMA-to-district crosswalk. A subsequent step uses
them to allocate the PUMS records. Every individual in the same PUMA
receives the same probability distribution, regardless of their
demographic characteristics. These are estimated allocation
probabilities; they do not reveal individuals' actual districts.

If a PUMA lies entirely within one assigned district, its allocation
weight is 1 without needing to estimate an internal split. Missing CVAP,
zero adult-population denominators and geographic exceptions follow the
separately documented rules in
[CVAP allocation decisions](02_cvap_allocation_decisions.md).
Missing estimates are not silently treated as zero.

**Implementation status, 2026-10-30:** Crosswalk construction and its
implemented checks passed, including population matching, the reviewed
geographic exceptions, CVAP accounting and within-PUMA weight sums.
The crosswalk has been saved. Coverage of the retained PUMS records and
application of these weights will be checked in the next stage.

## Connecticut development check

Verified on 2026-10-30 using the pinned Connecticut archive:

- All 49,926 blocks matched the district assignments.
- Block populations summed to the state total of 3,605,944.
- All 81 unassigned blocks had zero recorded population.
- POP100 and P1 totals agreed for every block.

The pilot code was replaced by the nationwide manifest loop.

## CVAP allocation decisions

See [CVAP allocation decisions](02_cvap_allocation_decisions.md) for the selected rules, evidence and implementation status.


## Reading 2020 block adult population

Script 02 reads P0030001, the total population aged 18 and over, from
segment 2 of each pinned 2020 PL 94-171 archive. It stores this as `vap20`.

The column order follows the Census Bureau's official R import script,
`R Versions/pl_part2_2020_dar.r`, lines 168-170:
five linking fields, 71 P3 cells, 73 P4 cells and three H1 cells.
P0030001 is therefore field 6.

Sources:
- [Official R import scripts](https://www2.census.gov/programs-surveys/decennial/rdo/about/2020-census-program/Phase3/SupportMaterials/2020PL_R_import_scripts.zip).
- [P3 variable definitions](https://api.census.gov/data/2020/dec/pl/groups/P3.html).

Records are matched within each state using LOGRECNO. Checks require
unique segment record identifiers, complete matches for state and block
records, integer counts between zero and total population, and block
adult counts summing to the state adult total.

These are 2020 adult counts, including noncitizens. They are used to
distribute 2020-2024 ACS block-group CVAP estimates among geographic
pieces. This requires an approximation about the distribution within
each block group. Zero adult-population denominators require explicit
handling before allocation.

Adult counts are validated before Sections 10-11 calculate the
CVAP contributions and allocation weights.


## Preparing national allocation inputs

Section 9 brings together block-group geography, PUMA and district
membership, adult counts, and the published CVAP estimates. It identifies
which block groups can be allocated directly, which require proportional
allocation, and which need further review.

The original block-group aggregation must preserve all block counts,
total population and adult population. Reviewed Connecticut identifier
rules are then applied. Ambiguous water relationships remain labelled
as conservative source coverage, rather than an exact partition of
blocks between newer block groups.

CVAP estimates are held once per target block group. They are not summed
after being repeated across district intersections. Missing New York
estimates remain unknown.

Outputs in `data/output`:
- `02_bg_identifier_links.csv`: original-to-CVAP identifier relationships.
- `02_bg_district_support.csv`: geographic coverage and 2020 population.
- `02_cvap_allocation_readiness.csv`: one row per target block group,
  containing its published CVAP estimate and proposed allocation case.

The national sum of `source_block_links` is not a unique-block count:
reviewed zero-population water coverage can appear under multiple
target groups. Population totals must nevertheless remain conserved.

This stage prepares inputs for the contribution and weight calculations
in Sections 10-11.

## Structural-zero allocation overrides

Section 9 implements the five reviewed structural-zero decisions recorded
on 2026-10-30. Their published CVAP estimates sum to 24 and remain visible
in the audits; their allocation inputs are zero.

The earlier Connecticut geographic exclusion of 5 is accounted for
separately. Missing New York estimates remain missing.

Subsequent weight calculations must use `cvap_for_allocation` and the
documented allocation cases, including the PUMA containment rule.

See [the allocation decision record](02_cvap_allocation_decisions.md)
for the exact cases, rationale, sources and accounting identity.

Section 9 execution validation passed on 2026-10-30, including the
five structural-zero overrides and the CVAP accounting checks.
Sections 10-11 construct the final crosswalk and passed their internal
checks on 2026-10-30.

## Calculating block-group CVAP contributions

Section 10 divides each block group's adjusted CVAP among its
PUMA-district portions. We first add up the 2020 adult counts in each
portion, then use that portion's share of all adults in the block group
to divide the CVAP estimate. This is algebraically equivalent to
allocating CVAP to individual blocks and then adding their contributions.

For directly contained block groups, the full adjusted estimate goes
to the single PUMA-district intersection. Published zero estimates,
reviewed structural zeros and the excluded Connecticut water estimate
contribute zero. Suppressed New York estimates remain unknown.

These contributions are estimates and can be fractional. They are not
rounded, and this stage does not assign individual PUMS records.

The script checks that:
- Direct allocation has exactly one destination.
- Proportional allocation uses a positive adult denominator.
- Missing contributions occur exactly for the reviewed New York cases.
- Each block group's contributions preserve its adjusted CVAP.
- Adult counts and geographic intersections remain conserved.
- Unassigned district rows receive no positive CVAP.
- The Connecticut land estimate of 5 is allocated exactly once.
- Contributions from observed estimates reconcile nationally.

Floating-point comparisons allow an absolute error of
`1e-8 + 1e-12 * abs(expected)`. This is a numerical tolerance, not a
statistical uncertainty interval.

Outputs in `data/output`:
- `02_bg_cvap_contributions.csv`: one row per block-group/PUMA/district
  intersection, containing its estimated CVAP contribution.
- `02_bg_cvap_conservation.csv`: one row per block group, containing
  published and adjusted estimates, contributions and validation results.

The intersection table omits repeated block-group CVAP totals to reduce
the risk of double counting. The conservation audit retains those totals
once per block group.

Section 10 execution validation passed on 2026-10-30.
Contributions from observed adjusted estimates total 240,785,100.
All 39 missing block-group estimates remain unknown.
The largest absolute block-group conservation error was zero.

## Constructing PUMA-to-district weights

Section 11 adds up the estimated citizen-adult contributions for each
PUMA-district intersection. For a PUMA spanning districts, it divides
each district's contribution by the complete adjusted CVAP total in
that PUMA.

If every original block of a PUMA belongs to one assigned district,
geography determines the allocation: that district receives weight 1.
This check includes zero-population blocks. Any unassigned block
prevents this structural-containment classification.

The two reviewed New York PUMAs therefore receive weight 1 for NY-02,
while their complete CVAP totals remain unknown. No missing population
estimate is filled in.

A PUMA requiring proportional allocation must have a complete, finite,
positive denominator. Otherwise the script stops for review.

The output retains valid geographic intersections with weight zero.
It excludes district code ZZ. Geographic identifiers remain character
strings, preserving leading zeros.

Validation checks:
- Exact agreement with original assigned PUMA-district intersections.
- Conservation of known CVAP contributions during aggregation.
- Complete PUMA coverage.
- Finite weights between zero and one.
- Weights summing to one within each PUMA.
- Positive allocation coverage for every assigned district.
- NY-02 weight 1 for PUMAs 36/03310 and 36/03313, with unknown
  complete CVAP totals preserved.

The weight-sum tolerance is 1e-12, a numerical allowance rather than
a statistical uncertainty interval.

Outputs:
- `data/intermediate/puma_cd_crosswalk.rds`: crosswalk for the next stage.
- `data/output/02_puma_cd_weights.csv`: readable copy of the crosswalk.
- `data/output/02_puma_cd_cvap.csv`: complete district contributions and
  separately labelled known subtotals.
- `data/output/02_puma_allocation_audit.csv`: PUMA coverage, complete
  CVAP totals, known subtotals, missingness, methods and weight sums.

The crosswalk columns are STATEFP, PUMA5CE, CDFP, allocation_weight and
weight_method. These weights have not yet been applied to PUMS records.

Section 11 execution passed on 2026-10-30.

| Check or output | Result |
|---|---:|
| PUMAs in the crosswalk | 2,462 |
| Assigned districts, including DC | 436 |
| PUMA-district rows | 4,183 |
| PUMAs using structural containment | 1,110 |
| PUMAs using CVAP shares | 1,352 |
| Retained zero-weight rows | 109 |
| Largest absolute within-PUMA weight-sum error | 2.220446e-16 |

Both reviewed New York PUMAs receive weight 1 for NY-02. Their complete
CVAP totals remain unknown; the missing estimates were not replaced by zero.

These checks establish internal consistency for the pinned inputs.
They do not independently validate the spatial allocation assumptions.
The weight-sum discrepancy is floating-point rounding.
The subsequent application stage must check that every retained PUMS
PUMA has a matching crosswalk entry before allocating records.
