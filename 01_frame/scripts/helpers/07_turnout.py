"""Build state general-election turnout with a traceable source for each count."""
import csv
import io
import zipfile
from importlib import import_module
from urllib.request import Request

fetch = import_module("helpers.05_benchmark_official").fetch

EAVS_URL = ("https://www.eac.gov/sites/default/files/2026-02/"
            "2024_EAVS_for_Public_Release_nolabel_V2_csv.zip")
EAVS_SHA = "4073b9f48e1791d44a78ddc543379f6c040c31ce733dfa47676330b4d7f6d6df"
UF_URL = "https://election.lab.ufl.edu/data-downloads/turnoutdata/Turnout_2024G_v0.4.csv"
UF_SHA = "9796cf57eda46924c7e5a4b26c2503dcafc8662d5d14a066dfe25a0fce7e85d9"
EAVS_MEMBER = "2024_EAVS_for_Public_Release_nolabel_V2.csv"


def eavs_state_counts(archive, state_fips):
    """Return reporting units, units with unavailable F1a, and reported F1a subtotal."""
    # The EAC publishes one record per administering jurisdiction. A state can report
    # at the state, county, or municipal level; the Maine UOCAVA row is a separate unit.
    # Use the postal code field. Wisconsin's local IDs omit state FIPS and two
    # California IDs omit their leading zero in the original CSV.
    seen = set()
    statewide = set()
    totals = {state: [0, 0, 0] for state in state_fips}
    territories = {"AS", "GU", "MP", "PR", "VI"}
    with zipfile.ZipFile(archive) as source:
        if source.namelist().count(EAVS_MEMBER) != 1:
            raise ValueError("Expected the 2024 EAVS v2 jurisdiction CSV exactly once.")
        with source.open(EAVS_MEMBER) as raw, io.TextIOWrapper(raw, encoding="utf-8-sig", newline="") as stream:
            reader = csv.DictReader(stream)
            required = {"State_Abbr", "FIPSCode", "Jurisdiction_Name", "F1a"}
            if not required.issubset(reader.fieldnames or []):
                raise ValueError("EAVS v2 jurisdiction and turnout columns are missing.")
            for row in reader:
                state = row["State_Abbr"]
                if state in territories:
                    continue
                if state not in totals:
                    raise ValueError(f"Unrecognized EAVS jurisdiction state {state!r}.")
                unit = row["FIPSCode"]
                if not unit.isascii() or not unit.isdigit() or not row["Jurisdiction_Name"].strip():
                    raise ValueError(f"Missing or invalid EAVS jurisdiction identifier in {state}.")
                key = (state, unit)
                if key in seen:
                    raise ValueError(f"Duplicate EAVS jurisdiction {key}.")
                seen.add(key)
                if unit == state_fips[state] + "00000000":
                    statewide.add(state)
                counts = totals[state]
                counts[0] += 1
                value = row["F1a"].strip()
                # EAVS nonresponse conventions: unavailable/does not apply/skipped,
                # plus blank responses. A literal zero is a reported count.
                if value in {"", "-99", "-88", "-77"}:
                    counts[1] += 1
                elif value.isascii() and value.isdigit():
                    counts[2] += int(value)
                else:
                    raise ValueError(f"Unexpected EAVS F1a value {value!r} for {key}.")
    for state, (units, _, _) in totals.items():
        if units == 0 or (state in statewide and units > 1):
            raise ValueError(f"Absent or overlapping statewide/local EAVS coverage for {state}.")
    return {state: tuple(counts) for state, counts in totals.items()}


def read_turnout(input_dir, state_fips, docs):
    """Use F1a, with state-level source decisions recorded in 07_turnout_sources.csv."""
    cache = input_dir / "07_turnout"
    cache.mkdir(parents=True, exist_ok=True)
    eavs_file = cache / "eavs2024_v2.zip"
    uf_file = cache / "Turnout_2024G_v0.4.csv"
    fetch(eavs_file, Request(EAVS_URL, headers={"User-Agent": "polling-without-people/1.0"}), EAVS_SHA)
    fetch(uf_file, UF_URL, UF_SHA)
    eavs = eavs_state_counts(eavs_file, state_fips)

    uf = {}
    with uf_file.open(encoding="utf-8-sig", newline="") as stream:
        for row in csv.DictReader(stream):
            state = row["STATE_ABV"]
            if state == "US":
                continue
            ballots = int(row["TOTAL_BALLOTS_COUNTED"])
            if ballots <= 0 or state in uf or state not in state_fips:
                raise ValueError(f"Unexpected University of Florida turnout record for {state!r}.")
            uf[state] = ballots
    if uf.keys() != state_fips.keys():
        raise ValueError("UF turnout must cover all states and DC.")

    decisions = {}
    with (docs / "07_turnout_sources.csv").open(encoding="utf-8", newline="") as stream:
        for row in csv.DictReader(stream):
            state = row["STUSAB"]
            if state in decisions or state not in state_fips:
                raise ValueError(f"Unexpected turnout decision for {state!r}.")
            if (row["source"] not in {"state_election_office", "uf_reported", "uf_estimated",
                                      "state_compilation_estimated", "eavs_f1a", "unresolved"}
                    or not row["source_url"].startswith("https://") or not row["locator"].strip()):
                raise ValueError(f"Missing or invalid turnout provenance for {state}.")
            decisions[state] = row

    states = {}
    for state, (units, unreported, reported) in eavs.items():
        counted, source, url, detail = reported, "eavs_f1a", EAVS_URL, "F1a subtotal."
        if state in decisions:
            row = decisions[state]
            source, url, detail = row["source"], row["source_url"], row["locator"]
            if source == "unresolved":
                if row["counted_turnout"]:
                    raise ValueError(f"{state}: unresolved turnout should have no selected value.")
                counted = None
            else:
                counted = int(row["counted_turnout"])
            if source.startswith("uf_") and counted != uf[state]:
                raise ValueError(f"{state}: decision disagrees with the pinned UF ballots column.")
            if source == "eavs_f1a" and counted != reported:
                raise ValueError(f"{state}: decision disagrees with the pinned EAVS F1a count.")
        elif unreported or abs(uf[state] - reported) >= 10_000:
            # A review threshold for these two published series, recorded in the Step 07 guide.
            raise ValueError(f"{state}: incomplete coverage or a turnout discrepancy requires review.")
        if counted is not None and counted <= 0:
            raise ValueError(f"{state}: no positive turnout count.")
        states[state] = dict(
            counted_turnout=counted, turnout_source=source,
            turnout_is_estimate=(None if counted is None else source in {"uf_estimated", "state_compilation_estimated"}), turnout_source_url=url,
            turnout_source_detail=detail, eavs_jurisdictions=units, eavs_unreported=unreported,
            eavs_reported_voters=reported, uf_ballots=uf[state],
            eavs_minus_selected=None if counted is None else reported - counted,
            uf_minus_selected=None if counted is None else uf[state] - counted,
        )
    return states
