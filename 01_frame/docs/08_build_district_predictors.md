# 08 — Build the 2024 citizen-adult district frame

## Plain-language summary

We want to learn from the people covered by each House contest in 2024, then
apply the same variables to districts on the 2026 map. The same five-year
PUMS extract describes both populations. In 2024, the unit is the district
elected to the 119th Congress. In 2026, it is the district electing the
120th Congress. A district number can stay the same while the residents
inside its boundaries change.

We take each PUMA's citizen-adult residents and assign fractions of their survey
weights to the districts it overlaps. For the older map, those fractions use the
Census blocks actually assigned to each **119th** district. They estimate
location within a PUMA. As in Step 02, this assumes people with different
demographic characteristics in the same PUMA have the same district
probabilities. The output records the size of each demographic group as a share
of all citizen adults in its district. Both maps include DC's delegate.

## Run

From the repository root, after Steps 01–06:

```sh
Rscript 01_frame/scripts/08_build_district_predictors.R
```

The R script calls the Python standard-library helper
[08_cd119_weights.py](../scripts/helpers/08_cd119_weights.py).
Step 05 already caches the Census `cd119.zip` file; the geographic helper
can fetch this one input if necessary. The other source archives and the
Step 02, 03, 04 and 06 products must be available locally.

## Geography and the two frames

1. Join the two pinned national Census block-equivalency files by their
   15-character block GEOID. Count blocks for every pair of assigned old and new
   districts. Call a footprint identical only if those joint blocks exhaust
   **both** district footprints. This also detects identical, renumbered areas.
   Unassigned `ZZ` water blocks have no voting district. The Census tabulates
   split blocks using a designated whole-block assignment. [119th Congress block
   equivalency files](https://www.census.gov/geographies/mapping-files/2025/dec/rdo/119-congressional-district-bef.html)
2. In states whose district footprints are all identical, carry the verified
   Step 02 PUMA weights to the corresponding CD119 IDs. This preserves the
   reviewed Connecticut and New York treatments after testing geographic
   identity. In changed states, reaggregate the original 2020 PL voting-age
   counts by block group and CD119. Check the block and adult counts against
   Step 02 at the CD120 level before computing old districts. The Step 02
   contributions also identify each block group's PUMA. In these changed
   states each source group belongs to exactly one PUMA.
3. Start with the published block-group CVAP estimate. A group contained in
   one assigned district contributes its full estimate, even with zero
   recorded 2020 adults. For a split group with adult support, distribute
   its estimate in proportion to its 2020 adult counts. Keep all block
   footprints, including cells with zero population, for containment.
   Wholly unassigned geography contributes no district CVAP.
4. For a split-PUMA crosswalk weight, divide the assigned CVAP in its
   intersection with CD119 by the assigned CVAP of the PUMA. A PUMA
   contained wholly in one assigned district has weight one. Reconcile
   geographic exclusions and check PUMA weights sum to one.
5. Read the original PUMS weights and PUMA IDs from Step 01 and the matching
   Step 04 demographics. Sum `PERWT` within each PUMA and demographic cell,
   multiply by the CD119 district weights, and then sum by district and
   cell. Every person in a PUMA receives the same geographic fractions, so
   this gives the same cell totals as splitting the weight of every person
   into separate person/district rows. Save the CD119 frame and derive its
   margins. Use the existing Step 06 cells for the CD120 margins.

### Old-map zero-adult decisions

A structural zero is an assumption about the contribution used in the
crosswalk. A published estimate is counted in full if a single assigned
old district identifies its location. If the old map splits a positive
estimate with zero recorded adult population, the script accepts the
zero-contribution convention only for reviewed cases. An unsupported case
stops the build and prints its state, block group, PUMA, estimate and
candidate districts for investigation. The original five CA/FL cases and
their estimates come from the [Step 02 decision record](02_cvap_allocation_decisions.md).
Their old-map treatment is determined from their CD119 coverage.

Tarrant County block group `484391139322` has a published estimate of five.
Step 05 established that its blocks belong entirely to TX-12 on CD120 and
span TX-12 and TX-26 on CD119, with zero recorded 2020 adults in both
intersections. For the CD119 crosswalk we record the source five and omit
its five from both the assigned-PUMA denominator and the two candidate
numerators. For CD120, Step 02 assigns its full five to TX-12. This extends
the reviewed zero-support convention to this specific 2024 ambiguity. All
PUMS people and their full original person weights remain in the frames.

## Inputs and products

All paths below are relative to `01_frame/data/` unless noted.

| Input | Use |
|---|---|
| `input/cd119.zip` and `input/cd120.zip` | Congressional district ID for each Census block on each map. Step 05 verifies both archive fingerprints. |
| `../docs/02_pl_2020_sources.csv` and `input/pl_2020/` | Identify and verify each needed state PL archive. Its block-level adult counts support within-block-group splits. |
| `output/02_bg_cvap_contributions.csv`, `output/02_cvap_allocation_readiness.csv` | Reconciled geographic support, PUMA, adult population, and one published CVAP estimate per group. |
| `output/02_puma_cd_weights.csv` | Verified PUMA weights where all district footprints in a state are identical. |
| `intermediate/pums_clean.rds`, `intermediate/pums_demographics.rds` | Person survey weights and original geography, linked to the exact harmonized demographics via sample, serial and person number. |
| `intermediate/pums_cd_cells.rds`, `output/03_pums_allocation_by_state.csv` | Step 06's CD120 frame and common state PUMS totals for reconciliation. |
| `input/CVAP_2020-2024_ACS_csv_files.zip` | Published citizen-adult estimates and margins of error for CD119 (`CD.csv`, Total row). [Census source](https://www.census.gov/programs-surveys/decennial-census/about/voting-rights/cvap/2020-2024-CVAP.html) |

| Product | Grain and use |
|---|---|
| `intermediate/08_puma_cd119_weights.csv` | One row per PUMA × original district with its allocation weight and method. |
| `intermediate/08_pums_cd119_cells.rds` | Positive CD119 population cells. Keys: state, CD119 and the five Step 04 demographic variables. `N` is allocated citizen-adult population. |
| `intermediate/08_district_demographics.csv` | One row per `congress,STATEFP,CDFP`. Includes full PUMS `cvap` and all 29 demographic shares for the House models. |
| `output/08_district_overlap.csv` | One row per nonempty assigned CD119–CD120 block intersection with a block count and `same_footprint`. Block counts measure overlap, not votes. |
| `output/08_cd119_allocation_exceptions.csv` | Positive estimates requiring a zero-adult or wholly-unassigned decision in recalculated states. Unchanged states reuse the Step 02 audits. |
| `output/08_cd119_cvap_benchmark.csv` | Comparison of reconstructed PUMS CVAP to separately published district CVAP and its Census margin of error. Survey weighting and allocation can produce differences. The benchmark does not replace or calibrate PUMS CVAP. |

The input tables keep state and district IDs as text, including leading
zeros and DC's `11/98`. Key model predictors are shares on the 0–1 scale:
14 age bands (18–22 through 78–82, then 83+), two recorded-sex categories,
six education categories, five race categories and two Hispanic-origin
categories. Categories sum to one within each family. Step 08 checks each
state's CVAP total on both maps against Step 03 and checks each demographic
subtotal is conserved within each state. The [Step 04 definitions](04_harmonize_pums.md)
describe the underlying survey codes.
