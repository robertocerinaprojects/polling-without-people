# Prepare House inputs for 2026 MrP

Run from the repository root.

*Snippet 1. Prepare the 2026 House inputs.*

```sh
Rscript 03_mrp/scripts/01_prepare_house_inputs.R
```

This step reads the full district election predictor table written to
`01_frame/data/intermediate/` by Step 10. See the [data inventory](data_catalogue.md) for
exact paths and the [2024 handoff](../../get_us_2024_xframe_data.md) for its build
command. To regenerate the annual roster from the pinned Clerk PDFs and
reviewed corrections, run the following command. The roster script
requires Python 3 and Poppler's `pdftotext`. [Step 08 roster build](../../01_frame/docs/08_house_slates.md)

*Snippet 2. Refresh candidate slates before rebuilding House inputs.*

```sh
python3 01_frame/scripts/08_prepare_house_slates.py
```

## Pre-election predictors

`district_election_inputs_cd120_2026.csv` keeps the Step 10 row order,
schema, and four choices per district. Join by `state_fips`,
`district_fips`, and `vote_choice`. Read both FIPS keys and
`matching_cd119` as text.

*Table 1. Pre-election predictor fields and their provenance.*

| Fields | Provenance |
|---|---|
| `vote_house_2024`, `vote_pres_2024` | Copied from Step 10. The former holds final House choice shares for 2024 rebased to CD120 and the latter holds actual 2024 statewide presidential shares. |
| `pres_vote_count`, `pres_total_votes`, `pres_cvap`, `pres_share_turnout`, `pres_source_used` | Copied 2024 statewide presidential counts and source information. |
| `state_fips`, `district_fips`, `state_abbr`, `state_name`, `district_name`, `congress`, `vote_choice`, `cvap`, and `age_*`, `sex_*`, `educ_*`, `race_*`, `eth_*` | Copied district labels, estimated citizen-adult population, and demographic shares from Step 10. |
| `matching_cd119`, `prediction_source`, `needs_prediction`, `fit_status` | Copied provenance of the 2024 House share. These fields describe the rebasing and fit for that historical predictor. |
| `lineup`, `lineup_year`, `nominee_count`, `incumbent`, `same_party_multiple`, `unopposed_party` | The reviewed Step 08 annual **2026** roster. Incumbency is measured on November 2, 2026, including sitting members running in another district. `unopposed_party` is the roster code for the sole nominee's party when there is exactly one nominee. |
| `on_ballot` | One if the 2026 roster has at least one eligible named nominee for the choice, zero otherwise. This follows the repository's roster convention, which includes an unopposed nominee even when no vote is held. Write-in-only candidates are excluded from roster counts. |
| `ballot_group`, `major_party_direction` | Recomputed from the 2026 nominee counts using the shared Step 09 ballot rules. Direction is Democratic presence minus Republican presence, with Other-only contests undefined. |

The `No Vote` choice has blank `nominee_count`, `on_ballot`, and
`incumbent` fields. Every district uses the annual 2026 roster, including
redrawn districts and the two special 2024 unopposed scenarios. [Ballot groups](../../01_frame/scripts/helpers/09_ballot_groups.R) · [Roster source and decisions](../../01_frame/docs/08_house_slates.md)

## November 3 House returns

`house_election_results_cd120_2026.csv` is the evaluation file. It uses the
same district and choice keys, names, Congress and `cvap` as the predictor
file. Use `source_race_id` to link an output row to the versioned
[candidate-count manifest](01_house_2026_source_votes.csv). At-large races
use `AL` in the source ID and `00` in `district_fips`. The DC delegate uses
`98`.

The build reconciles all retained source lines to the manifest's
`total_votes` before applying the line-level `disposition`. It uses
`counted` lines to sum D as Democratic, R as Republican, and I, L, G and O
as Other. It keeps `disqualified` and `unresolved` lines in the manifest.
Explicitly reported blanks and overvotes are outside the candidate
tally. Valid write-ins can contribute votes even when their party has
zero named ballot nominees.

In the results file, `total_votes` sums the three included candidate
groups. `unresolved_votes` reports the separately identifiable marks
excluded pending a usable breakdown. Both fields repeat across the four
choice rows. On the No Vote row, `vote_count` is district CVAP minus
included candidate votes. It includes everyone in the estimated
citizen-adult denominator without a counted candidate vote. Divide
each choice count by district CVAP to get `vote_house_2026`.

### Sources checked on November 21, 2026

The reference uses the latest returns located for the contests reviewed
in the audit, with a pinned national feed for other districts. Use the
row-level status and source URL when evaluating estimates against these
counts. The same manifest reproduces the benchmark after any of its
live sources update. The
[original snapshot](https://github.com/robertocerinaprojects/polling-without-people/blob/7f8d796604b48c54cf5a2efb4e2c38913e7807a8/03_mrp/docs/01_house_2026_source_votes.csv)
remains available by commit.

*Table 2. Official returns and treatment for the 2026 validation inputs.*

| Area | Return and treatment |
| --- | --- |
| Florida | Use the state’s official totals for all 27 tabulated House races, including named write-ins listed by the state. FL-10 elected Maxwell Frost unopposed with no tabulation. Its four counts and shares remain blank. [Florida Election Watch](https://floridaelectionwatch.gov/FederalOffices/USRepresentative) |
| Massachusetts | Use the Secretary of the Commonwealth’s nine district tables. Include the reported `All Others` bucket in Other and verify that the included counts plus blanks equal each published total. The manifest marks these returns `official` to identify their source without assigning a certification date. [State results](https://electionstats.state.ma.us/elections/search/year_from:2026/year_to:2026) |
| California | Use all 52 districtwide returns from the provisional media file generated November 20 at 11:17:35 p.m. Pacific. Join the candidate IDs to the state’s accompanying candidate file to identify party. [Voting results](https://media.sos.ca.gov/media/V26GG.txt) · [Candidate file](https://media.sos.ca.gov/media/C26GG.txt) |
| Arizona | The November 20 state export reproduces the nine districts’ candidate counts. Classify 3,972 `Unofficial Write-in` marks as disqualified and 437 `Unassigned Write-in` marks as unresolved. AZ-03 keeps 2,020 qualified Republican write-in votes for Jacob Parkman and excludes 1,286 disqualified marks. Its included total is 149,586, of which 16,850 are Other. [State export](https://app.enhancedvoting.com/cdn/results/Arizona/export-110326GeneralElection.json) · [Arizona counting rules](https://apps.azsos.gov/election/files/epm/2025/Election-Procedures-Manual-2025--FINAL-12-22-25.pdf#page=258) · [Maricopa canvass](https://elections.maricopa.gov/asset/jcr%3A228c42d5-7b4c-4e34-a9de-6384bcc80032/11-03-2026-0%20BOS%20CANVASS%20SUMMARY.pdf) |
| Maine 2 | Use the November 12 state central tabulation’s opening round, before ranked-choice transfers. Its 337,131 active ballots include 170,710 Republican, 165,178 Democratic, and 1,243 generic write-ins. The central summary gives no declared-only split, so those 1,243 stay unresolved. The earlier municipal figure of 123 declared write-ins belongs to a different tabulation. [Round summary](https://www1.maine.gov/sos/sites/maine.gov.sos/files/inline-files/Nov26%20CG2%20RCV%20Summary%20Report%2020261112_0.csv) · [State explanation](https://www3.maine.gov/sos/news/ranked-choice-voting-tabulation-results-announced-maine-congressional-district-2) |
| DC delegate | Use the November 20, 4:29 p.m. Eastern Decision Desk HQ report of 230,188 votes for the three named candidates. The publisher does not give a separate write-in total or explicitly label the round. [Decision Desk HQ](https://votes.decisiondeskhq.com/races/2026-11-03/district-of-columbia-us-house-at-large-general-election) |
| Alaska | Use the November 18 state detailed report, Round 1. The four named candidates account for 287,337 continuing ballots. The state excluded unresolved write-ins from this tabulation. [Alaska detailed report](https://www.elections.alaska.gov/enr/26GENR/results/RCV-USRep.pdf) |

The fallback is the November 21 Call the Map candidate-level CSV. A
fresh download on November 21 matched the original SHA-256
`e52101081c5d5a72c379e90a56b5715d17046b8b2334b942d8b24dd0681cf94d`.
Credit Call the Map (CC BY 4.0) and civicAPI, compiled from state and
county election offices, for its attributed rows. Feed statuses include
`counting`, `called` and `final`. Generic write-in lines in the fallback
retain the publisher’s classification where the reviewed sources give
no basis for a district-specific adjustment. The benchmark can therefore
contain provisional totals and write-in definitions that vary by source.
[Call the Map download and dictionary](https://www.callthemap.com/results/data)

### Rebuild checks

The build verifies that the predictor table, roster, and results
manifest cover the same 436 district keys. It checks one row per choice,
reconciles retained source lines, and verifies that included counts fit
within district CVAP. Each generated file has 1,744 rows, with observed
shares for 435 districts.
