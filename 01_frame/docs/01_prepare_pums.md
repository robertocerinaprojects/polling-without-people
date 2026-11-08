# 01 — Prepare PUMS

## Plain-language summary

We start with individual records downloaded from IPUMS USA by Script 00 for
the 2020–2024 ACS five-year sample. We check the source files and their
variable definitions against the project's approved source manifest.
We then retain citizens aged 18 and over, including people in institutions
and other group quarters, and keep the District of Columbia.

We preserve the source columns and person weights. We add readable demographic
labels and handle special codes explicitly, so an unknown value is not
treated as a substantive category. Unavailable household income stays missing;
zero and negative incomes are retained. Ages and population weights describe
the source observations and are not projected to 2026.

We check records and weighted population at each filtering step, validate
person identifiers and recoding, and save the cleaned person file with
its audit tables. Each person's available location is their PUMA.
District assignment is a subsequent step.

## Status and execution

Status: validated. The full Script 00 → Script 01 run passed the source,
filtering, recoding and final dataset checks and saved the outputs below.

Run from the repository root with the project's renv environment:

```bash
Rscript 01_frame/scripts/00_download_pums.R
Rscript 01_frame/scripts/01_prepare_pums.R
```

On a fresh environment, restore the recorded packages first:

```bash
Rscript -e 'renv::restore(prompt = FALSE)'
```

Script 00 needs an IPUMS account and `IPUMS_API_KEY` for a new download.
A completed local snapshot can be checked and used offline.

## Inputs and source validation

The source is the full IPUMS USA `us2024c` person extract, acquired by
[Script 00](00_download_pums.md). Paths below are relative to `01_frame/`.

| File | Role |
|---|---|
| `data/input/ipums_pums/current_snapshot.txt` | Selects the local snapshot directory. |
| `data/input/ipums_pums/<snapshot>/request.json` | Saved extraction definition; its SHA-256 must match the receipt. |
| `data/input/ipums_pums/<snapshot>/download_manifest.csv` | Records the returned filenames, sizes, SHA-256 fingerprints and extraction provenance. |
| `data/input/ipums_pums/<snapshot>/files/<returned filename>` | The XML codebook and compressed person CSV supplied by IPUMS. |
| `docs/00_pums_source.json` | Tracked specification of the approved data and parsed variable metadata. |

Script 01 verifies the saved request and both source files against their
local receipt. It then checks the compressed CSV size and fingerprint,
required columns and complete `ipumsr::ipums_var_info(ddi)` table against
the approved source manifest. The metadata includes variable definitions
and labels.

The approved compressed CSV has **249,052,624 bytes**. Its SHA-256 is:

```text
adb92df6553053b846773de170852e4d1b7b557d6d6aaf9827e9a37111f70a04
```

The approved variable-metadata SHA-256 is:

```text
c5216653fec547730c0edd2a5381cb10b1bbda82cbe0371a2b594c806223d65a
```

The named method `ipums_var_info_json_v1` is specified in the
[source approval document](00_download_pums.md#source-approval).
Each receipt also fingerprints its complete XML file. Account-specific
XML details can vary; the approved variable-metadata check determines whether
the definitions used for analysis match this project's specification.

A changed data or variable-metadata fingerprint stops preparation for review.
`--refresh` requests another download; approving changed content requires
an explicit update to the tracked source manifest.

## Population and processing

- Retain GQ codes 1–5, CITIZEN codes 0–2, and ages 18+.
- Include institutional residents and DC.
- Preserve all 24 source columns, source ages and person weights.
- Calculate record and weighted-population losses at each filtering stage.
- Add labels for recorded sex, Hispanic origin, race and education.
- Treat Hispanic-origin code 900 as unknown in the binary flag.
- Convert household-income code 9999999 to NA, without imputation.
- Retain zero and negative household incomes.
- Check label mappings, person-key uniqueness and geographic code structure.

The output column `gender` contains labels derived from recorded `SEX`.

## Outputs

| File | Purpose |
|---|---|
| `data/intermediate/pums_clean.rds` | Cleaned person records used for district allocation in Script 03 and demographic harmonization in [Script 04](04_harmonize_pums.md). |
| `data/output/01_pums_filtering.csv` | Records, weighted population and losses at each filtering stage. |
| `data/output/01_pums_recoding.csv` | Missing values in the six derived fields. |
| `data/output/01_pums_hispanic.csv` | Records and weighted population by Hispanic-origin flag. |
| `data/output/01_pums_income_by_gq.csv` | Missing household income by group-quarters category. |

Paths are relative to `01_frame/`. The audit CSVs support review; subsequent
scripts read the RDS. Downloaded and generated data are excluded from Git.

## Validated results

The completed preparation run using the approved IPUMS source produced:

| Measure | Result |
|---|---:|
| Source records | 16,095,728 |
| Retained records and unique person identifiers | 12,263,785 |
| Retained person-weight total | 240,960,972 |
| Columns | 30: 24 source and six derived |
| States including DC | 51 |
| Missing cleaned incomes | 816,970, all in GQ categories 3 and 4 |
| Missing values in the other five derived fields | 0 |
| Saved cleaned RDS size | 221 MiB |

These are observed results for the approved source snapshot. District
allocation and its validation are documented in the [Script 03 guide](03_apply_puma_cd_crosswalk.md).

## Data catalogue

See the [frame data catalogue](data_catalogue.md) for acquisition, exact
input/output schemas, producers and downstream consumers.
