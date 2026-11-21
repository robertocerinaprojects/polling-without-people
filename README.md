# Polling Without People

Replication pipeline under development. We review, refine and run each
analysis step before treating its outputs as validated.

## Principal deliverables

The 2024 xframe data are available in [the handoff directory](01_frame/data/output/10_handoff/).

| File | Contents |
|---|---|
| `district_election_inputs_cd120.csv` | District-by-choice 2024 House and statewide presidential shares, lineup, incumbency, and ballot presence on the 2026 map |
| `pums_cd_cells.rds` | ACS mother frame on the 2026 map with state names |
| `ces_2024_harmonized.rds` | Harmonized CES cell keys and both 2024 vote outcomes |

See the [data handoff](get_us_2024_xframe_data.md) for direct downloads, checksums,
the build command, and the lineup rules. See the [frame guide](01_frame/README.md)
for the upstream pipeline.

## Components

| Component | Purpose |
|---|---|
| [01_frame](01_frame/README.md) | Build the district-level citizen-adult population frame and harmonize the 2024 CES for matching to it |
| [02_personae](02_personae/README.md) | Sampling and persona-generation work |
| [03_mrp](03_mrp/README.md) | MrP analysis |

Each component's README is the authoritative index of its execution order,
implementation status and script documentation.

## Working with the repository

- Follow the [repository conventions](docs/repository_structure.md).
- Run individual steps from the repository root using their documented commands.
- The shared R environment lives at the root: `.Rprofile`, `renv.lock` and `renv/`.
- Codespaces configuration lives in `.devcontainer/`.
- The complete pipeline and a new end-to-end runner are not yet implemented.
