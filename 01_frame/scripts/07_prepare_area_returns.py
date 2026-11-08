"""Prepare 2024 presidential and House returns on election-day geography.

Run from the repository root. See 01_frame/docs/07_prepare_area_returns.md.
Use --returns-only to prepare the source counts without a local PUMS audit.
"""

import argparse
import csv
import math
import shutil
import subprocess
from importlib import import_module
from pathlib import Path
from tempfile import TemporaryDirectory

official = import_module("helpers.05_benchmark_official")
president = import_module("helpers.07_president_returns")
house = import_module("helpers.07_house_returns")


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


def write_covariates(presidential, state_audit, destination):
    states = {}
    state_rows = read_rows(state_audit)
    if not state_rows or not {"STATEFP", "input_weight", "allocated_weight"} <= state_rows[0].keys():
        raise ValueError(f"Step 03 audit is empty or missing required columns: {state_audit}")
    for row in state_rows:
        state = row["STATEFP"]
        cvap = float(row["input_weight"])
        allocated = float(row["allocated_weight"])
        if (state in states or not math.isfinite(cvap) or cvap <= 0 or
                not math.isclose(cvap, allocated, rel_tol=1e-12)):
            raise ValueError(f"Invalid or unreconciled Step 03 population for state {state}")
        states[state] = cvap

    votes = read_rows(presidential)
    if set(states) != {row["STATEFP"] for row in votes}:
        raise ValueError("Step 03 and the FEC presidential returns cover different states")

    columns = [f"votes_{party}" for party in president.PARTIES]
    shares = [f"share_{party}" for party in president.PARTIES]
    fields = ["STATEFP", "STUSAB", "cvap", *columns, "total_votes", "did_not_vote_est",
              *shares, "share_did_not_vote"]
    with destination.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        for row in votes:
            cvap = states[row["STATEFP"]]
            residual = cvap - int(row["total_votes"])
            if residual < 0:
                raise ValueError(f"{row['STUSAB']}: valid presidential votes exceed Step 03 CVAP")
            row.update(cvap=cvap, did_not_vote_est=residual, share_did_not_vote=residual / cvap)
            for column, share in zip(columns, shares):
                row[share] = int(row[column]) / cvap
            if not math.isclose(sum(row[key] for key in shares) + row["share_did_not_vote"],
                                1, rel_tol=1e-12):
                raise ValueError(f"{row['STUSAB']}: presidential shares do not sum to one")
            writer.writerow({field: row[field] for field in fields})
    return sum(states.values()), sum(int(row["total_votes"]) for row in votes)


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

    with TemporaryDirectory(dir=data) as temp:
        stage = Path(temp)
        president.write_president(xlsx, stage, state_fips)
        house.write_house(report, stage, state_fips)
        products = {
            "07_president_votes_2024.csv": intermediate,
            "07_house_votes_cd119.csv": intermediate,
            "07_president_source_votes_2024.csv": output,
            "07_house_source_lines_cd119.csv": output,
        }
        if not args.returns_only:
            name = "07_state_presidential_covariates_2024.csv"
            cvap, valid_votes = write_covariates(stage / "07_president_votes_2024.csv", state_audit, stage / name)
            products[name] = intermediate
        publish(stage, products)
        for filename, directory in products.items():
            print(f"Saved {directory / filename}")
    if not args.returns_only:
        print(f"State CVAP summed nationwide: {cvap:,.2f}. "
              f"Estimated Did not vote: {cvap - valid_votes:,.2f}.")


if __name__ == "__main__":
    main()
