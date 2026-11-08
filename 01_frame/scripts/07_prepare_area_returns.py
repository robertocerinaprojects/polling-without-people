"""Prepare 2024 presidential and House returns on election-day geography.

Run from the repository root. See 01_frame/docs/07_prepare_area_returns.md.
Use --returns-only to prepare the source counts without a local PUMS audit.
"""

import argparse
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
turnout = import_module("helpers.07_turnout")
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
    if len(votes) != len(states) or set(states) != {row["STATEFP"] for row in votes}:
        raise ValueError("Step 03 and the state returns must have exactly one row for every state and DC")

    fields = [*president.STATE_FIELDS, "cvap", "did_not_vote_est",
              "share_dem", "share_rep", "share_other", "share_did_not_vote"]
    with destination.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        for row in votes:
            cvap = states[row["STATEFP"]]
            dem, rep = int(row["votes_dem"]), int(row["votes_rep"])
            if int(row["valid_presidential_votes"]) > cvap:
                raise ValueError(f"{row['STUSAB']}: valid presidential votes exceed Step 03 CVAP")
            row.update(cvap=cvap, share_dem=dem / cvap, share_rep=rep / cvap)
            if row["turnout_source"] == "unresolved":
                if any(row[key] for key in ("counted_turnout", "voters_other",
                                            "turnout_without_valid_presidential_vote", "turnout_is_estimate")):
                    raise ValueError(f"{row['STUSAB']}: unresolved turnout with nonempty dependent fields")
                writer.writerow(row)
                continue
            counted = int(row["counted_turnout"])
            residual = cvap - counted
            if residual < 0:
                raise ValueError(f"{row['STUSAB']}: general-election turnout exceeds Step 03 CVAP")
            other = int(row["voters_other"])
            if min(dem, rep, other) < 0 or dem + rep + other != counted:
                raise ValueError(f"{row['STUSAB']}: turnout categories do not reconcile")
            row.update(did_not_vote_est=residual, share_other=other / cvap, share_did_not_vote=residual / cvap)
            if not math.isclose(math.fsum((row["share_dem"], row["share_rep"], row["share_other"],
                                           row["share_did_not_vote"])), 1, rel_tol=1e-12):
                raise ValueError(f"{row['STUSAB']}: four CVAP shares do not sum to one")
            writer.writerow(row)
    national_turnout = None
    if all(row["counted_turnout"] for row in votes):
        national_turnout = sum(int(row["counted_turnout"]) for row in votes)
    return sum(states.values()), national_turnout


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
        turnout_by_state = turnout.read_turnout(data / "input", state_fips, frame / "docs")
        president.write_president(xlsx, stage, state_fips, turnout_by_state)
        house.write_house(report, stage, state_fips)
        products = {
            "07_president_votes_2024.csv": intermediate,
            "07_house_votes_cd119.csv": intermediate,
            "07_president_source_votes_2024.csv": output,
            "07_turnout_audit.csv": output,
            "07_house_source_lines_cd119.csv": output,
        }
        name = "07_state_presidential_covariates_2024.csv"
        if not args.returns_only:
            cvap, counted = write_covariates(stage / "07_president_votes_2024.csv", state_audit, stage / name)
            products[name] = intermediate
        elif (intermediate / name).is_file():
            print(f"The existing {intermediate / name} is outside this returns-only run. "
                  "Run Step 07 without --returns-only to refresh it before analysis.", file=sys.stderr)
        publish(stage, products)
        for filename, directory in products.items():
            print(f"Saved {directory / filename}")
    if not args.returns_only:
        print(f"State CVAP summed nationwide: {cvap:,.2f}.")
        if counted is not None:
            print(f"Counted turnout: {counted:,}. Estimated Did not vote: {cvap - counted:,.2f}.")
    unresolved = sorted(st for st, row in turnout_by_state.items() if row["turnout_source"] == "unresolved")
    if unresolved:
        print(f"Statewide turnout unresolved for {', '.join(unresolved)}. National turnout and "
              "Did not vote totals are unavailable.")


if __name__ == "__main__":
    main()
