# Frame

This component prepares the population records and geographic allocation
inputs used to build the stratification frame. Development is incomplete.

## Script status

Run individual steps from the repository root, following their companion documents.

| Order | Script | Status | Documentation |
|---|---|---|---|
| 01 | `scripts/01_prepare_pums.R` | validated | [PUMS preparation](docs/01_prepare_pums.md) |
| 02 | `scripts/02_build_puma_cd_crosswalk.R` | validated | [PUMA-to-district crosswalk](docs/02_build_puma_cd_crosswalk.md) |
| 03 | `scripts/03_apply_puma_cd_crosswalk.R` | draft | [Crosswalk application](docs/03_apply_puma_cd_crosswalk.md) |

Steps 01 and 02 passed their documented checks using the pinned inputs.
Step 03 currently contains a coverage-audit draft; reviewed execution and
person-level allocation remain pending.

Steps 01 and 02 read their respective external inputs independently.
Step 03 reads both `data/intermediate/pums_clean.rds` and
`data/intermediate/puma_cd_crosswalk.rds`.

## Data and documentation

- `data/input/`: external source files.
- `data/intermediate/`: generated working datasets.
- `data/output/`: generated audits and exports.
- `docs/`: script explanations, decisions and source manifests.

The [data catalogue](docs/data_catalogue.md) records source snapshots,
acquisition, file schemas, producing scripts and downstream consumers.
It covers current intermediates, audits and script-generated documentation.

The active scripts and their documentation stand alone: no retired script,
historical review CSV or legacy document is required to run or interpret them.
Later frame stages remain under review; retirement history is recorded
separately in the [migration record](../docs/migration.md).

See the [shared conventions](../docs/repository_structure.md).
