# MrP data catalogue

The [Step 01 guide](01_prepare_house_inputs.md) records column provenance,
date, transformations, and results coverage. The fitted MrP and survey
interfaces remain pending.

| Repository path | Source or producer | Consumer and schema |
|---|---|---|
| `01_frame/data/intermediate/10_district_election_predictors_cd120.csv` | Frame Step 10. [Handoff](../../get_us_2024_xframe_data.md) | MrP Step 01. District-by-choice predictors, CD120 keys, ACS citizen-adult population, and 2024 House and presidential shares. |
| `01_frame/data/intermediate/08_house_slates_2026.csv` | Frame Step 08. [Pinned sources and roster checks](../../01_frame/docs/08_house_slates.md) | MrP Step 01. One reviewed annual nominee and election-eve incumbency summary per district. |
| `03_mrp/docs/01_house_2026_source_votes.csv` | Versioned candidate-count manifest transcribed from a November 21 download and two supplements. The guide records exact URLs, acquisition method, reported dates and raw fingerprint. | MrP Step 01. Keyed by source race and candidate/party line. Contains integer reported votes, status and constituency-source metadata. |
| `03_mrp/data/input/district_election_inputs_cd120_2026.csv` | MrP Step 01 with the Frame Step 10 CSV and Step 08 roster. | Future MrP. District-choice result predictors from 2024 and 2026 lineup covariates. |
| `03_mrp/data/input/house_election_results_cd120_2026.csv` | MrP Step 01 with the source-vote manifest and Frame Step 10 CD120 geography and population. | Future evaluation. Same district and choice keys as the predictors, with November 3, 2026 House counts, shares and result status. |

Both generated input CSVs are local files. Regenerate them with the
command in the Step 01 guide. The source-vote manifest is versioned so
the same snapshot can be used even after the publisher updates its feed.
