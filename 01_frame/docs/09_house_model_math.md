# The district House vote model in Step 09

Each observed 2024 district contributes one vector of four vote shares. The four rows for that district in the district-by-party covariate file describe one composition. The regression relates that composition to district demographics, party lineups, incumbency and statewide presidential vote shares. A state effect lets districts in the same state resemble one another.

[Complete generated Stan program](09_house_model_generated.stan) · [R model and priors](../scripts/helpers/09_model.R) · [Inputs, validation and projection](09_model_house_votes.md)

## Response and likelihood

Let $N_i$ be district $i$’s unrounded PUMS citizen-adult population and $D_i,R_i,O_i$ its tabulated Democratic, Republican and Other House votes. The four **observed shares** are

$$
r_i = \frac{1}{N_i}(D_i, R_i, O_i, N_i-D_i-R_i-O_i).
$$

The residual estimates the share of citizen adults without a classified House candidate vote. The published returns supply no composition for FL-20 or OK-03. Their simulated results are separate from the 434 districts available for fitting and scoring.

The Dirichlet likelihood requires positive components. Hanretty (2021, section 3.2) gives an exact zero the share of one vote in an average election. We apply that convention to U.S. House races. Let $T$ be the districts used for this fit and $V_j=D_j+R_j+O_j$ the classified House candidate votes in district $j$. Each district in $T$ contributes once to the average. The replacement share is

$$
m_T=\frac{1}{|T|}\sum_{j\in T} V_j,\qquad \delta_T=\frac{1}{m_T}.
$$

For the validation model, $T$ contains the 404 training districts. For the final model, $T$ contains all 434 tabulated districts including DC, with 148,310,611 classified House votes. The national mean is 341,729.5184 votes per district, giving $\delta_T\approx 0.000002926291$ as a fraction, or 0.0002926291%. The denominator for the original vote shares is still the district's own CVAP. [Hanretty (2021), section 3.2](https://chrishanretty.co.uk/pubs/10.1016_j.ijforecast.2021.03.007/fulltext.pdf#page=7)

For a training row with $z_i$ exact zeros, the fitted response is

$$
y_{ik} =
\begin{cases}
r_{ik} & z_i=0,\\
\delta_T & z_i>0 \text{ and } r_{ik}=0,\\
(1-z_i\delta_T)\dfrac{r_{ik}}{\sum_{h:r_{ih}>0}r_{ih}} & z_i>0 \text{ and } r_{ik}>0.
\end{cases}
$$

Each exact zero in the training set gets the same value. The originally positive entries keep their relative proportions and together receive the remaining mass. The zero audit records the raw and adjusted values for each choice with an observed zero. Holdout scoring and carried returns use the original shares, including zeros.

With $s(i)$ denoting the state or DC and $\phi>0$ the common precision, the model is

$$
\pi_{ik}=\frac{\exp(\eta_{ik})}{\sum_{h=1}^4\exp(\eta_{ih})},
\qquad y_i \mid \pi_i,\phi \sim \operatorname{Dirichlet}(\phi\pi_i).
$$

Each district supplies one likelihood term with equal weight. Conditional on the predictors and parameters, the mean of share $k$ is $\pi_{ik}$, and its variance is $\pi_{ik}(1-\pi_{ik})/(1+\phi)$. CVAP supplies the denominator for the raw response. Posterior expected shares and predictive share draws come directly from this continuous model. [Stan Dirichlet distribution](https://mc-stan.org/docs/functions-reference/simplex_distributions.html)

## Four outcome equations

Let $x_i$ contain the 11 standardized demographic shares in the table below, $\ell_i$ the four lineup terms, $I_{ik}$ the indicator that at least one of party $k$'s nominees was serving in Congress immediately before the applicable election, $q_{ik}$ the standardized statewide presidential share matching House outcome $k$, and $w_{ib}$ the centered age weight for band $b$. Training-set means and sample standard deviations give each training district equal weight. A state presidential share appears once per district in that state when calculating these constants. The validation fit uses only its 404 training districts to estimate them. The final fit recomputes them from all 434 districts.

For each $k\in\{D,R,O\}$ the utility is

$$
\eta_{ik}=a_k+x_i^\mathsf{T}\beta_k+
(\ell_i-\bar\ell)^\mathsf{T}\delta_k+\lambda(I_{ik}-\bar I_k)+\gamma_k q_{ik}
+u_{s(i),k}+\sum_{b=1}^{14} w_{ib}v_{bk}.
$$

For the fourth outcome, $H$ (no House candidate vote),

$$
\eta_{iH}=\gamma_H q_{iH}.
$$

The intercept $a_k$ is the centered intercept in the generated Stan program. brms centers the fixed effects, including each party's lineup and incumbency columns. The previously standardized demographic and presidential columns have training means of zero up to floating-point precision. The no-vote utility has a free presidential slope and anchors its other coefficients at zero.

The training mean $\bar I_k$ is the proportion of training districts with a sitting nominee for party $k$. Changing that party's flag from 0 to 1 adds $\lambda$ to its utility, holding the other inputs fixed. For example, changing only the Republican flag multiplies $\pi_{iR}/\pi_{iD}$ by $e^\lambda$. The percentage-point change in Republican share depends on all four starting shares. Using the same $\lambda$ for Democrats, Republicans and Other lets a sitting Other candidate on the prediction map use the association estimated from the 2024 major-party incumbents.

| Input family | Coding |
|---|---|
| Recorded sex | Female share. Male is the reference. |
| Education | No high-school diploma, some college, two-year degree, four-year degree and postgraduate shares. High-school graduate is the reference. |
| Race | Black, Native American, Asian and Other/Multi shares. White is the reference. |
| Hispanic ethnicity | Hispanic share. Non-Hispanic is the reference. Ethnicity and race are separate variables. |
| Presidential vote | One share **per utility**: Democratic for D, Republican for R, Other for O, and no presidential candidate vote for H. Each uses the state's full PUMS citizen-adult denominator. |
| Lineup | Three 0/1 indicators for D/R/Other, a sole major party, and a sole major party plus Other. D versus R is the reference. A fourth term is +1 for D as the sole major party, −1 for R as the sole major party and 0 if both are present. The four terms retain these units. An Other-only ballot is outside the fitted groups. |
| Candidate incumbency | Each of D, R and Other uses its own 0/1 flag. The party gets one when at least one eligible nominee was a sitting member, even if multiple nominees ran. There is no incumbency term in the no-House-vote equation. |
| Age | Thirteen five-year bands from 18–22 through 78–82, plus 83+. Each district contributes to every band in proportion to the centered weight below. |

For a non-age demographic or presidential share $p_{ij}$, the standardized value is $(p_{ij}-\bar p_j)/s_j$ using its training mean and sample SD. The four presidential shares enter different utilities, so the model has no four-column presidential composition within any single utility. State effects and statewide predictors can still compete to explain between-state differences.

For raw district age shares $A_{ib}$ and training districts $T$,

$$
\bar A_b=\frac{1}{|T|}\sum_{i\in T} A_{ib},\quad
c_A=\sqrt{\frac{1}{|T|}\sum_{i\in T}\sum_b(A_{ib}-\bar A_b)^2},\quad
w_{ib}=\frac{A_{ib}-\bar A_b}{c_A}.
$$

All 14 weights share the same scale. Since every district's raw age composition sums to one, $\sum_b w_{ib}=0$. Adding a common constant to every age coefficient for one outcome leaves every prediction identical. The likelihood therefore sees at most 13 age contrasts. The code includes 14 age effects with a proper hierarchical prior. Their common direction is prior-only. A 13-dimensional orthonormal contrast basis could express the same age predictions and contrast prior with one fewer latent variable per candidate utility. The current model pools bands around zero independently and gives adjacent age bands the same prior relationship as distant ones.

## Priors and sampling

Student distributions below use location and scale. For each candidate utility, $a_k\sim t_4(0,3)$. All fixed slopes, including the single shared $\lambda$ and the four $\gamma_k$, have independent $t_4(0,2.5)$ priors. State and age effects are independent across their two families and the three candidate utilities. Given their scales,

$$
u_{sk}=\sigma_{u,k}z^u_{sk},\quad v_{bk}=\sigma_{v,k}z^v_{bk},\qquad
z^u_{sk},z^v_{bk}\overset{\mathrm{iid}}{\sim}\mathcal N(0,1).
$$

Each of the six scale parameters independently follows a half-$t_4(0,1)$. The common precision has $\log\phi\sim\mathcal N(3,1.5^2)$. The Stan file shows the non-centered random effects, centered fixed-effect intercepts, likelihood and transformed intercepts reported by brms.

The run fits 404 districts, scores 30 held-out districts, then refits on all 434 tabulated districts. Each fit uses four NUTS chains with at most two running concurrently. Each chain has 1,000 warmup and 1,000 retained iterations, with target acceptance 0.97 and maximum tree depth 13. Step 09 checks monitored parameters for maximum R-hat below 1.01, minimum bulk and tail effective sample sizes of at least 400 with four chains, zero post-warmup divergences and zero maximum-tree-depth hits. The files are `01_frame/data/output/09_holdout_sampler_diagnostics.csv` and `01_frame/data/output/09_full_sampler_diagnostics.csv`. These are sampling checks. The separate 30-district comparison against the presidential benchmark measures predictive accuracy.

## Verify the code from the saved national fit

The companion Stan source was generated from the R formula and priors with brms 2.23.0. The R helper specifies which incumbency column belongs to each candidate outcome. Look for `shared_incumbency` in the Stan file. One sampled parameter supplies the corresponding entry in `b_muD`, `b_muR` and `b_muOther`, and receives one prior. After a national refit, run the following from the repository root to inspect the fitted formulas and save their Stan program.

```r
saved <- readRDS("01_frame/data/intermediate/09_house_full_fit.rds")
print(stats::formula(saved$fit$model))
cat(as.character(brms::stancode(saved$fit$model)), file = "09_house_model_from_fit.stan")
```

[brms family documentation](https://paulbuerkner.com/brms/reference/brmsfamily.html) · [brms multiple-membership weights](https://paulbuerkner.com/brms/reference/mm.html)
