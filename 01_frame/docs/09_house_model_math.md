# The district House vote model in Step 09

Each 2024 district supplies one observation with four counts. We estimate how its demographic composition, party lineup and statewide presidential results relate to those counts. A state effect lets districts in the same state resemble one another. Four probabilities sum to one, and a common concentration parameter describes how much observed district shares can vary around those probabilities.

[Complete generated Stan program](09_house_model_generated.stan) · [R model and priors](../scripts/helpers/09_model.R) · [Inputs, validation and projection](09_model_house_votes.md)

## Response and likelihood

Let $i$ index a district, $s(i)$ its state or DC, $N_i$ its unrounded PUMS citizen-adult population, and $n_i=\operatorname{round}(N_i)$. In the order Democrat, Republican, Other, no House candidate vote, the response is

$$
y_i=(D_i,R_i,O_i,n_i-D_i-R_i-O_i).
$$

The first three entries are observed votes for this office. The last entry estimates citizen adults without a classified candidate vote. Scoring uses the unrounded denominator and the corresponding unrounded residual. FL-20 and OK-03 have missing House outcomes on the original map. They are excluded from fitting and scoring.

$$
\pi_{ik}=\frac{\exp(\eta_{ik})}{\sum_{h=1}^4\exp(\eta_{ih})},
\qquad
y_i\mid n_i,\pi_i,\phi\sim\operatorname{DirichletMultinomial}(n_i,\phi\pi_i),\qquad \phi>0.
$$

Equivalently, one could draw a district-specific probability vector from $\operatorname{Dirichlet}(\phi\pi_i)$ and then draw $n_i$ multinomial outcomes. The generated Stan program integrates out that vector. Its likelihood loops over districts. The variance of outcome $k$ is $n_i\pi_{ik}(1-\pi_{ik})(n_i+\phi)/(1+\phi)$. One precision $\phi$ serves all districts and choices.

## Four outcome equations

Let $x_i$ contain the 11 standardized demographic shares in the table below, $\ell_i$ the four lineup terms, $q_{ik}$ the standardized statewide presidential share matching House outcome $k$, and $w_{ib}$ the centered age weight for band $b$. Training-set means and sample standard deviations give each training district equal weight. A state presidential share appears once per district in that state when calculating these constants. The validation fit uses only its 404 training districts to estimate them. The final fit recomputes them from all 434 districts.

For each $k\in\{D,R,O\}$ the utility is

$$
\eta_{ik}=a_k+x_i^\mathsf{T}\beta_k+
(\ell_i-\bar\ell)^\mathsf{T}\delta_k+\gamma_k q_{ik}
+u_{s(i),k}+\sum_{b=1}^{14} w_{ib}v_{bk}.
$$

For the fourth outcome, $H$ (no House candidate vote),

$$
\eta_{iH}=\gamma_H q_{iH}.
$$

Here $a_k$ is the centered intercept in the generated Stan program. On each of the three candidate logits, brms centers the entire fixed-effects matrix (including the lineup columns). The already standardized demographic and presidential columns have zero training mean up to floating-point precision. The no-vote utility has a free presidential slope and anchors all other coefficients at zero. Changes to any candidate utility also change the no-vote probability through the shared softmax denominator. Statewide House vote is absent from the regression.

| Input family | Coding |
|---|---|
| Recorded sex | Female share. Male is the reference. |
| Education | No high-school diploma, some college, two-year degree, four-year degree and postgraduate shares. High-school graduate is the reference. |
| Race | Black, Native American, Asian and Other/Multi shares. White is the reference. |
| Hispanic ethnicity | Hispanic share. Non-Hispanic is the reference. Ethnicity and race are separate variables. |
| Presidential vote | One share **per utility**: Democratic for D, Republican for R, Other for O, and no presidential candidate vote for H. Each uses the state's full PUMS citizen-adult denominator. |
| Lineup | Three 0/1 indicators for D/R/Other, a sole major party, and a sole major party plus Other. D versus R is the reference. A fourth term is +1 for D as the sole major party, −1 for R as the sole major party and 0 if both are present. The four terms retain these units. An Other-only ballot is outside the fitted groups. |
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

Student distributions below use location and scale. For each candidate utility, $a_k\sim t_4(0,3)$. All fixed slopes, including all four $\gamma_k$, have independent $t_4(0,2.5)$ priors. State and age effects are independent across their two families and the three candidate utilities. Given their scales,

$$
u_{sk}=\sigma_{u,k}z^u_{sk},\quad v_{bk}=\sigma_{v,k}z^v_{bk},\qquad
z^u_{sk},z^v_{bk}\overset{\mathrm{iid}}{\sim}\mathcal N(0,1).
$$

Each of the six scale parameters independently follows a half-$t_4(0,1)$. The common precision has $\log\phi\sim\mathcal N(3,1.5^2)$. The Stan file shows the non-centered random effects, centered fixed-effect intercepts, likelihood and transformed intercepts reported by brms.

The run fits 404 districts, scores 30 held-out districts, then refits on all 434 tabulated districts. Each fit uses four NUTS chains with at most two running concurrently. Each chain has 1,000 warmup and 1,000 retained iterations, with target acceptance 0.97 and maximum tree depth 13. Step 09 checks monitored parameters for maximum R-hat below 1.01, minimum bulk and tail effective sample sizes of at least 400 with four chains, zero post-warmup divergences and zero maximum-tree-depth hits. The files are `01_frame/data/output/09_holdout_sampler_diagnostics.csv` and `01_frame/data/output/09_full_sampler_diagnostics.csv`. These are sampling checks. The separate 30-district comparison against the presidential benchmark measures predictive accuracy.

## Verify the code from the saved national fit

The companion source was generated with the pinned brms 2.23.0 model and priors. The source was identical for the holdout and refit designs on a fixture and matched the stored source of a sampled brms fit. The numerical national inputs and fitted estimates live in the Codespace. After Step 09 finishes, run the following from the repository root to write the source embedded in that exact fit:

```r
saved <- readRDS("01_frame/data/intermediate/09_house_full_fit.rds")
cat(as.character(brms::stancode(saved$fit$model)), file = "09_house_model_from_fit.stan")
```

[brms family documentation](https://paulbuerkner.com/brms/reference/brmsfamily.html) · [brms multiple-membership weights](https://paulbuerkner.com/brms/reference/mm.html) · [Stan Dirichlet–multinomial reference](https://mc-stan.org/docs/functions-reference/multivariate_discrete_distributions.html)
