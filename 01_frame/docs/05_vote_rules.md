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
table, with their original survey weights.

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

The questionnaires define the response codes. The ordering is a project
decision. We follow the original House rule's order for both offices. The
original House implementation used three slots for pre-election responses and
the pre-election party roster for post responses. The V9 release and data
guide include fourth and fifth pre-election slots. Reading them resolves eight
additional outcomes. Reading the correct post-election roster changes two
additional House party classifications. Post House code 12 appears in the
questionnaire and has zero responses in the reviewed CSV. Post presidential
code 7 appears in neither the questionnaire nor the reviewed CSV.

The previous project had no equivalent respondent-level presidential rule.
The table above defines the corresponding rule for this office. Hypothetical
preferences asked of known nonvoters, second choices and validated turnout
are outside these outcomes. Each office-specific outcome describes the
2024 election.

## District and District of Columbia

The demographic matching geography uses the respondent's pre-election
residence expressed on the 2026 district map. For House votes we also retain
`house_vote_state_2024` and `house_vote_cd119_2024` in the 2024 election's
119th Congress geography. These identify the state and district in the wave
of the answer used, including turnout-based answers. A respondent can change
residence between waves. If the outcome is unresolved, these two derived
fields and `house_contest_2024` remain missing and the original geography
fields are still available.

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
[Original House implementation at the reviewed commit](https://github.com/robertocerinaprojects/polling-without-people/blob/e6373a8/legacy/frame/scripts/Script13_CES_vote2024_waterfall.R).
