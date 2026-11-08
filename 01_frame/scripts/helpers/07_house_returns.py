"""Observed regular 2024 House general-election returns in CD119 geography."""

from collections import defaultdict
from importlib import import_module

clerk = import_module(".05_benchmark_official", __package__)


def write_house(report, stage, state_fips):
    """Write a row per 119th district and the source lines from the Clerk's report."""
    lines = clerk.house_source_lines(report)
    district_rows, _ = clerk.house_rows(report, lines)  # Reconcile all 50 state recaps + US totals.
    voting_counts = {(state, district): [dem, rep, other, total]
                     for state, district, dem, rep, other, total in district_rows}
    by_district = defaultdict(list)
    source_rows = []
    result = []
    for row in lines:
        key = (row.state, row.district)
        by_district[key].append(row)
        office = "delegate" if row.state == "DC" else "representative"
        source_rows.append((state_fips[row.state], row.state, row.district, office, row.kind,
                            row.label, row.candidate, row.ballot_label, row.party, row.votes))

    if set(by_district) != set(voting_counts) | {("DC", "98")} or len(by_district) != 436:
        raise ValueError("Unexpected House or delegate district coverage")
    unpolled = {key for key, rows in by_district.items() if any(row.votes is None for row in rows)}
    if unpolled != clerk.HOUSE_UNTABULATED:
        raise ValueError("The districts with unreported votes differ from the two Clerk footnotes")
    for (state, district), rows in sorted(by_district.items(), key=lambda x: (state_fips[x[0][0]], x[0][1])):
        key = state, district
        office = "delegate" if state == "DC" else "representative"
        status = "observed"
        # The Clerk prints the first preferences in Alaska and the final two
        # candidate totals after ranked-choice tabulation in Maine district 2.
        tabulation = {("AK", "00"): "first_preferences", ("ME", "02"): "final_ranked_choice"}.get(key, "as_published")
        if key in unpolled:
            if len(rows) != 1 or rows[0].kind != "candidate" or rows[0].votes is not None:
                raise ValueError(f"Unexpected candidate listing for unpolled {key}")
            counts = [None] * 4
            status = "unopposed_not_on_ballot"
            tabulation = "no_tabulation"
        else:
            counts = [sum(row.votes for row in rows if row.party == p) for p in clerk.PARTIES]
            counts.append(sum(counts))
            if counts[-1] <= 0:
                raise ValueError(f"No candidate votes found for {key}")
            if office == "representative" and counts != voting_counts[key]:
                raise ValueError(f"Candidate vote counts differ from the voting-seat benchmark for {key}")
            if office == "delegate":
                # DC prints one race total including both under- and over-votes.
                printed_total = [row.votes for row in rows if row.kind == "reported_total"]
                accounting = sum(row.votes for row in rows if row.kind == "accounting")
                if printed_total != [counts[-1] + accounting] or printed_total != [328404]:
                    raise ValueError("DC delegate candidate and ballot-accounting counts do not reconcile")
        result.append((state_fips[state], state, district, office, status, tabulation, *counts))
    clerk.save(stage / "07_house_source_lines_cd119.csv",
               ["STATEFP", "STUSAB", "CDFP119", "office", "line_type", "source_label", "candidate",
                "ballot_label", "party_group", "votes"], source_rows)
    clerk.save(stage / "07_house_votes_cd119.csv",
               ["STATEFP", "STUSAB", "CDFP119", "office", "status", "tabulation", "votes_dem", "votes_rep",
                "votes_other", "total_votes"], result)
