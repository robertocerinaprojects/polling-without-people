"""Read presidential popular votes from the pinned FEC state-results workbook."""

import csv
from collections import Counter
from contextlib import closing

from openpyxl import load_workbook


# The FEC table from state election offices lists votes under each nominee
# across ballot lines. The two final response columns are explicitly included
# in the state's valid presidential total (see the companion FEC PDF, pp. 6–9).
NOMINEE_PARTY = {"HARRIS": "dem", "TRUMP": "rep"}
PARTIES = ("dem", "rep", "other")
VOTE_COLUMNS = (
    "AYYADURAI", "BOWMAN", "DE LA CRUZ", "DUNCAN", "EBKE", "EVERYLOVE", "FRUIT",
    "GARRITY", "HARRIS", "HUBER", "KENNEDY", "KISHORE", "OLIVER", "PRESTON",
    "SKOUSEN", "SONSKI", "STEIN", "STODDEN", "SUPREME", "TERRY", "TRUMP", "WELLS",
    "WEST", "WOOD", "NONE OF THESE CANDIDATES", "WRITE-INS (SCATTERED)",
)


def write_president(xlsx, stage, state_fips):
    """Write one 2024 result per state/DC and a state-by-source-column audit."""
    state_rows = []
    audit_rows = []
    seen = set()
    national = Counter()
    with closing(load_workbook(xlsx, read_only=True, data_only=True)) as workbook:
        rows = iter(workbook["OFFICIAL 2024 PRES GE RESULTS"].values)
        header = next(rows)
        votes_columns = header[4:-1]
        if (header[:4] != ("STATE", "ELECTORAL VOTES", "ELECTORAL VOTE: TRUMP (R)",
                           "ELECTORAL VOTE: HARRIS (D)") or header[-1] != "TOTAL VOTES"
                or votes_columns != VOTE_COLUMNS):
            raise ValueError("Unexpected FEC presidential result columns")

        for row in rows:
            state = row[0]
            if state == "Total:":
                if list(row[4:]) != [national[column] for column in header[4:]]:
                    raise ValueError("State returns differ from the FEC national column totals")
                break
            if state not in state_fips or state in seen:
                raise ValueError(f"Unexpected or repeated FEC state: {state!r}")
            seen.add(state)
            counts = Counter()
            for source, votes in zip(votes_columns, row[4:-1]):
                if votes is not None and (type(votes) is not int or votes < 0):
                    raise ValueError(f"Invalid FEC count for {state}/{source}: {votes!r}")
                party = NOMINEE_PARTY.get(source, "other")
                # Preserve blank source cells in the audit. They add no separately
                # identified votes in the FEC table, even if scattered votes exist.
                audit_rows.append((state_fips[state], state, source, party, votes))
                if votes is not None:
                    counts[party] += votes
                    national[source] += votes
            total = row[-1]
            if type(total) is not int or total <= 0 or sum(counts.values()) != total:
                raise ValueError(f"Candidate and residual counts differ from {state}'s FEC total")
            state_rows.append((state_fips[state], state, *(counts[party] for party in PARTIES), total))
            national["TOTAL VOTES"] += total
        else:
            raise ValueError("Missing FEC national totals row")

    if seen != set(state_fips) or len(seen) != 51 or state_fips.get("DC") != "11":
        raise ValueError("Expected 50 states and the District of Columbia")
    files = (
        ("07_president_votes_2024.csv",
         ("STATEFP", "STUSAB", *(f"votes_{party}" for party in PARTIES), "total_votes"), state_rows),
        ("07_president_source_votes_2024.csv", ("STATEFP", "STUSAB", "fec_column", "party", "votes"), audit_rows),
    )
    for filename, columns, data in files:
        with (stage / filename).open("w", encoding="utf-8", newline="") as stream:
            writer = csv.writer(stream, lineterminator="\n")
            writer.writerow(columns)
            writer.writerows(data)
