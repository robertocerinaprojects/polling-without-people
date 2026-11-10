# CES 2024 House and presidential vote

## What the two variables mean

We keep one outcome for each office and a companion field that says which
answer supplied it. We use what the person reported after the election
whenever available. If they did not supply a usable post-election answer, we
can still have a pre-election report from someone who had already voted, or a
pre-election preference. The source field lets an analysis distinguish a vote
report from a preference. Neither is an independently verified ballot.

`house_vote_2024` and `pres_vote_2024` each have four categories:
Democratic, Republican, Other and No Vote. A missing value means that no
step below supplied an outcome. A person may have an outcome for one office
and a missing value for the other. All eligible people remain in the CES
table with their original `commonweight`. Additional weights are available
by `caseid` in the raw CES release.

## First usable answer wins, independently for each office

| Source recorded | House rule | Presidential rule |
|---|---|---|
| `post_choice` | `CC24_412` slots 1–5 select candidates from the post-election roster. Code 10 gives Other. Code 11 (did not vote in this race) or 12 (did not vote) gives No Vote. Code 13 (not sure) falls through. | `CC24_410` codes 1 Harris and 2 Trump give Democratic and Republican. Codes 3 Kennedy, 4 Stein, 5 West, 6 Oliver and 8 Other give Other. Code 9 gives No Vote. |
| `post_nonvoter` | `CC24_401` codes 1–4 report general-election nonparticipation, including attempting to vote without succeeding. Assign No Vote. Code 5 alone supplies no office-specific choice. | Same general-election rule. |
| `pre_reported` | `CC24_367_voted` records an already-cast vote. Slots 1–5 select the pre-election roster, 10 gives Other and 99 gives No Vote. Code 98 (unsure) falls through. | `CC24_364a` codes 1 Harris, 2 Trump and 3 someone else give Democratic, Republican and Other. Code 5 gives No Vote. Code 4 (unsure) falls through. |
| `pre_preference` | `CC24_367` slots 1–5 select the pre-election roster, 10 gives Other and 99 (no one) gives No Vote. Code 98 (unsure) falls through. | `CC24_364b` codes 1 Harris, 2 Trump and 3 Other give Democratic, Republican and Other. Code 4 (will not vote) gives No Vote. Code 5 (unsure) falls through. |
| `pre_nonvoter` | `CC24_363 == 5` means the respondent intended not to vote. Assign No Vote. | Same general-election rule. |
| `unresolved` | Leave the outcome missing. | Leave the outcome missing. |

Candidate slots are specific to the respondent and the survey wave.
`HouseCand1Party` through `HouseCand5Party` describe pre-election choices.
The corresponding `_post` fields describe post-election choices. Democratic
and Republican labels retain their party. Other valid party labels, including
Independent and No Party Preference, give Other. A missing slot label
(including empty, `-1` and `__NA__`) cannot establish a party. In that case
the search continues. Skipped and not-asked answers also fall through.

The questionnaires define the response codes. The project uses the same
order of sources for both offices. In the V9 release, eight House outcomes
come from the fourth and fifth pre-election candidate slots. House code 12
appears in the post-election questionnaire and has zero responses in the
reviewed CSV. Presidential code 7 appears in neither the post-election
questionnaire nor the reviewed CSV.

The hypothetical `CC24_410_nv` and `CC24_412_nv` questions ask nonvoters
whom they would have chosen. The vote outcome uses the reported choices and
preferences listed above. Validated turnout is used separately in the
election benchmark.

## District and District of Columbia

The demographic matching geography uses the respondent's pre-election
residence expressed on the 2026 district map. For House votes we also retain
`house_vote_state_2024` and `house_vote_cd119_2024` in the 2024 election's
119th Congress geography. These identify the state and district in the wave
of the answer used, including turnout-based answers. A respondent can change
residence between waves. If the outcome is unresolved, these two derived
fields and `house_contest_2024` remain missing and the original geography
fields are still available. Script 05 checks every resolved ballot state–district
pair against the reviewed Census list for the 119th Congress.

For DC the House question concerns the delegate and the district code is
`98`. We retain the responses and mark `house_contest_2024 = "DC delegate"`.
For a voting-member-only analysis select `"US House representative"`.
Presidential votes cover DC on the same terms as the states. There were 159
eligible respondents with pre-election DC residence. Two additional
respondents living in other states pre-election gave DC delegate answers in
the post-election survey.

## Reviewed run on the pinned CES source

All figures are unweighted respondent counts, using the 58,627 self-reported
citizens in the harmonized sample.

| Outcome | House | President |
|---|---:|---:|
| Democratic | 26,906 | 28,846 |
| Republican | 20,551 | 22,062 |
| Other | 1,079 | 1,860 |
| No Vote | 7,286 | 4,836 |
| Missing | 2,805 | 1,023 |

| Source | House | President |
|---|---:|---:|
| Post-election choice or office-specific nonvote | 42,856 | 43,500 |
| Post-election general nonvote | 3,143 | 3,142 |
| Pre-election report of an already-cast vote | 1,104 | 1,106 |
| Pre-election preference | 7,881 | 9,682 |
| Pre-election general nonvoting intention | 838 | 174 |
| Unresolved | 2,805 | 1,023 |

The source questionnaires, data guide and pinned CSV are published together in
[CES 2024 Common Content, V9](https://doi.org/10.7910/DVN/X11EP6).

## Comparison with 2024 election returns

The optional benchmarks run separately from CES preparation.
The [official returns reader](../scripts/helpers/05_benchmark_official.py) supplies
the election counts. The [national and state comparison](../scripts/helpers/05_benchmark_votes.R)
and the [House district comparison](../scripts/helpers/05_benchmark_house_districts.R)
use the cleaned survey outcomes.

An independent calculation from the pinned CES V9 release reproduced the
ten unweighted outcome counts above. For a simple national comparison, use
the eligible respondents' `commonweight`, count each respondent once per
office and use their cleaned candidate choice. The Democratic two-party
share is the sum of weights for Democratic choices divided by the sum of
weights for Democratic and Republican choices. Other, No Vote and unresolved
responses are outside this denominator.

| Office | Respondents with a major-party choice | Weighted CES Democratic two-party share | Official Democratic two-party share | CES minus official (percentage points) |
|---|---:|---:|---:|---:|
| President, 50 states and DC | 50,908 | 48.52% | 49.25% | −0.73 |
| House, voting-member contests | 47,331 | 48.74% | 48.61% | +0.13 |

For House, use the 2024 contest in the wave that supplied the answer and
exclude DC delegate choices. The official count combines ballot lines for
the same candidate and groups major-party affiliates with their party.
FL-20 and OK-03 returned unopposed members without tabulated candidate votes.
The national official share uses the published candidate counts.
[Presidential returns](https://www.fec.gov/resources/cms-content/documents/2024presgeresults.pdf) ·
[House returns](https://clerk.house.gov/member_info/electionInfo/2024/statistics2024.pdf)

The local errors were larger. Giving each jurisdiction equal weight, the
root mean squared error in Democratic two-party share was 4.17 percentage
points across the states and DC for President and 8.07 across the 433 House
districts with counted candidate votes. These comparisons concern the 2024
ballots in the original election geography.

Table 3 of the CES guide reports a 2.05-point presidential state-level root
mean squared error for the authors' validated-voter analysis. The guide
recommends `commonpostweight` for adult-sample analyses using post-election
items. A separate check using the full V9 release, direct post-election
presidential choices, validated voters and `vvweight_post` yielded 2.71
points. The difference from 2.05 remains unexplained. Table 3 gives no
House district benchmark. Presidential vote choice also enters CES weighting,
so national agreement provides limited independent evidence about vote accuracy.
[CES 2024 guide, pp. 17–21](https://dataverse.harvard.edu/api/access/datafile/12050326)

## Reproduce the vote benchmark

Run these optional commands from the repository root after Step 05. The first
requires Python with `openpyxl` and Poppler's `pdftotext` executable. It
fetches the FEC workbook and the Clerk's House report, checks their SHA-256
fingerprints, and reuses matching files in `01_frame/data/input/05_vote_benchmark/`.
The two R checks read the detailed harmonized CES. The first also checks its
vote outcomes, source flags and ballot geography against the pinned raw CES
one respondent at a time.

```sh
python3 01_frame/scripts/helpers/05_benchmark_official.py
Rscript 01_frame/scripts/helpers/05_benchmark_votes.R
Rscript 01_frame/scripts/helpers/05_benchmark_house_districts.R
```

Generated tables are under `01_frame/data/output/05_vote_benchmark/`.
The `reference/` subdirectory holds official counts for presidential states,
House states and House districts. `national_comparison.csv` and
`state_comparison.csv` give the weighted shares, denominators and return
differences. `ces_vote_benchmark_shares.csv` contains the survey-only estimates.
`state_error_summary.csv` includes the full-sample validated-voter comparison
and alternative residence definitions. `house_district_accuracy.csv` and
`house_district_metrics.csv` give the 2024 district results, and
`house_counted_seat_sensitivity.csv` shows what changes when the two seats
without a published candidate count are omitted from both inputs.

The national and state tables distinguish the project's combined answers
with `commonweight`, that same measure with `commonpostweight`, direct
post-election choices, and the full-release validated-voter calculation.
For the latter, use a positive `vvweight_post`, turnout codes 1–6 in
`TS_g2024` and post-election residence. For the combined answers, use
residence in the wave supplying the outcome. House district comparisons
use the source-wave 119th Congress contest. The calculations use the
detailed Step 05 file to preserve those distinctions for every respondent.
