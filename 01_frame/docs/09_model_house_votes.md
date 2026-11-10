# Prepare the district inputs for the House vote model

## Plain-language summary

Start with one row for each House district in the 2024 election, including DC. Attach the district’s estimated citizen-adult population, demographic composition, statewide presidential result and candidate lineup. Divide each party’s recorded House votes by the district’s citizen-adult population. The remaining share represents citizen adults without a counted House candidate vote. The resulting table supplies the outcomes and predictors for the [sequential beta regressions](09_validate_house_beta.md).

We also prepare the predictors for the same election expressed on 2026 boundaries. The district-by-party file lets you inspect both maps together.

## Run from the repository root

```sh
Rscript 01_frame/scripts/09_model_house_votes.R prepare
```

## Outcome and predictors

Let `N` be the district’s unrounded survey-weighted PUMS citizen-adult population and `D`, `R` and `O` its 2024 Democratic, Republican and Other House candidate vote counts. The observed shares are `D/N`, `R/N`, `O/N` and `(N − D − R − O)/N`. A citizen who cast a presidential vote and left the House contest blank falls in the fourth group. Both the shares and the residual depend on the estimated population denominator. [Office-specific vote classification](07_prepare_area_returns.md)

Both district maps cover 435 House seats plus DC’s delegate seat. The four outcomes are available for 434 districts on the 2024 map. FL-20 and OK-03 have missing counts and shares because their unopposed winners took office without a tabulated general-election contest. A tabulated contest with zero votes for one party retains its observed zero. The validation script assigns the training and holdout districts and derives its three conditional outcomes from the counts. [Validation split, endpoints and predictors](09_validate_house_beta.md)

The tables carry all 29 district demographic shares across age, recorded sex, race, Hispanic ethnicity and education. The four presidential shares use the state’s citizen-adult denominator. Each candidate party receives its own 0/1 incumbency flag. It is one when any eligible nominee from that party was serving in Congress before the election. For example, a contest between two Democrats contributes one Democratic outcome, two Democratic nominees and one incumbency flag. [District demographics](08_build_district_predictors.md) · [Candidate rosters](08_house_slates.md)

## Districts on the 2026 map

Every CD120 target uses its own district demographics. The block comparison and availability of 2024 returns establish which lineup accompanies it.

| Target districts | Prepared lineup and source flag |
|---|---|
| 290 exact matches with a tabulated 2024 contest | Use the matched CD119 district’s 2024 nominees. `observed_same_footprint` identifies where the 2024 counts are available. |
| 144 redrawn districts outside the special cases below | Use the reviewed 2026 nominees. `model_redrawn` identifies a target requiring an estimate. |
| FL-20 and OK-03 | Use the declared 2024 winner as the sole named nominee for the hypothetical election. `model_unopposed_2024` identifies these two targets. |

The FL-20 scenario uses Democrat Sheila Cherfilus-McCormick with the population of the redrawn Florida district. OK-03 retains its footprint and uses Republican Frank D. Lucas. Both were sitting members of Congress. The script checks both names, parties and incumbency flags against the 2024 nominee audit. The target table carries scenario identifiers and predictors for future estimation. [Reviewed unpolled winners and official sources](09_unpolled_house_winners_2024.csv)

## Reading the district-by-party covariates

Open `01_frame/data/intermediate/09_house_party_inputs.csv`. Read `STATEFP` and `CDFP` as text to preserve their leading zeros. The key is `congress, STATEFP, CDFP, party`. There are 3,488 rows comprising four choices (`D`, `R`, `Other`, `DidNotVote`) for each district on each map. Each row contains the choice’s statewide presidential share and the district’s demographics. The three candidate groups also have `nominee_count`, `has_nominee` and `incumbent`. District CVAP repeats across the four rows and counts once per district.

`observed_share_2024` is filled for tabulated CD119 contests. CD120 rows carry their target predictors, the lineup year and the source flag described above. The separate wide training table has the vote counts needed to construct the conditional beta responses.

## Files and lineage

Paths are relative to `01_frame/data/`.

| Input | Use |
|---|---|
| `intermediate/07_house_votes_cd119.csv` | Counts and tabulation status for the original district outcomes. |
| `intermediate/07_state_presidential_covariates_2024.csv` | State CVAP totals for reconciliation and four statewide presidential shares. |
| `intermediate/08_district_demographics.csv` | Unrounded population denominator and demographic margins for every district on each map. |
| `intermediate/08_house_slates_2024.csv`, `intermediate/08_house_slates_2026.csv` | Nominee counts, party groups and incumbency flags for each election. |
| `output/08_house_slate_nominees.csv`, [reviewed winner file](09_unpolled_house_winners_2024.csv) | Verify the sole nominees and their incumbency in FL-20 and OK-03. |
| `output/08_district_overlap.csv` | Establish which 2026 districts have an exact 2024 block-footprint match. |

| Output | Contents |
|---|---|
| `intermediate/09_house_training_cd119.csv` | 436 original districts with counts, outcomes, missing-contest flags and predictors. |
| `intermediate/09_house_target_cd120.csv` | 436 target districts with predictors, footprint matches and lineup decisions. |
| `intermediate/09_house_party_inputs.csv` | District-by-party rows on both maps with observed outcomes where available. |
| `output/09_training_slate_counts.csv` | Counts of original districts by ballot configuration, candidate structure and reporting status. |
