"""Build regular November House candidate configurations for CD119 and CD120."""
from collections import Counter
import csv
import hashlib
from pathlib import Path
import re
import subprocess
from tempfile import TemporaryDirectory
from urllib.request import urlopen

FRAME = Path(__file__).resolve().parents[1]
# House Clerk official nominee directories, checked against published ballot metadata.
# Digests identify the two PDFs reviewed for this release. See 08_house_slates.md.
SOURCE_DIGEST = {
    2024: "e53acf48e946a270da18aac1ff665c07a6cb7e11057f8f28cfb239f282a3a617",
    2026: "cb2e4194c88042cf22f8589fb6b8c352d29b501f96abc62a962b6cc52e2c28a8",
}
# SHA-256 of the sorted state, district and D/R/O counts independently checked
# against the November rosters and federal DC sample ballots for both years.
REVIEWED_CONFIGURATIONS = {
    2024: "b9c60a19c2965132ac20893b8b6d88089365ca9a17175fc0951006bb54b2fe35",
    2026: "76d1b784c9790bb1b7f94f6abb97c14cb54f719d06adf2ba94aa38cb9453d762",
}
AT_LARGE = {"AK", "DE", "ND", "SD", "VT", "WY"}
TERRITORIES = {"AMERICAN SAMOA", "GUAM", "NORTHERN MARIANA ISLANDS", "PUERTO RICO", "VIRGIN ISLANDS"}
DEMOCRATIC = {"Democrat", "Democratic", "Democratic-Farmer-Labor", "Democratic-Nonpartisan League"}


def csv_rows(path):
    with path.open(encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def nominees(year, states):
    congress = {2024: 119, 2026: 120}[year]
    url = f"https://clerk.house.gov/member_info/electionInfo/{year}/{congress}-nominations.pdf"
    path = FRAME / "data" / "input" / f"{congress}-nominations.pdf"
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        content = path.read_bytes()
    else:
        with urlopen(url, timeout=120) as response:
            content = response.read()
    if hashlib.sha256(content).hexdigest() != SOURCE_DIGEST[year]:
        raise ValueError(f"Nominee list differs from the reviewed {year} PDF: {url}")
    if not path.exists():
        with TemporaryDirectory(dir=path.parent) as d:
            staged = Path(d) / path.name
            staged.write_bytes(content)
            staged.replace(path)
    result = subprocess.run(
        ["pdftotext", "-enc", "UTF-8", "-layout", str(path), "-"],
        capture_output=True, check=True, encoding="utf-8"
    )

    roster = {}
    state = district = None
    reading_house = False
    for raw in result.stdout.splitlines():
        line = raw.strip()
        heading = re.sub(r"\d+$", "", line.partition("—")[0])
        if heading in states or heading in TERRITORIES:
            state = states.get(heading)
            reading_house = False
            if "Continued" not in line:
                district = None
                if state and state["STUSAB"] in AT_LARGE:
                    district = "00"
                elif state and state["STUSAB"] == "DC":
                    district = "98"
            continue
        if line.startswith("FOR "):
            reading_house = bool(state and (
                heading == "FOR UNITED STATES REPRESENTATIVE" or
                (state["STUSAB"] == "DC" and heading == "FOR DELEGATE")
            ))
            continue
        if not reading_house:
            continue
        # The dot leader separates name/party from residence. Intro, footnote,
        # Senate, territory and historical table rows are outside the selection.
        cells = re.split(r"\.{2,}|…", line, maxsplit=1)
        if len(cells) != 2:
            continue
        label = cells[0].strip()
        district_prefix = re.match(r"^(?:\d+\s+)?(\d{1,2})\s+(.+)", label)
        if district_prefix:
            district = f"{int(district_prefix[1]):02d}"
            label = district_prefix[2]
        terms = [x.strip() for x in re.sub("[*†‡]", "", label).split(",")]
        if not district or len(terms) < 2:
            raise ValueError(f"Unexpected {year} House nominee row: {line}")
        split = 2 if terms[1] in {"Jr.", "Sr.", "Jr", "Sr", "II", "III", "IV"} else 1
        name = ", ".join(terms[:split])
        key = (state["STATEFP"], district, name)
        if key in roster or not terms[split:]:
            raise ValueError(f"Duplicate or incomplete {year} nominee: {key}")
        roster[key] = dict(party=", ".join(terms[split:]), included=1,
                           decision="clerk_nominee", source=url)
    return roster


def apply_reviews(roster, decisions):
    for row in decisions:
        key = (row["STATEFP"], row["CDFP"], row["candidate"])
        action = row["action"]
        if action == "add":
            if key in roster:
                raise ValueError(f"Reviewed addition already appears: {key}")
            roster[key] = dict(party=row["party"], included=1,
                               decision=row["reason"], source=row["source"])
        elif action == "remove":
            if roster[key]["party"] != row["party"] or not roster[key]["included"]:
                raise ValueError(f"Reviewed removal disagrees with input: {key}")
            roster[key].update(included=0, decision=row["reason"], source=row["source"])
        else:
            raise ValueError(f"Unexpected reviewed action: {action}")


def summarize(year, roster):
    groups = {}
    audit = []
    for (state, district, name), nominee in sorted(roster.items()):
        parties = set(nominee["party"].split(", "))
        is_dem = bool(parties & DEMOCRATIC)
        is_rep = "Republican" in parties
        if is_dem and is_rep:
            raise ValueError(f"Both major party labels on one candidate: {name}")
        group = "D" if is_dem else ("R" if is_rep else "O")
        audit.append(dict(year=year, STATEFP=state, CDFP=district, candidate=name,
                          party_group=group, **nominee))
        if nominee["included"]:
            groups.setdefault((state, district), Counter())[group] += 1
    slates = []
    for (state, district), counts in sorted(groups.items()):
        slate = "".join(c for c in "DRO" if counts[c])
        size = sum(counts.values())
        slates.append(dict(STATEFP=state, CDFP=district, n_dem=counts["D"], n_rep=counts["R"],
                           n_other=counts["O"], slate=slate, unopposed=int(size == 1),
                           same_party_multiple=int(len(slate) == 1 and size > 1)))
    return audit, slates


def save(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    with TemporaryDirectory(dir=path.parent) as tmp:
        temporary = Path(tmp) / path.name
        with temporary.open("w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=list(rows[0]), lineterminator="\n")
            writer.writeheader()
            writer.writerows(rows)
        temporary.replace(path)


def main():
    manifest = csv_rows(FRAME / "docs" / "02_pl_2020_sources.csv")
    states = {r["state_name"].upper(): r for r in manifest}
    reviews = csv_rows(FRAME / "docs" / "08_house_slate_corrections.csv")
    if {r["year"] for r in reviews} != {str(y) for y in SOURCE_DIGEST}:
        raise ValueError("Unexpected election year in the slate review table.")
    tables = {}
    audit = []
    district_sets = []
    for year in SOURCE_DIGEST:
        roster = nominees(year, states)
        apply_reviews(roster, [r for r in reviews if r["year"] == str(year)])
        evidence, slates = summarize(year, roster)
        districts = {(r["STATEFP"], r["CDFP"]) for r in slates}
        if (len(districts) != 436 or {s for s, d in districts} != {r["STATEFP"] for r in manifest}
                or ("11", "98") not in districts):
            raise ValueError(f"Expected 435 voting districts plus the DC delegate in {year}")
        fields = ("STATEFP", "CDFP", "n_dem", "n_rep", "n_other")
        lines = (",".join(str(row[key]) for key in fields) for row in slates)
        digest = hashlib.sha256(("\n".join(lines) + "\n").encode("ascii")).hexdigest()
        if digest != REVIEWED_CONFIGURATIONS[year]:
            raise ValueError(f"District party counts differ from the independently reviewed {year} slate.")
        district_sets.append(districts)
        tables[year] = slates
        audit.extend(evidence)
    if district_sets[0] != district_sets[1]:
        raise ValueError("District labels differ between election years; check apportionment.")
    for year, slates in tables.items():
        target = FRAME / "data" / "intermediate" / f"08_house_slates_{year}.csv"
        save(target, slates)
        print(f"{year}: {len(slates)} seats including DC; configurations {dict(Counter(r['slate'] for r in slates))}")
    save(FRAME / "data" / "output" / "08_house_slate_nominees.csv", audit)


if __name__ == "__main__":
    main()
