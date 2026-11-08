# Estimate 2024 House voting on the 2026 district map

## Plain-language summary

For each district we want four shares of its citizen-adult population: Democratic
House voters, Republican House voters, other House voters, and people without
a recorded vote for a House candidate. Where the 2026 boundaries enclose
exactly the same area as a tabulated 2024 district, we already know the three
candidate counts. Where the boundaries changed, we use the new district's
PUMS demographics and its 2026 candidate lineup to estimate all four shares
for the **whole district**.

We learn the relationship from observed 2024 House elections on their 2024
boundaries. The model also uses each state's 2024 presidential shares. We test
it on 30 held-out districts and then refit on all 434 tabulated contests.
The final table covers 435 voting districts and the DC delegate district.
Each row sums to one. State totals calculated from the final table can differ
from recorded 2024 House totals because some district rows are predictions.

The two district maps describe the same 2020–2024 citizen-adult population.
The projection estimates how the 2024 voting relationship translates to the
new geography and lineup. Actual 2026 turnout and changes in public opinion
lie outside this calculation.

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

If the Step 08 products are already available, start with the last command.
To inspect individual stages, use `prepare` to write the input tables, `fit`
to validate and refit the model, and `predict` to generate the district results.
Prediction checks that the saved full fit matches the current model and training
inputs. Generated data stay local under `01_frame/data/`.

## Outcome and predictors

Let `N` denote the district's unrounded, survey-weighted PUMS citizen-adult
population on the relevant map. Step 07 classifies the observed 2024 House
candidate votes into Democratic (`D`), Republican (`R`) and Other (`O`).
The observed shares divide each count by `N`. The fourth share is
`(N − D − R − O) / N`. It includes people who voted for another office and
left the House contest blank. It is an estimate because `N` is an estimate.
For the count likelihood, we use the integer response
`(D, R, O, round(N) − D − R − O)`. A recorded zero is a valid outcome.
The two contests without recorded votes have missing outcomes and sit outside
the training and validation sets.

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
review. Write-ins in the observed returns mean a party can receive votes
without a named nominee. The lineup therefore influences the predicted
shares without forcing the other choices to zero.
[Nominee sources and ballot audit](08_house_slates.md)

### Four linked choices

The district counts follow a Dirichlet–multinomial distribution. Four linear
predictors determine the mean shares through a softmax transformation, which
makes them add up to one. A fitted concentration parameter controls variation
around those shares. Each linear predictor uses exactly one election-share
covariate: the matching Democratic, Republican, Other or no-candidate-vote
presidential share. The no-House-vote choice serves as the reference for the
intercepts, demographics, state, age and lineup effects. Its own presidential
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
   their 2024 lineups. For a jurisdiction absent from training, draw a state
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
   Every held-out district gets equal weight in these scores.
5. Refit on **all 434 observed contests**, including the 30 validation
   districts. Use this fit for the final estimates.

## Districts on the 2026 map

Step 08 compares the Census blocks on each map. For observed carry-forward,
a match requires the entire old and new footprint to agree in both directions,
including when a district number changes. [Census 119th Congress geography](https://www.census.gov/geographies/mapping-files/2025/dec/rdo/119-congressional-district-bef.html) · [Census 120th Congress geography](https://www.census.gov/geographies/mapping-files/2027/dec/rdo/120-congressional-district-bef.html)

| 2026 district situation | Districts | How its final row is calculated |
|---|---:|---|
| Identical footprint, observed 2024 return | 290 | Carry the three official candidate counts, divide by the target district's PUMS CVAP, and compute the remaining no-candidate-vote share. |
| Changed footprint | 145 | Give the full model the whole new district's PUMS demographics, state, 2024 state presidential shares and 2026 lineup. Use the posterior mean of each of the four shares. |
| Identical footprint, missing 2024 return | 1 | For OK-03, use the target's PUMS demographics and its verified Republican-only 2024 lineup. Its four shares estimate the outcome had that contest gone to a vote. |

**Florida example.** Old FL-20 had no tabulated House vote and supplies no
training outcome. For **new FL-20**, Step 09 takes a single row from the
district-augmented PUMS margins on the new map. The reviewed 2026 roster
lists one Democrat, one Republican and one Other nominee, so the model uses
the three-party group. It combines those inputs with Florida's state effect
and its four 2024 presidential shares to produce a single set of estimates
for the whole district. New FL-22 likewise gets its own demographics and
lineup. [Nominee sources](08_house_slates.md) · [Official 2024 House returns](https://clerk.house.gov/member_info/electionInfo/2024/statistics2024.pdf)

To see the new FL-20 result after a full run:

```r
final <- read.csv("01_frame/data/intermediate/09_house_final_shares_cd120.csv",
                  colClasses = c(STATEFP = "character", CDFP = "character"))
print(subset(final, STATEFP == "12" & CDFP == "20"))
```

## Files and lineage

Paths are relative to `01_frame/data/`.

| Input or output | Role |
|---|---|
| `intermediate/07_house_votes_cd119.csv` | 2024 House candidate counts and reporting status. Supplies district outcomes and the official counts carried to identical footprints. |
| `intermediate/07_state_presidential_covariates_2024.csv` | The four statewide presidential shares used as predictors and as the validation benchmark. |
| `intermediate/08_district_demographics.csv` | District population denominators and demographic margins on both maps. |
| `intermediate/08_house_slates_2024.csv`, `intermediate/08_house_slates_2026.csv` | Reviewed district nominee counts for each year and their party groupings. |
| `output/08_district_overlap.csv` | Block evidence identifying exact matches between district footprints. |
| `intermediate/09_house_training_cd119.csv`, `intermediate/09_house_target_cd120.csv` | Inspectable inputs on each map. The 2024 table retains the two flagged missing contests. |
| `output/09_training_slate_counts.csv` | Grouped and original 2024 configurations by candidate structure and tabulation status. |
| `output/09_holdout_districts.csv`, `output/09_holdout_predictions.csv`, `output/09_holdout_scores.csv`, `output/09_holdout_plots.pdf` | The 30-district test roster, both methods' predictions and intervals, eight rows of scores and four plots. |
| `output/09_holdout_sampler_diagnostics.csv`, `output/09_full_sampler_diagnostics.csv` | Sampler checks for each fit. |
| `intermediate/09_house_full_fit.rds` | Full fitted model, training inputs, seed and model-source fingerprints. |
| `intermediate/09_house_final_shares_cd120.csv` | One row per district keyed by `STATEFP,CDFP`, with shares `dem,rep,other,did_not_vote` that sum to one. |
| `output/09_house_district_status.csv` | Source of each final row, its matched old district where available, whether prediction was needed and the lineup year used. |
