"""Count named candidates and identify sitting members in each House contest.

The 2024 roster uses 119th Congress districts and the 2026 roster uses the 120th.
Read the pinned Clerk lists, apply the documented ballot corrections, then
write both annual district tables and the candidate-by-candidate audit.
Also build the counterfactual district table using 2026 nominees and
November 4, 2024 House membership.
"""

from collections import Counter
import csv
import hashlib
from pathlib import Path
import re
import subprocess
import unicodedata
from tempfile import TemporaryDirectory
from urllib.request import urlopen

FRAME = Path(__file__).resolve().parents[1]
# House Clerk official nominee directories, checked against published ballot metadata.
# Digests identify the two PDFs reviewed for this release. See 08_house_slates.md.
SOURCE_DIGEST = {
    2024: "e53acf48e946a270da18aac1ff665c07a6cb7e11057f8f28cfb239f282a3a617",
    2026: "cb2e4194c88042cf22f8589fb6b8c352d29b501f96abc62a962b6cc52e2c28a8",
}
# SHA-256 of the reviewed district keys, nominee counts and incumbent flags.
# The independent roster and congressional membership checks are documented
# in 08_house_slates.md. The column order is in check_district_roster().
REVIEWED_ROSTERS = {
    2024: "6b889f8426e0c8724907a72336ff034354e94f0b7c8387170eee24085c132dc4",
    2026: "bb4df3569d73825cd13471c1f3485367905f0e8158b3117dd6259ed927ab6983",
}
AT_LARGE = {"AK", "DE", "ND", "SD", "VT", "WY"}
TERRITORIES = {"AMERICAN SAMOA", "GUAM", "NORTHERN MARIANA ISLANDS", "PUERTO RICO", "VIRGIN ISLANDS"}
DEMOCRATIC = {"Democrat", "Democratic", "Democratic-Farmer-Labor", "Democratic-Nonpartisan League"}


def csv_rows(path):
    with path.open(encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


# Source PDFs and roster parsing ------------------------------------------------
def nominee_pdf(year):
    """Reuse or download the reviewed Clerk PDF and return its path and source URL."""
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
    return path, url


def read_nominee_rows(text, year, states, url):
    """Follow state, office and district headings while reading the Clerk's layout."""
    roster = {}
    state = district = None
    reading_house = False
    for raw in text.splitlines():
        line = raw.strip()
        # Ignore footnote digits and the text after the dash in a heading.
        # A continued page keeps the current district. A new state resets it.
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
            house_heading = heading == "FOR UNITED STATES REPRESENTATIVE"
            dc_delegate_heading = state and state["STUSAB"] == "DC" and heading == "FOR DELEGATE"
            reading_house = bool(state and (house_heading or dc_delegate_heading))
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
        # A suffix such as “Jr.” belongs to the name. Keep the remaining
        # comma-separated party labels together for cross-endorsed nominees.
        # Read the Clerk's service mark before removing it from the name.
        # A former member (‡) can stand again after time out of Congress.
        marks = re.findall("[*†‡]", label)
        if len(marks) > 1 or "†" in marks:
            # † denotes service during this Congress. None of our reviewed
            # House/Delegate rows carries it; check dates if a new one does.
            raise ValueError(f"Review congressional service for {year}: {label}")
        service_mark = marks[0] if marks else ""
        terms = [part.strip() for part in re.sub("[*†‡]", "", label).split(",")]
        if not district or len(terms) < 2:
            raise ValueError(f"Unexpected {year} House nominee row: {line}")
        party_start = 2 if terms[1] in {"Jr.", "Sr.", "Jr", "Sr", "II", "III", "IV"} else 1
        name = ", ".join(terms[:party_start])
        party_labels = terms[party_start:]
        key = (state["STATEFP"], district, name)
        if key in roster or not party_labels:
            raise ValueError(f"Duplicate or incomplete {year} nominee: {key}")
        roster[key] = dict(party=", ".join(party_labels), included=1,
                           decision="clerk_nominee", source=url,
                           clerk_service_mark=service_mark, incumbent=int(service_mark == "*"),
                           incumbent_source=url)
    return roster


def nominees(year, states):
    path, url = nominee_pdf(year)
    result = subprocess.run(
        ["pdftotext", "-enc", "UTF-8", "-layout", str(path), "-"],
        capture_output=True, check=True, encoding="utf-8"
    )
    sitting_congress = {2024: 118, 2026: 119}[year]
    if f"Those marked * are incumbent in the {sitting_congress}th Congress" not in result.stdout:
        raise ValueError(f"Could not verify the Clerk's incumbency legend for {year}.")
    return read_nominee_rows(result.stdout, year, states, url)


# Reviewed corrections and district counts --------------------------------------
def apply_reviews(roster, decisions):
    """Apply the ballot review table; keep removed nominees in the audit."""
    for row in decisions:
        key = (row["STATEFP"], row["CDFP"], row["candidate"])
        action = row["action"]
        if action == "add":
            if key in roster:
                raise ValueError(f"Reviewed addition already appears: {key}")
            # These names are absent from the October PDF. Read the separate
            # membership review for each addition before counting the nominee.
            if row["incumbent"] not in {"0", "1"} or not row["incumbent_source"]:
                raise ValueError(f"Missing incumbency review for added nominee: {key}")
            roster[key] = dict(party=row["party"], included=1,
                               decision=row["reason"], source=row["source"],
                               clerk_service_mark="not_listed", incumbent=int(row["incumbent"]),
                               incumbent_source=row["incumbent_source"])
        elif action == "remove":
            if roster[key]["party"] != row["party"] or not roster[key]["included"]:
                raise ValueError(f"Reviewed removal disagrees with input: {key}")
            roster[key].update(included=0, decision=row["reason"], source=row["source"])
        else:
            raise ValueError(f"Unexpected reviewed action: {action}")


def summarize(year, roster):
    """Count each included nominee once, even if they carry multiple party labels."""
    counts_by_district = {}
    parties_with_incumbents = set()
    audit = []
    for (state, district, name), nominee in sorted(roster.items()):
        parties = set(nominee["party"].split(", "))
        is_dem = bool(parties & DEMOCRATIC)
        is_rep = "Republican" in parties
        if is_dem and is_rep:
            raise ValueError(f"Both major party labels on one candidate: {name}")
        if is_dem:
            group = "D"
        elif is_rep:
            group = "R"
        else:
            group = "O"
        audit.append(dict(year=year, STATEFP=state, CDFP=district, candidate=name,
                          party_group=group, **nominee))
        if nominee["included"]:
            counts_by_district.setdefault((state, district), Counter())[group] += 1
            if nominee["incumbent"]:
                parties_with_incumbents.add((state, district, group))

    # The slate string records which groups are present. “D” can mean either
    # one unopposed Democrat or a choice between two or more Democrats.
    slates = []
    for (state, district), counts in sorted(counts_by_district.items()):
        slate = "".join(party for party in "DRO" if counts[party])
        candidate_count = sum(counts.values())
        slates.append(dict(STATEFP=state, CDFP=district, n_dem=counts["D"], n_rep=counts["R"],
                           n_other=counts["O"], slate=slate, unopposed=int(candidate_count == 1),
                           same_party_multiple=int(len(slate) == 1 and candidate_count > 1),
                           incumbent_dem=int((state, district, "D") in parties_with_incumbents),
                           incumbent_rep=int((state, district, "R") in parties_with_incumbents),
                           incumbent_other=int((state, district, "O") in parties_with_incumbents)))
    return audit, slates


# Counterfactual incumbency for the 2026 nominees -----------------------------
def member_name_key(name):
    """Allow Clerk variants in accents, punctuation, middle initials and suffixes."""
    name = re.sub(r'“[^”]+”|"[^"]+"', " ", name)
    name = unicodedata.normalize("NFKD", name.casefold())
    name = "".join(char for char in name if not unicodedata.combining(char))
    words = re.findall(r"[a-z]+", name.replace("’", "'").replace("'", ""))
    return " ".join(word for word in words if len(word) > 1 and word not in {"jr", "sr", "ii", "iii", "iv"})


def election_eve_members(districts):
    path = FRAME / "docs" / "08_house_members_2024_election_eve.csv"
    rows = csv_rows(path)
    seats = {(row["STATEFP"], row["CDFP118"]) for row in rows}
    # The three voting-seat vacancies on November 4 were NJ-09, TX-18 and WI-08.
    if len(seats) != len(rows) or seats != districts - {("34", "09"), ("48", "18"), ("55", "08")}:
        raise ValueError(f"Unexpected November 4 House seat coverage in {path}")
    # Index the full House membership across districts within each state.
    # A district key would miss incumbents who ran in a different seat.
    # Keeping the state avoids joining nominees to out-of-state namesakes.
    members = {}
    for row in rows:
        key = (row["STATEFP"], member_name_key(row["member"]))
        if not key[1] or key in members:
            raise ValueError(f"Missing or ambiguous November 4 member name: {row}")
        members[key] = row
    return members


def counterfactual_slates(audit, roster, members):
    """Use the 2026 ballot party and the nominee's House seat on November 4, 2024."""
    scenario = {}
    for row in audit:
        member = members.get((row["STATEFP"], member_name_key(row["candidate"])))
        incumbent = int(member is not None)
        # The reviewed 2024 slate provides an independent check on the match
        # for both sitting members and challengers.
        if row["year"] == 2024 and row["included"] and incumbent != row["incumbent"]:
            raise ValueError(f"November 4 membership disagrees with reviewed 2024 nominee: {row['candidate']}")
        row.update(incumbent_2024=incumbent,
                   member_name_2024=member["member"] if member else "",
                   member_district_2024=member["CDFP118"] if member else "")
        # Copy the 2026 nominee so the annual audit retains its own service flag.
        if row["year"] == 2026:
            key = (row["STATEFP"], row["CDFP"], row["candidate"])
            scenario[key] = dict(roster[key], incumbent=incumbent)
    _, slates = summarize(2026, scenario)
    return slates


def check_district_roster(year, slates, manifest):
    districts = {(row["STATEFP"], row["CDFP"]) for row in slates}
    actual_states = {state for state, district in districts}
    expected_states = {row["STATEFP"] for row in manifest}
    if len(districts) != 436 or actual_states != expected_states or ("11", "98") not in districts:
        raise ValueError(f"Expected 435 voting districts plus the DC delegate in {year}")

    # Check each district. Two seats exchanging incumbents could preserve the
    # national count while giving each district the wrong predictors.
    fields = ("STATEFP", "CDFP", "n_dem", "n_rep", "n_other",
              "incumbent_dem", "incumbent_rep", "incumbent_other")
    lines = [",".join(str(row[field]) for field in fields) for row in slates]
    fingerprint = hashlib.sha256(("\n".join(lines) + "\n").encode("ascii")).hexdigest()
    if fingerprint != REVIEWED_ROSTERS[year]:
        raise ValueError(f"District nominee counts or incumbency flags differ from the reviewed {year} roster.")
    return districts


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
    rosters = {}
    for year in SOURCE_DIGEST:
        roster = nominees(year, states)
        year_reviews = [row for row in reviews if row["year"] == str(year)]
        apply_reviews(roster, year_reviews)
        rosters[year] = roster
        evidence, slates = summarize(year, roster)
        districts = check_district_roster(year, slates, manifest)
        district_sets.append(districts)
        tables[year] = slates
        audit.extend(evidence)
    if district_sets[0] != district_sets[1]:
        raise ValueError("District labels differ between election years; check apportionment.")
    members = election_eve_members(district_sets[0])
    scenario = counterfactual_slates(audit, rosters[2026], members)
    save(FRAME / "data" / "intermediate" / "08_house_slates_2026_incumbency_2024.csv", scenario)
    for year, slates in tables.items():
        target = FRAME / "data" / "intermediate" / f"08_house_slates_{year}.csv"
        save(target, slates)
        configurations = dict(Counter(row["slate"] for row in slates))
        print(f"{year}: {len(slates)} seats including DC; configurations {configurations}")
    save(FRAME / "data" / "output" / "08_house_slate_nominees.csv", audit)


if __name__ == "__main__":
    main()
