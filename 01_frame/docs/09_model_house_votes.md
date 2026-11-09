# Estimate 2024 House voting on the 2026 district map

The active selection step is the [sequential beta comparison](09_compare_house_beta.md). Use this guide for the shared `prepare` stage and for reproducing the earlier Dirichlet fit and projections. A Dirichlet projection is not a result of the beta comparison.

## Plain-language summary

For every district, we want the share of citizen adults who voted Democratic, Republican or Other for the House, plus the share without a recorded House candidate vote. Step 09 fits one Dirichlet regression to the four shares from each tabulated 2024 contest. It scores predictions for 30 held-out districts, then refits on all 434 tabulated districts.

The covariate file has **one row per district and choice on each map**. Read its four rows together. The demographics describe the district, while the nominee count, incumbency and matching statewide presidential share describe the individual choice. If two Democrats ran against each other, the Democratic row records both nominees and their combined House votes. The final estimate matrix has one row per district and four share columns.

Where an old and new district contain exactly the same blocks and the 2024 votes are known, we carry the candidate counts forward. For redrawn districts we predict from their new population composition. The House returns give no vote totals for FL-20 and OK-03 in 2024. Their 2024 rows keep all four vote shares missing. Only on the 2026 map do we predict these districts, using their target populations and the verified 2024 winner as the sole named nominee. The model estimates all four shares under that hypothetical ballot. Actual 2026 turnout and public opinion lie outside this calculation.

## Run checkpoint, 8 November 2026

The Codespace run of Step 08 produced 872 district/map rows, 436 for each map including DC. Both maps represent 240,960,972 PUMS citizen adults. Each year's nominee roster covered 436 seats. Step 09 restored its R packages, compiled the Stan program, and reached warmup for the holdout fit. That run predated the Dirichlet share model and the unopposed-ballot scenarios. A fresh holdout fit and full refit are required to publish results for this specification.

Before restarting, review two parameter choices:

- Decide whether to express the four probabilities using a zero no-House-vote reference logit while keeping the matching presidential nonvoting effect. Subtracting the current nonvote utility from all four utilities preserves the fitted probabilities. Dropping its presidential slope is a separate change to the model.
- Decide whether to express the age effect with 13 independent contrasts and a sum-to-zero constraint on the 14 age coefficients. With the corresponding contrast prior this preserves the current predictions. The present model centers the age weights and puts a proper prior on all 14 coefficients.

The [current equations](09_house_model_math.md) include the party-specific incumbency predictor.

## Build and run

Run from the repository root. Step 07 supplies the voting data. Step 08
builds the demographic margins and lineups for both maps. The lockfile pins
`brms` 2.23.0 and `rstan` 2.32.7. The roster builder uses Python 3 and
`pdftotext`. R needs a C++ compiler for Stan.

```sh
Rscript -e 'renv::restore(prompt = FALSE)'
Rscript 01_frame/scripts/08_build_district_predictors.R
/usr/bin/python3 01_frame/scripts/08_prepare_house_slates.py
Rscript 01_frame/scripts/09_model_house_votes.R all
```

On an existing checkout with Step 08 district demographics, rerun the roster script and use `Rscript 01_frame/scripts/09_model_house_votes.R prepare` to inspect `09_house_party_inputs.csv` and the zero audit before sampling.
To inspect individual stages, use `prepare` to write the input tables, `fit`
to validate and refit the model, and `predict` to generate the district results.
Prediction checks that the saved full fit matches the current model and training
inputs. Generated data stay local under `01_frame/data/`.

## Outcome and predictors

The [model equations and priors](09_house_model_math.md) and the [generated Stan program](09_house_model_generated.stan) give the exact Step 09 specification.

Let `N` denote the district's unrounded, survey-weighted PUMS citizen-adult
population on the relevant map. Step 07 classifies the observed 2024 House
candidate votes into Democratic (`D`), Republican (`R`) and Other (`O`).
The observed shares divide each count by `N`. The fourth share is
`(N − D − R − O) / N`. It includes people who voted for another office and
left the House contest blank. It is an estimate because `N` is an estimate.

The Dirichlet model gives each district equal weight and requires four positive shares that sum to one. Following Hanretty’s reasoning, we give a reported zero the share of **one vote in an average U.S. House contest**. For each fit we add Democratic, Republican and Other votes within each training district, average those totals across training districts, and take the reciprocal. The 404 training districts determine the replacement for validation. The national refit uses 148,310,611 classified House candidate votes across all 434 tabulated districts, including DC. That is 341,729.52 votes per district, so one vote corresponds to a share of 0.000002926291, or 0.0002926291%. FL-20 and OK-03 contribute no turnout observations to this calculation. [Hanretty (2021), section 3.2](https://chrishanretty.co.uk/pubs/10.1016_j.ijforecast.2021.03.007/fulltext.pdf#page=7)

If a district has two zeros, for example, we give each that one-vote share and distribute the rest among the two positive choices in their original proportions. A district with four positive shares enters the likelihood exactly as observed. The raw shares and official counts remain available in the published tables.

Across the 434 tabulated 2024 elections, 208 districts reported zero candidate votes for at least one party group. There were 19 Democratic zeros, 16 Republican zeros and 186 Other zeros. The zero audit includes every choice, including the residual, and records its raw and fitted values. The zero-replacement convention can influence estimates when many districts report zero, because the Dirichlet likelihood uses log shares. For an exact observed zero, the Dirichlet’s theoretical central 90% predictive interval excludes zero. Scoring against the raw outcomes makes this limitation visible in the reported coverage. FL-20 and OK-03 have unknown outcomes and enter neither the zero adjustment nor fitting or scoring. [Response equations](09_house_model_math.md#response-and-likelihood)

| Predictor | Model coding |
|---|---|
| Recorded sex | Female share, with male as the reference. |
| Education | Shares with no high-school diploma, some college, a two-year degree, a four-year degree or postgraduate education. High-school graduates form the reference. |
| Race | Black, Native American, Asian and Other/Multi shares, with White as the reference. |
| Hispanic ethnicity | Hispanic share, with non-Hispanic as the reference. Race and ethnicity retain their separate PUMS definitions. |
| Age | Thirteen five-year bands from 18–22 to 78–82 and one open-ended 83+ band. Each district's age distribution weights its age-band effects. |
| State | Partially pooled state effects, including DC. |
| State presidential vote | Each of the four House choices has its own slope for its matching **2024 presidential share**. Step 07 divides the three presidential candidate counts by the state's PUMS CVAP. The fourth share is the remaining share without a presidential candidate vote. |
| House lineup | Nominee groups and a directional contrast identifying the major party in a one-major-party contest. |
| Candidate incumbency | A 0/1 indicator for whether at least one eligible nominee for the corresponding party was serving in Congress immediately before that election. Democratic, Republican and Other flags enter their own choice's equation. |

Step 08 produces all 29 demographic shares. Omitting one reference category
from each non-age demographic family avoids exact collinearity.
[Demographics on both maps](08_build_district_predictors.md)

### Candidate groups

| 2024 nominee configuration | Group in the model | Tabulated districts |
|---|---|---:|
| Democratic and Republican | `D_vs_R` (reference) | 272 |
| Democratic, Republican and Other | `D_vs_R_vs_Other` | 127 |
| Democratic only or Republican only | `main_party_uncontested` | 27 |
| Democratic and Other or Republican and Other | `main_party_missing` | 8 |
| Other only | Outside the fitted groups | 0 |

Two Democrats running against one another count as Democratic only for this
party grouping. The roster retains the number of distinct nominees. In
either one-major-party group, a shared directional contrast takes +1 for
Democratic and −1 for Republican. It takes zero when both major parties run.
This lets the model pool rare configurations while distinguishing which major
party was present. An Other-only lineup requiring a prediction would need
review. In 113 tabulated districts with no named Other nominee, classified Other votes totaled 128,514. Twelve of the 20 tabulated races with only one named nominee recorded votes for Other. Write-ins can count for a party without a listed nominee. The model therefore allows a party to receive a positive share when it has no named nominee. This applies to the FL-20 and OK-03 projections as well.
[Nominee sources and ballot audit](08_house_slates.md)

### Candidate incumbency

The training data use the 2024 roster. In CA-34, Jimmy Gomez and David Kim both ran as Democrats. Gomez was a sitting member, so the two candidates' votes are added in the Democratic outcome and the Democratic incumbency flag is 1. In CA-12, the two Democrats were Lateefah Simon and Jennifer Tran. Neither was a sitting member, so the same lineup group has a Democratic flag of 0. Each district still contributes one observation. [House candidate sources and audit](08_house_slates.md)

The model learns one incumbency effect from the 2024 contests and applies it to the party fielding the sitting member. This is a modeling assumption. In particular, the 2024 roster has no sitting Other nominee from whom to learn a separate effect. Sharing the coefficient lets a 2026 Other nominee who is a sitting member receive the same estimated effect. The no-House-vote outcome has no incumbency term. Its predicted share can still change because the four shares sum to one.

Chris Hanretty's work on multiparty constituency vote shares motivates using a joint share model. Here the U.S. incumbency indicator comes from the nominee roster for the relevant election. [Hanretty, *Forecasting multiparty by-elections using Dirichlet regression* (2021)](https://doi.org/10.1016/j.ijforecast.2021.03.007)

### Four linked choices

The district shares follow a Dirichlet distribution. Four linear
predictors determine the mean shares through a softmax transformation, which
makes them add up to one. A fitted concentration parameter controls variation
around those shares. Each linear predictor uses exactly one election-share
covariate, namely the matching Democratic, Republican, Other or no-candidate-vote
presidential share. The no-House-vote choice serves as the reference for the
intercepts, demographics, state, age, lineup and incumbency effects. Its own presidential
slope is estimated. The script checks the fixed-effects model matrices that
`brms` generates. [Model family documentation](https://paulbuerkner.com/brms/reference/brmsfamily.html)

Age enters through all 14 shares together. A district with a larger share of
18–22-year-olds than the training average gives extra weight to that band's
effect. Training-set means center the band shares, and one common training
scale preserves their relative weights. Band effects share an estimated
variance within each nonreference choice, with no assumed age ordering.
Non-age demographic and presidential shares use their training means and
standard deviations. [Weighted group effects in brms](https://paulbuerkner.com/brms/reference/mm.html)

Priors are Student-t(4, 0, 2.5) for fixed slopes, Student-t(4, 0, 3) for
intercepts, half-Student-t(4, 0, 1) for group standard deviations, and
lognormal(3, 1.5) for concentration. The validation fit and full fit each run
four chains. Sampler diagnostics check divergences, tree depth, R-hat and
effective sample sizes before the fit can supply predictions.

## Holdout validation and full refit

1. Sort the 434 eligible district identifiers. Always hold out Alaska,
   Delaware, North Dakota, South Dakota, Vermont and Wyoming, plus DC's
   delegate district. Sample another 23 districts without replacement from the
   remaining eligible seats using seed `20241105`. Save the 30 identifiers
   and fit on the other 404.
2. Predict the four House shares on the held-out **2024 boundaries** with
   their 2024 lineups and incumbency flags. For a jurisdiction absent from training, draw a state
   effect from the fitted distribution of state effects. Use the posterior
   mean as the point estimate and the 5th and 95th percentiles of posterior
   predictive district outcomes as the 90% interval. The interval conditions
   on the estimated district population and demographics.
3. For a benchmark, predict each district's House share using just the state's
   matching presidential share. For each choice, the 365th smallest absolute
   benchmark error among the 404 training districts sets its 90% interval
   radius. Clip the endpoints to [0, 1].
4. Score both sets of predictions separately for each choice. Report bias
   (mean predicted minus observed) and RMSE in percentage points, Spearman
   rank correlation, and the count and percentage inside the 90% predictive
   interval. Each of the four plots puts predictions on the x-axis, observed
   shares on the y-axis and displays both methods' horizontal intervals and
   scores. The seven fixed jurisdictions are deliberately overrepresented.
   Every held-out district gets equal weight in these scores. Both methods use the raw observed shares, including exact zeros. The two unpolled seats contribute no validation outcomes.
5. Refit on **all 434 observed contests**, including the 30 validation
   districts. Use this fit for the final estimates.

## The two unopposed 2024 scenarios

The Clerk records Sheila Cherfilus-McCormick (Democrat, FL-20) and Frank D. Lucas (Republican, OK-03) as elected without tabulated House votes. Both were sitting members. For each of these contests the CD119 file keeps four missing vote shares, covers the district’s population and records the actual nominee and incumbency. Only the 434 tabulated elections enter fitting and validation. [2024 House election statistics](https://clerk.house.gov/member_info/electionInfo/2024/statistics2024.pdf) · [Clerk nominee roster and service marks](https://clerk.house.gov/member_info/electionInfo/2024/119-nominations.pdf) · [Cherfilus-McCormick](https://clerk.house.gov/Members/C001127) · [Lucas](https://clerk.house.gov/Members/L000491)

For the **CD120 projections**, we ask how residents of each target district might have voted if the 2024 winner had appeared as the sole named nominee. New FL-20 uses its full redrawn population, Florida’s 2024 presidential shares and a one-Democrat lineup with Democratic incumbency = 1. OK-03 uses its target population, Oklahoma’s presidential shares and a one-Republican lineup with Republican incumbency = 1. In both cases the other two party groups have zero nominees and incumbency = 0. The district number identifies the hypothetical ballot. Step 08 also preserves FL-20’s actual 2026 three-party roster.

The ordinary model supplies all four predicted shares, just as it does when predicting a tabulated unopposed contest in validation. Having one named nominee affects the predictors. A write-in can still receive a vote, and the fitted shares for Democratic, Republican, Other and no House candidate vote sum to one. We publish those four means directly. The two sets of predictions appear only on CD120.

## Districts on the 2026 map

For carrying observed counts, Step 08 requires the full old and new block footprints to agree in both directions, even across a district renumbering. The final estimates cover 435 voting districts and DC. State sums can differ from the recorded House totals where districts have modeled results. [Census 119th Congress geography](https://www.census.gov/geographies/mapping-files/2025/dec/rdo/119-congressional-district-bef.html) · [Census 120th Congress geography](https://www.census.gov/geographies/mapping-files/2027/dec/rdo/120-congressional-district-bef.html)

| 2026 district situation | Districts | How its final row is calculated |
|---|---:|---|
| Identical footprint, observed 2024 return | 290 | Carry the three official counts, divide by the target district’s PUMS CVAP, and calculate the residual share. |
| Redrawn footprint, ordinary projection | 144 | Predict all four shares using the new population composition, 2024 state presidential shares, and 2026 lineup and incumbents. |
| Redrawn FL-20 | 1 | Use FL-20’s new population, Florida’s 2024 presidential shares and the 2024 Democratic-incumbent-only scenario. |
| Identical unpolled OK-03 | 1 | Use the target population, Oklahoma’s 2024 presidential shares and the 2024 Republican-incumbent-only scenario. |

## Reading the district-by-party covariates

In `09_house_party_covariates.csv`, the unique key is `congress, STATEFP, CDFP, party`. The four values of `party` are `D`, `R`, `Other` and `DidNotVote`. For example, the four rows for the original FL-20 describe the district’s population and its actual 2024 nominee. All four original vote shares are missing. Its Democratic row has one nominee and an incumbency flag of 1. Republican and Other each have zero nominees and a flag of 0. The no-House-vote row has no applicable nominee count or incumbency flag.

The field `state_presidential_share` follows the choice on the row. The 29 demographic shares and `cvap` repeat across the four rows, so count each district’s CVAP only once when summing populations. `lineup_year` identifies the source election for the lineup and `unopposed_party` identifies the designated winner’s party in the two scenarios. `observed_share_2024` is populated for tabulated CD119 elections only. Consult `outcome_source` to distinguish tabulated, missing, carried and predicted outcomes. On CD119, `house_share` holds 434 observed compositions. Its eight rows for FL-20 and OK-03 retain missing values. On CD120, all 436 districts have four shares that sum to one and match the corresponding columns in `09_house_final_shares_cd120.csv`. The preparation-stage `09_house_party_inputs.csv` lets you inspect the covariates and observed outcomes before fitting.

## Files and lineage

Paths are relative to `01_frame/data/`.

| Input or output | Role |
|---|---|
| `intermediate/07_house_votes_cd119.csv` | 2024 House candidate counts and reporting status. Supplies district outcomes and the official counts carried to identical footprints. |
| `intermediate/07_state_presidential_covariates_2024.csv` | The four statewide presidential shares used as predictors and as the validation benchmark. |
| `intermediate/08_district_demographics.csv` | District population denominators and demographic margins on both maps. |
| `intermediate/08_house_slates_2024.csv`, `intermediate/08_house_slates_2026.csv` | Reviewed nominee counts, party groupings and three party-specific incumbency flags for each district and election. |
| `output/08_house_slate_nominees.csv` and tracked [unpolled winners](09_unpolled_house_winners_2024.csv) | Verify that each declared winner was the sole eligible nominee, under the named party, with the stated pre-election incumbency flag. |
| `output/08_district_overlap.csv` | Block evidence identifying exact matches between district footprints. |
| `intermediate/09_house_party_inputs.csv` | Preparation-stage district-by-party covariates, with original observed shares where available. The file contains 3,488 rows, four choices for each of 436 districts on each map, including DC. |
| `intermediate/09_house_party_covariates.csv` | Final district-by-party file. It adds `house_share` using CD119 observed returns where available and the complete CD120 share matrix. |
| `intermediate/09_house_training_cd119.csv`, `intermediate/09_house_target_cd120.csv` | Inspectable inputs on each map. The 2024 table retains the two flagged missing contests. |
| `output/09_dirichlet_zero_audit.csv` | Records raw zeros and their fitting replacements. The replacement is estimated again from 404 districts when fitting the validation model. |
| `output/09_training_slate_counts.csv` | Grouped and original 2024 configurations by candidate structure and tabulation status. |
| `output/09_holdout_districts.csv`, `output/09_holdout_predictions.csv`, `output/09_holdout_scores.csv`, `output/09_holdout_plots.pdf` | The 30-district test roster, both methods' predictions and intervals, eight rows of scores and four plots. |
| `output/09_holdout_sampler_diagnostics.csv`, `output/09_full_sampler_diagnostics.csv` | Sampler checks for each fit. |
| `intermediate/09_house_full_fit.rds` | Full fitted model, training inputs, seed and model-source fingerprints. |
| `intermediate/09_house_final_shares_cd120.csv` | One row per district keyed by `STATEFP,CDFP`, with shares `dem,rep,other,did_not_vote` that sum to one. |
| `output/09_house_district_status.csv` | Source of each final row, its matched old district where available, whether prediction was needed and the lineup year used. The incumbency flags and lineup year identify the chosen roster. For a carried seat these describe the matched 2024 contest; its shares come directly from counts. |
