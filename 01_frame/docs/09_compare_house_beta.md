# Sequential beta regression for 2024 House shares

## What a district contributes

Consider a district with 100 citizen adults, 40 of whom cast no counted House vote. Of the remaining 60, suppose 30 voted Republican, 24 Democratic and six Other. The three regression responses are 40/100, 30/60 and 24/30. The four shares we want back are 40%, 30%, 24% and 6% of the district's citizen adults. The conditional Democratic share of 80% is an intermediate calculation.

Each row in `09_house_training_cd119.csv` represents a district on its **2024 boundaries**. Let $N_i$ be its unrounded, survey-weighted PUMS citizen-adult population and $R_i,D_i,O_i$ its tabulated House candidate votes. Define $V_i=R_i+D_i+O_i$ and $H_i=N_i-V_i$. The no-House-vote outcome includes someone who voted only for another office. $H_i$ is an estimate, since its denominator comes from PUMS.

The fixed order after no House vote follows the national 2024 House candidate totals. Across the 434 tabulated districts, Republicans received 74,844,655 votes, Democrats 71,039,742 and Other candidates 2,426,214. The 404 development districts give the same ordering. Each fold uses that order. [House returns and classification rules](07_prepare_area_returns.md)

| Stage $j$ | Question | Observed conditional response $q_{ij}$ | Included in that fit |
|---|---|---|---|
| 1 | What share of citizen adults cast no House candidate vote? | $H_i/N_i$ | $N_i>0$ with a tabulated contest |
| 2 | Among House candidate votes, what share went to Republicans? | $R_i/V_i$ | $V_i>0$ |
| 3 | Among Democratic and Other votes, what share went to Democrats? | $D_i/(D_i+O_i)$ | $D_i+O_i>0$ |

Seven tabulated districts had $D_i+O_i=0$. Six are in development and TX-01 is in the holdout. Each supplies information to the stages with a defined outcome. All 30 held-out districts can receive four predictions because prediction uses covariates alone. The two unpolled 2024 contests, FL-20 and OK-03, enter neither development nor evaluation.

## Likelihood and reconstruction

For each stage $j$ and district with a defined response, all three models use

$$
q_{ij}^{*}\mid\mu_{ij},\phi_j
\sim {\rm Beta}\big(\mu_{ij}\phi_j,(1-\mu_{ij})\phi_j\big),
\qquad
\mu_{ij}={\rm logit}^{-1}(\eta_{ij}).
$$

The precision $\phi_j$ is common to districts within a stage. The conditional variance of the response is $\mu_{ij}(1-\mu_{ij})/(1+\phi_j)$. Each district supplies one likelihood contribution per defined stage, regardless of the number of votes in its denominator. Conditional on the predictors and stage-specific parameters, the three beta fractions are modeled independently. The resulting **unconditional** shares are dependent because they divide up the same district population. [brms beta likelihood](https://paulbuerkner.com/brms/articles/brms_families.html)

An ordinary beta likelihood needs interior observations. In each training split define $\delta=1/\mathrm{mean}(V_i)$ using its tabulated training contests. For a defined conditional response use $\delta$ for an exact zero, $1-\delta$ for an exact one, and the raw fraction otherwise. An undefined fraction contributes no observation to its stage. The raw shares supply all validation targets. This extends our earlier one-vote boundary convention to both ends of a scalar proportion. [Zero-replacement motivation, section 3.2](https://chrishanretty.co.uk/pubs/10.1016_j.ijforecast.2021.03.007/fulltext.pdf#page=7)

With a draw $(a_i,b_i,c_i)$ in the stage order above, compute

$$
p_{iH}=a_i,\qquad p_{iR}=(1-a_i)b_i,\qquad
p_{iD}=(1-a_i)(1-b_i)c_i,\qquad
p_{iO}=(1-a_i)(1-b_i)(1-c_i).
$$

Thus Other receives the remainder. These four shares sum to one for every draw. For point predictions, combine stage draws of the conditional means and average the reconstructed shares. For 90% predictive intervals, combine draws of new beta outcomes and take each reconstructed share's 5th and 95th percentiles. No held-out district supplies its realized turnout or Republican share to predict a later stage.

## The three linear predictors

At each stage we use its own intercept, slopes, state effects, age effects and precision. Write $x_{ij}$ for the fixed predictors of district $i$ at stage $j$, $s(i)$ for its state or DC, and $w_{ijb}$ for its weight in age band $b$. For each of the three prior choices, the three distinct equations have the form

$$
\begin{aligned}
{\rm logit}(\mu_{iH})&=\alpha_H+x_{iH}^{\mathsf T}\beta_H+u_{s(i),H}+\sum_{b=1}^{14}w_{iHb}v_{Hb},\\
{\rm logit}(\mu_{iR\mid V})&=\alpha_R+x_{iR}^{\mathsf T}\beta_R+u_{s(i),R}+\sum_{b=1}^{14}w_{iRb}v_{Rb},\\
{\rm logit}(\mu_{iD\mid D+O})&=\alpha_D+x_{iD}^{\mathsf T}\beta_D+u_{s(i),D}+\sum_{b=1}^{14}w_{iDb}v_{Db}.
\end{aligned}
$$

| Part of $x_{ij}$ | Predictors |
|---|---|
| Recorded sex | Female share. Male is the reference. |
| Education | No high-school diploma, some college, two-year degree, four-year degree and postgraduate shares. High-school graduate is the reference. |
| Race | Black, Native American, Asian and Other/Multi shares. White is the reference. |
| Ethnicity | Hispanic share. Non-Hispanic is the reference. |
| Named nominees | Indicators for D–R–Other, one major party alone, and one major party plus Other. D versus R is the reference. A direction term is +1 when only D among the major parties runs, −1 when only R runs, and zero when both run. Two nominees of the same party count as one party group. |
| State presidential result | Stage 1 uses the 2024 statewide no-presidential-candidate-vote share. Stage 2 uses the Republican presidential share. Stage 3 uses the Democratic presidential share. All three are *marginal* shares of that state's citizen adults. |
| Party incumbency | Stage 1 uses an indicator for any sitting nominee. Stage 2 uses Republican incumbency and any Democratic-or-Other incumbent. Stage 3 uses Democratic incumbency and Other incumbency. A party indicator is one if at least one eligible nominee was already serving. A predictor constant throughout a stage's training data supplies no estimated slope. |

Age enters through partially pooled effects. The age bands are 18–22, 23–27, 28–32, 33–37, 38–42, 43–47, 48–52, 53–57, 58–62, 63–67, 68–72, 73–77, 78–82 and 83+. Their shares use the district citizen-adult population. State-level aggregate House vote and household income are absent from the design. The residual Other share has no fourth equation.

Every varying fixed predictor, including the lineup indicators, uses its training mean and sample standard deviation within the stage. The centered intercept therefore represents a district at those training means with zero random effects. A unit change in a standardized predictor is one training standard deviation. When a fold has no variation in a predictor, the fit omits it and applies that same design to its validation districts. In particular, the 2024 nominees supply no sitting Other candidate to identify a separate Other-incumbency slope at stage 3.

Let $T_j$ be the training districts with a defined stage-$j$ outcome and $n_j=|T_j|$. For district $i$ with age shares $A_{ib}$, define

$$
\bar A_{jb}=\frac{1}{n_j}\sum_{i\in T_j}A_{ib},\qquad
s_{Aj}=\sqrt{\frac{1}{n_j}\sum_{i\in T_j}\sum_b(A_{ib}-\bar A_{jb})^2},\qquad
w_{ijb}=\frac{A_{ib}-\bar A_{jb}}{s_{Aj}}.
$$

The weights sum to zero across age bands. A change common to all 14 age effects cancels, so their contribution identifies 13 contrasts. The model uses a proper prior on the 14 coefficients. Adjacent age bands receive the same prior treatment as any other pair of bands.

## How the three models differ

The three variants use identical responses, design columns, beta likelihood, and state and age hierarchy. Each stage has its own independent parameters. For **every** variant the common priors are

$$
\begin{aligned}
\alpha_j&\sim t_4(0,3), &\log\phi_j&\sim\mathcal N(3,1.5^2),\\
u_{sj}\mid\sigma_{u,j}&\sim\mathcal N(0,\sigma_{u,j}^2),&
v_{jb}\mid\sigma_{v,j}&\sim\mathcal N(0,\sigma_{v,j}^2),\\
\sigma_{u,j},\sigma_{v,j}&\stackrel{\mathrm{ind}}{\sim} t^+_4(0,1).
\end{aligned}
$$

The two random-effect families are independent, with independent effects within a family conditional on its scale. An unseen state's effect is drawn from the fitted state distribution. Districts from the same unseen state share that draw within a stage. In the equations below $k$ indexes a retained fixed slope, $t$ uses a location and scale, and $+$ restricts a scale to positive values.

### 1. Vanilla beta

$$
\beta_{jk}\stackrel{\rm ind}{\sim} t_4(0,2.5).
$$

This is the weakly informative benchmark. Each standardized slope has a heavy-tailed prior that lets the fit retain a large association. There is no tuning parameter for this variant.

### 2. Ridge beta

$$
\beta_{jk}\mid s \stackrel{\rm ind}{\sim}\mathcal N(0,s^2),\qquad
s\in\{0.35,1.00\}.
$$

For a fixed $s$, the negative log prior adds $\sum_{jk}\beta_{jk}^{2}/(2s^2)$ to the negative log likelihood, up to a constant. Smaller $s$ gives more shrinkage. One CV-selected $s$ applies across all three stages. State effects, age effects and intercepts keep the common priors above.

### 3. Regularized horseshoe beta

For a tuning value $r\in\{0.25,1.00\}$, each stage has its own global scale $\tau_j$, slab scale $c_j$ and local scales $\lambda_{jk}$:

$$
\begin{aligned}
\tau_j &\sim {\rm Cauchy}^{+}(0,r/\sqrt{n_j}),&
\lambda_{jk}&\sim {\rm Cauchy}^{+}(0,1),\\
c_j^2&=2^2 v_j,& v_j&\sim {\rm InvGamma}(2,2),\\
\widetilde{\lambda}_{jk}^2&=\frac{c_j^2\lambda_{jk}^2}{c_j^2+\tau_j^2\lambda_{jk}^2},&
\beta_{jk}\mid \tau_j,\lambda_{jk},c_j &\sim
\mathcal N(0,\tau_j^2\widetilde{\lambda}_{jk}^2).
\end{aligned}
$$

Here $r$ is the prior ratio of relevant to irrelevant slopes. The global scale pulls the slopes toward zero, local scales let individual signals escape that shrinkage, and the finite slab moderates exceptionally large slopes. Cross-validation chooses one $r$ for the sequence. This is `brms::horseshoe(par_ratio = r, scale_slab = 2, df_slab = 4)`. [brms regularized horseshoe](https://paulbuerkner.com/brms/reference/horseshoe.html)

## Validation and model selection

1. Reserve the same 30 districts as the earlier Step 09 comparison. They comprise the six at-large states, DC and 23 other districts selected with seed 20241105. This fixed test set gives extra weight to unseen states compared with a simple random sample of districts.
2. Assign the remaining 404 districts to five folds of 80 or 81, spreading each nominee lineup across folds. Five folds leave 323 or 324 districts for each inner fit while keeping the number of Stan fits manageable. For each of five prior settings, fit three regressions on four folds and reconstruct **four unconditional shares** for every district in the fifth. Compute the endpoint adjustment and predictor scales from the training split. On the 404-district fit, stages 1 and 2 use 404 rows and stage 3 uses 398.
3. Across the out-of-fold district predictions, compute the pooled percentage-point error
$$
 {\rm RMSE}_{\rm CV}=100\sqrt{\frac{1}{4\cdot404}
 \sum_{i=1}^{404}\sum_{k\in\{H,R,D,O\}}(\widehat p_{ik}-p_{ik})^2}.
$$
   Each district and each choice receives equal weight. Within each prior family keep the setting with the lowest score. Across families recommend the one with the lowest cross-validated score, with exact ties going to vanilla, then ridge, then horseshoe. This is a predictive criterion on the scale used in the analyses.
4. Refit each of the three finalists on the 404 development districts, then predict all 30 held-out districts once. Report the holdout results for all three and highlight whether they support the CV recommendation. Comparison ends here. A refit on all 434 districts and projection onto 2026 boundaries belong to the subsequent step.

For each choice, bias is $100\,{\rm mean}(\widehat p-p)$, RMSE is $100\sqrt{{\rm mean}((\widehat p-p)^2)}$, Spearman's $\rho$ compares ranks using average ranks for ties, and coverage is the fraction of original shares inside their inclusive 90% predictive intervals. Bias and RMSE are in percentage points. The presidential benchmark predicts each choice with its state's corresponding presidential share. Its marginal intervals use the 90% finite-sample rank of absolute benchmark errors in the 404 training districts and are clipped to $[0,1]$. The baseline interval uses training errors. The beta-model interval uses the posterior predictive distribution.

Eleven of the 30 held-out districts recorded exactly zero Other votes. Mathematically, a continuous beta sequence puts its central predictive intervals inside the unit interval. Its theoretical central intervals can therefore cover at most 19 of these 30 raw Other shares, even with good point predictions. Report Other coverage alongside pooled RMSE to make that limitation visible.

## Running the comparison

The single required input is `01_frame/data/intermediate/09_house_training_cd119.csv` from `09_model_house_votes.R prepare`. Run from the repository root.

~~~bash
Rscript 01_frame/scripts/09_compare_house_beta.R plan
Rscript 01_frame/scripts/09_compare_house_beta.R compare
~~~

`plan` validates the input and writes the split, party order and tuning grid. `compare` runs the same plan and fits 84 component regressions: 75 for cross-validation and nine for the 30-district comparison, before any diagnostic retries. The sampler starts with four chains of 2,000 iterations each, including 1,000 warmup, using at most two concurrent chains. Each fit checks R-hat below 1.01, bulk and tail effective sample sizes of at least 400, zero divergences and zero tree-depth-limit hits, including checks on estimated horseshoe scales. A failing stage gets one retry with 4,000 iterations per chain (2,000 warmup) and a higher target acceptance. If it still fails, the script identifies its saved diagnostic file and stops before recommending a model. Completed work is cached under `01_frame/data/intermediate/09_beta_cache/`. The run key includes the data, analysis code, relevant software versions and settings. Rerun the same command to continue after an interruption.

Results go to `01_frame/data/output/09_beta_comparison/<run-key>/`. The comparison prints the location. `latest_complete.txt` in the parent directory names the most recent completed run.

| File in the run directory | Contents |
|---|---|
| `09_beta_district_splits.csv`, `09_beta_party_order.csv`, `09_beta_prior_grid.csv` | District IDs, development folds, holdout selection, national House candidate totals and exact tuning values. |
| `09_beta_out_of_fold_predictions.csv`, `09_beta_cv_scores.csv`, `09_beta_cv_finalists.csv` | Predictions and 90% intervals from the fold that excluded each district, pooled RMSE for all settings, and the finalist for each family. |
| `09_beta_cv_scores_by_choice.csv`, `09_beta_cv_scores_by_fold.csv` | Bias, RMSE, rank correlation and interval coverage per choice for every setting, plus pooled RMSE for each fold. |
| `09_beta_holdout_vanilla.pdf`, `09_beta_holdout_ridge.pdf`, `09_beta_holdout_horseshoe.pdf` | Four pages per family, one per outcome. Each plots the observed share on $y$, predicted share on $x$, the $y=x$ line and horizontal 90% predictive intervals. Separate legends report four metrics for the fitted model and the state presidential benchmark. |
| `09_beta_holdout_scores.csv`, `09_beta_holdout_predictions.csv` | Four scores per choice and method, plus the underlying district predictions, interval endpoints, observed shares and benchmark. |
| `09_beta_recommendation.txt`, `09_beta_recommendation.csv` | The CV-selected family, its tuning setting and how its independent holdout performance compares with the other families and benchmark. |
