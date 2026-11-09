"""Classify the 2024 regular House rows in MIT's district returns, release 15.

MIT Election Data and Science Lab, doi:10.7910/DVN/IG0UN2. Keep its published
tabulation for each contest: first preferences in Alaska and final-round
candidate counts in ME-02. The exhausted ballots in the latter do not enter
vote counts; adding earlier write-in totals to the final round would count
some people's ballots twice.
"""

import csv
from pathlib import Path


PARTY_GROUP = {
    "DEMOCRAT": "Democratic",
    "DEMOCRATIC-FARMER-LABOR": "Democratic",
    "DEMOCRATIC-NONPARTISAN LEAGUE": "Democratic",
    "REPUBLICAN": "Republican",
    "REPUBLICAN, LIBERTARIAN": "Republican",
}

POOLED = {"WRITEIN", "OTHER WRITE-INS", "SCATTERING", "MISCELLANEOUS", "ALL OTHERS"}
ACCOUNTING = {
    "BLANK", "BLANKS", "BLANK VOTES", "UNDER VOTES", "OVER VOTES",
    "EXHAUSTED BALLOTS", "VOID", "SPOILED", "NONE OF THESE CANDIDATES",
}

# Four MIT candidate cells contain a ballot-line name in place of a nominee.
# The Clerk prints these lines under the corresponding named nominees on
# PDF pages 15 and 49: https://clerk.house.gov/member_info/electionInfo/2024/statistics2024.pdf
FUSION_CANDIDATE = {
    ("CT", "01", "WORKING FAMILIES"): "JOHN B. LARSON",
    ("CT", "03", "INDEPENDENT"): "MICHAEL MASSEY",
    ("CT", "05", "WORKING FAMILIES"): "JAHANA HAYES",
    ("NY", "05", "CONSERVATIVE"): "PAUL KING",
}

# The Clerk notes that these unopposed candidates did not appear on the
# ballot. MIT encodes each with candidatevotes=1 and totalvotes=-1.
UNPOLLED = {("FL", "20"), ("OK", "03")}


def classify_house_choice(row, contest, nominee_party, clerk_alias):
    """Classify a tabulated line and explain its treatment in the source audit."""
    candidate = row["candidate"]
    if candidate in ACCOUNTING:
        return "Excluded", "Office ballot accounting"
    if candidate in POOLED:
        return "Other", "Pooled votes without an identified nominee"

    # Attribute every line for a major-party nominee in this district to
    # that nominee, including named write-ins and cross-endorsements.
    if nominee_party:
        if clerk_alias:
            return nominee_party, "Ballot line attributed to nominee in Clerk report"
        if row["party"] not in PARTY_GROUP:
            return nominee_party, "Same district nominee also has a major-party line"
        if row["writein"] == "TRUE":
            return nominee_party, "Named major-party write-in"
        return nominee_party, "Named major-party candidate"

    if row["fusion_ticket"] == "TRUE" or (row["party"] == "NA" and row["writein"] != "TRUE"):
        raise ValueError(f"Unreviewed House ballot line in {contest}: {candidate}")
    if row["writein"] == "TRUE":
        return "Other", "Named write-in outside D/R"
    return "Other", "Named candidate outside D/R"


def classify_house(path):
    """Return each published 2024 House row with its office participation decision.

    source_votes and source_totalvotes reproduce MIT's reported numbers, even
    the unpolled placeholders. Unresolved rows must propagate to missing
    district counts and shares. DC's delegate is CD 98 in Census geography.
    """
    with Path(path).open(encoding="utf-8-sig", newline="") as stream:
        rows = [row for row in csv.DictReader(stream) if row["year"] == "2024"]

    # First pass: find each nominee's major-party affiliation within a seat.
    # A cross-endorsing party can appear before the major party in the file.
    party_by_seat_and_candidate = {}
    records = []
    contests = set()
    tally_fields = ("office", "stage", "special", "runoff", "mode", "unofficial")
    regular_general = ("US HOUSE", "GEN", "FALSE", "FALSE", "TOTAL", "FALSE")
    for row in rows:
        if tuple(row[field] for field in tally_fields) != regular_general:
            raise ValueError("Unreviewed House contest or tally type in the 2024 source")
        state = row["state_po"]
        district = "98" if state == "DC" else row["district"].zfill(2)
        contest = (state, district)
        contests.add(contest)
        candidate = row["candidate"]
        records.append((contest, candidate, row))
        affiliation = PARTY_GROUP.get(row["party"])
        if affiliation:
            nominee_key = (contest, candidate)
            previous = party_by_seat_and_candidate.get(nominee_key)
            if previous is not None and previous != affiliation:
                raise ValueError(f"Conflicting major-party affiliations for {contest} {candidate}")
            party_by_seat_and_candidate[nominee_key] = affiliation
    # Reviewed release 15 has 1,353 source rows spanning 435 seats and DC.
    if len(records) != 1353 or len(contests) != 436:
        raise ValueError("Unexpected coverage in the 2024 House release")

    # Second pass: use the complete list of nominees to classify each source
    # line in its original order. Four alias lookups above recover the name
    # when MIT supplies the ballot-line label in the candidate field.
    audit = []
    observed_aliases = set()
    unpolled_rows = []
    for contest, candidate, row in records:
        state, district = contest
        votes = int(row["candidatevotes"])
        reported_total = int(row["totalvotes"])
        alias_key = (state, district, candidate)
        nominee = FUSION_CANDIDATE.get(alias_key, candidate)
        nominee_party = party_by_seat_and_candidate.get((contest, nominee))
        clerk_alias = alias_key in FUSION_CANDIDATE
        if clerk_alias:
            if nominee_party is None:
                raise ValueError(f"The Clerk's nominee is missing from MIT: {alias_key}")
            observed_aliases.add(alias_key)
        if contest in UNPOLLED:
            if (votes, reported_total) != (1, -1):
                raise ValueError(f"Unreviewed unpolled-district record in {contest}")
            unpolled_rows.append(contest)
            category, reason = "Unresolved", "Unopposed; no election returns published"
        elif votes < 0 or reported_total < 0:
            raise ValueError(f"Unreviewed negative count in {contest}")
        else:
            category, reason = classify_house_choice(row, contest, nominee_party, clerk_alias)

        audit.append({
            "STATEFP": row["state_fips"].zfill(2),
            "STUSAB": state,
            "district_2024": district,
            "source_candidate": candidate,
            "source_party": row["party"],
            "source_votes": votes,
            "source_totalvotes": reported_total,
            "source_writein": row["writein"],
            "attributed_candidate": "" if candidate in ACCOUNTING | POOLED else nominee,
            "category": category,
            "reason": reason,
        })
    if observed_aliases != set(FUSION_CANDIDATE) or sorted(unpolled_rows) != sorted(UNPOLLED):
        raise ValueError("The reviewed House exceptions differ from the source")
    return audit
