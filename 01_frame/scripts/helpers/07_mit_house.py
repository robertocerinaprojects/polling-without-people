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


def classify_house(path):
    """Return each published 2024 House row with its office participation decision.

    source_votes and source_totalvotes reproduce MIT's reported numbers, even
    the unpolled placeholders. Unresolved rows must propagate to missing
    district counts and shares. DC's delegate is CD 98 in Census geography.
    """
    with Path(path).open(encoding="utf-8-sig", newline="") as stream:
        rows = [r for r in csv.DictReader(stream) if r["year"] == "2024"]

    nominees = {}
    records = []
    contests = set()
    for row in rows:
        if (row["office"], row["stage"], row["special"], row["runoff"],
                row["mode"], row["unofficial"]) != (
                "US HOUSE", "GEN", "FALSE", "FALSE", "TOTAL", "FALSE"):
            raise ValueError("Unreviewed House contest or tally type in the 2024 source")
        state = row["state_po"]
        district = "98" if state == "DC" else row["district"].zfill(2)
        key = (state, district)
        contests.add(key)
        candidate = row["candidate"]
        records.append((key, candidate, row))
        affiliation = PARTY_GROUP.get(row["party"])
        if affiliation:
            if nominees.setdefault((key, candidate), affiliation) != affiliation:
                raise ValueError(f"Conflicting major-party affiliations for {key} {candidate}")
    if len(records) != 1353 or len(contests) != 436:
        raise ValueError("Unexpected coverage in the 2024 House release")

    audit = []
    seen_fusion = set()
    seen_unpolled = []
    for key, candidate, row in records:
        state, district = key
        votes = int(row["candidatevotes"])
        reported_total = int(row["totalvotes"])
        fusion_key = (state, district, candidate)
        nominee = FUSION_CANDIDATE.get(fusion_key, candidate)
        affiliation = nominees.get((key, nominee))
        if fusion_key in FUSION_CANDIDATE:
            if affiliation is None:
                raise ValueError(f"The Clerk's nominee is missing from MIT: {fusion_key}")
            seen_fusion.add(fusion_key)
        if key in UNPOLLED:
            if (votes, reported_total) != (1, -1):
                raise ValueError(f"Unreviewed unpolled-district record in {key}")
            seen_unpolled.append(key)
            category, reason = "Unresolved", "Unopposed; no election returns published"
        elif votes < 0 or reported_total < 0:
            raise ValueError(f"Unreviewed negative count in {key}")
        elif candidate in ACCOUNTING:
            category, reason = "Excluded", "Office ballot accounting"
        elif candidate in POOLED:
            category, reason = "Other", "Pooled votes without an identified nominee"
        elif affiliation:
            category = affiliation
            if fusion_key in FUSION_CANDIDATE:
                reason = "Ballot line attributed to nominee in Clerk report"
            elif row["party"] not in PARTY_GROUP:
                reason = "Same district nominee also has a major-party line"
            elif row["writein"] == "TRUE":
                reason = "Named major-party write-in"
            else:
                reason = "Named major-party candidate"
        else:
            if row["fusion_ticket"] == "TRUE" or (row["party"] == "NA" and row["writein"] != "TRUE"):
                raise ValueError(f"Unreviewed House ballot line in {key}: {candidate}")
            category = "Other"
            reason = "Named write-in outside D/R" if row["writein"] == "TRUE" else "Named candidate outside D/R"
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
    if seen_fusion != set(FUSION_CANDIDATE) or sorted(seen_unpolled) != sorted(UNPOLLED):
        raise ValueError("The reviewed House exceptions differ from the source")
    return audit
