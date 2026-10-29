## Script 13
### Purpose: Construct vote_2024 column for CES respondents

Build a single, clean party-level vote variable for each CES respondent by combining information from multiple CES vote-related questions across the pre-election and post-election waves. The resulting `vote_2024` column is the modeling target for the multinomial vote-choice regression that powers MrsP.

### Inputs and outputs
- Input: `ces_with_cd_v2.rds` (from Script 12)
- Output: `ces_with_cd_v2.rds` (overwritten, now with `vote_2024` column added)

### The CES vote-related variables

The CES 2024 captures vote information through five questions across two waves. Each has its own gating logic and response codes.

#### Pre-election wave (asked of all pre-wave respondents, with branching)

**CC24_363 — Vote intention**

> "Do you intend to vote in the 2024 general election on November 5th?"

| Code | Meaning |
|---|---|
| 1 | Yes, definitely |
| 2 | Probably |
| 3 | I already voted (early or absentee) |
| 4 | I plan to vote before November 5th |
| 5 | No |
| 6 | Undecided |
| 8 / 9 | Skipped / Not asked |

Asked of all respondents.

**CC24_367 — House preference**

> "In the general election for U.S. House of Representatives in your area, who do you prefer?"

| Code | Meaning |
|---|---|
| 1-5 | $HouseCand1Name through $HouseCand5Name (candidate index) |
| 10 | Other |
| 98 | I'm not sure |
| 99 | No one |
| 998 / 999 | Skipped / Not asked |

Asked of respondents who hadn't already voted at pre-wave time.

**CC24_367_voted — House vote (early voters only)**

> "For which House candidate did you vote?"

| Code | Meaning |
|---|---|
| 1-5 | Candidate index (same mapping as CC24_367) |
| 10 | Other |
| 98 | Not sure |
| 99 | Didn't vote |
| 998 / 999 | Skipped / Not asked |

ONLY asked of respondents who said `CC24_363 == 3` (already voted before the pre-election survey).

#### Post-election wave (only for `tookpost == 2` respondents)

**CC24_401 — Turnout**

> "Voted in the 2024 election? Which of the following statements best describes you?"

| Code | Meaning |
|---|---|
| 1 | I did not vote in the election this November |
| 2 | I thought about voting this time – but didn't |
| 3 | I usually vote, but didn't this time |
| 4 | I attempted to vote but did not or could not |
| 5 | I definitely voted in the November 2024 General Election |
| 8 / 9 | Skipped / Not asked |

Asked of all post-wave respondents.

**CC24_412 — House vote (post-wave)**

> "Who did you vote in the election (House)?"

| Code | Meaning |
|---|---|
| 1-5 | Candidate index (same mapping) |
| 10 | Other |
| 11 | I did not vote in this race |
| 12 | I did not vote |
| 13 | Not sure |
| 98 / 99 | Skipped / Not asked |

Only shown if at least one House candidate exists for that respondent's district.

#### Candidate party lookup

`HouseCand1Party`, ..., `HouseCand5Party` hold the party affiliation of each candidate that appeared on the respondent's ballot. The candidate index in any of the vote questions above maps directly to these columns. For example, if `CC24_412 == 2` for a respondent, their vote went to HouseCand2, whose party is in `HouseCand2Party` for that row.

### Waterfall logic

The five questions don't all answer the same thing. They span:
- Pre-vs-post wave timing
- Stated preference vs reported actual vote
- Confirmed turnout vs intended turnout
- Asked of all respondents vs gated by other answers

The waterfall combines them in order of reliability:

| Priority | Source | Reliability |
|---|---|---|
| (a) | CC24_412 | Most reliable: retrospective report of actual vote, asked of most respondents |
| (b) | CC24_401 | Confirms non-voting status when CC24_412 is missing |
| (c) | CC24_367_voted | Reported actual vote, just collected pre-wave for early voters |
| (d) | CC24_367 | Pre-election preference, not confirmed vote |
| (e) | CC24_363 | Pre-election intent; only the "No" code (5) contributes meaningfully |
| (f) | NA | No clean information available |

Justification for the ordering:

- **Post-wave responses are retrospective** ("what did you do?") and most accurate when available
- **CC24_401 confirms non-voting status**; for the "No Vote" category, it's authoritative
- **CC24_367_voted is a reported actual vote** (just collected pre-wave for early voters); equivalent reliability to CC24_412 but with smaller sample. Falls below CC24_412 only because CC24_412 is asked of more people
- **CC24_367 is a pre-election preference**, not a confirmed vote, so less reliable than actual vote reports
- **CC24_363 only contributes "No Vote" cases** — positive vote intent without a candidate name is too weak to record

### Helper function: `party_from_candidate()`

Translates a candidate index (1-5) plus the five `HouseCand*Party` columns into a standardized party label. The function is called from each waterfall step that involves a candidate index.

Party standardization:

| Raw party | Standardized |
|---|---|
| Democratic | Democratic |
| Republican | Republican |
| Libertarian | Libertarian |
| Green | Green |
| Independent | Independent |
| No Party Preference | Independent (CA ballot convention; functionally equivalent) |
| Any other party (Unity, write-ins, fringe) | Other |
| NA | NA |

### Output factor levels

`vote_2024` is converted to a factor with explicit level ordering. Democratic and Republican come first so they serve as reference categories in the downstream multinomial regression:
Democratic, Republican, Libertarian, Green, Independent, Other, No Vote

### Final collapse

Libertarian, Green, and Independent each have very small respondent counts (typically <1% each in the CES sample). This is too sparse for stable estimation in a multinomial regression at the cell level. They're collapsed with "Other" to create a single residual category.

Final levels:
Democratic, Republican, Other, No Vote

This is a 4-level multinomial target. Note that "No Vote" is treated as a vote choice alongside the partisan options — i.e., the model estimates P(vote | demographics, CD) as a joint distribution over choosing each major party, the residual category, or abstaining.

### Validation

The script prints:

- Distribution of each component column (CC24_412, CC24_401, CC24_367_voted, CC24_367, CC24_363)
- Distribution of `vote_2024` after the waterfall
- Coverage rate: percentage of respondents with non-NA `vote_2024`
- Distribution of `vote_2024` after the final collapse

Coverage is expected to be high (>95%) because the waterfall has multiple chances to assign a label, and `CC24_401` plus `CC24_363 == 5` together cover almost all "No Vote" cases that CC24_412 misses.

### Note on row inflation

`ces_with_cd_v2` has row inflation from the ZCTA crosswalk: respondents whose ZCTA spans multiple CDs appear in multiple rows (with `afact < 1`). The `vote_2024` column is the same across all rows for a given respondent (vote choice doesn't depend on CD assignment), so the column is correctly populated regardless of inflation. Distribution checks deduplicate by `caseid` to count each respondent once.

### Save

The script overwrites `ces_with_cd_v2.rds` with the new column added. Downstream scripts use this file as the canonical CES file with `vote_2024` available.