"""Build PUMA → CD119 weights on original 2024 House boundaries.

The caller supplies an output staging directory. Inputs are the pinned Step 02
and 05 sources and the Step 02 audits; all block IDs retain their leading zeros.
"""
import argparse
import csv
import math
from collections import Counter, defaultdict
from importlib import import_module
from pathlib import Path
from tempfile import TemporaryDirectory

geo = import_module("05_ces_district_geography")
FRAME = geo.FRAME
WEIGHT_FIELDS = ("STATEFP", "PUMA5CE", "CDFP119", "allocation_weight", "weight_method")
OVERLAP_FIELDS = ("STATEFP", "CDFP119", "CDFP120", "blocks", "same_footprint")
EXCEPTION_FIELDS = ("STATEFP", "bg_cvap", "PUMA5CE", "CDFP119s", "cvap_est", "treatment")

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
    """A common district number or a contained subset alone cannot prove equality."""
    pairs = Counter()
    old = Counter()
    new = Counter()
    for (prior, county, following), n in county_counts.items():
        pairs[prior, following] += n
        old[prior] += n
        new[following] += n
    return [(state, prior, following, n, n == old[prior] == new[following])
            for (prior, following), n in sorted(pairs.items())]


def changed_state_weights(state, manifest, blocks, support_file, readiness_file):
    if state in {"09", "36"}:
        raise ValueError("CT/NY exception geography changed; review before assigning CD119 weights.")
    # In states redrawn between these pinned maps, block groups use their 2020
    # identifiers and each nests in one 2020 PUMA. Verify these prerequisites.
    puma = {}
    new_support = {}
    for r in rows(support_file):
        if r["STATEFP"] != state:
            continue
        bg, new = r["bg_cvap"], r["CDFP"]
        if (puma.setdefault(bg, r["PUMA5CE"]) != r["PUMA5CE"] or
                r["coverage_only"].upper() != "FALSE" or (bg, new) in new_support):
            raise ValueError(f"Unexpected PUMA or geographic support for {bg}/{new}")
        new_support[bg, new] = int(r["source_block_links"]), int(r["vap20"])
    published = {}
    for r in rows(readiness_file):
        if r["STATEFP"] == state:
            bg = r["bg_cvap"]
            if bg in published:
                raise ValueError(f"Duplicate source CVAP estimate for {bg}")
            published[bg] = float(r["cvap_est"])
    if published.keys() != puma.keys() or any(not math.isfinite(n) or n < 0 for n in published.values()):
        raise ValueError(f"Missing geographic support or source CVAP for {state}")

    # Step 05 verifies the PL archive and joins every block to both BEFs using
    # GEOID. Group the SAME individual blocks under the old district IDs.
    block_counts, adult_counts = geo.old_intersections(blocks, manifest)
    new_counts, new_adults = Counter(), Counter()
    old_adults = defaultdict(Counter)
    for (bg, new, old), n in block_counts.items():
        new_counts[bg, new] += n
        new_adults[bg, new] += adult_counts[bg, new, old]
        old_adults[bg][old] += adult_counts[bg, new, old]  # preserve zero-adult intersections
    if (new_counts.keys() != new_support.keys() or
            any((v, new_adults[k]) != new_support[k] for k, v in new_counts.items())):
        raise ValueError(f"Step 02 block or adult counts differ for state {state}")

    return allocate_groups(state, old_adults, puma, published)


def allocate_groups(state, old_adults, puma, published):
    masses = defaultdict(Counter)
    exceptions = []
    excluded = 0
    for bg, districts in old_adults.items():
        area = puma[bg]
        estimate = published[bg]
        all_adults = sum(districts.values())
        for district in districts:
            masses[area][district] += 0  # keep even zero-weight footprint intersections
        if estimate == 0:
            continue
        if districts.keys() == {"ZZ"}:
            excluded += estimate
            reason = "wholly_unassigned"
        elif len(districts) == 1:
            district = next(iter(districts))
            masses[area][district] += estimate
            if all_adults:
                continue
            reason = "zero_adults_direct_containment"
        elif all_adults > 0 and districts.get("ZZ", 0) == 0:
            for district, adults in districts.items():
                masses[area][district] += estimate * adults / all_adults
            continue
        elif ("ZZ" not in districts and all_adults == 0 and
              estimate == REVIEWED_SPLITS.get(bg) and
              (bg != "484391139322" or districts.keys() == {"12", "26"})):
            reason = "zero_adults_split_excluded"
            excluded += estimate
        else:
            raise ValueError(f"Unreviewed CD119 allocation: {state} {bg} PUMA {area}; "
                             f"published CVAP={estimate}, adults by district={dict(districts)}")
        exceptions.append((state, bg, area, "|".join(sorted(districts)), estimate, reason))

    total = math.fsum(value for group in masses.values() for value in group.values())
    if not math.isclose(total + excluded, math.fsum(published.values()), rel_tol=1e-12, abs_tol=1e-7):
        raise ValueError(f"Unreconciled source CVAP in state {state}")
    result = []
    for area, groups in sorted(masses.items()):
        contained = len(groups) == 1 and "ZZ" not in groups
        if groups.pop("ZZ", 0) != 0 or not groups:
            raise ValueError(f"Unreconciled unassigned coverage in {state}/{area}")
        denominator = math.fsum(groups.values())
        if not contained and denominator <= 0:
            raise ValueError(f"No assigned district CVAP for split PUMA {state}/{area}")
        for district, mass in sorted(groups.items()):
            weight = 1.0 if contained else mass / denominator
            result.append((state, area, district, weight,
                           "structural_single_district" if contained else "cvap_share"))
    return result, exceptions


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
            if all(match for _, _, _, _, match in pairs):
                lookup = {new: old for _, old, new, _, _ in pairs}
                weights.extend((state, r["PUMA5CE"], lookup[r["CDFP"]], float(r["allocation_weight"]),
                                r["weight_method"]) for r in existing[state])
            else:
                print(f"Rebuilding PUMA weights on CD119 boundaries in {entry['STUSAB']}", flush=True)
                calculated, audit = changed_state_weights(state, entry, blocks, support, readiness)
                weights.extend(calculated)
                exceptions.extend(audit)
    expected = {(s, r["PUMA5CE"]) for s, group in existing.items() for r in group}
    sums = defaultdict(list)
    keys = set()
    for state, puma, district, weight, _ in weights:
        key = (state, puma, district)
        if key in keys or not math.isfinite(weight) or not 0 <= weight <= 1:
            raise ValueError(f"Invalid crosswalk row for {key}")
        keys.add(key)
        sums[state, puma].append(weight)
    old_areas = {(s, old) for s, old, _, _, _ in overlap}
    new_areas = {(s, new) for s, _, new, _, _ in overlap}
    if (len(old_areas) != 436 or len(new_areas) != 436 or ("11", "98") not in old_areas or
            old_areas != {(s, d) for s, _, d in keys} or sums.keys() != expected or
            any(abs(math.fsum(group) - 1) > 1e-12 for group in sums.values())):
        raise ValueError("District coverage, PUMA coverage or within-PUMA shares failed")
    write(destination / "08_puma_cd119_weights.csv", WEIGHT_FIELDS, sorted(weights))
    write(destination / "08_district_overlap.csv", OVERLAP_FIELDS, overlap)
    write(destination / "08_cd119_allocation_exceptions.csv", EXCEPTION_FIELDS, exceptions)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("staging_directory", type=Path)
    build(parser.parse_args().staging_directory)
