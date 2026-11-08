"""Rebuild the public 2024 presidential and House benchmarks.

Requires Python 3, openpyxl, and the pdftotext executable from Poppler.
Run from the repository root; see 01_frame/docs/05_vote_rules.md.
Caches the two checksum-pinned documents under data/input and exports
three aggregate reference tables under data/output.
"""

import argparse
import csv
import hashlib
import re
import subprocess
from tempfile import TemporaryDirectory
import urllib.request
from collections import Counter, defaultdict
from pathlib import Path
from typing import NamedTuple, Optional

from openpyxl import load_workbook


FEC_URL = "https://www.fec.gov/documents/5645/2024presgeresults.xlsx"
FEC_SHA256 = "68acdee2924d771b92a05cd950dec850b462c633c05563207ac7e206116e7366"
CLERK_URL = "https://clerk.house.gov/member_info/electionInfo/2024/statistics2024.pdf"
CLERK_SHA256 = "d4ba800fc17135b616ae556c92861080ab962d95916ace34b546c5aac824aec4"
STATES = dict(zip(
    ("Alabama|Alaska|Arizona|Arkansas|California|Colorado|Connecticut|Delaware|"
     "Florida|Georgia|Hawaii|Idaho|Illinois|Indiana|Iowa|Kansas|Kentucky|"
     "Louisiana|Maine|Maryland|Massachusetts|Michigan|Minnesota|Mississippi|"
     "Missouri|Montana|Nebraska|Nevada|New Hampshire|New Jersey|New Mexico|"
     "New York|North Carolina|North Dakota|Ohio|Oklahoma|Oregon|Pennsylvania|"
     "Rhode Island|South Carolina|South Dakota|Tennessee|Texas|Utah|Vermont|"
     "Virginia|Washington|West Virginia|Wisconsin|Wyoming").upper().split("|"),
    ("AL AK AZ AR CA CO CT DE FL GA HI ID IL IN IA KS KY LA ME MD MA MI MN "
     "MS MO MT NE NV NH NJ NM NY NC ND OH OK OR PA RI SC SD TN TX UT VT VA "
     "WA WV WI WY").split(),
))
PARTIES = ("Democratic", "Republican", "Other")


def fetch(path, url, checksum):
    data = path.read_bytes() if path.exists() else urllib.request.urlopen(url, timeout=90).read()
    if hashlib.sha256(data).hexdigest() != checksum:
        raise ValueError(f"Unreviewed source {url}")
    if not path.exists():
        with TemporaryDirectory(dir=path.parent) as directory:
            temporary = Path(directory) / path.name
            temporary.write_bytes(data)
            temporary.replace(path)


def save(path, header, rows):
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(header)
        writer.writerows(rows)


def president_rows(xlsx):
    book = load_workbook(xlsx, data_only=True, read_only=True)
    table = book["OFFICIAL 2024 PRES GE RESULTS"].values
    positions = dict((name, i) for i, name in enumerate(next(table)))
    wanted = ["HARRIS", "TRUMP", "TOTAL VOTES"]
    result = [(r[0], *(r[positions[name]] for name in wanted))
              for r in table if r[0] in set(STATES.values()) | {"DC"}]
    book.close()
    assert len(result) == len({r[0] for r in result}) == 51
    assert [sum(r[i] for r in result) for i in (1, 2, 3)] == [75017613, 77302580, 155238302]
    return result


class HouseLine(NamedTuple):
    state: str
    district: str
    kind: str
    label: str
    candidate: str
    ballot_label: str
    party: str
    votes: Optional[int]


# The Clerk's state recaps footnote these unopposed candidates as omitted
# from the general-election ballot. The report gives neither a count nor a share.
HOUSE_UNTABULATED = {("FL", "20"), ("OK", "03")}


def house_source_lines(report):
    """Read each printed contest line once, preserving the Clerk's original label."""
    state, district = None, None
    house = False
    last_candidate, last_party = "", ""
    cross_endorsements = {
        "CT": {"Independent", "Working Families"},
        "NY": {"Conservative", "Common Sense", "Working Families",
               "Common Sense Suffolk", "Conservative, Common Sense"},
    }
    accounting = {"Blank Votes", "Blank", "Blanks", "Over Votes", "Under Votes",
                  "Void", "Continuing Ballots", "Exhausted Ballots"}
    unattributed = {"Write-in", "Other Write-ins", "Scattering", "Miscellaneous", "All Others"}
    state_headers = {**STATES, "DISTRICT OF COLUMBIA": "DC"}
    result = []
    for line in report.splitlines():
        text = line.strip()
        if text in state_headers:
            state, district, house = state_headers[text], None, False
            last_candidate, last_party = "", ""
            continue
        if text.startswith(("Recapitulation of Votes Cast", "FOR PRESIDENTIAL",
                            "FOR UNITED STATES SENATOR", "FOR RESIDENT", "FOR DELEGATE")):
            house = False
        if text in {"FOR UNITED STATES REPRESENTATIVE", "FOR UNITED STATES REPRESENTATIVE—Continued"}:
            house = True
            continue
        if state == "DC" and text == "FOR DELEGATE":
            # DC's section ends at its printed Total. Later delegate sections
            # for other jurisdictions in the same PDF are outside our scope.
            house, district = True, "98"
            continue
        if not house or not text:
            continue
        if text == "AT LARGE":
            district = "00"
            last_candidate, last_party = "", ""
            continue
        new_district = re.match(r"^(\d+)\.\s+", text)
        if new_district:
            district = new_district[1].zfill(2)
            last_candidate, last_party = "", ""
            text = text[new_district.end():]
        row = re.fullmatch(r"(.*?)\s*\.{3,}\s*([\d,]+|\(1\))", text)
        if not row:
            if not re.fullmatch(r"\(?\d+\)?|.*—Continued", text):
                raise ValueError(f"Unknown line in {state}-{district}: {text}")
            continue
        if state is None or district is None:
            raise ValueError(f"Missing contest identifier for {text}")
        label, count = row.groups()
        if count == "(1)" and (state, district) not in HOUSE_UNTABULATED:
            raise ValueError("Unexpected district footnote")
        votes = None if count == "(1)" else int(count.replace(",", ""))
        candidate, ballot_label, party = "", "", ""
        if state == "DC" and label == "Total":
            kind, state, house = "reported_total", None, False
            result.append(HouseLine("DC", district, kind, label, "", "", "", votes))
            continue
        if label in accounting:
            kind = "accounting"
        elif label in cross_endorsements.get(state, set()):
            if not last_candidate:
                raise ValueError(f"Fusion line without a candidate in {state}-{district}: {label}")
            kind, candidate, ballot_label, party = "fusion", last_candidate, label, last_party
        elif label in unattributed:
            kind, party = "unattributed_votes", "Other"
        else:
            # Suffixes such as 'Jr.,' belong to the name. The two dual labels
            # below are the only comma-separated party pairs in the pinned PDF.
            named = re.fullmatch(r"(.+?), (Progressive, Independent|Republican, Libertarian|[^,]+)", label)
            if not named:
                raise ValueError(f"Unrecognized candidate line: {label}")
            candidate, ballot_label = named.groups()
            if ballot_label in {"Democrat", "Democratic-Farmer-Labor", "Democratic-Nonpartisan League", "Write-in (Democratic)"}:
                party = "Democratic"
            elif ballot_label in {"Republican", "Republican, Libertarian"}:
                party = "Republican"
            else:
                party = "Other"
            kind = "candidate"
            last_candidate, last_party = candidate, party
        if kind not in {"candidate", "fusion"}:
            last_candidate, last_party = "", ""
        result.append(HouseLine(state, district, kind, label, candidate, ballot_label, party, votes))
    return result


def house_rows(report, lines=None):
    if lines is None:
        lines = house_source_lines(report)
    districts = defaultdict(Counter)
    raw_sum = Counter()
    for row in lines:
        if row.state == "DC":
            continue  # The Step 05 national voting-House benchmark covers 435 seats.
        # Its published benchmark represents the two unpolled seats as zero
        # counted votes. house_source_lines retains the original missing counts.
        votes = row.votes or 0
        raw_sum[row.state] += votes
        if row.party:
            districts[row.state, row.district][row.party] += votes

    # Reconcile every individual candidate and accounting entry to the state's
    # total in the national recap before discarding blanks or combining fusion.
    recap = report.split("Recapitulation of Votes Cast for United States Representatives,", 1)[1]
    recap = recap.split("Political Divisions of the U.S. Senate", 1)[0]
    state_total = {}
    for line in recap.splitlines():
        m = re.match(r"^([A-Za-z ]+)\s*\.{3,}.*?([\d,]+)\s*$", line.strip())
        if m and m[1].strip().upper() in STATES:
            state_total[STATES[m[1].strip().upper()]] = int(m[2].replace(",", ""))
    if (dict(raw_sum) != state_total or len(state_total) != 50 or
            sum(raw_sum.values()) != 149543421):
        raise ValueError("House source lines differ from the Clerk's state recapitulation")
    unpolled = {k for k, v in districts.items() if sum(v.values()) == 0}
    if len(districts) != 435 or unpolled != HOUSE_UNTABULATED:
        raise ValueError("Unexpected coverage in the voting House districts")
    state_counts = defaultdict(Counter)
    for (st, _), counts in districts.items():
        state_counts[st].update(counts)
    totals = sum(state_counts.values(), Counter())
    if [totals[k] for k in PARTIES] != [70788202, 74824890, 2383450]:
        raise ValueError("House party counts differ from the reviewed Clerk totals")
    result = []
    for unit, counts in sorted(districts.items()):
        result.append((*unit, *(counts[k] for k in PARTIES), sum(counts.values())))
    state_rows = [(st, *(v[k] for k in PARTIES), sum(v.values())) for st,v in sorted(state_counts.items())]
    return result, state_rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-dir", type=Path, default=Path("01_frame/data/input/05_vote_benchmark"))
    parser.add_argument("--output-dir", type=Path, default=Path("01_frame/data/output/05_vote_benchmark/reference"))
    args = parser.parse_args()
    out = args.output_dir
    out.mkdir(parents=True, exist_ok=True)
    args.input_dir.mkdir(parents=True, exist_ok=True)
    xlsx, pdf = args.input_dir / "fec2024.xlsx", args.input_dir / "clerk2024.pdf"
    fetch(xlsx, FEC_URL, FEC_SHA256)
    fetch(pdf, CLERK_URL, CLERK_SHA256)
    report = subprocess.run(["pdftotext", "-layout", str(pdf), "-"], text=True,
                            capture_output=True, check=True).stdout
    district, states = house_rows(report)
    with TemporaryDirectory(dir=out) as directory:
        stage = Path(directory)
        save(stage / "president_by_state.csv", ["state", "Democratic", "Republican", "total"], president_rows(xlsx))
        save(stage / "house_by_state.csv", ["state", *PARTIES, "total"], states)
        save(stage / "house_by_district.csv", ["state", "district", *PARTIES, "total"], district)
        for reference in stage.iterdir():
            reference.replace(out / reference.name)
    print(f"Official 2024 reference tables saved to {out}")


if __name__ == "__main__":
    main()
