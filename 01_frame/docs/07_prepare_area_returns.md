# Prepare 2024 area-level election returns

## Plain-language summary

For the presidential covariates, everyone whose general-election ballot was
counted belongs to one of three groups. Someone with a counted Harris vote goes
in Democratic. Someone with a counted Trump vote goes in Republican. Everyone
else with a counted ballot goes in **Other**. This includes someone who voted
for Jill Stein, someone whose presidential selection was invalid, and someone
who voted only for House. To estimate **Did not vote**, we subtract the number
of people whose ballots counted from the state's estimated citizen-adult
population. One voter contributes only once. The sources support this calculation
in 50 of the 51 states/DC, including estimates in Mississippi and Texas. Missouri retains
its observed presidential results and has missing turnout-dependent values.

For House, we keep the observed candidate returns in the district that held
each 2024 contest. If that district later split, allocating its votes across
the 2026 districts requires a separate calculation.

## Run

From the repository root after Step 03:

```sh
python3 01_frame/scripts/07_prepare_area_returns.py
```

Use `--returns-only` on a fresh checkout to build the presidential counts
(including turnout), House counts and three source audits. The default run
also writes the four state shares using the Step 03 population totals.
The script requires Python 3 with `openpyxl` and Poppler's `pdftotext`.
On an existing Ubuntu Codespace, `sudo apt-get update && sudo apt-get install -y poppler-utils python3-openpyxl`
installs these for the system Python (`/usr/bin/python3`).

## Sources and local files

Paths below are relative to `01_frame/`. The script downloads missing
source files and verifies the fingerprint of each downloaded or cached file.

| Cached file | Source and version | SHA-256 |
|---|---|---|
| `data/input/05_vote_benchmark/fec2024.xlsx` | Federal Election Commission (FEC), *Official 2024 Presidential General Election Results*. The FEC compiled state election office returns and dated the release January 16, 2025. We reuse the same workbook as the Step 05 election benchmark. [FEC results index](https://www.fec.gov/introduction-campaign-finance/election-results-and-voting-information/) · [Workbook](https://www.fec.gov/documents/5645/2024presgeresults.xlsx) · [Report and notes](https://www.fec.gov/resources/cms-content/documents/2024presgeresults.pdf) | `68acdee2924d771b92a05cd950dec850b462c633c05563207ac7e206116e7366` |
| `data/input/05_vote_benchmark/clerk2024.pdf` | Office of the Clerk, U.S. House of Representatives, *Statistics of the Presidential and Congressional Election of November 5, 2024*. The original delegate and representative results come from this report. The optional Step 05 benchmark shares the same cached copy. [Clerk's index](https://clerk.house.gov/Members/ViewElectionInformation) · [Report](https://clerk.house.gov/member_info/electionInfo/2024/statistics2024.pdf) | `d4ba800fc17135b616ae556c92861080ab962d95916ace34b546c5aac824aec4` |
| `data/input/07_turnout/eavs2024_v2.zip` | U.S. Election Assistance Commission (EAC), 2024 Election Administration and Voting Survey (EAVS), version 2.0, February 12, 2026. Item F1a counts voters who cast a ballot that counted in the general election. [Data release and codebook](https://www.eac.gov/research-and-data/studies-and-reports) · [Question F1](https://www.eac.gov/sites/default/files/2024-04/2024_EAVS_FINAL_508c.pdf) | `4073b9f48e1791d44a78ddc543379f6c040c31ce733dfa47676330b4d7f6d6df` |
| `data/input/07_turnout/Turnout_2024G_v0.4.csv` | Michael P. McDonald, University of Florida Election Lab, *2024 General Election Turnout Rates*, version 0.4. The `TOTAL_BALLOTS_COUNTED` field provides a comparison for every state and the selected count for designated exceptions. [Source and documentation](https://election.lab.ufl.edu/dataset/2024-general-election-turnout-rates-v0-4/) | `9796cf57eda46924c7e5a4b26c2503dcafc8662d5d14a066dfe25a0fce7e85d9` |

EAVS is a survey of election administrators. We add the reported F1a voters
across jurisdictions in each state. The audit gives the number of jurisdictions with an unavailable response and the subtotal from those that reported.
The [turnout exception manifest](07_turnout_sources.csv) records the reviewed
exceptions and confirmations. It gives the count, source, URL and the location
of the count within the source. Step 07 uses a state election-office total when
specified there. Arkansas uses a corroborated UF total. For
Mississippi we use the UF turnout estimate and flag it with
`turnout_is_estimate=True`. An error of 100 in the selected turnout raises
or lowers Other by 100 and moves Did not vote by 100 in the opposite direction.
Texas uses the Legislative Council's published turnout of 11,460,798.
Its precinct methodology permits using the vote count in the highest-turnout
contest where turnout is unavailable. We flag the state count as an estimate.
[2024 state total, page 1](https://data.capitol.texas.gov/dataset/f8542d9e-1bf2-423e-9c79-244cc659012a/resource/9139aaa6-8e5f-4fa5-a691-6ab4e97c7cfa/download/plans2101_r206_election24g.pdf) ·
[Council election data methods](https://redistricting.capitol.texas.gov/docs/pubs/data_for_2021_redistricting.pdf)

The turnout audit retains both the EAVS and UF figures for comparison. We
reviewed every state where these totals differ by at least 10,000. This
threshold prioritizes source review. Smaller discrepancies can also affect the
estimates.
Where EAVS responses are unavailable, the script requires an explicit source
decision. The records for Hawaii and Maine explain how turnout from areas
without a separate count is covered.

The [state manifest](02_pl_2020_sources.csv) supplies state postal abbreviations
and two-digit state FIPS codes. CVAP comes from the sum of the person weights
for citizens aged 18+ in the 2020–2024 ACS PUMS, saved as `input_weight` in
`data/output/03_pums_allocation_by_state.csv`. Step 07 checks that
`allocated_weight` agrees in each state. The [saved-file check](06_build_pums_cells.md#check-the-saved-analysis-files)
also reconciles this total to the mother frame.

### Why Missouri has missing turnout

Missouri publishes 2,995,376 under its turnout label. Its reporting method
uses contest votes as a proxy. A ballot can count even if its voter leaves that contest blank.
Two county checks also rule out adopting the available nationwide series as-is:

- The EAVS subtotal for Missouri is 3,126,837. In St. Francois County alone,
  EAVS reports 36,844 while the county's official turnout table reports 28,858.
  Correcting one county would still leave the others unchecked.
  [County official turnout, p. 3](https://www.sfcgov.org/download/clerk/elections/results/election_results/November-5-2024-Official-Election-Results.pdf)
- UF gives 3,000,000 for Missouri. St. Louis County counted 510,186 ballots
  and recorded 502,738 valid presidential votes, a gap of 7,448. Adding this
  one county's gap to 2,995,327 valid statewide presidential votes yields a
  statewide lower bound of 3,002,775 counted ballots, already above UF's figure.
  [County turnout report](https://extcontent.stlouisco.com/BOE/biennial/2024Biennial.pdf) ·
  [Official county presidential results](https://www.sos.mo.gov/CMSImages/ElectionResultsStatistics/ActualResults-November52024.pdf) ·
  [Official statewide results](https://www.sos.mo.gov/CMSImages/ElectionResultsStatistics/2024GeneralElection.pdf) ·
  [State turnout definition](https://www.sos.mo.gov/elections/results)

For Missouri, `turnout_source=unresolved`. An empty turnout-dependent field
means the quantity is unknown. A numeric zero would require evidence that the
count was zero. Democratic and Republican votes, other valid presidential
votes, the valid presidential total, CVAP and the Democratic and Republican
CVAP shares remain available. The empty measures are `counted_turnout`,
`turnout_without_valid_presidential_vote`, `voters_other`, `did_not_vote_est`
and the two dependent shares (`share_other` and `share_did_not_vote`). A
national sum that skips Missouri would cover only 50 jurisdictions.

## Presidential grouping and shares

| State category | Numerator | Who it counts |
|---|---|---|
| Democratic | `votes_dem` | Every presidential vote credited to Harris, across ballot lines. |
| Republican | `votes_rep` | Every presidential vote credited to Trump, across ballot lines. |
| Other | `voters_other = counted_turnout - votes_dem - votes_rep` | Every counted general-election ballot outside those two nominee totals. |
| Did not vote | `did_not_vote_est = cvap - counted_turnout` | Estimated citizen-adult population outside counted turnout. |

Where turnout is available, the four numerators divide by the same state `cvap` to give `share_dem`,
`share_rep`, `share_other` and `share_did_not_vote`. The last group is a
residual. The frame estimates the average resident citizen-adult population over
five years. Turnout measures the election-day ballot count and may include
overseas voters or voters eligible only for local contests. An attempted vote
whose ballot was rejected is also outside counted turnout. These aggregate
data cannot identify who stayed home.

Two additional fields show exactly what went into Other:

- `valid_presidential_other` counts every valid FEC presidential selection
  outside Harris and Trump. Across the 50 states and DC it totals 2,918,109,
  comprising 862,049 votes for Stein (Green), 650,126 for Oliver (Libertarian)
  and 1,405,934 remaining selections. The last subtotal includes other named
  candidates, scattered write-ins and Nevada's “None of These Candidates.”
  These groups are components of Other, so adding them again would double-count.
- `turnout_without_valid_presidential_vote = counted_turnout - valid_presidential_votes`
  measures the rest of Other. It can include blank or invalid selections,
  ballots that did not include a presidential contest, and differences between
  the turnout and returns sources. A statewide difference does not identify
  those reasons for individual voters.

**DC example.** Of 328,871 counted ballots citywide, 294,185 recorded a vote for
Harris and 21,076 for Trump. That leaves **13,610 Other**. Of these, 10,608 are
valid presidential selections outside Harris and Trump and 3,002 are the
difference between counted turnout and the 325,869 valid presidential votes.
The presidential contest reports 2,075 undervotes and 460 overvotes. That
leaves 467 in the difference between the citywide and contest counts. DC
permitted eligible noncitizens to vote in local contests. The aggregate figures
do not establish which voters account for all 467.
[DC certified results](https://electionresults.dcboe.org/election_results/2024-General-Election) ·
[DC Board of Elections after-action report](https://www.dcboe.org/getmedia/ded21983-eaca-4ab2-8539-8fefc6a86aa3/After-Action-Report-General-Election-2024_FINAL.pdf) ·
[DC local voter eligibility](https://www.dcboe.org/voters/register-to-vote/non-citizen)

### Reading the FEC candidate table

In states allowing
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

### Ballot terms and double counting

| Election record | How it enters the state presidential covariates |
|---|---|
| Undervote | The voter marked fewer options than allowed. A counted ballot left blank for president goes in Other. |
| Overvote | The voter marked too many options. If the ballot counts and its presidential selection is invalid, it goes in Other. |
| Spoiled ballot | A voter can surrender a spoiled ballot and receive a replacement. The counted replacement determines the outcome. Counting the surrendered paper would count the voter twice. |
| Void ballot or selection | A void presidential selection on a counted ballot goes in Other. A wholly rejected ballot supplies no counted turnout. |
| “None of These Candidates” | Nevada's printed choice is a valid counted presidential selection in Other. |

The script obtains the total number of counted voters directly. Adding
separately reported spoiled papers, undervotes or overvotes to that number
would duplicate voters or introduce papers that never counted. For example,
Oregon reports ballots returned by mail as well as ballots that counted.
Returned ballots can include rejections, so the state covariate uses counted
turnout. [Oregon 2024 ballot-return statistics](https://sos.oregon.gov/elections/Documents/statistics/November-general-2024-statistical-summary-participation.pdf) ·
[Oregon ballot rejection and cure](https://sos.oregon.gov/elections/Pages/track-your-ballot.aspx)
[EAC glossary](https://www.eac.gov/sites/default/files/glossary_files/Glossary_of_Election_Terms_EAC.pdf)

In the **CES**, the presidential outcome comes from an individual's
office-specific response, with documented pre-election fallbacks. An eligible
respondent who reports no presidential vote can appear as No Vote there while
a counted ballot with no presidential choice contributes to Other here. An
unresolved survey answer stays missing. The two-party benchmark uses only
Democratic and Republican choices. [CES vote rules](05_vote_rules.md)

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

| File | Contents and use |
|---|---|
| `data/intermediate/07_president_votes_2024.csv` | 51 state/DC rows. `STATEFP, STUSAB, votes_dem, votes_rep, voters_other, counted_turnout, valid_presidential_other, valid_presidential_votes, turnout_without_valid_presidential_vote, turnout_source, turnout_is_estimate`. Supplies the state covariates and the two components of Other. |
| `data/intermediate/07_state_presidential_covariates_2024.csv` | The same 51 rows with `cvap, did_not_vote_est, share_dem, share_rep, share_other, share_did_not_vote` added. Requires the Step 03 population audit. |
| `data/intermediate/07_house_votes_cd119.csv` | 436 original district rows. District, office, availability, tabulation, candidate groups and total. Input for the later boundary adjustment. |
| `data/output/07_president_source_votes_2024.csv` | 1,326 FEC source cells (51 jurisdictions × 26 columns). The 423 numeric entries and 903 blank cells preserve candidate or selection name, grouping and count. Its `party=other` rows supply the valid presidential component only. |
| `data/output/07_turnout_audit.csv` | One row per state/DC with selected turnout, source and estimate flag, EAVS coverage and reported subtotal, UF comparison (`uf_ballots`), valid presidential votes and the decomposition of Other. `eavs_minus_selected` and `uf_minus_selected` give signed differences from the selected count. `turnout_source_url` and `turnout_source_detail` identify the evidence. |
| `data/output/07_house_source_lines_cd119.csv` | 1,355 House and delegate lines, retaining original labels, candidate and ballot lines, harmonized group, row type and count. |

The script reconciles 75,017,613 Democratic votes, 77,302,580 Republican votes
and 2,918,109 other valid selections to the FEC national total of 155,238,302
and checks each state against the printed totals. Each available turnout count
must cover all valid presidential votes. The two components of Other must sum
to `voters_other`, and the three counted groups must sum to turnout. In a full
run the four shares must sum to one wherever all are defined, and each
estimated nonvoting residual must be nonnegative. The voting-seat counts reconcile to the Clerk's state
recapitulation and the project's original House benchmark.
