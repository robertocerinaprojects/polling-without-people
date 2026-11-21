# Prepare House inputs for 2026 MrP

Run from the repository root.

```sh
Rscript 03_mrp/scripts/01_prepare_house_inputs.R
```

This step reads the full district election predictor table written to
`01_frame/data/intermediate/` by Step 10. See the [data inventory](data_catalogue.md) for
exact paths and the [2024 handoff](../../get_us_2024_xframe_data.md) for its build
command. To regenerate the annual roster from the pinned Clerk PDFs and
reviewed corrections, run the following command. The roster script
requires Python 3 and Poppler's `pdftotext`. [Step 08 roster build](../../01_frame/docs/08_house_slates.md)

```sh
python3 01_frame/scripts/08_prepare_house_slates.py
```

## Pre-election predictors

`district_election_inputs_cd120_2026.csv` keeps the Step 10 row order,
schema, and four choices per district. Join by `state_fips`,
`district_fips`, and `vote_choice`. Read both FIPS keys and
`matching_cd119` as text.

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

`house_election_results_cd120_2026.csv` is a separate evaluation file.
It uses the same district and choice keys, names, Congress and `cvap`
as the predictor file. The source table has one row per published
candidate or write-in line with the original party group, votes, reported
contest total, publication status, source URL and available source
timestamps. Use `source_race_id` to link an output row to its source
lines. State abbreviations plus two-digit district numbers match the
source IDs. At-large districts use `AL` in the source ID and `00` in
`district_fips`. The DC delegate uses `98`.

For each contest, the script sums reported votes under D as Democratic,
R as Republican, and I, L, G and O as Other. This uses the counting
source's party attribution, including named write-ins and aggregation of
fusion-line votes as published. For example, the AZ-03 source records
2,020 votes for Republican write-in Jacob Parkman even though the
Republican group has zero roster nominees. Separately reported blank or
invalid ballots do not contribute to the party counts. [Arizona returns](https://app.enhancedvoting.com/results/public/Arizona/elections/110326GeneralElection/ballot-items/248c0000-c0a3-7204-1287-08df11bc03cf)

`total_votes` is the sum of the three choice counts and reconciles to the
source contest total. On the No Vote row, `vote_count` is estimated
district `cvap` minus `total_votes`. `vote_house_2026` is
`vote_count / cvap` for each choice. No Vote therefore measures the
residual relative to the ACS citizen-adult denominator. The file
describes the November 3 ballot, using first choices in the explicitly
supplemented ranked-choice contests. Later runoffs are outside this
snapshot.

### Snapshot and exceptions

- The main snapshot is the Call the Map candidate-level November CSV
  downloaded on November 21, 2026. It contains 435 voting seats. The
  pinned manifest takes only the House rows and retains their source
  metadata and numerical fields. Call the Map collects returns from
  election offices and uses civicAPI for rows identified as such. Credit
  Call the Map (CC BY 4.0) and civicAPI for the rows it supplies. The raw
  download SHA-256 is
  `e52101081c5d5a72c379e90a56b5715d17046b8b2334b942d8b24dd0681cf94d`.
  The download URL is live. Rebuild the checked release from the
  versioned [source votes](01_house_2026_source_votes.csv).
  [Download and data dictionary](https://www.callthemap.com/results/data)
- Alaska replaces the main feed's AK-AL rows with the Alaska Division of
  Elections' November 18 unofficial detailed report, page 2, Round 1.
  Its 287,337 continuing ballots are the sum of the four reported
  candidate counts. The report excludes unresolved write-ins.
  [Alaska detailed report](https://www.elections.alaska.gov/enr/26GENR/results/RCV-USRep.pdf)
- The national feed omits the DC delegate. The pinned supplement
  transcribes the Decision Desk HQ November 13, 10:10 a.m. Eastern
  snapshot of three candidate counts, total 221,110. These are
  provisional first-choice counts for the named candidates. The source
  gives no separate write-in total, so the DC shares reflect its
  published scope. [Decision Desk HQ results](https://votes.decisiondeskhq.com/races/2026-11-03/district-of-columbia-us-house-at-large-general-election)
- FL-10 elected Maxwell Frost unopposed with no vote tabulation. All four
  counts and shares are blank and `result_status` is
  `unopposed_no_tabulation`. [Florida Division of Elections](https://dos.elections.myflorida.com/candidates/CanList.asp?OfficeGroup=FED&cantype=FED&elecid=20261103-GEN)

For the other districts `result_status` preserves the source status.
`final` indicates certification per the publisher, `called` indicates a
race call, and `counting` indicates a count in progress. The two
supplements are marked `provisional`. The release has six districts
marked final and four marked counting. Use its reported status and
source dates when evaluating against these shares.

### Rebuild checks

The build verifies the same 436 district keys in the handoff, annual
roster, and returns manifest, checks one row per choice, reconciles
candidate counts to each published total, and checks that the totals
fit within district CVAP. The November 21 build wrote 1,744 rows to
each file, with observed shares available for 435 districts.
