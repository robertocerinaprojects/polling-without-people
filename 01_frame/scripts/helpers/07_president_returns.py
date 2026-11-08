"""Reconcile presidential votes and general-election turnout for each state and DC."""

import csv
from collections import Counter
from contextlib import closing

from openpyxl import load_workbook


# The FEC table from state election offices lists votes under each nominee
# across ballot lines. The two final response columns are explicitly included
# in the state's valid presidential total (see the companion FEC PDF, pp. 6–9).
NOMINEE_PARTY = {"HARRIS": "dem", "TRUMP": "rep"}
STATE_FIELDS = (
    "STATEFP", "STUSAB", "votes_dem", "votes_rep", "voters_other", "counted_turnout",
    "valid_presidential_other", "valid_presidential_votes", "turnout_without_valid_presidential_vote",
    "turnout_source", "turnout_is_estimate",
)
VOTE_COLUMNS = (
    "AYYADURAI", "BOWMAN", "DE LA CRUZ", "DUNCAN", "EBKE", "EVERYLOVE", "FRUIT",
    "GARRITY", "HARRIS", "HUBER", "KENNEDY", "KISHORE", "OLIVER", "PRESTON",
    "SKOUSEN", "SONSKI", "STEIN", "STODDEN", "SUPREME", "TERRY", "TRUMP", "WELLS",
    "WEST", "WOOD", "NONE OF THESE CANDIDATES", "WRITE-INS (SCATTERED)",
)


def write_president(xlsx, stage, state_fips, turnout):
    """Write state counts, the FEC source-column audit and the turnout reconciliation."""
    if set(turnout) != set(state_fips):
        raise ValueError("Turnout and the state manifest cover different jurisdictions")
    state_rows = []
    audit_rows = []
    turnout_rows = []
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
            record = turnout[state]
            counted = record["counted_turnout"]
            if (record.get("STATEFP", state_fips[state]) != state_fips[state] or
                    record.get("STUSAB", state) != state):
                raise ValueError(f"{state}: turnout provenance identifies a different jurisdiction")
            source_name, estimate = record["turnout_source"], record["turnout_is_estimate"]
            if source_name == "unresolved":
                if counted is not None or estimate is not None:
                    raise ValueError(f"{state}: an unresolved turnout requires a missing count and estimate flag")
                without_valid_vote = voters_other = None
            else:
                if (type(counted) is not int or counted < total or type(estimate) is not bool or
                        not isinstance(source_name, str) or not source_name.strip()):
                    raise ValueError(f"{state}: invalid turnout source or turnout below valid presidential votes")
                # A counted general-election ballot can have no valid presidential choice.
                without_valid_vote = counted - total
                voters_other = counted - counts["dem"] - counts["rep"]
                if voters_other != counts["other"] + without_valid_vote:
                    raise ValueError(f"{state}: general-election voters outside Democratic/Republican do not reconcile")
            state_rows.append((
                state_fips[state], state, counts["dem"], counts["rep"], voters_other, counted,
                counts["other"], total, without_valid_vote, source_name, estimate,
            ))
            turnout_rows.append({
                **record, "STATEFP": state_fips[state], "STUSAB": state,
                "valid_presidential_votes": total, "turnout_without_valid_presidential_vote": without_valid_vote,
                "valid_presidential_other": counts["other"], "voters_other": voters_other,
            })
            national["TOTAL VOTES"] += total
        else:
            raise ValueError("Missing FEC national totals row")

    if seen != set(state_fips) or len(seen) != 51 or state_fips.get("DC") != "11":
        raise ValueError("Expected 50 states and the District of Columbia")
    files = (
        ("07_president_votes_2024.csv", STATE_FIELDS, state_rows),
        ("07_president_source_votes_2024.csv", ("STATEFP", "STUSAB", "fec_column", "party", "votes"), audit_rows),
    )
    for filename, columns, data in files:
        with (stage / filename).open("w", encoding="utf-8", newline="") as stream:
            writer = csv.writer(stream, lineterminator="\n")
            writer.writerow(columns)
            writer.writerows(data)

    # Keep the chosen source and the underlying EAVS counts visible even for overrides.
    audit_fields = [
        "STATEFP", "STUSAB", "counted_turnout", "turnout_source", "turnout_is_estimate",
        "eavs_jurisdictions", "eavs_unreported", "eavs_reported_voters", "valid_presidential_votes",
        "turnout_without_valid_presidential_vote", "valid_presidential_other", "voters_other",
    ]
    if any(not set(audit_fields).issubset(row) for row in turnout_rows):
        raise ValueError("Turnout reconciliation is missing required provenance fields")
    extra_fields = sorted(set().union(*(row.keys() for row in turnout_rows)) - set(audit_fields))
    with (stage / "07_turnout_audit.csv").open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=audit_fields + extra_fields, lineterminator="\n")
        writer.writeheader()
        writer.writerows(turnout_rows)
