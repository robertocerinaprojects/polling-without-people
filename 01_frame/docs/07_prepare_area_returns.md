# 07 — Prepare area-level election returns

## Plain-language summary

How many citizen adults cast a counted vote for a candidate for each office?
For president, we count candidate votes in each state and DC. For House, we
count them in the district that held the 2024 election, including DC's
delegate district. We follow the candidate across ballot lines and assign
their votes to Democratic, Republican or Other. We compare the MIT counts
with official returns before using them.

For a state with 100 citizen adults and 70 counted presidential candidate
votes, presidential turnout under this definition is 70% and Did not vote
for president is 30%. The 30 can include people who voted for House and
left president blank. We retain blank, invalid and “none” vote totals in the
source audits. They add nothing to the 70, and they are already covered by
the residual of 30. Step 07 leaves each House count in the district where
the election took place. Step 09 uses those observed counts to fit the
House model on the 2024 map.

## Follow a vote through the code

In Connecticut's first House district, MIT lists one candidate as
`WORKING FAMILIES`. The Clerk credits that ballot line to John B. Larson.
The [MIT House reader](../scripts/helpers/07_mit_house.py) first identifies
the major-party nominees in each district. On its second pass it can credit
both of Larson's lines to Democratic, even if the Working Families row
comes first. An unattributed pool of write-ins goes to Other. An undervote
stays in the source audit.

In the [main script](../scripts/07_prepare_area_returns.py), `reconcile_returns`
compares each of the three candidate totals with the Clerk's district totals.
It returns both the selected counts and the side-by-side audit. For president
the same comparison uses the FEC state totals. The table below records the
seven reviewed differences in presidential Other.

## Ballot decisions for both offices

| What the source reports for this office | Treatment |
|---|---|
| Vote for a Democratic or Republican candidate | Assign to that candidate's party, including named write-ins and votes credited on local or cross-endorsing party lines. |
| Vote for any other named candidate | Other. This includes Green, Libertarian, independent and other candidates. |
| Pooled write-ins, scattered votes or other candidates reported together | Other. A separately reported write-in explicitly credited to the relevant Democratic or Republican candidate goes to that candidate. |
| No selection recorded, including blank or undervote | Exclude the row from candidate totals. |
| An explicit choice of none of the candidates | Exclude the row from candidate totals. Nevada's “None of These Candidates” is a real ballot choice that the project treats this way. |
| Too many selections, reported as an overvote | Exclude the row from candidate totals. |
| Spoiled, void, exhausted or other ballot-accounting entry | Exclude the row from candidate totals. A credited replacement ballot contributes through its candidate tally. |
| A tally which sums or repeats other source lines | Use it only to check the return. Adding it to candidate counts would count votes twice. |
| A contest with no measured vote count | Preserve the contest and its status with missing outcome counts. |

A blank **party** label on a write-in entry does not mean a blank ballot.
For example, Alabama's unattributed presidential write-ins contribute to
Other. In New York, the MIT presidential file credits Harris on a combined
Working Families/Democratic line. All votes credited there go to Democratic.
The presidential `party_simplified` field alone cannot implement the
rules above. The source audits record the original labels. The categories
apply to the area covariates. The [CES outcome rules](05_vote_rules.md)
separately describe respondents' answers and survey-wave fallbacks.

## Source snapshots and running the script

From the repository root:

```bash
/usr/bin/python3 01_frame/scripts/07_prepare_area_returns.py
```

Use `--returns-only` to prepare the two offices' observed counts and audits
without the Step 03 state PUMS file. If a state presidential shares file
already exists, this mode leaves it in place. A full run refreshes it.
The command uses the Codespace's system Python. In another environment,
use a Python 3 interpreter with `openpyxl` and make Poppler's `pdftotext`
available on the command path. Paths in the table are relative to `01_frame/`.

| Cached input | Release and use | SHA-256 of reviewed bytes |
|---|---|---|
| `data/input/07_area_returns/1976-2024-president.csv` | MIT Election Data and Science Lab, U.S. President 1976–2024, Harvard Dataverse v10.1, file 13887042. State votes. [Release](https://dataverse.harvard.edu/dataset.xhtml?persistentId=doi:10.7910/DVN/42MVDX&version=10.1) | `9936410a6dd4ecc8be7fe202c6dff5b5f8fee59d88f35ab542ed12879941dcb7` |
| `data/input/07_area_returns/1976-2024-house.csv` | MIT Election Data and Science Lab, U.S. House 1976–2024, Harvard Dataverse v15.0, file 13592823. District votes. [Release](https://dataverse.harvard.edu/dataset.xhtml?persistentId=doi:10.7910/DVN/IG0UN2&version=15.0) | `76eec42483ee9f0fc5cf6e377442c783d1ae6eefa929729fd6561a69bab47f2a` |
| `data/input/05_vote_benchmark/fec2024.xlsx` | Federal Election Commission, official 2024 presidential general election results, compiled from state election offices. [Workbook](https://www.fec.gov/documents/5645/2024presgeresults.xlsx) · [Report and notes](https://www.fec.gov/resources/cms-content/documents/2024presgeresults.pdf) | `68acdee2924d771b92a05cd950dec850b462c633c05563207ac7e206116e7366` |
| `data/input/05_vote_benchmark/clerk2024.pdf` | U.S. House Clerk, statistics of the November 5, 2024 federal election. Official House returns and notes on unpolled and ranked-choice contests. [Report](https://clerk.house.gov/member_info/electionInfo/2024/statistics2024.pdf) | `d4ba800fc17135b616ae556c92861080ab962d95916ace34b546c5aac824aec4` |

Step 07 verifies downloads and reuses cached files with matching fingerprints.
If Harvard asks for a guestbook response, open the release, complete the
guestbook, download the file in **Original Format**, and place the extracted
original bytes at the listed path. Harvard lists the House file as
`1976-2024-house.tab`. Its original bytes are comma-separated, and the project
stores those bytes as `1976-2024-house.csv`. Re-exporting the table or saving
a converted tab-delimited version changes the fingerprint.

The [Census state manifest](02_pl_2020_sources.csv) maps postal abbreviations to
state FIPS codes. For state CVAP, Step 07 reads `input_weight` from
`data/output/03_pums_allocation_by_state.csv` and checks it against
`allocated_weight`. This is the sum of person weights (`PERWT`) for citizens
aged 18 and older in the 2020–2024 ACS PUMS. It estimates the average
resident citizen-adult population over the five-year period. Election-day
counts and this population estimate can differ in timing and coverage.

## Calculating presidential shares

For each state and DC, let `total_votes = votes_dem + votes_rep + votes_other`.
The three counts cover votes credited to candidates or to pools of candidates.
Use the same full state `cvap` in every denominator.

| Result | Calculation |
|---|---|
| Democratic, Republican or Other share | Corresponding candidate count divided by `cvap` |
| Presidential turnout share | `total_votes / cvap` |
| Estimated citizens without a counted candidate vote for president | `did_not_vote_est = cvap - total_votes` |
| Did not vote for president share | `did_not_vote_est / cvap` |

The Did not vote estimate combines people who cast no ballot with people
whose ballot yielded no credited candidate vote for this office. Individual
voters cannot be identified from aggregate returns. Excluded source rows
are never added to the residual. This also handles places where separate
undervote and overvote totals are unavailable. General-election ballots cast
for any office do not enter the calculation.

For DC, 294,185 votes for Harris and 21,076 for Trump enter the two major-party
categories. Kennedy's 2,778 and the 7,830 pooled write-ins give 10,608 Other.
That makes 325,869 presidential candidate votes. The 2,075 undervotes and
460 overvotes remain in the audit. The DC Did not vote estimate is its PUMS
citizen-adult population minus 325,869. [DC certified results](https://electionresults.dcboe.org/election_results/2024-General-Election)

## House geography and tabulation

The House table represents 435 seats and DC's delegate on the original
**119th Congress** map. Read `STATEFP` and `CDFP119` as strings. District
`00` is at large, and state/district `11/98` is DC's delegate. The
DC delegate has 314,069 credited candidate and write-in votes. The
source audit also records 561 overvotes and 13,774 undervotes for that contest. [DC certified results](https://electionresults.dcboe.org/election_results/2024-General-Election)

| Contest | Treatment |
|---|---|
| FL-20 and OK-03 | The Clerk records the winners as unopposed and omitted from the ballot. MIT uses placeholder numbers. The audit retains the source rows; the analysis counts are missing. |
| AK at large | Use published first preferences and record the tabulation method. |
| ME-02 | Use the published final-round counts for Golden and Theriault. Exclude the 11,340 exhausted ballots. First-round write-in votes could have transferred to a finalist, so adding them to final-round counts would duplicate votes. |
| DC | Keep the delegate contest and identify it separately from voting House seats. |

Ranked-choice categories refer to the round in the table. In particular,
an exhausted final-round ballot can have expressed a valid first preference.
An eventual Did not vote residual on these data means no candidate vote
credited in the selected tabulation. It cannot establish that the voter
left the office blank.

**How the House counts enter the model.** For the 434 tabulated contests,
Step 09 divides each party’s count by the original district’s unrounded PUMS
citizen-adult population. The remaining share is the fourth outcome, citizens
without a counted House candidate vote. The original FL-20 and OK-03 rows retain four missing shares because their House contests had no tabulated votes.
[House model outcome and predictors](09_model_house_votes.md#outcome-and-predictors)

Step 08 compares the two maps using Census blocks. On the new map, Step 09
carries candidate counts for the 290 tabulated districts whose footprints
match and divides by the target district’s population. It predicts 144
redrawn districts with their 2026 lineups. For the new FL-20 and OK-03 it predicts all four shares using each target district’s population and the sole declared 2024 winner as the named incumbent nominee. The ordinary model allows write-in support in these contests and supplies the final estimates directly. State aggregates can differ from the 2024 House returns. [District projection rules](09_model_house_votes.md#districts-on-the-2026-map)

## Outputs and source reconciliation

Step 07 retains one audit row per MIT source row for the 2024 election:
535 presidential rows and 1,353 House rows. These audits show why an
accounting line did or did not contribute to an office's candidate vote.
The official-source audits preserve the FEC workbook contributions and the
Clerk's House return lines. Compare party counts within each office and
geography before using the selected counts.

The two presidential sources agree on the Democratic and Republican counts
in every state and DC. They differ on Other in seven states after applying
the same rule to both files. In these states Step 07 uses the FEC's compiled
state-office returns and records both sets of numbers. Elsewhere it uses the
matching MIT figures. Source differences require review if a release changes.

| State | MIT Other minus FEC Other |
|---|---:|
| Arizona | −842 |
| Delaware | +1 |
| Montana | −27 |
| New York | +105 |
| Pennsylvania | −24,526 |
| Rhode Island | −300 |
| West Virginia | +2 |

Across all 50 states and DC, the selected returns sum to 75,017,613 Democratic,
77,302,580 Republican and 2,898,484 Other, or 155,218,677 presidential candidate
votes. Nevada's 19,625 explicit “None of These Candidates” selections explain
the difference from the FEC's published 155,238,302 total. [FEC results and notes](https://www.fec.gov/resources/cms-content/documents/2024presgeresults.pdf)

The House D/R/Other totals agree with the Clerk for all 434 tabulated
contests, including DC. The selected counts come from MIT there. The two
unpolled contests have missing counts and are identified as such in both
the House table and the comparison audit.

| Output, relative to `01_frame/data/` | What it provides |
|---|---|
| `intermediate/07_president_votes_2024.csv` | State and DC candidate counts, `total_votes` and `source_used`. |
| `intermediate/07_state_presidential_covariates_2024.csv` | Presidential counts with `cvap`, `did_not_vote_est`, `share_dem`, `share_rep`, `share_other`, `share_turnout` and `share_did_not_vote`. Full run only. |
| `intermediate/07_house_votes_cd119.csv` | Original district counts, `total_votes`, tabulation, availability and `source_used`. Supplies observed House outcomes for fitting and the counts carried to identical districts. |
| `output/07_mit_president_rows.csv` and `output/07_mit_house_rows.csv` | Original MIT vote lines and their treatment by office. |
| `output/07_president_source_votes_2024.csv` and `output/07_house_source_lines_cd119.csv` | Official-source lines supporting the comparison. |
| `output/07_vote_source_comparison.csv` | By office and geography, MIT and official counts, `source_used` and `status`. |
