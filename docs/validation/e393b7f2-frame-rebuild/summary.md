# Frame product audit

Local commit `e393b7f24940aff87425c4886dbaeba957f0f873`. Inspected 174 files.
0 expected product or input patterns absent. Local source changes appear in checkout.json.

## Checks

- **pass** — ipums_active_source. 3/3 files match the expected bytes. Data match the approval; DDI bytes match the receipt. Step 01 separately checks parsed DDI definitions.
- **pass** — pl_2020_source_archives. 51/51 files match the expected bytes.
- **pass** — six_census_source_pins. 6/6 files match the expected bytes.
- **pass** — 07.presidential_returns. 51 jurisdictions; reviewed D/R/Other counts sum to 155,218,677.
- **pass** — 07.presidential_shares. Recomputed every state share from the selected returns and Step 03 CVAP. National residual 85,742,295.
- **pass** — 07.house_returns. 434 classified contests and two unpolled districts with missing counts (FL-20, OK-03).
- **pass** — 08.roster_2024. 436 rows; counts and incumbency match the reviewed roster digest; lineup indicators reconcile.
- **pass** — 08.roster_2026. 436 rows; counts and incumbency match the reviewed roster digest; lineup indicators reconcile.
- **in_progress** — 09.beta_completion. Run directories exist without a completion pointer (plan, interrupted or active).
- **pass** — 06.saved_analysis_files. Verified 58627 CES respondents and 11 analysis columns. Verified 497550 positive population cells across 436 districts including DC. Allocated CVAP: 240960972
- **review** — vanilla_beta_current_run_key. No completed holdout run is recorded. Expected report directory: 01_frame/data/output/09_beta_holdout/02929a33684d62797246 (present). A matching checkpoint directory exists.
- **review** — Independent rebuild. 70 identical, 0 different/unreadable, 10 absent. Applies only to products in this receipt.

## Files to review

- `01_frame/data/input/usa_00003.csv.gz` — retired.  Earlier PUMS source; Step 01 reads the approved snapshot
- `01_frame/data/input/usa_00003.xml` — retired.  Earlier PUMS source; Step 01 reads the approved snapshot
- `01_frame/data/intermediate/09_beta_cache/b9aa56f9092d3624/vanilla/fold_1/stage_1.rds` — earlier model workflow. writer or entry point absent Training or prediction cache belonging to a CV setting and assessment; it is distinct from the holdout-only fit cache.
- `01_frame/data/intermediate/09_beta_cache/b9aa56f9092d3624/vanilla/fold_1/stage_2.rds` — earlier model workflow. writer or entry point absent Training or prediction cache belonging to a CV setting and assessment; it is distinct from the holdout-only fit cache.
- `01_frame/data/output/09_beta_comparison/b9aa56f9092d3624/09_beta_district_splits.csv` — earlier model workflow. writer or entry point absent The plural splits file contains CV fold membership and differs from the single holdout roster.
- `01_frame/data/output/09_beta_comparison/b9aa56f9092d3624/09_beta_party_order.csv` — earlier model workflow. writer or entry point absent Previous CV run plan records the party ordering.
- `01_frame/data/output/09_beta_comparison/b9aa56f9092d3624/09_beta_prior_grid.csv` — earlier model workflow. writer or entry point absent Former ridge/horseshoe tuning grid.

## Files from earlier model workflows

- comparison: 5 files. See files.csv for their paths.
- dirichlet: 1 files. See files.csv for their paths.

**70 local files matched the bytes recorded by an independent successful pipeline rebuild in this audit.**

## Reading the inventory

files.csv includes file fingerprints, commands, and the validation performed by each writer. A writer match establishes which script can create a file. A matching clean rebuild supports equivalence of the saved bytes with a current successful run. A receipt created at the time of publication would be needed to establish the original creation history.
The checks examine files one at a time. Re-run the inventory after an active model finishes to capture its published outputs together. Missing outputs of conditional or optional workflows are expected. An unmapped file requires human review before any cleanup.
