# Prepare the district inputs for the House vote model

## Plain-language summary

Start with one row for each House district in the 2024 election, including DC. Attach the district’s estimated citizen-adult population, demographic composition, statewide presidential result and candidate lineup. Divide each party’s recorded House votes by the district’s citizen-adult population. The remaining share represents citizen adults without a counted House candidate vote. The resulting table supplies the outcomes and predictors for the [sequential beta regressions](09_validate_house_beta.md).

We also prepare the predictors for the same election expressed on 2026 boundaries. The district-by-party file lets you inspect both maps together.

## Run from the repository root

*Snippet 1. Prepare the House model inputs.*

```sh
Rscript 01_frame/scripts/09_model_house_votes.R prepare
```

## Outcome and predictors

Let $N$ be the district’s unrounded survey-weighted PUMS citizen-adult
population and $D$, $R$, and $O$ its 2024 Democratic, Republican, and Other
House candidate vote counts. For these three choices and No Vote, the observed
shares are

*Equation 1. Unconditional House shares of the citizen-adult population.*

$$
(q_D,q_R,q_O,q_0)=\frac{1}{N}(D,R,O,N-D-R-O).
$$

A citizen who cast a presidential vote and left the House contest blank
falls in the fourth group. [Office-specific vote classification](07_prepare_area_returns.md)

Both district maps cover 435 House seats plus DC’s delegate seat. The four outcomes are available for 434 districts on the 2024 map. FL-20 and OK-03 have missing counts and shares because their unopposed winners took office without a tabulated general-election contest. A tabulated contest with zero votes for one party retains its observed zero. The validation script assigns the training and holdout districts and derives its three conditional outcomes from the counts. [Validation split, endpoints and predictors](09_validate_house_beta.md)

The tables carry all 29 district demographic shares across age, recorded sex, race, Hispanic ethnicity and education. The four presidential shares use the state’s citizen-adult denominator. Each candidate party receives its own 0/1 incumbency flag. It is one when any eligible nominee from that party was serving in Congress before the election. For example, a contest between two Democrats contributes one Democratic outcome, two Democratic nominees and one incumbency flag. [District demographics](08_build_district_predictors.md) · [Candidate rosters](08_house_slates.md)

## Districts on the 2026 map

Every CD120 target uses its own district demographics. The block comparison and availability of 2024 returns establish which lineup accompanies it.

For modeled redrawn districts, we assume that if the 2026 district boundaries had been in place for the 2024 election, the nominees would have been the same people who ran in those districts in 2026. Evaluate incumbency for each of those nominees immediately before the 2024 general election. A nominee serving in the U.S. House at that point counts as an incumbent even if they represented a different district. A nominee who first entered the House after that election receives no incumbency credit for this scenario. Set each party's district-level incumbency flag if any of its nominees qualifies.

Step 08 builds the scenario roster from the November 4, 2024 House membership reference. The nominee audit records each match and the seat the person held. [Membership source and preparation](08_house_slates.md#which-years-lineup-enters-the-model)

*Table 1. CD120 lineup and source rules by district scenario.*

| Target districts | Prepared lineup and source flag |
|---|---|
| 290 exact matches with a tabulated 2024 contest | Use the matched CD119 district’s 2024 nominees. `observed_same_footprint` identifies where the 2024 counts are available. |
| 144 redrawn districts outside the special cases below | Use the reviewed 2026 nominees with 2024 incumbency. `model_redrawn` identifies a target requiring an estimate. |
| FL-20 and OK-03 | Use the declared 2024 winner as the sole named nominee for the hypothetical election. `model_unopposed_2024` identifies these two targets. |

The FL-20 scenario uses Democrat Sheila Cherfilus-McCormick with the population of the redrawn Florida district. OK-03 retains its footprint and uses Republican Frank D. Lucas. Both were sitting members of Congress. The script checks both names, parties and incumbency flags against the 2024 nominee audit. The target table carries scenario identifiers and predictors for future estimation. [Reviewed unpolled winners and official sources](09_unpolled_house_winners_2024.csv)

## Structural zeros in redrawn districts

Let $b_k$ indicate that party group $k$ has an eligible nominee on the
target slate. For each prediction draw with shares $q_k$, apply

*Equation 2. Transfer vote mass from absent party groups to No Vote.*

$$
q_k^{*}=b_k q_k\quad(k\in\{D,R,O\}),\qquad
q_0^{*}=q_0+\sum_{k\in\{D,R,O\}}(1-b_k)q_k .
$$

Compute means and intervals from the adjusted draws. The rule applies
to Democratic, Republican and Other in any redrawn district, including
the FL-20 scenario. OK-03 has the same footprint and keeps the model's
unadjusted shares. The separate adjusted holdout uses the same transfer
on predictions for the frozen 2024 districts and leaves their observed
returns as counted.

## Build and inspect the final CD120 shares

After preparing the model inputs, run from the repository root.

*Snippet 2. Fit and export the CD120 House shares.*

```sh
Rscript 01_frame/scripts/09_predict_house_cd120.R
```

The production fit uses all 434 tabulated 2024 contests and keeps its
checkpoints in `data/intermediate/09_house_cd120_fit/`. The 30-district
holdout is a separate validation run on the 2024 map.
Production defaults to a target acceptance of 0.995 and uses 0.999 for
any retry triggered by the existing diagnostics. The first production
no-vote fit had one divergence at 0.99. Its retry at 0.995 passed with
zero divergences.

*Table 2. Raw and ballot-adjusted CD120 share exports.*

| File under `data/output/` | Contents |
|---|---|
| `09_house_raw_shares_cd120.csv` | Observed shares and unadjusted model means. |
| `09_house_final_shares_cd120.csv` | Same observed shares and model means after the redrawn-district adjustment. |
| `09_house_cd120_sampler_diagnostics.csv` | Convergence status and effective sample sizes by stage. |

In the November 22, 2026 rebuild, all three production stages passed the
project’s diagnostic checks on their first attempt at a target acceptance
of 0.995. Each stage used four chains with 1,000 warmup and 500 retained
iterations per chain. The offline rerun reused those fits and reproduced
the same handoff files. [Rebuild summary](../README.md#latest-verified-rebuild)

Both share files have one row per district. Read `STATEFP` and `CDFP` as
text. The four share columns are proportions that sum to one. On
identical footprints with tabulated results, the script carries the
official 2024 candidate counts forward and divides by the CD120
citizen-adult population. The no-vote share is the remaining proportion.
Use `prediction_source` to identify those observations, the redrawn
predictions, and the two unopposed scenarios. A `provisional` fit status
indicates that a stage failed its diagnostic thresholds.

## Reading the district-by-party covariates

Open `01_frame/data/intermediate/09_house_party_inputs.csv`. Read `STATEFP` and `CDFP` as text to preserve their leading zeros. The key is `congress, STATEFP, CDFP, party`. There are 3,488 rows comprising four choices (`D`, `R`, `Other`, `DidNotVote`) for each district on each map. Each row contains the choice’s statewide presidential share and the district’s demographics. The three candidate groups also have `nominee_count`, `has_nominee` and `incumbent`. District CVAP repeats across the four rows and counts once per district.

`observed_share_2024` is filled for tabulated CD119 contests. CD120 rows carry their target predictors, the lineup year and the source flag described above. The separate wide training table has the vote counts needed to construct the conditional beta responses.

## Files and lineage

Paths are relative to `01_frame/data/`.

*Table 3. Inputs to the sequential House model and projection.*

| Input | Use |
|---|---|
| `intermediate/07_house_votes_cd119.csv` | Counts and tabulation status for the original district outcomes. |
| `intermediate/07_state_presidential_covariates_2024.csv` | State CVAP totals for reconciliation and four statewide presidential shares. |
| `intermediate/08_district_demographics.csv` | Unrounded population denominator and demographic margins for every district on each map. |
| `intermediate/08_house_slates_2024.csv`, `intermediate/08_house_slates_2026_incumbency_2024.csv` | Actual 2024 ballot and counterfactual ballot with 2026 nominees. Both use November 2024 incumbency. |
| `output/08_house_slate_nominees.csv`, [reviewed winner file](09_unpolled_house_winners_2024.csv) | Verify the sole nominees and their incumbency in FL-20 and OK-03. |
| `output/08_district_overlap.csv` | Establish which 2026 districts have an exact 2024 block-footprint match. |

*Table 4. House model products and their coverage.*

| Output | Contents |
|---|---|
| `intermediate/09_house_training_cd119.csv` | 436 original districts with counts, outcomes, missing-contest flags and predictors. |
| `intermediate/09_house_target_cd120.csv` | 436 target districts with predictors, footprint matches and lineup decisions. |
| `intermediate/09_house_party_inputs.csv` | District-by-party rows on both maps with observed outcomes where available. |
| `output/09_training_slate_counts.csv` | Counts of original districts by ballot configuration, candidate structure and reporting status. |
