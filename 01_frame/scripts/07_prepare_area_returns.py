"""Prepare 2024 presidential and House returns on election-day geography.

Run from the repository root. See 01_frame/docs/07_prepare_area_returns.md.
Use --returns-only to prepare the source counts without a local PUMS audit.
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
PRESIDENT_OTHER_DIFFERENCES = {"AZ": -842, "DE": 1, "MT": -27, "NY": 105,
                               "PA": -24526, "RI": -300, "WV": 2}
VOTE_COLUMNS = ("votes_dem", "votes_rep", "votes_other")


def read_rows(path):
    with path.open(encoding="utf-8", newline="") as stream:
        return list(csv.DictReader(stream))


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


def write_rows(path, rows):
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def reconcile_returns(mit_rows, official_path, office, comparison):
    # The official helper has already checked its source totals. Keep MIT's
    # original records, including administrative entries and unpolled indicators.
    groups = defaultdict(Counter)
    unobserved = set()
    for row in mit_rows:
        key = (row["STATEFP"], row["district_2024"])
        tally = groups[key]
        category = row["category"]
        if category == "Unresolved":
            unobserved.add(key)
        elif category in official.PARTIES:
            tally[category] += row["source_votes"]
        elif category != "Excluded":
            raise ValueError(f"Unexpected source classification: {row}")

    rows = read_rows(official_path)
    keys = [(row["STATEFP"], row.get("CDFP119", "")) for row in rows]
    if len(keys) != len(set(keys)) or set(keys) != groups.keys():
        raise ValueError(f"MIT and the official {office} source disagree on geography")
    differences = {}
    for row, key in zip(rows, keys):
        counts = groups[key]
        check = {"office": office, "STATEFP": key[0], "STUSAB": row["STUSAB"],
                 "CDFP119": key[1]}
        if key in unobserved or row.get("status") == "unopposed_not_on_ballot":
            if (office != "House" or key not in unobserved or counts or
                    row.get("status") != "unopposed_not_on_ballot" or
                    any(row[column] != "" for column in (*VOTE_COLUMNS, "total_votes"))):
                raise ValueError(f"MIT and official source disagree on unpolled contest {key}")
            status, source = "unopposed_not_on_ballot", "no_tabulation"
            for column in VOTE_COLUMNS:
                check[f"mit_{column}"] = check[f"official_{column}"] = None
        else:
            if sum(counts.values()) <= 0:
                raise ValueError(f"No candidate votes for {office} {key}")
            status, source = "matched", "MIT"
            for party, column in zip(official.PARTIES, VOTE_COLUMNS):
                reported = int(row[column])
                check[f"mit_{column}"] = counts[party]
                check[f"official_{column}"] = reported
                delta = counts[party] - reported
                if delta:
                    if office != "President" or party != "Other":
                        raise ValueError(f"{office} {key} {party}: source difference {delta}")
                    differences[row["STUSAB"]] = delta
                    status, source = "reviewed_other_difference", "FEC"
            if source == "MIT":
                for party, column in zip(official.PARTIES, VOTE_COLUMNS):
                    row[column] = counts[party]
            if sum(int(row[c]) for c in VOTE_COLUMNS) != int(row["total_votes"]):
                raise ValueError(f"Selected candidate totals do not reconcile for {office} {key}")
        row["source_used"] = source
        comparison.append({**check, "status": status, "source_used": source})
    if office == "President" and differences != PRESIDENT_OTHER_DIFFERENCES:
        raise ValueError(f"Unreviewed presidential source discrepancies: {differences}")
    write_rows(official_path, rows)


def write_covariates(presidential, state_audit, destination):
    states = {}
    for row in read_rows(state_audit):
        state = row["STATEFP"]
        cvap = float(row["input_weight"])
        allocated = float(row["allocated_weight"])
        if (state in states or not math.isfinite(cvap) or cvap <= 0 or
                not math.isclose(cvap, allocated, rel_tol=1e-12)):
            raise ValueError(f"Invalid or unreconciled Step 03 population for state {state}")
        states[state] = cvap

    votes = read_rows(presidential)
    if len(votes) != len(states) or set(states) != {row["STATEFP"] for row in votes}:
        raise ValueError("Step 03 and the presidential returns must cover the same states and DC")
    for row in votes:
        cvap = states[row["STATEFP"]]
        total = int(row["total_votes"])
        residual = cvap - total
        if residual < 0:
            raise ValueError(f"{row['STUSAB']}: candidate votes exceed the Step 03 population")
        row.update(cvap=cvap, did_not_vote_est=residual, share_turnout=total / cvap,
                   share_did_not_vote=residual / cvap)
        for party, column in zip(president.PARTIES, VOTE_COLUMNS):
            row[f"share_{party}"] = int(row[column]) / cvap
        party_share = math.fsum(row[f"share_{party}"] for party in president.PARTIES)
        if not (math.isclose(party_share, row["share_turnout"], abs_tol=1e-12) and
                math.isclose(party_share + row["share_did_not_vote"], 1, abs_tol=1e-12)):
            raise ValueError(f"{row['STUSAB']}: presidential shares do not reconcile")
    write_rows(destination, votes)
    return math.fsum(states.values()), sum(int(row["total_votes"]) for row in votes)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--returns-only", action="store_true",
                        help="Write the observed returns and their source audits only")
    args = parser.parse_args()
    frame = Path("01_frame")
    manifest = read_rows(frame / "docs" / "02_pl_2020_sources.csv")
    state_fips = {row["STUSAB"]: row["STATEFP"] for row in manifest}
    if (len(manifest) != 51 or set(state_fips) != set(official.STATES.values()) | {"DC"} or
            len(set(state_fips.values())) != 51 or state_fips["DC"] != "11" or
            not all(len(code) == 2 and code.isdigit() for code in state_fips.values())):
        raise ValueError("Invalid state keys in the Census manifest")

    data = frame / "data"
    source = data / "input" / "05_vote_benchmark"
    intermediate = data / "intermediate"
    output = data / "output"
    state_audit = output / "03_pums_allocation_by_state.csv"
    if not args.returns_only and not state_audit.is_file():
        parser.error(f"Missing {state_audit}. Run Step 03 or use --returns-only for the election results.")
    for directory in (source, intermediate, output):
        directory.mkdir(parents=True, exist_ok=True)
    xlsx, pdf = source / "fec2024.xlsx", source / "clerk2024.pdf"
    official.fetch(xlsx, official.FEC_URL, official.FEC_SHA256)
    official.fetch(pdf, official.CLERK_URL, official.CLERK_SHA256)
    report = subprocess.run(["pdftotext", "-layout", str(pdf), "-"],
                            check=True, capture_output=True, encoding="utf-8").stdout

    pres_path, house_path = mit_sources.obtain_mit_sources(data / "input")
    with TemporaryDirectory(dir=data) as temp:
        stage = Path(temp)
        comparison = []
        president.write_president(xlsx, stage, state_fips)
        house.write_house(report, stage, state_fips)
        for office, records, audit, totals in (
            ("President", mit_president.classify_president(pres_path),
             "07_mit_president_rows.csv", "07_president_votes_2024.csv"),
            ("House", mit_house.classify_house(house_path),
             "07_mit_house_rows.csv", "07_house_votes_cd119.csv"),
        ):
            write_rows(stage / audit, records)
            reconcile_returns(records, stage / totals, office, comparison)
        write_rows(stage / "07_vote_source_comparison.csv", comparison)
        products = {
            "07_president_votes_2024.csv": intermediate,
            "07_house_votes_cd119.csv": intermediate,
            "07_president_source_votes_2024.csv": output,
            "07_house_source_lines_cd119.csv": output,
            "07_mit_president_rows.csv": output,
            "07_mit_house_rows.csv": output,
            "07_vote_source_comparison.csv": output,
        }
        name = "07_state_presidential_covariates_2024.csv"
        if not args.returns_only:
            cvap, total = write_covariates(stage / "07_president_votes_2024.csv", state_audit, stage / name)
            products[name] = intermediate
        elif (intermediate / name).exists():
            print(f"Run without --returns-only to refresh {name} before analysis.", file=sys.stderr)
        publish(stage, products)
        for filename, directory in products.items():
            print(f"Saved {directory / filename}")
    if not args.returns_only:
        print(f"State PUMS CVAP: {cvap:,.2f}. Classified presidential votes: {total:,}. "
              f"Estimated without a presidential candidate vote: {cvap - total:,.2f}.")
    if (output / "07_turnout_audit.csv").exists():
        print("07_turnout_audit.csv is from the earlier election-wide turnout definition "
              "and is not an input or output of this calculation.", file=sys.stderr)


if __name__ == "__main__":
    main()
