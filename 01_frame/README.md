# Frame

This component prepares the citizen-adult population records and geographic
allocation inputs used to build the stratification frame.

## Script status

Run individual steps from the repository root, following their companion documents.

| Order | Script | Status | Documentation |
|---|---|---|---|
| 00 | `scripts/00_download_pums.R` | validated | [IPUMS download](docs/00_download_pums.md) |
| 01 | `scripts/01_prepare_pums.R` | validated | [PUMS preparation](docs/01_prepare_pums.md) |
| 02 | `scripts/02_build_puma_cd_crosswalk.R` | validated | [PUMA-to-district crosswalk](docs/02_build_puma_cd_crosswalk.md) |
| 03 | `scripts/03_apply_puma_cd_crosswalk.R` | validated | [Crosswalk application](docs/03_apply_puma_cd_crosswalk.md) |

Step 00 downloads the specified IPUMS USA extract, records its files and
fingerprints, and reuses verified local files on ordinary reruns. Acquisition,
24-column validation and offline reuse passed. Use `--refresh` to request
a separate snapshot.

Step 01 checks the selected download against its receipt and the tracked
[source manifest](docs/00_pums_source.json), then prepares citizens aged 18+.
The complete download-to-preparation run passed and saved 12,263,785 records
with a total person weight of 240,960,972. Step 02 passed its documented
crosswalk checks. Step 03 matched all 2,462 PUMAs and saved 20,333,303
person–district rows. The district contributions preserved the total person
weight of 240,960,972.

The input flow is Step 00 → Step 01 → `data/intermediate/pums_clean.rds`.
Step 02 independently produces `data/intermediate/puma_cd_crosswalk.rds`.
Step 03 reads both RDS files and distributes each person’s weight across
districts using their PUMA’s probabilities. Its output is
`data/intermediate/pums_cd_allocation.rds`.

## Data and documentation

- `data/input/`: external source files and local acquisition receipts.
- `data/intermediate/`: generated working datasets.
- `data/output/`: generated audits and exports.
- `docs/`: script explanations, decisions and tracked source manifests.

The [data catalogue](docs/data_catalogue.md) records source snapshots,
acquisition, file schemas, producing scripts and downstream consumers.
It covers intermediates, audits and script-generated documentation.

See the [shared conventions](../docs/repository_structure.md).
