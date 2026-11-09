"""Prepare 2024 presidential and House returns on election-day geography.

For president, compare MIT state counts with the Federal Election Commission
and divide the selected counts by each state's PUMS citizen-adult population.
For House, compare MIT district counts with the Clerk on the 2024 boundaries.

Run from the repository root. Use --returns-only for counts and source audits.
Decisions and outputs: 01_frame/docs/07_prepare_area_returns.md.
"""

import argparse
from collections import Counter, defaultdict
import csv
import math
import shutil
import subprocess
import sys
from importlib import import_module
from pathlib import Path
from tempfile import TemporaryDirectory

official = import_module("helpers.05_benchmark_official")
president = import_module("helpers.07_president_returns")
house = import_module("helpers.07_house_returns")
mit_sources = import_module("helpers.07_mit_sources")
mit_president = import_module("helpers.07_mit_president")
mit_house = import_module("helpers.07_mit_house")

# MIT minus FEC for Other after excluding Nevada's explicit None selection.
# These seven differences are documented for the two checksum-pinned editions.
PRESIDENT_OTHER_DIFFERENCES = {
    "AZ": -842, "DE": 1, "MT": -27, "NY": 105, "PA": -24526, "RI": -300, "WV": 2,
}
PARTY_VOTE_COLUMNS = {
    "Democratic": "votes_dem",
    "Republican": "votes_rep",
    "Other": "votes_other",
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--returns-only", action="store_true",
                        help="Write the observed returns and their source audits only")
    args = parser.parse_args()
    frame = Path("01_frame")
    state_fips = read_state_codes(frame / "docs" / "02_pl_2020_sources.csv")
    data = frame / "data"
    source = data / "input" / "05_vote_benchmark"
    intermediate = data / "intermediate"
    output = data / "output"
    state_audit = output / "03_pums_allocation_by_state.csv"
    if not args.returns_only and not state_audit.is_file():
        parser.error(f"Missing {state_audit}. Run Step 03 or use --returns-only for the election results.")
    for directory in (source, intermediate, output):
        directory.mkdir(parents=True, exist_ok=True)

    # Read the official FEC workbook and the Clerk's district-by-district report.
    xlsx = source / "fec2024.xlsx"
    pdf = source / "clerk2024.pdf"
    official.fetch(xlsx, official.FEC_URL, official.FEC_SHA256)
    official.fetch(pdf, official.CLERK_URL, official.CLERK_SHA256)
    report = subprocess.run(
        ["pdftotext", "-layout", str(pdf), "-"], check=True, capture_output=True, encoding="utf-8"
    ).stdout

    mit_pres_path, mit_house_path = mit_sources.obtain_mit_sources(data / "input")
    with TemporaryDirectory(dir=data) as temp:
        stage = Path(temp)
        # Each official reader writes its counts and a source-line audit here.
        # Replace the staged counts with our selected rows after both comparisons pass.
        president.write_president(xlsx, stage, state_fips)
        house.write_house(report, stage, state_fips)
        president_path = stage / "07_president_votes_2024.csv"
        house_path = stage / "07_house_votes_cd119.csv"

        presidential_lines = mit_president.classify_president(mit_pres_path)
        house_lines = mit_house.classify_house(mit_house_path)
        state_votes, president_comparison = reconcile_returns(
            presidential_lines, read_rows(president_path), "President"
        )
        district_votes, house_comparison = reconcile_returns(
            house_lines, read_rows(house_path), "House"
        )

        write_rows(president_path, state_votes)
        write_rows(house_path, district_votes)
        write_rows(stage / "07_mit_president_rows.csv", presidential_lines)
        write_rows(stage / "07_mit_house_rows.csv", house_lines)
        write_rows(stage / "07_vote_source_comparison.csv", president_comparison + house_comparison)

        products = {
            "07_president_votes_2024.csv": intermediate,
            "07_house_votes_cd119.csv": intermediate,
            "07_president_source_votes_2024.csv": output,
            "07_house_source_lines_cd119.csv": output,
            "07_mit_president_rows.csv": output,
            "07_mit_house_rows.csv": output,
            "07_vote_source_comparison.csv": output,
        }
        # The optional eighth file uses the Step 03 citizen-adult population.
        shares_file = "07_state_presidential_covariates_2024.csv"
        if not args.returns_only:
            cvap, total = write_covariates(president_path, state_audit, stage / shares_file)
            products[shares_file] = intermediate
        elif (intermediate / shares_file).exists():
            print(f"Run without --returns-only to refresh {shares_file} before analysis.", file=sys.stderr)
        publish(stage, products)
        for filename, directory in products.items():
            print(f"Saved {directory / filename}")
    if not args.returns_only:
        print(f"State PUMS CVAP: {cvap:,.2f}. Classified presidential votes: {total:,}. "
              f"Estimated without a presidential candidate vote: {cvap - total:,.2f}.")
    if (output / "07_turnout_audit.csv").exists():
        print("07_turnout_audit.csv is from the earlier election-wide turnout definition "
              "and is not an input or output of this calculation.", file=sys.stderr)


def tally_mit_votes(mit_rows):
    """Sum the classified rows within each state (President) or district (House)."""
    counts_by_area = defaultdict(Counter)
    unpolled = set()
    for row in mit_rows:
        area = (row["STATEFP"], row["district_2024"])
        counts = counts_by_area[area]  # Keep an entry even for an unpolled contest.
        category = row["category"]
        if category in PARTY_VOTE_COLUMNS:
            counts[category] += row["source_votes"]
        elif category == "Unresolved":
            unpolled.add(area)
        elif category != "Excluded":
            raise ValueError(f"Unexpected source classification: {row}")
    return counts_by_area, unpolled


def reconcile_returns(mit_rows, official_rows, office):
    """Return the selected counts and the side-by-side audit, in official file order."""
    mit_counts, mit_unpolled = tally_mit_votes(mit_rows)
    # Presidential rows have an empty district key. For House, use the original
    # 119th Congress district, including DC's delegate district 98.
    official_by_area = {(row["STATEFP"], row.get("CDFP119", "")): row for row in official_rows}
    if len(official_by_area) != len(official_rows) or official_by_area.keys() != mit_counts.keys():
        raise ValueError(f"MIT and the official {office} source disagree on geography")

    selected_rows = []
    comparison_rows = []
    presidential_other_deltas = {}
    for area, reported in official_by_area.items():
        counts = mit_counts[area]
        selected = reported.copy()
        audit = {
            "office": office, "STATEFP": area[0], "STUSAB": reported["STUSAB"], "CDFP119": area[1]
        }

        # FL-20 and OK-03 have winners but no counts. The MIT reader flags
        # its placeholder rows (1 vote, total -1). The Clerk must agree.
        official_unpolled = reported.get("status") == "unopposed_not_on_ballot"
        if area in mit_unpolled or official_unpolled:
            if office != "House" or area not in mit_unpolled or not official_unpolled or counts:
                raise ValueError(f"MIT and official source disagree on unpolled contest {area}")
            if any(reported[c] != "" for c in (*PARTY_VOTE_COLUMNS.values(), "total_votes")):
                raise ValueError(f"MIT and official source disagree on unpolled contest {area}")
            for column in PARTY_VOTE_COLUMNS.values():
                audit[f"mit_{column}"] = None
                audit[f"official_{column}"] = None
            status, source = "unopposed_not_on_ballot", "no_tabulation"
        else:
            if sum(counts.values()) <= 0:
                raise ValueError(f"No candidate votes for {office} {area}")

            other_delta = 0
            for party, column in PARTY_VOTE_COLUMNS.items():
                official_count = int(reported[column])
                audit[f"mit_{column}"] = counts[party]
                audit[f"official_{column}"] = official_count
                delta = counts[party] - official_count
                if delta:
                    if office != "President" or party != "Other":
                        raise ValueError(f"{office} {area} {party}: source difference {delta}")
                    other_delta = delta

            # Matching counts use MIT. A reviewed discrepancy in presidential
            # Other uses the whole FEC state row. Check the exact deltas below.
            if other_delta:
                presidential_other_deltas[reported["STUSAB"]] = other_delta
                status, source = "reviewed_other_difference", "FEC"
            else:
                for party, column in PARTY_VOTE_COLUMNS.items():
                    selected[column] = counts[party]
                status, source = "matched", "MIT"

            selected_total = sum(int(selected[column]) for column in PARTY_VOTE_COLUMNS.values())
            if selected_total != int(reported["total_votes"]):
                raise ValueError(f"Selected candidate totals do not reconcile for {office} {area}")

        selected["source_used"] = source
        selected_rows.append(selected)
        comparison_rows.append({**audit, "status": status, "source_used": source})

    if office == "President" and presidential_other_deltas != PRESIDENT_OTHER_DIFFERENCES:
        raise ValueError(f"Unreviewed presidential source discrepancies: {presidential_other_deltas}")
    return selected_rows, comparison_rows


def read_state_cvap(state_audit):
    """Step 03 records both the original person weights and their district allocations."""
    cvap_by_state = {}
    for row in read_rows(state_audit):
        state = row["STATEFP"]
        cvap = float(row["input_weight"])
        allocated = float(row["allocated_weight"])
        if (state in cvap_by_state or not math.isfinite(cvap) or cvap <= 0 or
                not math.isclose(cvap, allocated, rel_tol=1e-12)):
            raise ValueError(f"Invalid or unreconciled Step 03 population for state {state}")
        cvap_by_state[state] = cvap
    return cvap_by_state


def write_covariates(presidential, state_audit, destination):
    cvap_by_state = read_state_cvap(state_audit)
    votes = read_rows(presidential)
    if len(votes) != len(cvap_by_state) or set(cvap_by_state) != {row["STATEFP"] for row in votes}:
        raise ValueError("Step 03 and the presidential returns must cover the same states and DC")

    for row in votes:
        cvap = cvap_by_state[row["STATEFP"]]
        candidate_votes = int(row["total_votes"])
        # A voter who cast a House vote but left president blank is already
        # in this residual. Subtract only votes credited to presidential candidates.
        without_candidate_vote = cvap - candidate_votes
        if without_candidate_vote < 0:
            raise ValueError(f"{row['STUSAB']}: candidate votes exceed the Step 03 population")

        row["cvap"] = cvap
        row["did_not_vote_est"] = without_candidate_vote
        row["share_turnout"] = candidate_votes / cvap
        row["share_did_not_vote"] = without_candidate_vote / cvap
        row["share_dem"] = int(row["votes_dem"]) / cvap
        row["share_rep"] = int(row["votes_rep"]) / cvap
        row["share_other"] = int(row["votes_other"]) / cvap

        candidate_share = math.fsum((row["share_dem"], row["share_rep"], row["share_other"]))
        all_choices = candidate_share + row["share_did_not_vote"]
        if (not math.isclose(candidate_share, row["share_turnout"], abs_tol=1e-12) or
                not math.isclose(all_choices, 1, abs_tol=1e-12)):
            raise ValueError(f"{row['STUSAB']}: presidential shares do not reconcile")
    write_rows(destination, votes)
    return math.fsum(cvap_by_state.values()), sum(int(row["total_votes"]) for row in votes)


def read_state_codes(manifest_path):
    manifest = read_rows(manifest_path)
    state_fips = {row["STUSAB"]: row["STATEFP"] for row in manifest}
    expected_states = set(official.STATES.values()) | {"DC"}
    if (len(manifest) != 51 or set(state_fips) != expected_states or
            len(set(state_fips.values())) != 51 or state_fips["DC"] != "11" or
            not all(len(code) == 2 and code.isdigit() for code in state_fips.values())):
        raise ValueError("Invalid state keys in the Census manifest")
    return state_fips


def read_rows(path):
    with path.open(encoding="utf-8", newline="") as stream:
        return list(csv.DictReader(stream))


def write_rows(path, rows):
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def publish(stage, products):
    # All files are small. Preserve earlier products if a later rename fails.
    backups = stage / "previous"
    backups.mkdir()
    for filename, directory in products.items():
        destination = directory / filename
        if not (stage / filename).is_file() or (destination.exists() and not destination.is_file()):
            raise ValueError(f"Cannot publish {destination}")
        if destination.exists():
            shutil.copy2(destination, backups / filename)
    published = []
    try:
        for filename, directory in products.items():
            destination = directory / filename
            (stage / filename).replace(destination)
            published.append(destination)
    except OSError:
        for destination in reversed(published):
            backup = backups / destination.name
            if backup.exists():
                backup.replace(destination)
            else:
                destination.unlink()
        raise


if __name__ == "__main__":
    main()
