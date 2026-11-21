# MrP

## Script status

| Order | Script | Status | Documentation |
|---|---|---|---|
| 01 | `scripts/01_prepare_house_inputs.R` | Input build checked against the 2024 handoff, reviewed 2026 roster, and pinned November returns snapshot | [2026 House inputs](docs/01_prepare_house_inputs.md) |

Step 01 uses the existing CD120 frame handoff and writes two files in
`data/input/`. The district predictors contain the 2024 vote shares and
2026 House roster covariates. The separate House results file supports
evaluation. The survey and MrP estimation are pending.

See the [data catalogue](docs/data_catalogue.md) and the
[repository conventions](../docs/repository_structure.md).
