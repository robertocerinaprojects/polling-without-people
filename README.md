# Polling Without People

Replication pipeline under development. We review, refine and run each
analysis step before treating its outputs as validated.

## Principal deliverables

| Deliverable | Status |
|---|---|
| 2024 House choice shares on the 2026 congressional map | Built and checked. Step 09 writes `01_frame/data/output/09_house_final_shares_cd120.csv`. |
| ACS mother frame on the 2026 congressional map | Built and checked. Step 06 writes `01_frame/data/intermediate/pums_cd_cells.rds`. |

See the [frame guide](01_frame/README.md#principal-deliverables) for the
files to inspect, the scenario assumption and the build steps.

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
