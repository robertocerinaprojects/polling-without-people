# 02 — Build PUMA-to-district crosswalk

## Plain-language summary

Our PUMS file contains individual records for which we know the PUMA,
but not the block group or block. We want to assign each individual a
probability of allocation to each congressional district equal to the
estimated share of citizen adults in their PUMA who live in that district.

To calculate this, we start with the ACS estimate of citizen adults in
each block group. The proposed method distributes that estimate among
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

**Implementation status, 2026-10-30:** National block population and
adult-population matching passed, as did the reviewed New York and
Connecticut geographic checks. Constructing and validating the final
allocation weights remains pending. The summary above describes the
intended completed method.

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

These are 2020 adult counts, including noncitizens. The planned use is to
distribute 2020-2024 ACS block-group CVAP estimates among geographic
pieces. This requires an approximation about the distribution within
each block group. Zero adult-population denominators require explicit
handling before allocation.

This addition reads and validates adult counts; it does not yet
construct the CVAP allocation weights.


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

This stage prepares allocation inputs. Final crosswalk weights remain
to be calculated and validated.

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
Final crosswalk weights remain pending.
