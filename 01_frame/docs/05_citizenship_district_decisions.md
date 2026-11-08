# CES citizenship, district vintage and race assignment

## Decisions recorded 2026-11-08

Keep CES respondents aged 18+ who answered Yes to the US citizenship question
and meet the frame's existing gender eligibility rule. Keep each person's
original survey responses, source district and case ID. Express their 2024
residence in the district geography used for the 2026 election. Draw a harmonized
race only for respondents whose primary CES race was Hispanic/Latino.

The five race probabilities come from Hispanic adult citizens in the processed
PUMS with the same harmonized sex/gender category, education, age group and
state plus 120th congressional district. Race is the outcome of the draw.
These choices establish the analysis sample and imputation rule. The
crosswalk and empty-profile conventions below specify how to implement them.

## Citizenship and survey scope

CES `cit1` is the answer to “Are you a United States citizen?” Script 05
requires an explicit Yes (1), audits No (2) and missing separately and
preserves the full downloaded survey. The sample includes adults who did not
vote. The harmonized gender rule uses `gender4` codes 1 and 2. Survey
respondent counts below are unweighted.

| Sample | Respondents | Citizen Yes | Citizen No | Missing | Primary Hispanic |
|---|---:|---:|---:|---:|---:|
| Full CES | 60,000 | 59,171 | 785 | 44 | 5,150 |
| Gender-eligible | 59,446 | 58,627 | 775 | 44 | 5,102 |
| Retained, gender-eligible citizens | 58,627 | 58,627 | 0 | 0 | 4,869 |

Another 2,417 retained citizens have Hispanic origin and a different primary
race. Their primary race supplies the harmonized category directly. One
retained respondent has unresolved Hispanic origin.

## Place the same residence on the 2026 map

`cdid119` identifies the district for the House **elected in 2024**. The
2026 election chooses the 120th Congress. The district number is specific to
both a state and a plan. The pre-election residence state (`inputstate`),
county (`countyfips`) and district (`cdid119`) describe the same survey
vintage. This overlay represents the 2024 residence under 2026 boundaries.
A later move and any actual 2026 voting behavior are outside its scope.

1. Join the two national Census Block Equivalency Files by their common
   15-character 2020 Census block ID. Apply the frame's 50-state-plus-DC
   scope. The 156 blocks coded `ZZ` in both files have no assigned district.
   Normalize CES district 1 to `00` in the six at-large states and to `98`
   in DC. Preserve the raw 2024 CES codes.
2. If every assigned block of an old district has one new district, use it
   with probability 1. For a split old district, narrow to blocks in the same
   county and old district where that combination exists. A single remaining
   destination again gets probability 1. If the county is missing or the
   county/old-district combination is absent, use the old district and flag
   this in the respondent audit. A ZIP used for district mapping in the
   original survey is less precise than a respondent's residential block.
3. For a remaining split, use each candidate district's share of the
   estimated citizen-adult population of the county/old-district intersection
   (or of the old district for a broader match). Begin with the assigned CVAP
   contribution already produced by Step 02 for each block group and 120th
   district. Where the old boundary splits that contribution, divide it by
   the shares of 2020 block voting-age population. County and PUMA are fixed
   within each of these original block groups in the affected states. Sum
   the resulting contributions and normalize within source geography.
4. Preserve the full lookup and each person's positive district probabilities.
   Draw one destination per person in stable case-ID order using seed 20261108.
   The analysis table has one row and one copy of the survey weight per person.
   The candidate audit can also be used for a probability-weighted analysis.

These are whole-block Census tabulation plans. The published Colorado
exception assigns one legally split block to CO-08 in both files. A unique
destination is a statement about this overlay and the CES geography, rather
than independent address validation. The CD120 archive is the same snapshot
used in Step 02. The national file includes the October 2026 Missouri update.

| Audit of the original geography | All retained citizens | Race-draw recipients |
|---|---:|---:|
| One destination from old district alone | 41,553 | 2,347 |
| One destination after adding county | 6,090 | 512 |
| Multiple destinations using county and old district | 10,799 | 1,993 |
| County missing or county/old-district pair absent in a split district; use old district | 185 | 17 |
| Total | 58,627 | 4,869 |

Of the 185 broad matches in split districts, 184 had a county/old-district
pair absent from the lookup and one lacked a county code.

In the overlay, 295 of the 436 old districts (including DC) have one
destination and 141 split. A split can still have just one *positive*
population share. For the race-draw group, 2,010 people have more than one
geographic possibility and 1,999 have more than one positive working
probability.

### A five-person estimate in Tarrant County

Census block group `484391139322` contributes an estimated five citizen adults
to **new TX-12**. Its blocks are in **old TX-12 and TX-26**. Their recorded
2020 voting-age populations are zero, so age counts cannot divide the five
between the two old districts. Keep the five once in
`05_ces_unknown_origin_cvap.csv`. For split source areas, the working
probabilities use known-origin CVAP. The lookup also records the range
obtained by putting all five in either admissible old district. These
bounds cover this specific uncertainty. They are separate from ACS sampling
uncertainty. A single geographic destination still receives probability 1.

For example, the 11 race-draw recipients in Tarrant County and old TX-12
have three working probabilities: approximately 78.9% for new TX-12, 6.2%
for TX-24 and 14.9% for TX-25. Varying the old-district placement of the
five changes any probability for those 11 by less than 0.001 percentage
points. Reviewed exceptions within the original Step 02 allocations keep
their documented treatment.

## Draw race in the same district

Join Step 04's categories to Step 03's person–district rows using the full
person key, `SAMPLE + SERIAL + PERNUM`. Restrict donors to Hispanic citizens
aged 18+. For each sex/gender, education and age profile in a district,
sum `allocated_person_weight` by race and divide by the sum for all five races.
This weight already includes the original person weight and that person's
PUMA-to-district probability. State and national totals recombine each
person's contributions before counting donors and measuring effective donor
size. The helper reconciles race totals with the national Step 04 table.

For each of the 4,869 recipients, draw the race conditional on the **same**
120th district drawn for that respondent, using a separate seed of 2024.
The draw assumes those CES respondents would have the same distribution
of harmonized race categories as Hispanic PUMS citizens with the matched
profile. Choosing Hispanic/Latino as primary race may distinguish recipients
from others with Hispanic origin even within that profile. A draw represents
a plausible category, while the original CES answers remain available.
A single stored district and race realization does not propagate uncertainty
from the survey estimates or the draws into downstream model intervals.
The analysis records the imputation flag and donor level used. The donor audit shows the five
probabilities for **every positive candidate district**, including candidates
that were not drawn. Expected survey counts average these probabilities over
each person's possible districts. Realized counts come from the one stored
district and race per person.

Use the empirical district distribution whenever its total donor weight is
positive. An unobserved race in a nonempty group has empirical share zero.
For an empty district group, use the same sex/gender, education and age
profile in the state, then in the nation if needed. An empty national profile
stops the run. The support audit gives donor counts and effective donor size
for the exact and used pools. Small positive pools retain their observed
shares, so inspect support before treating strong local patterns as precise.

District differences reflect the PUMA populations assigned to each district.
Public-use PUMS does not reveal a person's residential block. Within a PUMA,
Step 03 assigns the same location distribution to every demographic profile.
Likewise, the geographic transfer for a CES respondent in a split area uses
the area's overall citizen-adult distribution. Use of these two approximations
and the Hispanic PUMS donor population should accompany interpretation.

## Sources

- [2024 CES Common Content and questionnaires, V9](https://doi.org/10.7910/DVN/X11EP6)
- [119th Congress block assignments and tabulation notes](https://www.census.gov/geographies/mapping-files/2025/dec/rdo/119-congressional-district-bef.html)
- [120th Congress block assignments and revision history](https://www.census.gov/geographies/mapping-files/2027/dec/rdo/120-congressional-district-bef.html)
- [Step 02 allocation decisions](02_cvap_allocation_decisions.md)
- [Step 04 categories and national donor totals](04_harmonize_pums.md)
