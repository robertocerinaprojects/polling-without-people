# Polling Without People

Replication pipeline under development. We review, refine and run each
analysis step before treating its outputs as validated.

## Components

| Component | Purpose |
|---|---|
| [01_frame](01_frame/README.md) | Build the population frame and its geographic allocation inputs |
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

## Historical material

The [migration record](docs/migration.md) identifies retired material,
replacements, unresolved work and historical files that remain local-only.
The active components do not depend on the temporary historical quarantine;
their required inputs and methods are documented within the active layout.
