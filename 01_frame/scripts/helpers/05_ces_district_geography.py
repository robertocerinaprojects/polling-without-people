"""Build the 119th-to-120th Congress residence lookup for CES Script 05.

Run from the repository root. On first use, download the national CD119 block
equivalency archive from Census; Script 02 supplies the other local inputs.
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
FIELDS = ("STATEFP", "CD119", "county_fips", "CD120", "district_probability",
          "geography_method", "blocks", "overlap_cvap", "possible_unresolved_cvap",
          "probability_min", "probability_max")
AUDIT_FIELDS = ("STATEFP", "county_fips", "bg_cvap", "CD120", "CD119_candidates",
                "blocks_by_candidate", "vap20", "cvap_unknown_origin")


def verify_hash(path, expected):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    if digest.hexdigest() != expected:
        raise ValueError(f"Unexpected SHA-256 for {path}")


def load_bef_paths():
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
            cells[key] = (int(row["source_block_links"]), int(row["vap20"]), cvap)
    if not cells:
        raise ValueError(f"Missing Script 02 contributions for {state}.")
    return cells


def old_intersections(blocks, manifest_row):
    """Return checked block counts and voting-age counts by BG, new CD, old CD."""
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
                g = line.split(b"|", 35)
                if g[2] != b"750":
                    continue
                if g[3:7] != [b"00", b"00", b"000", b"00"]:
                    raise ValueError("Unreviewed PL block summary variant.")
                # Geography file fields 13/15/33/35 carry state/county/tract/block.
                block = (g[12] + g[14] + g[32] + g[34]).decode("ascii")
                old, new = blocks.pop(block)
                inter = (block[:12], new, old)
                counts[inter] += 1
                adults[inter] += adult_by_record.pop(g[7])
    if blocks:
        raise ValueError(f"PL block coverage differs from both BEFs in {postal}")
    return counts, adults


def reaggregate_cvap(state, counts, adults, cells):
    source = defaultdict(list)
    for group, new, old in counts:
        source[group, new].append(old)
    if cells.keys() != source.keys():
        raise ValueError(f"Step 02 and BEF block-group/district identifiers differ in {state}")
    masses = Counter()
    unresolved = []
    for (group, new), olds in source.items():
        block_total, adult_total, cvap = cells[group, new]
        if (sum(counts[group, new, old] for old in olds) != block_total or
                sum(adults[group, new, old] for old in olds) != adult_total):
            raise ValueError(f"Block or adult totals differ from Section 02 at {group}, CD{new}")
        if cvap == 0:
            continue
        if len(olds) > 1 and adult_total == 0:
            # Reviewed Tarrant County exception. All five are already assigned
            # to new TX-12; zero adult counts leave their prior district unknown.
            by_old = {old: counts[group, new, old] for old in olds}
            if (state, group, new, cvap, by_old) != (
                    "48", "484391139322", "12", 5.0, {"12": 7, "26": 25}):
                raise ValueError(f"Review positive CVAP split across old districts without adult support: {group}, CD{new}")
            unresolved.append((state, group[:5], group, new, "12|26", "7|25", 0, cvap))
            continue
        for old in olds:
            share = 1.0 if len(olds) == 1 else adults[group, new, old] / adult_total
            masses[old, group[:5], new] += cvap * share
    expected = math.fsum(c[2] for c in cells.values())
    accounted = math.fsum(masses.values()) + math.fsum(row[-1] for row in unresolved)
    if not math.isclose(accounted, expected, rel_tol=1e-12, abs_tol=1e-6):
        raise ValueError(f"CVAP not conserved across the district overlay in {state}")
    return masses, unresolved


def lookup_rows(state, counts, masses, unresolved):
    groups = defaultdict(Counter)
    mass_groups = defaultdict(Counter)
    for (old, county, new), n in counts.items():
        for area in (county, ""):
            groups[old, area][new] += n
            if masses is not None:
                mass_groups[old, area][new] += masses[old, county, new]
    # For each possible prior district, the full unresolved mass could have
    # come from that district or none of it. These per-origin bounds do not
    # allocate or double-count the five people in the separate source ledger.
    possible = defaultdict(Counter)
    for _, county, _, new, old_choices, _, _, mass in unresolved:
        for old in old_choices.split("|"):
            for area in (county, ""):
                possible[old, area][new] += mass
    for (old, county), destinations in sorted(groups.items()):
        if len(groups[old, ""]) == 1:
            method = "old_district_contained"
        elif len(destinations) == 1:
            method = "county_district_contained"
        else:
            method = "county_district_cvap" if county else "old_district_cvap"
        denom = math.fsum(mass_groups[old, county].values())
        weights = {}
        if len(destinations) == 1:
            weights[next(iter(destinations))] = 1.0
        else:
            if denom == 0:
                raise ValueError(f"Review split district {state}/{old}/{county} with zero known-origin CVAP.")
            weights = {new: mass_groups[old, county][new] / denom for new in destinations}
        if not math.isclose(
                math.fsum(weights.values()), 1.0, abs_tol=1e-12, rel_tol=0):
            raise ValueError(f"District probabilities did not sum to one for {state}/{old}/{county}")
        for new, n in sorted(destinations.items()):
            cvap = mass_groups[old, county][new] if masses is not None else None
            low = high = weights[new]
            possible_total = math.fsum(possible[old, county].values())
            if possible_total and len(destinations) > 1 and denom:
                gained = possible[old, county][new]
                low = cvap / (denom + possible_total - gained)
                high = (cvap + gained) / (denom + gained)
            yield (state, old, county, new, weights[new], method, n, cvap,
                   possible_total, low, high)


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
