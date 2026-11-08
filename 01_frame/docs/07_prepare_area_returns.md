# Prepare 2024 area-level election returns

## Plain-language summary

For each state and DC, we count the votes reported for Kamala Harris as
Democrat and the votes reported for Donald Trump as Republican. Other
contains every remaining **counted presidential selection**, including
Green, Libertarian, other candidates, reported write-ins, and Nevada's
official “None of These Candidates” option. A blank or invalid presidential
vote contributes nothing to these three counts.

For Did not vote, we subtract the total counted presidential selections
from the state's estimated citizen voting-age population (CVAP). The
residual includes people who voted for another office and left President
blank, as well as people who cast no ballot. It also reflects differences
between the 2024 electorate and the 2020–2024 average resident population.
It is a frame-based estimate of no counted presidential selection.
The returns cannot identify individual nonvoters.

For the House, we keep each contest in the district that held the election in
2024. We keep the candidate and ballot lines alongside the district party
totals. A district that later split has one observed result on the old map.
Estimating where those votes fall on the new map is a separate analysis.

## Run

From the repository root, run the following command after Step 03.

```sh
python3 01_frame/scripts/07_prepare_area_returns.py
```

To download and harmonize just the returns on a fresh checkout, append
`--returns-only`. That run writes the two returns tables and two source audits.
The default also writes the population-based state covariates.
The script uses Python 3 with `openpyxl` and
Poppler's `pdftotext` for the House report. For an existing Ubuntu Codespace,
`sudo apt-get update && sudo apt-get install -y poppler-utils python3-openpyxl`
installs these for the system Python (`/usr/bin/python3`).

### Sources and local files

Paths below are relative to `01_frame/`. The script downloads missing source
files and verifies the SHA-256 of each download or cached copy before parsing.

| Cached file | Source and version | SHA-256 |
|---|---|---|
| `data/input/05_vote_benchmark/fec2024.xlsx` | Federal Election Commission (FEC), *Official 2024 Presidential General Election Results*. The FEC compiled state election office returns and dated the release January 16, 2025. We reuse the same workbook as the Step 05 election benchmark. [FEC results index](https://www.fec.gov/introduction-campaign-finance/election-results-and-voting-information/) · [Workbook](https://www.fec.gov/documents/5645/2024presgeresults.xlsx) · [Report and notes](https://www.fec.gov/resources/cms-content/documents/2024presgeresults.pdf) | `68acdee2924d771b92a05cd950dec850b462c633c05563207ac7e206116e7366` |
| `data/input/05_vote_benchmark/clerk2024.pdf` | Office of the Clerk, U.S. House of Representatives, *Statistics of the Presidential and Congressional Election of November 5, 2024*. The original delegate and representative results come from this report. The optional Step 05 benchmark shares the same cached copy. [Clerk's index](https://clerk.house.gov/Members/ViewElectionInformation) · [Report](https://clerk.house.gov/member_info/electionInfo/2024/statistics2024.pdf) | `d4ba800fc17135b616ae556c92861080ab962d95916ace34b546c5aac824aec4` |

The [state manifest](02_pl_2020_sources.csv) supplies the postal abbreviations
and two-digit state FIPS codes. The default run also reads `STATEFP`,
`input_weight`, and `allocated_weight` from
`data/output/03_pums_allocation_by_state.csv`. The first weight sums each
citizen adult's survey weight once. Step 07 verifies that the second reconciles
to it in every state. The [saved-file check](06_build_pums_cells.md#check-the-saved-analysis-files)
independently reconciles these totals to the mother frame.

## Presidential grouping and shares

| Output category | Count for a state |
|---|---|
| Democrat | Popular votes in the FEC's `HARRIS` column. |
| Republican | Popular votes in the FEC's `TRUMP` column. |
| Other | Every other counted presidential selection in `TOTAL VOTES`. This includes Jill Stein (Green), Chase Oliver (Libertarian), the remaining named candidates, reported scattered write-ins and Nevada's “None of These Candidates.” |
| Did not vote | `did_not_vote_est = cvap - total_votes`. A citizen adult whose ballot contains no counted presidential selection contributes to this residual in principle. |

All four shares divide by state CVAP and sum to one. In states allowing
several parties to endorse the same ticket, the FEC combines those ballot
lines under the candidate's name. For example, the New York certificate
lists 4,341,375 Democratic-line votes and 277,820 Working Families votes
for Harris. The workbook reports their sum, 4,619,195, once.
[New York certificate of ascertainment](https://www.archives.gov/files/electoral-college/2024/ascertainment-new-york.pdf)

The workbook has a popular-vote column for each of 24 named candidates.
It includes separately identified write-ins for those candidates where the
state reported them. Its two additional result columns cover scattered
write-ins and Nevada's recorded “None of These Candidates” choice. The
source audit retains each state-by-column cell. A blank cell means
that the FEC supplied no separate count for that state and column.
Summing those cells by candidate or selection reproduces each national
vote count. Electoral College votes are never
included in the popular-vote totals.
[FEC source and write-in reporting notes](https://www.fec.gov/resources/cms-content/documents/2024presgeresults.pdf)

Across the 50 states and DC, the workbook reports 75,017,613 Democratic
votes, 77,302,580 Republican votes and **2,918,109 Other** selections,
for **155,238,302** in total. Other includes 862,049 for Stein, 650,126
for Oliver, and 1,405,934 for the remaining selections. The latter
includes 210,381 scattered write-ins and 19,625 “None of These Candidates”
selections. These subtotals are already included in Other.

The legacy state script grouped every row outside the two major parties in
the MIT Election Data and Science Lab file as Other. In its reviewed 2024
release, that would include 199,150 marked under-, over-, void and spoiled
ballots in nine jurisdictions. The current rule uses the FEC's counted
presidential selections. These two source definitions can therefore give
different values for Other and for the residual.
[Historical dataset](https://doi.org/10.7910/DVN/42MVDX)

### Ballot terms

| Term | Meaning for these covariates |
|---|---|
| Undervote or blank | The ballot has fewer selections than the contest allows. Someone may leave the presidential contest empty and still vote for House. |
| Overvote | The voter marks more selections than the contest allows. If the presidential vote is invalid, it contributes nothing to any presidential candidate. |
| Spoiled | A voter may spoil a ballot before casting it and obtain a replacement. Only the valid choice on the counted ballot can enter the presidential results. |
| Void | A ballot or selection has been invalidated under the reporting jurisdiction's rules. |
| “None of These Candidates” | Nevada offers this printed choice. A voter can deliberately select it and the FEC includes it in the counted contest total. |

Election officials use these terms in specific local reporting contexts.
[U.S. Election Assistance Commission glossary](https://www.eac.gov/sites/default/files/glossary_files/Glossary_of_Election_Terms_EAC.pdf)

The FEC does not provide a comparable count of blank or invalid
presidential ballots in each state. Step 07 excludes them from the party
counts without assigning reasons to individual people. A direct estimate
of who turned out for *any* office would require a ballot-participation
source. The [CES benchmark](05_vote_rules.md#comparison-with-2024-election-returns)
uses the same FEC workbook to check weighted survey estimates.
[U.S. Election Assistance Commission glossary](https://www.eac.gov/sites/default/files/glossary_files/Glossary_of_Election_Terms_EAC.pdf)

## House results and their geography

Read `STATEFP` and `CDFP119` as strings. A district key combines both
fields. `00` denotes an at-large representative and `11/98` denotes
DC's nonvoting delegate. The 2024 election seated the 119th Congress.
Joining on a same-numbered `CDFP120` can attach the result to different voters
after redistricting. The source contains district totals and lacks the location
of individual votes within a divided district.

The wide table groups House candidate votes as Democrat, Republican and Other.
The Clerk's Democratic labels include the Minnesota Democratic-Farmer-Labor
and North Dakota Democratic-Nonpartisan League parties. For fusion tickets,
additional ballot lines inherit the preceding named candidate's affiliation.
Unattributed write-ins enter Other. The source-line audit retains the printed
labels. House `total_votes` sums candidate and write-in votes. Blank, overvote,
undervote, exhausted, continuing and printed-total lines remain available as
ballot-accounting evidence and contribute no additional candidate votes.

| Case | Treatment in the 2024 district table |
|---|---|
| FL-20 and OK-03 | Unopposed candidates were omitted from the ballot. The rows identify each seat, flag `unopposed_not_on_ballot` and leave all four counts missing. |
| AK at large | The Clerk prints first preferences. Retain them and flag the tabulation. |
| ME-02 | The Clerk prints final ranked-choice candidate totals. Retain them and flag the tabulation. |
| DC delegate | Separate office, `delegate`. Candidate and write-in total 314,069. Adding 13,774 undervotes and 561 overvotes reconciles to the Clerk's 328,404. |

The 433 voting-seat contests with tabulated counts sum to 147,996,542 votes.
The separately identified delegate raises the number of districts with a
reported count to 434. The file contains 436 rows including the two unpolled
seats.

## Outputs and verification

| File | Rows and contents |
|---|---|
| `data/intermediate/07_president_votes_2024.csv` | 51 state/DC rows. `STATEFP`, `STUSAB`, `votes_dem`, `votes_rep`, `votes_other`, `total_votes`. |
| `data/intermediate/07_state_presidential_covariates_2024.csv` | 51 state/DC rows in a full run. State identifiers, CVAP, the three vote counts, total votes, estimated Did not vote and four CVAP-denominated shares. |
| `data/intermediate/07_house_votes_cd119.csv` | 436 original district rows. State, district, office, availability, tabulation, three party counts and candidate total. Input for the future boundary adjustment. |
| `data/output/07_president_source_votes_2024.csv` | 1,326 state-by-source cells (51 × 26). The 423 published numeric entries and 903 blank cells retain their original candidate or selection labels and their harmonised group. |
| `data/output/07_house_source_lines_cd119.csv` | 1,355 House and delegate lines, with original label, candidate, ballot label, row type, harmonized group and count. Includes accounting and fusion lines. |

For each state, the script reconciles the three observed presidential groups
to the FEC's printed state total and checks the source columns against the
national row. As independent state-level checks, Texas reports 6,393,597
Republican, 4,835,250 Democratic and 159,827 Other selections. California
reports 6,081,697 Republican, 9,276,179 Democratic and 507,599 Other.
[Texas certificate of ascertainment](https://www.archives.gov/files/electoral-college/2024/ascertainment-texas.pdf) ·
[California statement of vote](https://elections.cdn.sos.ca.gov/sov/2024-general/sov/complete-sov.pdf)

The voting-seat results reconcile to the Clerk's state recapitulation before
candidate counts are separated from ballot-accounting lines. The 435-seat
aggregates reproduce the project's original House benchmark. Given the verified
national frame population of 240,960,972 and the FEC total of 155,238,302,
the expected national Did not vote residual is **85,722,670**.
