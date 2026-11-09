"""Build PUMA → CD119 weights on original 2024 House boundaries.

Compare the Census blocks assigned to districts on both maps. Reuse Step 02
PUMA weights where every district in a state has the same footprint. In other
states, apportion each block group's citizen voting-age population (CVAP) on
the original CD119 map, then calculate each district's share within its PUMA.
The caller supplies the output staging directory.
"""
import argparse
import csv
import math
from collections import Counter, defaultdict
from importlib import import_module
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import NamedTuple

geo = import_module("05_ces_district_geography")
FRAME = geo.FRAME
WEIGHT_FIELDS = ("STATEFP", "PUMA5CE", "CDFP119", "allocation_weight", "weight_method")
EXCEPTION_FIELDS = ("STATEFP", "bg_cvap", "PUMA5CE", "CDFP119s", "cvap_est", "treatment")

# One row describes an intersection on the two maps. District IDs can change
# even when every assigned block stays together.
class DistrictOverlap(NamedTuple):
    STATEFP: str
    CDFP119: str
    CDFP120: str
    blocks: int
    same_footprint: bool


OVERLAP_FIELDS = DistrictOverlap._fields

# Source of the five listed CA/FL cases: Step 02 allocation decisions.
# Source of TX: Step 05 old-origin exception audit. Five estimated citizen adults
# are supported only by 2020 blocks with zero adults on both sides of CD119 12/26.
# Under the Step 02 treatment for a positive estimate without population support,
# the CD119 calculation sets its contribution to zero and records the adjustment.
REVIEWED_SPLITS = {
    "060379800031": 5, "120219900000": 4, "120719800001": 5,
    "120869806001": 5, "120999900000": 5, "484391139322": 5,
}


def rows(path):
    with path.open(encoding="utf-8-sig", newline="") as stream:
        yield from csv.DictReader(stream)


def write(path, fields, records):
    with path.open("w", encoding="utf-8", newline="") as stream:
        out = csv.writer(stream, lineterminator="\n")
        out.writerow(fields)
        out.writerows(records)


def footprint_rows(state, county_counts):
    """Districts match when the intersection contains *all* assigned blocks of both districts."""
    shared_blocks = Counter()
    cd119_blocks = Counter()
    cd120_blocks = Counter()
    for (cd119, county, cd120), count in county_counts.items():
        shared_blocks[cd119, cd120] += count
        cd119_blocks[cd119] += count
        cd120_blocks[cd120] += count

    overlaps = []
    for (cd119, cd120), count in sorted(shared_blocks.items()):
        overlaps.append(DistrictOverlap(
            STATEFP=state,
            CDFP119=cd119,
            CDFP120=cd120,
            blocks=count,
            same_footprint=(count == cd119_blocks[cd119] == cd120_blocks[cd120]),
        ))
    return overlaps


def changed_state_weights(state, manifest, blocks, support_file, readiness_file):
    if state in {"09", "36"}:
        raise ValueError("CT/NY exception geography changed; review before assigning CD119 weights.")
    # In states redrawn between these pinned maps, block groups use their 2020
    # identifiers and each nests in one 2020 PUMA. Verify these prerequisites.
    puma_by_group = {}
    cd120_support = {}
    for row in rows(support_file):
        if row["STATEFP"] != state:
            continue
        group, cd120 = row["bg_cvap"], row["CDFP"]
        puma = puma_by_group.setdefault(group, row["PUMA5CE"])
        if (puma != row["PUMA5CE"] or row["coverage_only"].upper() != "FALSE"
                or (group, cd120) in cd120_support):
            raise ValueError(f"Unexpected PUMA or geographic support for {group}/{cd120}")
        cd120_support[group, cd120] = int(row["source_block_links"]), int(row["vap20"])

    published_cvap = {}
    for row in rows(readiness_file):
        if row["STATEFP"] == state:
            group = row["bg_cvap"]
            if group in published_cvap:
                raise ValueError(f"Duplicate source CVAP estimate for {group}")
            published_cvap[group] = float(row["cvap_est"])
    if (published_cvap.keys() != puma_by_group.keys()
            or any(not math.isfinite(n) or n < 0 for n in published_cvap.values())):
        raise ValueError(f"Missing geographic support or source CVAP for {state}")

    # The same census block has a district on each map. First reproduce the
    # Step 02 block and adult counts on CD120. Keep the adults grouped by CD119
    # for the allocation, including intersections with zero recorded adults.
    block_counts, adult_counts = geo.old_intersections(blocks, manifest)
    cd120_blocks = Counter()
    cd120_adults = Counter()
    cd119_adults = defaultdict(Counter)
    for (group, cd120, cd119), count in block_counts.items():
        cd120_blocks[group, cd120] += count
        cd120_adults[group, cd120] += adult_counts[group, cd120, cd119]
        cd119_adults[group][cd119] += adult_counts[group, cd120, cd119]

    if (cd120_blocks.keys() != cd120_support.keys() or any(
        (count, cd120_adults[key]) != cd120_support[key] for key, count in cd120_blocks.items()
    )):
        raise ValueError(f"Step 02 block or adult counts differ for state {state}")

    return allocate_groups(state, cd119_adults, puma_by_group, published_cvap)


def allocate_groups(state, old_adults, puma, published):
    """Allocate block-group CVAP to old districts, then normalize within each PUMA."""
    cvap_by_puma = defaultdict(Counter)
    exceptions = []
    excluded_cvap = 0
    for group, adults_by_district in old_adults.items():
        puma_id = puma[group]
        estimate = published[group]
        total_adults = sum(adults_by_district.values())
        for district in adults_by_district:
            # Preserve geographic intersections even if they receive no people.
            cvap_by_puma[puma_id][district] += 0
        if estimate == 0:
            continue

        if adults_by_district.keys() == {"ZZ"}:
            # All the blocks are unassigned, so none of this estimate can enter a district.
            excluded_cvap += estimate
            reason = "wholly_unassigned"
        elif len(adults_by_district) == 1:
            # The single assigned district receives the full estimate even if the
            # 2020 Census recorded zero adults. Record that special case in the audit.
            district = next(iter(adults_by_district))
            cvap_by_puma[puma_id][district] += estimate
            if total_adults:
                continue
            reason = "zero_adults_direct_containment"
        elif total_adults > 0 and adults_by_district.get("ZZ", 0) == 0:
            for district, adults in adults_by_district.items():
                cvap_by_puma[puma_id][district] += estimate * adults / total_adults
            continue
        elif ("ZZ" not in adults_by_district and total_adults == 0
              and estimate == REVIEWED_SPLITS.get(group)
              and (group != "484391139322" or adults_by_district.keys() == {"12", "26"})):
            # These reviewed groups have several possible destinations and no
            # adult counts to split them. Omit the estimate from assigned CVAP.
            reason = "zero_adults_split_excluded"
            excluded_cvap += estimate
        else:
            raise ValueError(f"Unreviewed CD119 allocation: {state} {group} PUMA {puma_id}; "
                             f"published CVAP={estimate}, adults by district={dict(adults_by_district)}")
        exceptions.append((state, group, puma_id, "|".join(sorted(adults_by_district)), estimate, reason))

    assigned = math.fsum(value for districts in cvap_by_puma.values() for value in districts.values())
    if not math.isclose(assigned + excluded_cvap, math.fsum(published.values()), rel_tol=1e-12, abs_tol=1e-7):
        raise ValueError(f"Unreconciled source CVAP in state {state}")

    weights = []
    for puma_id, district_cvap in sorted(cvap_by_puma.items()):
        # Check containment before removing ZZ: an unassigned block prevents
        # claiming that every block of the PUMA belongs to one district.
        contained = len(district_cvap) == 1 and "ZZ" not in district_cvap
        if district_cvap.pop("ZZ", 0) != 0 or not district_cvap:
            raise ValueError(f"Unreconciled unassigned coverage in {state}/{puma_id}")
        assigned_cvap = math.fsum(district_cvap.values())
        if not contained and assigned_cvap <= 0:
            raise ValueError(f"No assigned district CVAP for split PUMA {state}/{puma_id}")
        method = "structural_single_district" if contained else "cvap_share"
        for district, contribution in sorted(district_cvap.items()):
            weight = 1.0 if contained else contribution / assigned_cvap
            weights.append((state, puma_id, district, weight, method))
    return weights, exceptions


def build(destination):
    manifest = {r["STATEFP"]: r for r in rows(FRAME / "docs" / "02_pl_2020_sources.csv")}
    if len(manifest) != 51:
        raise ValueError("Expected the 50 states and DC in the PL source manifest")
    support = geo.OUTPUT / "02_bg_cvap_contributions.csv"
    readiness = geo.OUTPUT / "02_cvap_allocation_readiness.csv"
    existing = defaultdict(list)
    for row in rows(geo.OUTPUT / "02_puma_cd_weights.csv"):
        existing[row["STATEFP"]].append(row)
    if existing.keys() != manifest.keys():
        raise ValueError("The Step 02 PUMA crosswalk and state manifest disagree")
    overlap, weights, exceptions = [], [], []
    paths = geo.load_bef_paths()
    with TemporaryDirectory(dir=destination) as work_folder:
        work = Path(work_folder)
        for congress, path in paths.items():
            geo.partition_bef(path, congress, work, manifest)
        for state, entry in sorted(manifest.items()):
            blocks, counts = geo.state_blocks(work, state)
            pairs = footprint_rows(state, counts)
            overlap.extend(pairs)
            # Reuse weights only if every assigned district in this state has
            # an exact match. Translate the labels, including any renumbered seats.
            if all(pair.same_footprint for pair in pairs):
                cd119_by_cd120 = {pair.CDFP120: pair.CDFP119 for pair in pairs}
                for row in existing[state]:
                    weights.append((state, row["PUMA5CE"], cd119_by_cd120[row["CDFP"]],
                                    float(row["allocation_weight"]), row["weight_method"]))
            else:
                # Any boundary change triggers a rebuild of every PUMA in this state.
                print(f"Rebuilding PUMA weights on CD119 boundaries in {entry['STUSAB']}", flush=True)
                calculated, audit = changed_state_weights(state, entry, blocks, support, readiness)
                weights.extend(calculated)
                exceptions.extend(audit)
    # One row per PUMA/district intersection. Keep each PUMA's weights together
    # for the final sum-to-one check.
    seen_intersections = set()
    weights_by_puma = defaultdict(list)
    for state, puma, district, weight, _ in weights:
        intersection = (state, puma, district)
        if intersection in seen_intersections or not math.isfinite(weight) or not 0 <= weight <= 1:
            raise ValueError(f"Invalid crosswalk row for {intersection}")
        seen_intersections.add(intersection)
        weights_by_puma[state, puma].append(weight)

    # Both maps cover 436 districts including DC. The weights must cover the
    # entire CD119 map and the same state/PUMA combinations as Step 02.
    cd119_districts = {(pair.STATEFP, pair.CDFP119) for pair in overlap}
    cd120_districts = {(pair.STATEFP, pair.CDFP120) for pair in overlap}
    weighted_districts = {(state, district) for state, puma, district in seen_intersections}
    expected_pumas = {
        (state, row["PUMA5CE"])
        for state, cd120_rows in existing.items()
        for row in cd120_rows
    }
    district_coverage_ok = (
        len(cd119_districts) == 436
        and len(cd120_districts) == 436
        and ("11", "98") in cd119_districts
        and weighted_districts == cd119_districts
    )
    if (not district_coverage_ok
            or weights_by_puma.keys() != expected_pumas
            or any(abs(math.fsum(puma_weights) - 1) > 1e-12
                   for puma_weights in weights_by_puma.values())):
        raise ValueError("District coverage, PUMA coverage or within-PUMA shares failed")
    write(destination / "08_puma_cd119_weights.csv", WEIGHT_FIELDS, sorted(weights))
    write(destination / "08_district_overlap.csv", OVERLAP_FIELDS, overlap)
    write(destination / "08_cd119_allocation_exceptions.csv", EXCEPTION_FIELDS, exceptions)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("staging_directory", type=Path)
    build(parser.parse_args().staging_directory)
