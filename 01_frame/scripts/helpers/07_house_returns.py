"""Observed regular 2024 House general-election returns in CD119 geography."""

from collections import defaultdict
from importlib import import_module

clerk = import_module(".05_benchmark_official", __package__)

# The Clerk reports first preferences in Alaska and the final two candidates in ME-02.
RANKED_CHOICE_TABULATION = {("AK", "00"): "first_preferences", ("ME", "02"): "final_ranked_choice"}


def district_result(key, rows, unpolled, voting_counts):
    """Return the contest status, count method, D/R/Other votes and candidate total."""
    if key in unpolled:
        # FL-20 and OK-03 list one nominee with a footnote in place of a count.
        if len(rows) != 1 or rows[0].kind != "candidate" or rows[0].votes is not None:
            raise ValueError(f"Unexpected candidate listing for unpolled {key}")
        return "unopposed_not_on_ballot", "no_tabulation", None, None, None, None

    by_party = {party: sum(row.votes for row in rows if row.party == party) for party in clerk.PARTIES}
    candidate_total = sum(by_party.values())
    counts = (by_party["Democratic"], by_party["Republican"], by_party["Other"], candidate_total)
    if candidate_total <= 0:
        raise ValueError(f"No candidate votes found for {key}")

    if key == ("DC", "98"):
        # DC's printed delegate total also counts under- and over-votes.
        printed_total = [row.votes for row in rows if row.kind == "reported_total"]
        accounting = sum(row.votes for row in rows if row.kind == "accounting")
        if printed_total != [candidate_total + accounting] or printed_total != [328404]:
            raise ValueError("DC delegate candidate and ballot-accounting counts do not reconcile")
    elif counts != voting_counts[key]:
        raise ValueError(f"Candidate vote counts differ from the voting-seat benchmark for {key}")

    return "observed", RANKED_CHOICE_TABULATION.get(key, "as_published"), *counts


def write_house(report, stage, state_fips):
    """Write a row per 119th district and the source lines from the Clerk's report."""
    lines = clerk.house_source_lines(report)
    district_rows, _ = clerk.house_rows(report, lines)  # Reconcile the 50 state recaps and national totals.
    voting_counts = {(state, district): (dem, rep, other, total)
                     for state, district, dem, rep, other, total in district_rows}
    by_district = defaultdict(list)
    source_rows = []
    for row in lines:
        by_district[row.state, row.district].append(row)
        office = "delegate" if row.state == "DC" else "representative"
        source_rows.append((state_fips[row.state], row.state, row.district, office, row.kind,
                            row.label, row.candidate, row.ballot_label, row.party, row.votes))

    if set(by_district) != set(voting_counts) | {("DC", "98")} or len(by_district) != 436:
        raise ValueError("Unexpected House or delegate district coverage")
    unpolled = {key for key, rows in by_district.items() if any(row.votes is None for row in rows)}
    if unpolled != clerk.HOUSE_UNTABULATED:
        raise ValueError("The districts with unreported votes differ from the two Clerk footnotes")

    district_order = sorted(by_district, key=lambda key: (state_fips[key[0]], key[1]))
    results = []
    for state, district in district_order:
        key = state, district
        office = "delegate" if state == "DC" else "representative"
        result = district_result(key, by_district[key], unpolled, voting_counts)
        results.append((state_fips[state], state, district, office, *result))

    clerk.save(stage / "07_house_source_lines_cd119.csv",
               ["STATEFP", "STUSAB", "CDFP119", "office", "line_type", "source_label", "candidate",
                "ballot_label", "party_group", "votes"], source_rows)
    clerk.save(stage / "07_house_votes_cd119.csv",
               ["STATEFP", "STUSAB", "CDFP119", "office", "status", "tabulation", "votes_dem", "votes_rep",
                "votes_other", "total_votes"], results)
