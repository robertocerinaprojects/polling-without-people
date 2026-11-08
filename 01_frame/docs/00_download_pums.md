# 00 — Download PUMS from IPUMS USA

## Plain-language summary

We request the full 2020–2024 ACS five-year person sample and the 24 variables
needed for population preparation. IPUMS USA builds the extract and provides
a compressed CSV with an XML codebook describing its variables and labels.

We keep each download as a source snapshot with its request and a receipt.
An ordinary rerun checks the saved files and reuses them without contacting
IPUMS. An incomplete download resumes the saved request. Running with
`--refresh` requests a separate snapshot and preserves existing snapshots.

Script 01 reads the selected snapshot, verifies its receipt, and checks its
data and variable metadata against the project's tracked source manifest.
It then prepares the citizen-adult population. The download step itself
only acquires and validates the source files.

## Status and execution

Status: validated. Acquisition, the 24-column checks and offline reuse passed.
The complete Script 00 → Script 01 run also passed and saved the cleaned
person file and preparation audits.

Run from the repository root:

```bash
Rscript 01_frame/scripts/00_download_pums.R
```

To request a separate snapshot:

```bash
Rscript 01_frame/scripts/00_download_pums.R --refresh
```

Use the ordinary command to resume a pending request. Refresh selects a new
attempt, which subsequent ordinary runs resume or reuse. Extract numbers
and returned filenames are specific to the IPUMS account.

A registered IPUMS USA account and the `IPUMS_API_KEY` Codespaces secret are
required for requests and downloads. Complete local snapshots can be reused
offline without the key. The script reads the key from the environment and
does not save it. R packages come from the project lockfile; `gzip` must be
available for the compressed-file integrity check.

## Extraction specification

| Setting | Value |
|---|---|
| Provider | IPUMS USA, which harmonizes Census ACS microdata |
| Collection | `usa` |
| Sample | `us2024c`: 2020–2024 ACS five-year sample |
| Format | Compressed CSV with a separate XML DDI codebook |
| Layout | Rectangular on persons (`P`); household fields attached to each person row |
| Population selection | All persons; no age, citizenship or state case selection |
| Additional transformations | No requested monetary adjustment, attached characteristics or data-quality flags |
| Downloaded variables | The 24 columns below |

```text
YEAR, MULTYEAR, SAMPLE, SERIAL, CBSERIAL, HHWT, CLUSTER, STATEFIP,
PUMA, CPUMA1020, STRATA, GQ, HHINCOME, PERNUM, PERWT, SEX, AGE,
RACE, RACED, HISPAN, HISPAND, CITIZEN, EDUC, EDUCD
```

The API sample identifier `us2024c` corresponds to numeric `SAMPLE = 202403`
in the microdata. The extraction definition is specified in Script 00.
Its API checks cover sample, fields, layout and selection settings.

### API names and downloaded columns

The API definition check requires 21 base variable names. Three of those
base names also supply detailed columns in the downloaded data:

| API base name | Required downloaded columns |
|---|---|
| EDUC | EDUC and EDUCD |
| HISPAN | HISPAN and HISPAND |
| RACE | RACE and RACED |

The API check permits these three detailed names as additional definition
entries. The downloaded CSV and DDI must contain all 24 expected columns.
Administrative annotations, such as automatic preselection, do not change
this field requirement.

IPUMS describes general/detailed versions in its
[USA FAQ](https://usa.ipums.org/usa-action/faq) and
[variable-selection explanation](https://forum.ipums.org/t/absence-of-detailed-version-of-variables/2870).

## Stored inputs, outputs and consumers

Paths below are relative to `01_frame/data/input/ipums_pums/`. A snapshot
directory uses UTC creation time and process number. Returned source
filenames are preserved.

| File | Producer and use |
|---|---|
| `current_snapshot.txt` | Script 00 selects the attempt to reuse or resume. Script 01 resolves its source files through this pointer. |
| `<snapshot>/request.json` | Complete requested specification. Script 00 checks it against its settings; Script 01 verifies its fingerprint against the receipt. |
| `<snapshot>/submission_started.txt` | Marks submission to prevent an automatic duplicate request if the response is lost. |
| `<snapshot>/extract_number.txt` | Account-specific extract number used to resume the request. |
| `<snapshot>/submitted_extract.rds` | API submission response, retained for provenance and recovery. |
| `<snapshot>/returned_definition.json` | Provider's returned settings, checked before downloading. |
| `<snapshot>/download_metadata.rds` | Completed API response with source download metadata. |
| `<snapshot>/files/<returned name>.xml` | Codebook validated by Script 00 and read by Script 01 for variable metadata and import. |
| `<snapshot>/files/<returned compressed data name>` | Person CSV checked by Script 00 and read by Script 01. |
| `<snapshot>/download_manifest.csv` | Receipt used by both scripts to verify source files. |
| `<snapshot>/download_in_progress/` | Temporary staging before checked files are moved into `files/`. |

The receipt has one row for the codebook and one for the microdata, with
columns `role, file, bytes, sha256, extract_number, sample, request_sha256,
downloaded_utc, provider_size_checked, provider_sha256_checked`.
The final two columns record whether supplied provider checks were verified.

Source files, receipts and account-specific state are ignored by Git.
The scripts, this document and `01_frame/docs/00_pums_source.json` are tracked.
That source manifest specifies which data and variable metadata Script 01
accepts for analysis.

## Checks, reuse and recovery

- Only one IPUMS acquisition or recovery can run in a cache at a time. The
  writer creates `.download-lock/` under `data/input/ipums_pums/` and records
  its host and process ID in `owner.txt`. An ordinary exit releases the lock.
  After a forced shutdown, verify the writer has stopped on that host before
  removing this lock directory and resuming Script 00. Preserve the snapshot
  and its submission marker so that a pending request can be recovered.
- A completed receipt is checked before any API call. Both files must match
  its byte counts and SHA-256 hashes. A mismatch stops for inspection.
- If a receipted file is absent, the script attempts to recover the same
  saved extract. Staged downloads are verified before missing files are
  restored; verified surviving files are preserved.
- Pending requests are checked at intervals of at most 30 seconds for up to
  30 minutes. A timeout preserves the extract number for an ordinary rerun.
- If an expired extract is no longer downloadable, use `--refresh` to request
  a separate snapshot. Failed or canceled requests stop for review.
- If submission started but no extract number was saved, inspect the account's
  extract history and verify the request before recording its number in
  `extract_number.txt`. The request may have been accepted even if its
  response did not reach the script.
- Downloads must be nonempty, match provider checks when supplied, pass
  `gzip -t`, parse as an IPUMS DDI, and contain the required 24 variables in
  both CSV and codebook. The script writes the receipt after these checks.

## Source approval

The tracked [source manifest](00_pums_source.json) specifies the compressed
CSV size and SHA-256 fingerprint, the required columns, and the fingerprint
of the complete parsed variable metadata. It also records source provenance
and the codebook used in the validated run.

The approved compressed CSV has **249,052,624 bytes** and SHA-256:

```text
adb92df6553053b846773de170852e4d1b7b557d6d6aaf9827e9a37111f70a04
```

The approved variable-metadata SHA-256 is:

```text
c5216653fec547730c0edd2a5381cb10b1bbda82cbe0371a2b594c806223d65a
```

Its named method, `ipums_var_info_json_v1`, hashes the UTF-8 string produced by:

```r
jsonlite::toJSON(
  ipumsr::ipums_var_info(ddi),
  dataframe = "rows", auto_unbox = TRUE,
  na = "null", null = "null", digits = NA, pretty = FALSE
)
```

SHA-256 is calculated with `serialize = FALSE` in the recorded R environment.
This fingerprint covers variable definitions and labels. Account-specific
XML content outside the variable table is verified through each snapshot's
own receipt.

The codebook used in the validated run has **121,139 bytes** and SHA-256:

```text
b2fc88a18873bf3ab85d7930cde8f3d9d452b56e3d62743c1e9019592cc75c2c
```

This identifies that codebook snapshot. XML files with different account or
extract metadata can be accepted when their own receipt checks pass and
their parsed variable metadata match the approved fingerprint.

Script 01 checks the selected snapshot, saved request, receipt and source
manifest before preparation. A changed data or variable-metadata fingerprint
stops the run for review. `--refresh` requests new files; it does not change
the approved source specification.

See [Script 01](01_prepare_pums.md#validated-results) for the completed
preparation results and the [data catalogue](data_catalogue.md) for lineage.

## Sources

- [Official sample identifiers](https://usa.ipums.org/usa-action/samples/sample_ids).
- [Define a microdata extract](https://tech.popdata.org/ipumsr/reference/define_extract_micro.html).
- [Submit an extract](https://tech.popdata.org/ipumsr/reference/submit_extract.html).
- [Retrieve extract state](https://tech.popdata.org/ipumsr/reference/get_extract_info.html).
- [Wait for completion and download expiry](https://tech.popdata.org/ipumsr/reference/wait_for_extract.html).
- [Download data and codebook](https://tech.popdata.org/ipumsr/reference/download_extract.html).
- [Save a reusable definition](https://tech.popdata.org/ipumsr/reference/save_extract_as_json.html).

IPUMS access and citation conditions apply to the acquired data.
