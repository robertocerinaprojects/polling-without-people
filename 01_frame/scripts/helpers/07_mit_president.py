"""Read and classify the 2024 state-level MIT presidential returns for audit."""

import csv
import hashlib
import io
from pathlib import Path


# Harvard Dataverse, MIT U.S. President 1976–2024, v10.1, original CSV.
# https://dataverse.harvard.edu/api/access/datafile/13887042?format=original
# A new source revision requires reviewing candidate and accounting labels again.
SOURCE_SHA256 = "9936410a6dd4ecc8be7fe202c6dff5b5f8fee59d88f35ab542ed12879941dcb7"

# The FEC report names the two major-party nominees. Match the entire name:
# the archive also contains a separate write-in for Sharon E Harris.
# https://www.fec.gov/resources/cms-content/documents/2024presgeresults.pdf
NOMINEES = {"HARRIS, KAMALA D.": "Democratic", "TRUMP, DONALD J.": "Republican"}
POOLED_CHOICES = {"WRITE-IN", "SCATTERING"}
EXCLUDED = {
    "NONE OF THESE CANDIDATES": "explicit_none",
    "UNDERVOTES": "no_selection",
    "OVERVOTES": "too_many_selections",
    "SPOILED": "ballot_accounting",
    "VOID": "ballot_accounting",
}


def classify_presidential_choice(name, writein):
    """Return the office-specific vote category and its audit reason."""
    if name in NOMINEES:
        reason = "named_nominee_writein" if writein else "named_nominee"
        return NOMINEES[name], reason
    if name in EXCLUDED:
        return "Excluded", EXCLUDED[name]
    if name in POOLED_CHOICES:
        return "Other", "pooled_choices"

    # The remaining labels in the pinned CSV are named candidates or tickets.
    # The party on a write-in alone cannot identify Harris or Trump.
    reason = "other_named_writein" if writein else "other_named_candidate"
    return "Other", reason


def classify_president(path):
    """Return one audit row per published 2024 candidate or accounting tally."""
    data = Path(path).read_bytes()
    if hashlib.sha256(data).hexdigest() != SOURCE_SHA256:
        raise ValueError("The MIT presidential release differs from the reviewed v10.1 original CSV")

    result = []
    with io.StringIO(data.decode("utf-8-sig"), newline="") as stream:
        for row in csv.DictReader(stream):
            if row["year"] != "2024":
                continue
            name = row["candidate"]
            writein = row["writein"] == "True"
            category, reason = classify_presidential_choice(name, writein)

            result.append({
                "STATEFP": row["state_fips"].zfill(2),
                "STUSAB": row["state_po"],
                "district_2024": "",
                "source_candidate": name,
                "source_party": row["party_detailed"],
                "source_party_simplified": row["party_simplified"],
                "source_writein": writein,
                "source_votes": int(row["candidatevotes"]),
                "source_totalvotes": int(row["totalvotes"]),
                "category": category,
                "reason": reason,
            })
    return result
