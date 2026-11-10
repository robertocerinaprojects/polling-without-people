# Validate sequential beta regressions for 2024 House vote shares

## What the model predicts

For each district on its 2024 boundaries we estimate four shares of its citizen voting-age population (CVAP). Consider a district with 100 citizen adults, 30 Republican House votes, 24 Democratic votes and six Other votes. The model first estimates the fraction with no counted House candidate vote (40/100), then the Republican fraction of House votes (30/60), then the Democratic fraction of the votes left (24/30). Multiplying these fractions back together gives 40% without a counted vote, 30% Republican, 24% Democratic and 6% Other. Each of the three steps is an ordinary beta regression in `brms`.

The input has one row per district. Its CVAP, $N_i$, is the unrounded sum of PUMS person weights allocated to that 2024 district. Electoral returns supply $R_i,D_i,O_i$, the **counts** of votes classified as Republican, Democratic and Other. Define $V_i=R_i+D_i+O_i$ and $H_i=N_i-V_i$. The informal label “stay home” means $H_i/N_i$. Someone who voted only for president also falls into this group. Uncertainty in the PUMS estimate of $N_i$ is not propagated through the model. [CVAP construction](08_build_district_predictors.md) · [Classification of votes](07_prepare_area_returns.md)

| Stage | Observed response $q_{ij}$ | Development districts used | State presidential share used |
|---|---|---:|---|
| H. No counted House candidate vote | $H_i/N_i$ | 404 | No counted presidential candidate vote |
| R. Republican among counted House votes | $R_i/V_i$ | 404 | Republican |
| D. Democratic among Democratic and Other votes | $D_i/(D_i+O_i)$ | 398 | Democratic |

Republicans received 74,844,655 counted House votes, Democrats 71,039,742 and Other candidates 2,426,214 across the 434 tabulated contests. This ranking fixes the R, D, Other order. FL-20 and OK-03 had no tabulated 2024 election. Their outcomes remain missing and they enter neither training nor evaluation. Seven districts with observed returns have an empty $D_i+O_i$ pool. Six are training districts and one, TX-01, is in the holdout. An empty pool removes only that district's stage-D **response**. We can still predict its four shares from its covariates.

## Likelihood and treatment of boundary shares

For $j\in\{H,R,D\}$ and each district with a defined stage response,

$$
q^*_{ij}\mid\mu_{ij},\phi_j
 \sim \operatorname{Beta}(\mu_{ij}\phi_j,(1-\mu_{ij})\phi_j),
\qquad
\operatorname{logit}(\mu_{ij})=\eta_{ij}.
$$

Each stage estimates a separate positive precision $\phi_j$, common to all districts within that stage. The conditional variance is $\mu_{ij}(1-\mu_{ij})/(1+\phi_j)$. Each eligible district supplies one likelihood term per stage. Its number of voters enters the fractions above and does not weight the regression. [brms beta parameterization](https://paulbuerkner.com/brms/articles/brms_families.html)

Exact zeros and ones require special treatment for an ordinary beta likelihood. Let $\delta=1/\operatorname{mean}_{i\in\mathrm{development}}V_i$. Each fit replaces an observed zero with $\delta$ and an observed one with $1-\delta$, and uses interior observations as recorded. The 404 development districts averaged 341,144.16 counted House votes, so $\delta\simeq0.0000029313$ as a proportion. This is a one-vote adjustment at the average **training** district size. All holdout scores use the original four shares, including their exact zeros. [Hanretty's boundary adjustment, section 3.2](https://chrishanretty.co.uk/pubs/10.1016_j.ijforecast.2021.03.007/fulltext.pdf#page=7)

## The predictors in each equation

Let $T_j$ be the development districts with a defined stage-$j$ response. For a numeric predictor $x$, let $z_j(x)=(x-\bar x_j)/s_{xj}$, where $\bar x_j$ and $s_{xj}$ are its mean and sample standard deviation across $T_j$. Districts get equal weight in these calculations. The held-out district is transformed with these same training values. The rule applies to every varying share, the presidential predictor, the party-lineup contrasts and the 0/1 incumbency indicator. A constant fixed-effect column cannot identify a slope and is omitted. Preparing a walk requires variation in each of its component shares. The presidential curve requires at least five distinct training values. A state code identifies a group.

| Term | Variables | Stages |
|---|---|---|
| Recorded sex | Female share (`sex_female`). Reference is male. | H, R, D |
| Race | Black, Native American, Asian, and Other/Multi shares (`race_black`, `race_native`, `race_asian`, `race_other_multi`). Reference is White. | H, R, D |
| Hispanic ethnicity | Hispanic share (`eth_hispanic`). Reference is non-Hispanic. | H, R, D |
| Age | Fourteen district shares in order: 18–22, 23–27, 28–32, 33–37, 38–42, 43–47, 48–52, 53–57, 58–62, 63–67, 68–72, 73–77, 78–82 and 83+. All fourteen have effects. | H, R, D |
| Education | Six district shares in order: no high-school diploma, high-school graduate, some college, two-year degree, four-year degree, postgraduate. All six have effects. | H, R, D |
| State | District's state or DC (`STATEFP`), with one random intercept per state in each regression. | H, R, D |
| State presidential result | Smooth of the corresponding statewide 2024 share: `pres_none`, `pres_rep` or `pres_dem`. Each share uses the full statewide citizen-adult denominator, including in stages R and D. | H, R, D |
| Ballot lineup | Fixed comparisons to D versus R, defined below from the 2024 House nominees. | R, D |
| Focal party incumbency | `incumbent_rep` for R and `incumbent_dem` for D. The raw value is 1 if at least one nominee from **that party** was serving in Congress on the eve of the election (including DC’s delegate) and 0 otherwise. | R, D |

For district $i$ let $X_{ij}$ contain the six standardized sex, race and ethnicity shares in the first three rows. Let $Z^A_{ij}$ and $Z^E_{ij}$ be the standardized age and education vectors. Define the demographic contribution for each stage as

$$
G_{ij}=X_{ij}^{\mathsf T}\beta_j+
       (Z^A_{ij})^{\mathsf T}\theta^A_j+
       (Z^E_{ij})^{\mathsf T}\theta^E_j.
$$

Let $s(i)$ be the district's state or DC, $P_{s,j}$ the corresponding state presidential share, $L_{ij}$ the standardized lineup contrasts and $I_{i,j}$ the focal party incumbent indicator. The complete linear predictors are

$$
\begin{aligned}
\eta_{iH}
 &=\alpha_H+G_{iH}+u_{s(i),H}+f_H\!\left(z_H(P_{s(i),H})\right),\\
\eta_{iR}
 &=\alpha_R+G_{iR}+u_{s(i),R}+f_R\!\left(z_R(P_{s(i),R})\right)
        +L_{iR}^{\mathsf T}\gamma_R+\lambda_R z_R(I_{i,R}),\\
\eta_{iD}
 &=\alpha_D+G_{iD}+u_{s(i),D}+f_D\!\left(z_D(P_{s(i),D})\right)
        +L_{iD}^{\mathsf T}\gamma_D+\lambda_D z_D(I_{i,D}).
\end{aligned}
$$

Each stage has its own coefficients, state effects, smooths and precision. All district demographic shares describe the entire district CVAP even when the **response** is conditional on voting for a candidate. The coefficients describe associations across districts. For example, the R-stage female-share coefficient estimates how the Republican share among House voters varies with district sex composition.

### Ballot lineup and incumbency

Each row of the table gives four **raw** contrast values. The first three capture the structure of the contest. The last distinguishes which major party is on the ballot whenever only one appears. This lets, for example, a district with a Republican as its only nominee have a different expected Republican share from one with a Democrat as its only nominee.

| 2024 nominees by party | D + R + Other | One major party alone | One major party + Other | Direction |
|---|---:|---:|---:|---:|
| D and R (reference) | 0 | 0 | 0 | 0 |
| D, R and Other | 1 | 0 | 0 | 0 |
| D alone | 0 | 1 | 0 | +1 |
| R alone | 0 | 1 | 0 | −1 |
| D and Other | 0 | 0 | 1 | +1 |
| R and Other | 0 | 0 | 1 | −1 |

Nominees are grouped by party. Two Democrats running against each other are a D-only lineup. If either is a sitting member of Congress, the Democratic incumbency indicator is one. At identical demographic and presidential values, comparing this lineup with and without a Democratic incumbent changes the D-stage log-odds by $\lambda_D/s_{I,D}$. The same reading applies to Republican incumbency in R. Centering the indicators changes the intercept, while the underlying reference comparisons remain D versus R and no focal incumbent. [Nominees and incumbency](08_house_slates.md)

### Ordered age and education effects

Each district has residents in many age bands and education categories. It enters the model once with **all** its shares. For each stage and each ordered block $g$ (age with $K=14$, education with $K=6$), model the differences between neighboring effects:

$$
d^g_{jh}=\theta^g_{j,h+1}-\theta^g_{jh},\qquad
d^g_{jh}\mid\tau_{jg}\overset{\rm iid}{\sim}\mathcal N(0,\tau_{jg}^2),
\qquad \sum_{b=1}^{K}\theta^g_{jb}=0.
$$

This is a first-order random walk (RW1). A smaller $\tau_{jg}$ lets adjacent effects borrow more from one another. The data can support larger changes or a reversal in direction. The sum-to-zero constraint identifies the overall level while allowing every category an effect, including the youngest age group and the lowest education category. One band is one step in the ordering, including the open-ended 83+ band. Smoothing operates on coefficients for a **one-standard-deviation** change in each share. For a one-percentage-point reallocation from band $b$ to band $c$, the change on the logit scale is $0.01(\theta^g_{jc}/s_{cj}-\theta^g_{jb}/s_{bj})$.

The code represents the walk with $K-1$ independent increments. The centered cumulative-sum matrix $B$ has entries $B_{bh}=\mathbf1(b>h)-(K-h)/K$. Then $\theta^g_j=B d^g_j$ and the weights on the increments in district $i$ are $(Z^g_{ij})^\mathsf T B$. Every raw composition sums to one. After separate standardization, each row satisfies $\sum_b s_{bj}Z^g_{ijb}=0$. The sum-to-zero constraint on the **coefficients** removes this dependency. The signed weights are supplied to `brms` without rescaling. [brms weighted group effects](https://paulbuerkner.com/brms/reference/mm.html)

### State, presidential curve and priors

State effects $u_{sj}\mid\sigma_j\overset{\rm iid}{\sim}\mathcal N(0,\sigma_j^2)$ pool states toward zero independently within stage. For a state present in training, prediction uses its posterior state effect. For a state absent from training, it draws a fresh effect from this fitted population distribution. All districts from the same new state share that draw in a given stage. The model uses the state identity alone to define this pooling.

Each $f_j$ is a centered natural cubic regression spline of the standardized stage-specific presidential share, `s(presidentialShare, bs = "cr", k = 5)`. The centering separates it from the intercept. A linear association is allowed, and a curvature penalty shrinks departures from a straight line. With five basis functions before centering, the usual full-rank design leaves one linear and three penalized components. The slope can vary over the range of statewide presidential shares. [mgcv cubic regression splines](https://stat.ethz.ch/R-manual/R-devel/library/mgcv/html/smooth.construct.cr.smooth.spec.html) · [brms smooth terms](https://paulbuerkner.com/brms/reference/s.html)

For each stage the independent priors are

$$
\begin{aligned}
\alpha_j &\sim t_4(0,3),&
\log\phi_j&\sim\mathcal N(3,1.5^2),\\
\beta_{jk},\,\gamma_{jk},\,\lambda_j,\,b_{\mathrm{linear},j}
    &\sim t_4(0,2.5),&
\sigma_j,\,\tau_{jA},\,\tau_{jE},\,\sigma_{f,j}
    &\sim t^+_4(0,1).
\end{aligned}
$$

Here $t_\nu(m,s)$ is a Student distribution with degrees of freedom $\nu$, location $m$ and scale $s$. A plus sign restricts a scale to be positive. $\gamma$ and $\lambda$ exist only in the party stages. In the spline basis used by `brms`, each penalized spline coefficient has a zero-mean Gaussian prior with standard deviation $\sigma_{f,j}$. The unpenalized spline component has the fixed-slope prior above. The stage precision pertains to the beta observations, distinct from the amounts of smoothing learned for the age, education and presidential terms.

## Reconstruct and validate four vote shares

For a draw $(a,b,c)$ from stages H, R and D in that order, compute

$$
p_H=a,\qquad p_R=(1-a)b,\qquad
p_D=(1-a)(1-b)c,\qquad p_O=(1-a)(1-b)(1-c).
$$

The four shares sum to one in every draw. The script pairs 500 independently sampled posterior draws from each stage. For point predictions the script reconstructs shares from draws of the stage means and averages them. For each 90% predictive interval it reconstructs shares from draws of new **beta outcomes** and takes the 5th and 95th percentiles. Only covariates from a held-out district go into any of its three predictions.

The frozen holdout includes Alaska, Delaware, North Dakota, South Dakota, Vermont, Wyoming, DC and 23 sampled districts (seed 20241105). Including all six single-district states and DC tests prediction in states entirely absent from training. The remaining 404 tabulated districts train the single model sequence. All parameter choices are fixed before evaluation. The reported scores apply to this particular holdout.

For each of H, R, D and Other, let $e_i=\hat p_i-p_i$ for the 30 held-out districts. The report includes

| Score | Calculation |
|---|---|
| Bias in percentage points | $100\,\operatorname{mean}(e_i)$. Positive bias means overprediction. |
| RMSE in percentage points | $100\sqrt{\operatorname{mean}(e_i^2)}$. |
| Spearman correlation | Correlation of observed and predicted ranks, averaging ties. |
| 90% predictive interval coverage (model only) | Fraction of observed shares inside the model's predictive interval, including its endpoints. |

The presidential baseline gives every district in a state the state's 2024 presidential share for that choice. Its three scores are bias, RMSE and Spearman correlation. The one-page, four-panel PDF plots predicted share on the horizontal axis and observed House share on the vertical axis. A district on the equality line was predicted exactly. Horizontal bars show the beta model's 90% predictive intervals.

The lineup shifts the predicted shares continuously. A party with no named nominee can receive a small positive prediction. In this holdout, 11 districts recorded **exactly zero** Other votes. A continuous beta model gives strictly interior central predictive intervals. The model's Other interval can therefore cover at most 19 of these 30 observations (63.3%), even if its point predictions for the zeros are very close. The CSV preserves those zeros so the plot and coverage score show this limitation.

## Inspect the district-by-party data

Step 09 preparation writes **`01_frame/data/intermediate/09_house_party_inputs.csv`**. Each district has four rows per map, one for each of `D`, `R`, `Other` and `DidNotVote`. The response column, `observed_share_2024`, is the choice’s share of district CVAP. The same row contains the district’s 29 demographic shares, the matching state presidential share and the ballot lineup. The three candidate choices also have party-specific nominee counts and incumbency. The 434 tabulated districts on the 2024 map (CD119) have observed shares. FL-20, OK-03 and all 2026-map rows (CD120) have missing outcomes in this input.

From the repository root, this shows the four choices for the first tabulated district and keeps the leading zeros in its geographic codes. Use `names(parties)` to see all demographic columns.

```r
parties <- read.csv("01_frame/data/intermediate/09_house_party_inputs.csv",
                    colClasses = c(STATEFP = "character", CDFP = "character"))
observed <- subset(parties, congress == 119 & !is.na(observed_share_2024))
head(observed[c("STATEFP", "CDFP", "party", "observed_share_2024", "cvap",
                "sex_female", "eth_hispanic", "state_presidential_share",
                "ballot_group", "incumbent")], 4)
```

For fitting, the driver reads the companion file `01_frame/data/intermediate/09_house_training_cd119.csv`, which keeps the vote counts on one row per district. On the training split, `beta_stage_targets()` calculates the no-candidate-vote share of CVAP, the Republican share of all counted candidate votes, and the Democratic share of Democratic plus Other votes. A zero remaining pool omits that district from the corresponding fit. The endpoint adjustment and predictor standardization happen during fitting. Other is the remainder after these three stages. The split CSV identifies the 404 training districts, 30 held-out districts and two unpolled districts.

## Run from the repository root

```bash
Rscript 01_frame/scripts/09_model_house_votes.R prepare  # if the CD119 training CSV is absent
Rscript 01_frame/scripts/09_validate_house_beta.R plan
Rscript 01_frame/scripts/09_validate_house_beta.R validate
```

`plan` prints the CPU allocation and sampling budget on the machine running R, checks the district data and writes the split. `validate` runs the three regressions in order. The input is `01_frame/data/intermediate/09_house_training_cd119.csv`.

To refresh the reports for the latest completed run from its saved predictions and open the four-panel PDF in Codespaces, run the following from the repository root. The report command reads the completed district predictions and requires no sampling.

```bash
Rscript 01_frame/scripts/09_validate_house_beta.R report
reports=01_frame/data/output/09_beta_holdout
code "$reports/$(cat "$reports/latest_complete.txt")/09_beta_holdout_plots.pdf"
```

Each stage has four chains. Each chain runs **1,000 warmup iterations and 125 sampling iterations** with no thinning. The four chains together supply **500 retained draws per stage**. These are raw draws. The effective sample sizes printed in the diagnostics measure how much independent information they contain. For each district the four point estimates and their 90% predictive intervals use the paired stage draws.

At startup, `parallelly::availableCores()` checks the CPUs available to the R process, including container limits. Up to four chains run concurrently. With one or two available cores the four chains run in batches. On larger machines with at least eight cores the sampler also assigns whole threads to each chain for the likelihood calculation, using static partitioning. For example, four cores run four chains with one thread apiece and eight cores run four chains with two threads apiece. The reported allocation is a CPU budget; actual utilization varies during compilation and sampling.

Stan prints the chain, iteration and phase every **10 iterations**, including warmup. Compilation precedes the first iteration. Timestamped messages identify the stage, eligible district count, cache reads, sampling attempts, diagnostics and report files. Running `validate` again under the same settings reuses completed checkpoints; an interrupted Stan chain starts again from the beginning of that stage. Sampling changes take effect when a new R process starts.

### Reading diagnostics and provisional results

For this analysis a parameter passes when its R-hat is **at most 1.05** and its bulk and tail effective sample sizes are **each greater than 100** across the four chains. Apply the cutoffs to the full-precision values. The check includes the fixed coefficients, state and random-walk effects and their scales, beta precision, and both the linear and penalized parts of the presidential spline. Each stage also needs 500 finite draws from the four chains, zero divergent transitions and zero hits at the maximum tree depth of 13.

A failed check on the no-House-vote or Republican stage triggers one retry with the same iterations and a higher target acceptance. The retry replaces the first attempt. If it also fails, the run reports the diagnostics and keeps the stage checkpoints for inspection.

The last stage splits the Democratic-plus-Other remainder. If its fit supplies usable draws but misses a diagnostic threshold, the script finishes scoring and labels the **Democratic and Other model results provisional** in the predictions and scores CSVs. The first two model outcomes and the state presidential benchmark do not depend on that last fit. A compilation error, missing chain or unusable prediction is reported as an execution failure; inventing the missing split would give misleading shares.

Results go under `01_frame/data/output/09_beta_holdout/<run-key>/`; the parent directory's `latest_complete.txt` names the latest run that published all reports, including one with a provisional final stage. The matching cache is under `01_frame/data/intermediate/09_beta_holdout_cache/<run-key>/`. The identifier connects the figure and its scored districts to the matching fit checkpoints.

Each fitted stage writes two small files alongside its checkpoint, for example `stage_1_none.stan` and `stage_1_none_parameters.csv`. Stages 2 and 3 use the stems `stage_2_rep` and `stage_3_dem`. The Stan file contains the program RStan stored with that fit. The CSV gives the parameter name, R-hat, both effective sample sizes and the pass flag. These files remain available after a successful run removes its large fit objects. Open a Stan file in the editor or run `less path/to/stage_1_none.stan` to read it in the terminal.

The [complete generated Stan program](stan/09_sequential_beta.stan) is available for reading before a fit. We generated it with the stage formulas, priors and static threading from the driver, using brms 2.23.0 and example district inputs. All three stages produced identical Stan text. In the likelihood, `Y` holds the stage-specific response, `Xc` holds the centered fixed predictors, and `Xs` and `Zs_1_1` supply the linear and penalized parts of the presidential curve. The three groups of random effects implement the age walk, education walk and state intercepts. Each stage receives its own data and estimates its own coefficients and precision. Use the checkpoint’s exported program to inspect a particular run.

| Run output | What it contains |
|---|---|
| `09_beta_district_split.csv` | District identifiers and the training, holdout or excluded assignment. |
| `09_beta_sampler_diagnostics.csv` | Per-stage sample size, endpoint adjustment and sampler checks. |
| `09_beta_holdout_predictions.csv` | Observed shares, point predictions and errors for both methods. Model rows also record interval endpoints, coverage indicators and sampler status. |
| `09_beta_holdout_scores.csv` | Bias, RMSE and Spearman correlation by choice and method. Model rows also record 90% predictive interval coverage and sampler status. |
| `09_beta_holdout_plots.pdf` | One page with four panels comparing the model and presidential baseline with the 2024 House results. |

Validation ends with the 2024 holdout. A refit on all tabulated districts and projections onto a new map belong to a later step.

## November 2026 holdout results

The [four-panel figure](../data/output/09_beta_holdout/3bf72b3e358bdf062b84/09_beta_holdout_plots.pdf) uses 30 held-out districts. The 404 training districts contributed no observations to the scores. The [district-level predictions](../data/output/09_beta_holdout/3bf72b3e358bdf062b84/09_beta_holdout_predictions.csv) give both methods’ point predictions for each district. The model also supplies a 90% predictive interval for each choice.

| Choice | Model RMSE (pp) | State presidential RMSE (pp) | Districts inside model’s 90% interval |
|---|---:|---:|---:|
| Democratic | 4.60 | 8.24 | 27/30 |
| Republican | 4.55 | 8.41 | 26/30 |
| Other | 0.86 | 3.70 | 19/30 |
| No counted House vote | 3.75 | 7.07 | 27/30 |

The [sampler audit](../data/output/09_beta_holdout/3bf72b3e358bdf062b84/09_beta_sampler_diagnostics.csv) records the result for each stage. The no-House-vote and Republican stages passed the prespecified checks. The Democratic-versus-Other stage recorded 1 divergent transition, 0 maximum-depth hits, a maximum R-hat of 1.038 and minimum bulk/tail effective sample sizes of 123/193. The predictions and scores CSVs record the sampler status for each outcome.

Run `3bf72b3e358bdf062b84` used R 4.3.3, mgcv 1.9-1 and brms 2.23.0. Each stage ran four chains with two threads apiece with 1,000 warmup and 125 retained iterations per chain. The training CSV’s SHA-256 matches the [independent preparation rebuild](../../docs/validation/e393b7f2-frame-rebuild/README.md).

A separate reproducibility check used R 4.5.3 and mgcv 1.9-3 from the project lockfile, with four single-threaded chains and the same data, seeds, draw budget and diagnostic rules (run `994cfc56d8ed1c587c1f`). The first stage had a minimum tail ESS of 92.6 on its initial fit. On its automatic retry, maximum R-hat was 1.068 and minimum bulk ESS was 83.1. This run stopped before scoring. The published figure and table above come from the completed R 4.3.3 run.
