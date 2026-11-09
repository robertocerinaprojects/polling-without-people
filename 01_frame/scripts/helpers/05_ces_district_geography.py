"""Build the 119th-to-120th Congress residence lookup for CES Script 05.

CD119 describes the respondent's district at the 2024 election. CD120 is
the map for the 2026 election. We locate the same 2024 residence on both
maps by joining their Census block assignments. Where a county and old
district still span several new districts, we estimate each new district's
share of the citizen voting-age population (CVAP).
"""

from collections import Counter, defaultdict
from contextlib import ExitStack
import csv
import hashlib
import math
import os
from pathlib import Path
import shutil
import tempfile
import urllib.request
from typing import NamedTuple, Optional
from zipfile import ZipFile


FRAME = Path("01_frame")
INPUT = FRAME / "data" / "input"
OUTPUT = FRAME / "data" / "output"
CD119_URL = (
    "https://www2.census.gov/programs-surveys/decennial/rdo/"
    "mapping-files/2025/119-congressional-district-befs/cd119.zip"
)
# SHA-256 of the downloaded official CD119 archive; second hash is Script 02's pin.
BEF_HASH = {
    119: "1433feb5178dc7b4188ee30f5f7f715851f4400740b8fe1ce606a876c6294bd6",
    120: "bc9a4fc543b8b279ce3663642a5cc4e19e32a8ef84f12371e26f754e5b8cc8a5",
}
# Named rows keep the CSV headers and the values written under them together.
class DistrictLookupRow(NamedTuple):
    STATEFP: str
    CD119: str
    county_fips: str
    CD120: str
    district_probability: float
    geography_method: str
    blocks: int
    overlap_cvap: Optional[float]
    possible_unresolved_cvap: float
    probability_min: float
    probability_max: float


class BlockGroupContribution(NamedTuple):
    blocks: int
    adults_2020: int
    cvap: float


class UnresolvedOrigin(NamedTuple):
    STATEFP: str
    county_fips: str
    bg_cvap: str
    CD120: str
    CD119_candidates: str
    blocks_by_candidate: str
    vap20: int
    cvap_unknown_origin: float


FIELDS = DistrictLookupRow._fields
AUDIT_FIELDS = UnresolvedOrigin._fields


def verify_hash(path, expected):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    if digest.hexdigest() != expected:
        raise ValueError(f"Unexpected SHA-256 for {path}")


def load_bef_paths():
    """Verify both block files, fetching CD119 from Census on its first use."""
    paths = {n: INPUT / f"cd{n}.zip" for n in BEF_HASH}
    verify_hash(paths[120], BEF_HASH[120])
    if paths[119].exists():
        verify_hash(paths[119], BEF_HASH[119])
    else:
        # Download and fingerprint completely before publishing a new cache file.
        with tempfile.NamedTemporaryFile(dir=INPUT, delete=False) as tmp:
            candidate = Path(tmp.name)
        try:
            with urllib.request.urlopen(CD119_URL, timeout=180) as src, candidate.open("wb") as dst:
                shutil.copyfileobj(src, dst)
            verify_hash(candidate, BEF_HASH[119])
            os.replace(candidate, paths[119])
        finally:
            candidate.unlink(missing_ok=True)
    return paths


def partition_bef(path, congress, work, states):
    # National files have different row orders. Partitioning keeps at most one
    # state's block-to-district assignment in memory during the geographic join.
    with ExitStack() as stack:
        outputs = {state: stack.enter_context((work / f"{congress}_{state}").open("wb"))
                   for state in states}
        archive = stack.enter_context(ZipFile(path))
        stream = stack.enter_context(archive.open(f"NationalCD{congress}.txt"))
        if congress == 119:
            header = b"GEOID,CDFP"
        else:
            header = b"GEOID,STATEFP,COUNTYFP,TRACTCE,BLOCKCE,CDFP"
        if stream.readline().strip() != header:
            raise ValueError(f"Unexpected CD{congress} header")
        for line in stream:
            parts = line.rstrip(b"\r\n").split(b",")
            block, cd = parts[0], parts[-1]
            state = block[:2].decode("ascii")
            if state == "72":
                continue  # same 50 states + DC scope as the person frame
            if len(block) != 15 or not block.isdigit() or state not in outputs:
                raise ValueError(f"Invalid or out-of-scope GEOID {block!r}")
            if len(cd) != 2 or not (cd.isdigit() or cd == b"ZZ"):
                raise ValueError(f"Invalid CD{congress} assignment {cd!r}")
            outputs[state].write(block + b"," + cd + b"\n")


def state_blocks(work, state):
    """Join by block ID; count each assigned old-district/county/new-district overlap."""
    old = {}
    with (work / f"119_{state}").open() as f:
        for block, cd in csv.reader(f):
            if block in old:
                raise ValueError(f"Duplicate CD119 GEOID {block}")
            old[block] = cd
    pairs = {}
    counts = Counter()
    with (work / f"120_{state}").open() as f:
        for block, new in csv.reader(f):
            prior = old.pop(block)  # rejects duplicates and extra CD120 blocks
            if (prior == "ZZ") != (new == "ZZ"):
                raise ValueError(f"District assignment changed to/from ZZ at {block}")
            pairs[block] = (prior, new)
            if prior != "ZZ":
                counts[prior, block[:5], new] += 1
    if old or not counts:
        raise ValueError(f"Unmatched block identifiers or no assigned blocks in {state}")
    return pairs, counts


def read_contributions(state, path):
    # All states whose plans split old districts in the pinned files use
    # unrevised 2020 block-group IDs. CT and NY are geographically contained.
    if state in {"09", "36"}:
        raise ValueError("Changed geography needs review of the CT/NY CVAP exceptions.")
    cells = {}
    with path.open(newline="") as f:
        for row in csv.DictReader(f):
            if row["STATEFP"] != state:
                continue
            group, cd = row["bg_cvap"], row["CDFP"]
            key = (group, cd)
            if key in cells or group[:2] != state or len(group) != 12:
                raise ValueError(f"Invalid or repeated Step 02 block-group/district {key}")
            if row["coverage_only"].upper() != "FALSE":
                raise ValueError(f"Ambiguous block-group identifier in split state: {key}")
            cvap = float(row["cvap_contribution"])  # missing estimates need separate review
            if not math.isfinite(cvap) or cvap < 0 or (cd == "ZZ" and cvap != 0):
                raise ValueError(f"Unsupported CVAP contribution at {key}")
            cells[key] = BlockGroupContribution(
                blocks=int(row["source_block_links"]), adults_2020=int(row["vap20"]), cvap=cvap
            )
    if not cells:
        raise ValueError(f"Missing Script 02 contributions for {state}.")
    return cells


def old_intersections(blocks, manifest_row):
    """Count blocks and 2020 adults by block group, new district and old district.

    Consume the supplied block dictionary as we match records. Any entries
    left over reveal blocks missing from the population file.
    """
    pl_path = Path(manifest_row["path"])
    verify_hash(pl_path, manifest_row["sha256"])
    postal = manifest_row["STUSAB"]
    adult_by_record = {}
    # Official PL segment 2: record identifier in field 5, P0030001
    # (persons age 18+) in field 6. Script 02 Section 4 documents the schema.
    counts = Counter()
    adults = Counter()
    with ZipFile(pl_path) as archive:
        with archive.open(f"{postal.lower()}000022020.pl") as f:
            for line in f:
                prefix = line.split(b"|", 6)
                record = prefix[4]
                if record in adult_by_record:
                    raise ValueError(f"Duplicate PL logical record {record!r}")
                n = int(prefix[5])
                if n < 0:
                    raise ValueError(f"Negative PL adult count at {record!r}")
                adult_by_record[record] = n
        with archive.open(f"{postal.lower()}geo2020.pl") as f:
            for line in f:
                fields = line.split(b"|", 35)
                if fields[2] != b"750":  # Summary level 750 identifies census blocks.
                    continue
                if fields[3:7] != [b"00", b"00", b"000", b"00"]:
                    raise ValueError("Unreviewed PL block summary variant.")
                # The block ID concatenates state, county, tract and block codes.
                block = (fields[12] + fields[14] + fields[32] + fields[34]).decode("ascii")
                old, new = blocks.pop(block)
                intersection = (block[:12], new, old)
                counts[intersection] += 1
                adults[intersection] += adult_by_record.pop(fields[7])
    if blocks:
        raise ValueError(f"PL block coverage differs from both BEFs in {postal}")
    return counts, adults


def reaggregate_cvap(state, counts, adults, cells):
    """Divide each Step 02 block-group/CD120 estimate among its CD119 districts."""
    old_districts_by_cell = defaultdict(list)
    for group, new, old in counts:
        old_districts_by_cell[group, new].append(old)
    if cells.keys() != old_districts_by_cell.keys():
        raise ValueError(f"Step 02 and BEF block-group/district identifiers differ in {state}")

    known_cvap = Counter()
    unresolved = []
    for (group, new), old_districts in old_districts_by_cell.items():
        county = group[:5]
        expected_blocks, expected_adults, cvap = cells[group, new]
        block_total = sum(counts[group, new, old] for old in old_districts)
        if (block_total != expected_blocks or
                sum(adults[group, new, old] for old in old_districts) != expected_adults):
            raise ValueError(f"Block or adult totals differ from Section 02 at {group}, CD{new}")
        if cvap == 0:
            continue

        if len(old_districts) > 1 and expected_adults == 0:
            # In this Tarrant County block group, all estimated citizens belong
            # to new TX-12. Their old district could be TX-12 or TX-26. Neither
            # portion has recorded adults, so a population-weighted split is undefined.
            blocks_by_old = {old: counts[group, new, old] for old in old_districts}
            if not (state == "48" and group == "484391139322" and new == "12"
                    and cvap == 5.0 and blocks_by_old == {"12": 7, "26": 25}):
                raise ValueError(
                    f"Review positive CVAP split across old districts without adult support: {group}, CD{new}"
                )
            unresolved.append(UnresolvedOrigin(
                STATEFP=state, county_fips=county, bg_cvap=group, CD120=new,
                CD119_candidates="12|26", blocks_by_candidate="7|25",
                vap20=0, cvap_unknown_origin=cvap
            ))
            continue

        for old in old_districts:
            # Containment also works when 2020 adult counts are zero.
            share = 1.0 if len(old_districts) == 1 else adults[group, new, old] / expected_adults
            known_cvap[old, county, new] += cvap * share

    expected = math.fsum(cvap for _, _, cvap in cells.values())
    accounted = math.fsum(known_cvap.values()) + math.fsum(row.cvap_unknown_origin for row in unresolved)
    if not math.isclose(accounted, expected, rel_tol=1e-12, abs_tol=1e-6):
        raise ValueError(f"CVAP not conserved across the district overlay in {state}")
    return known_cvap, unresolved


def possible_cvap_by_origin(unresolved):
    """Count how much of the unresolved CVAP *could* belong to each old district."""
    possible = defaultdict(Counter)
    for record in unresolved:
        row = UnresolvedOrigin(*record)
        for old in row.CD119_candidates.split("|"):
            for area in (row.county_fips, ""):
                possible[old, area][row.CD120] += row.cvap_unknown_origin
    return possible


def lookup_rows(state, counts, masses, unresolved):
    """Emit a county-specific lookup and a whole-old-district lookup for each origin."""
    block_counts = defaultdict(Counter)
    known_cvap = defaultdict(Counter)
    for (old, county, new), n in counts.items():
        # The CES uses the blank-county row when the respondent has no county
        # code or their reported county/old-district pair is absent.
        for area in (county, ""):
            block_counts[old, area][new] += n
            if masses is not None:
                known_cvap[old, area][new] += masses[old, county, new]

    # The audit counts the five Texans once. Here their whole estimate is a
    # possibility for each eligible old district, used only for its bounds.
    possible = possible_cvap_by_origin(unresolved)
    for (old, county), destinations in sorted(block_counts.items()):
        if len(block_counts[old, ""]) == 1:
            method = "old_district_contained"
        elif len(destinations) == 1:
            method = "county_district_contained"
        elif county:
            method = "county_district_cvap"
        else:
            method = "old_district_cvap"

        known_by_destination = known_cvap[old, county]
        known_total = math.fsum(known_by_destination.values())
        if len(destinations) == 1:
            probabilities = {next(iter(destinations)): 1.0}
        else:
            if known_total == 0:
                raise ValueError(f"Review split district {state}/{old}/{county} with zero known-origin CVAP.")
            probabilities = {new: known_by_destination[new] / known_total for new in destinations}
        if not math.isclose(math.fsum(probabilities.values()), 1.0, abs_tol=1e-12, rel_tol=0):
            raise ValueError(f"District probabilities did not sum to one for {state}/{old}/{county}")

        possible_total = math.fsum(possible[old, county].values())
        for new, n in sorted(destinations.items()):
            district_cvap = known_by_destination[new] if masses is not None else None
            probability = probabilities[new]
            low = high = probability
            if possible_total and len(destinations) > 1 and known_total:
                # For the minimum, add only the possible CVAP headed elsewhere
                # to this origin's denominator. For the maximum, add only the
                # possible CVAP headed here, to both numerator and denominator.
                possible_here = possible[old, county][new]
                low = district_cvap / (known_total + possible_total - possible_here)
                high = (district_cvap + possible_here) / (known_total + possible_here)
            yield DistrictLookupRow(
                STATEFP=state, CD119=old, county_fips=county, CD120=new,
                district_probability=probability, geography_method=method, blocks=n,
                overlap_cvap=district_cvap, possible_unresolved_cvap=possible_total,
                probability_min=low, probability_max=high
            )


def main():
    manifest_path = FRAME / "docs" / "02_pl_2020_sources.csv"
    with manifest_path.open(newline="") as f:
        manifest = {r["STATEFP"]: r for r in csv.DictReader(f)}
    if len(manifest) != 51:
        raise ValueError("Expected all 50 states plus DC in the reviewed PL manifest.")
    contributions = OUTPUT / "02_bg_cvap_contributions.csv"
    if not contributions.is_file():
        raise FileNotFoundError(f"Run Script 02 to generate {contributions}")
    paths = load_bef_paths()
    rows = []
    exception_audit = []
    with tempfile.TemporaryDirectory() as scratch:
        work = Path(scratch)
        for congress, path in paths.items():
            partition_bef(path, congress, work, manifest)
        for state, details in sorted(manifest.items()):
            # Keep one state's blocks in memory at a time. If every old
            # district is contained, the map alone gives every probability.
            blocks, counts = state_blocks(work, state)
            destinations = defaultdict(set)
            for old, county, new in counts:
                destinations[old].add(new)
            masses, unresolved = None, []
            if any(len(d) > 1 for d in destinations.values()):
                print(f"Estimating split-district CVAP in {details['STUSAB']}", flush=True)
                cells = read_contributions(state, contributions)
                block_counts, adults = old_intersections(blocks, details)
                masses, unresolved = reaggregate_cvap(state, block_counts, adults, cells)
                exception_audit.extend(unresolved)
            rows.extend(lookup_rows(state, counts, masses, unresolved))
    if len(exception_audit) != 1:
        raise ValueError("The reviewed single TX unknown-origin exception changed.")
    # Include all intersections, even with a modeled probability of zero. The
    # caller can inspect any unresolved area before drawing for real respondents.
    with tempfile.TemporaryDirectory(dir=OUTPUT) as tmp:
        products = (("05_ces_unknown_origin_cvap.csv", AUDIT_FIELDS, exception_audit),
                    ("05_ces_district_lookup.csv", FIELDS, rows))
        for name, fields, values in products:
            with (Path(tmp) / name).open("w", newline="", encoding="utf-8") as f:
                writer = csv.writer(f, lineterminator="\n")
                writer.writerow(fields)
                writer.writerows(values)
        for name, _, _ in products:
            os.replace(Path(tmp) / name, OUTPUT / name)
    print(f"Saved {len(rows):,} rows to {OUTPUT / '05_ces_district_lookup.csv'}")


if __name__ == "__main__":
    main()
