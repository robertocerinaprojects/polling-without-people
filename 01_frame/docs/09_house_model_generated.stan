// generated with brms 2.23.0
functions {
  /* dirichlet-multinomial-logit log-PMF
   * Args:
   *   y: array of integer response values
   *   mu: vector of category logit probabilities
   *   phi: precision parameter (sum of Dirichlet alphas)
   * Returns:
   *   a scalar to be added to the log posterior
  */
  real dirichlet_multinomial_logit2_lpmf(array[] int y, vector mu, real phi) {
    // get Dirichlet alphas
    int N = num_elements(mu);
    vector[N] alpha = phi * softmax(mu);

    // get trials from y
    real T = sum(y);

    return lgamma(phi) + lgamma(T + 1.0) - lgamma(T + phi) +
      sum(lgamma(to_vector(y) + alpha)) - sum(lgamma(alpha)) - sum(lgamma(to_vector(y) + 1));
  }
}
data {
  int<lower=1> N;  // total number of observations
  int<lower=2> ncat;  // number of categories
  array[N, ncat] int Y;  // response array
  array[N] int trials;  // number of trials
  int<lower=1> K_muD;  // number of population-level effects
  matrix[N, K_muD] X_muD;  // population-level design matrix
  int<lower=1> Kc_muD;  // number of population-level effects after centering
  int<lower=1> K_muR;  // number of population-level effects
  matrix[N, K_muR] X_muR;  // population-level design matrix
  int<lower=1> Kc_muR;  // number of population-level effects after centering
  int<lower=1> K_muOther;  // number of population-level effects
  matrix[N, K_muOther] X_muOther;  // population-level design matrix
  int<lower=1> Kc_muOther;  // number of population-level effects after centering
  int<lower=1> K_muDidNotVote;  // number of population-level effects
  matrix[N, K_muDidNotVote] X_muDidNotVote;  // population-level design matrix
  // data for group-level effects of ID 1
  int<lower=1> N_1;  // number of grouping levels
  int<lower=1> M_1;  // number of coefficients per level
  array[N] int<lower=1> J_1_1;  // grouping indicator per observation
  array[N] real W_1_1;  // multi-membership weights
  array[N] int<lower=1> J_1_2;  // grouping indicator per observation
  array[N] real W_1_2;  // multi-membership weights
  array[N] int<lower=1> J_1_3;  // grouping indicator per observation
  array[N] real W_1_3;  // multi-membership weights
  array[N] int<lower=1> J_1_4;  // grouping indicator per observation
  array[N] real W_1_4;  // multi-membership weights
  array[N] int<lower=1> J_1_5;  // grouping indicator per observation
  array[N] real W_1_5;  // multi-membership weights
  array[N] int<lower=1> J_1_6;  // grouping indicator per observation
  array[N] real W_1_6;  // multi-membership weights
  array[N] int<lower=1> J_1_7;  // grouping indicator per observation
  array[N] real W_1_7;  // multi-membership weights
  array[N] int<lower=1> J_1_8;  // grouping indicator per observation
  array[N] real W_1_8;  // multi-membership weights
  array[N] int<lower=1> J_1_9;  // grouping indicator per observation
  array[N] real W_1_9;  // multi-membership weights
  array[N] int<lower=1> J_1_10;  // grouping indicator per observation
  array[N] real W_1_10;  // multi-membership weights
  array[N] int<lower=1> J_1_11;  // grouping indicator per observation
  array[N] real W_1_11;  // multi-membership weights
  array[N] int<lower=1> J_1_12;  // grouping indicator per observation
  array[N] real W_1_12;  // multi-membership weights
  array[N] int<lower=1> J_1_13;  // grouping indicator per observation
  array[N] real W_1_13;  // multi-membership weights
  array[N] int<lower=1> J_1_14;  // grouping indicator per observation
  array[N] real W_1_14;  // multi-membership weights
  // group-level predictor values
  vector[N] Z_1_muD_1_1;
  vector[N] Z_1_muD_1_2;
  vector[N] Z_1_muD_1_3;
  vector[N] Z_1_muD_1_4;
  vector[N] Z_1_muD_1_5;
  vector[N] Z_1_muD_1_6;
  vector[N] Z_1_muD_1_7;
  vector[N] Z_1_muD_1_8;
  vector[N] Z_1_muD_1_9;
  vector[N] Z_1_muD_1_10;
  vector[N] Z_1_muD_1_11;
  vector[N] Z_1_muD_1_12;
  vector[N] Z_1_muD_1_13;
  vector[N] Z_1_muD_1_14;
  // data for group-level effects of ID 2
  int<lower=1> N_2;  // number of grouping levels
  int<lower=1> M_2;  // number of coefficients per level
  array[N] int<lower=1> J_2;  // grouping indicator per observation
  // group-level predictor values
  vector[N] Z_2_muD_1;
  // data for group-level effects of ID 3
  int<lower=1> N_3;  // number of grouping levels
  int<lower=1> M_3;  // number of coefficients per level
  array[N] int<lower=1> J_3_1;  // grouping indicator per observation
  array[N] real W_3_1;  // multi-membership weights
  array[N] int<lower=1> J_3_2;  // grouping indicator per observation
  array[N] real W_3_2;  // multi-membership weights
  array[N] int<lower=1> J_3_3;  // grouping indicator per observation
  array[N] real W_3_3;  // multi-membership weights
  array[N] int<lower=1> J_3_4;  // grouping indicator per observation
  array[N] real W_3_4;  // multi-membership weights
  array[N] int<lower=1> J_3_5;  // grouping indicator per observation
  array[N] real W_3_5;  // multi-membership weights
  array[N] int<lower=1> J_3_6;  // grouping indicator per observation
  array[N] real W_3_6;  // multi-membership weights
  array[N] int<lower=1> J_3_7;  // grouping indicator per observation
  array[N] real W_3_7;  // multi-membership weights
  array[N] int<lower=1> J_3_8;  // grouping indicator per observation
  array[N] real W_3_8;  // multi-membership weights
  array[N] int<lower=1> J_3_9;  // grouping indicator per observation
  array[N] real W_3_9;  // multi-membership weights
  array[N] int<lower=1> J_3_10;  // grouping indicator per observation
  array[N] real W_3_10;  // multi-membership weights
  array[N] int<lower=1> J_3_11;  // grouping indicator per observation
  array[N] real W_3_11;  // multi-membership weights
  array[N] int<lower=1> J_3_12;  // grouping indicator per observation
  array[N] real W_3_12;  // multi-membership weights
  array[N] int<lower=1> J_3_13;  // grouping indicator per observation
  array[N] real W_3_13;  // multi-membership weights
  array[N] int<lower=1> J_3_14;  // grouping indicator per observation
  array[N] real W_3_14;  // multi-membership weights
  // group-level predictor values
  vector[N] Z_3_muR_1_1;
  vector[N] Z_3_muR_1_2;
  vector[N] Z_3_muR_1_3;
  vector[N] Z_3_muR_1_4;
  vector[N] Z_3_muR_1_5;
  vector[N] Z_3_muR_1_6;
  vector[N] Z_3_muR_1_7;
  vector[N] Z_3_muR_1_8;
  vector[N] Z_3_muR_1_9;
  vector[N] Z_3_muR_1_10;
  vector[N] Z_3_muR_1_11;
  vector[N] Z_3_muR_1_12;
  vector[N] Z_3_muR_1_13;
  vector[N] Z_3_muR_1_14;
  // data for group-level effects of ID 4
  int<lower=1> N_4;  // number of grouping levels
  int<lower=1> M_4;  // number of coefficients per level
  array[N] int<lower=1> J_4;  // grouping indicator per observation
  // group-level predictor values
  vector[N] Z_4_muR_1;
  // data for group-level effects of ID 5
  int<lower=1> N_5;  // number of grouping levels
  int<lower=1> M_5;  // number of coefficients per level
  array[N] int<lower=1> J_5_1;  // grouping indicator per observation
  array[N] real W_5_1;  // multi-membership weights
  array[N] int<lower=1> J_5_2;  // grouping indicator per observation
  array[N] real W_5_2;  // multi-membership weights
  array[N] int<lower=1> J_5_3;  // grouping indicator per observation
  array[N] real W_5_3;  // multi-membership weights
  array[N] int<lower=1> J_5_4;  // grouping indicator per observation
  array[N] real W_5_4;  // multi-membership weights
  array[N] int<lower=1> J_5_5;  // grouping indicator per observation
  array[N] real W_5_5;  // multi-membership weights
  array[N] int<lower=1> J_5_6;  // grouping indicator per observation
  array[N] real W_5_6;  // multi-membership weights
  array[N] int<lower=1> J_5_7;  // grouping indicator per observation
  array[N] real W_5_7;  // multi-membership weights
  array[N] int<lower=1> J_5_8;  // grouping indicator per observation
  array[N] real W_5_8;  // multi-membership weights
  array[N] int<lower=1> J_5_9;  // grouping indicator per observation
  array[N] real W_5_9;  // multi-membership weights
  array[N] int<lower=1> J_5_10;  // grouping indicator per observation
  array[N] real W_5_10;  // multi-membership weights
  array[N] int<lower=1> J_5_11;  // grouping indicator per observation
  array[N] real W_5_11;  // multi-membership weights
  array[N] int<lower=1> J_5_12;  // grouping indicator per observation
  array[N] real W_5_12;  // multi-membership weights
  array[N] int<lower=1> J_5_13;  // grouping indicator per observation
  array[N] real W_5_13;  // multi-membership weights
  array[N] int<lower=1> J_5_14;  // grouping indicator per observation
  array[N] real W_5_14;  // multi-membership weights
  // group-level predictor values
  vector[N] Z_5_muOther_1_1;
  vector[N] Z_5_muOther_1_2;
  vector[N] Z_5_muOther_1_3;
  vector[N] Z_5_muOther_1_4;
  vector[N] Z_5_muOther_1_5;
  vector[N] Z_5_muOther_1_6;
  vector[N] Z_5_muOther_1_7;
  vector[N] Z_5_muOther_1_8;
  vector[N] Z_5_muOther_1_9;
  vector[N] Z_5_muOther_1_10;
  vector[N] Z_5_muOther_1_11;
  vector[N] Z_5_muOther_1_12;
  vector[N] Z_5_muOther_1_13;
  vector[N] Z_5_muOther_1_14;
  // data for group-level effects of ID 6
  int<lower=1> N_6;  // number of grouping levels
  int<lower=1> M_6;  // number of coefficients per level
  array[N] int<lower=1> J_6;  // grouping indicator per observation
  // group-level predictor values
  vector[N] Z_6_muOther_1;
  int prior_only;  // should the likelihood be ignored?
}
transformed data {
  matrix[N, Kc_muD] Xc_muD;  // centered version of X_muD without an intercept
  vector[Kc_muD] means_X_muD;  // column means of X_muD before centering
  matrix[N, Kc_muR] Xc_muR;  // centered version of X_muR without an intercept
  vector[Kc_muR] means_X_muR;  // column means of X_muR before centering
  matrix[N, Kc_muOther] Xc_muOther;  // centered version of X_muOther without an intercept
  vector[Kc_muOther] means_X_muOther;  // column means of X_muOther before centering
  for (i in 2:K_muD) {
    means_X_muD[i - 1] = mean(X_muD[, i]);
    Xc_muD[, i - 1] = X_muD[, i] - means_X_muD[i - 1];
  }
  for (i in 2:K_muR) {
    means_X_muR[i - 1] = mean(X_muR[, i]);
    Xc_muR[, i - 1] = X_muR[, i] - means_X_muR[i - 1];
  }
  for (i in 2:K_muOther) {
    means_X_muOther[i - 1] = mean(X_muOther[, i]);
    Xc_muOther[, i - 1] = X_muOther[, i] - means_X_muOther[i - 1];
  }
}
parameters {
  vector[Kc_muD] b_muD;  // regression coefficients
  real Intercept_muD;  // temporary intercept for centered predictors
  vector[Kc_muR] b_muR;  // regression coefficients
  real Intercept_muR;  // temporary intercept for centered predictors
  vector[Kc_muOther] b_muOther;  // regression coefficients
  real Intercept_muOther;  // temporary intercept for centered predictors
  vector[K_muDidNotVote] b_muDidNotVote;  // regression coefficients
  real<lower=0> phi;  // precision parameter
  vector<lower=0>[M_1] sd_1;  // group-level standard deviations
  array[M_1] vector[N_1] z_1;  // standardized group-level effects
  vector<lower=0>[M_2] sd_2;  // group-level standard deviations
  array[M_2] vector[N_2] z_2;  // standardized group-level effects
  vector<lower=0>[M_3] sd_3;  // group-level standard deviations
  array[M_3] vector[N_3] z_3;  // standardized group-level effects
  vector<lower=0>[M_4] sd_4;  // group-level standard deviations
  array[M_4] vector[N_4] z_4;  // standardized group-level effects
  vector<lower=0>[M_5] sd_5;  // group-level standard deviations
  array[M_5] vector[N_5] z_5;  // standardized group-level effects
  vector<lower=0>[M_6] sd_6;  // group-level standard deviations
  array[M_6] vector[N_6] z_6;  // standardized group-level effects
}
transformed parameters {
  vector[N_1] r_1_muD_1;  // actual group-level effects
  vector[N_2] r_2_muD_1;  // actual group-level effects
  vector[N_3] r_3_muR_1;  // actual group-level effects
  vector[N_4] r_4_muR_1;  // actual group-level effects
  vector[N_5] r_5_muOther_1;  // actual group-level effects
  vector[N_6] r_6_muOther_1;  // actual group-level effects
  // prior contributions to the log posterior
  real lprior = 0;
  r_1_muD_1 = (sd_1[1] * (z_1[1]));
  r_2_muD_1 = (sd_2[1] * (z_2[1]));
  r_3_muR_1 = (sd_3[1] * (z_3[1]));
  r_4_muR_1 = (sd_4[1] * (z_4[1]));
  r_5_muOther_1 = (sd_5[1] * (z_5[1]));
  r_6_muOther_1 = (sd_6[1] * (z_6[1]));
  lprior += student_t_lpdf(b_muD | 4, 0, 2.5);
  lprior += student_t_lpdf(Intercept_muD | 4, 0, 3);
  lprior += student_t_lpdf(b_muR | 4, 0, 2.5);
  lprior += student_t_lpdf(Intercept_muR | 4, 0, 3);
  lprior += student_t_lpdf(b_muOther | 4, 0, 2.5);
  lprior += student_t_lpdf(Intercept_muOther | 4, 0, 3);
  lprior += student_t_lpdf(b_muDidNotVote | 4, 0, 2.5);
  lprior += lognormal_lpdf(phi | 3, 1.5);
  lprior += student_t_lpdf(sd_1 | 4, 0, 1)
    - 1 * student_t_lccdf(0 | 4, 0, 1);
  lprior += student_t_lpdf(sd_2 | 4, 0, 1)
    - 1 * student_t_lccdf(0 | 4, 0, 1);
  lprior += student_t_lpdf(sd_3 | 4, 0, 1)
    - 1 * student_t_lccdf(0 | 4, 0, 1);
  lprior += student_t_lpdf(sd_4 | 4, 0, 1)
    - 1 * student_t_lccdf(0 | 4, 0, 1);
  lprior += student_t_lpdf(sd_5 | 4, 0, 1)
    - 1 * student_t_lccdf(0 | 4, 0, 1);
  lprior += student_t_lpdf(sd_6 | 4, 0, 1)
    - 1 * student_t_lccdf(0 | 4, 0, 1);
}
model {
  // likelihood including constants
  if (!prior_only) {
    // initialize linear predictor term
    vector[N] muD = rep_vector(0.0, N);
    // initialize linear predictor term
    vector[N] muR = rep_vector(0.0, N);
    // initialize linear predictor term
    vector[N] muOther = rep_vector(0.0, N);
    // initialize linear predictor term
    vector[N] muDidNotVote = rep_vector(0.0, N);
    // linear predictor matrix
    array[N] vector[ncat] mu;
    muD += Intercept_muD + Xc_muD * b_muD;
    muR += Intercept_muR + Xc_muR * b_muR;
    muOther += Intercept_muOther + Xc_muOther * b_muOther;
    muDidNotVote += X_muDidNotVote * b_muDidNotVote;
    for (n in 1:N) {
      // add more terms to the linear predictor
      muD[n] += W_1_1[n] * r_1_muD_1[J_1_1[n]] * Z_1_muD_1_1[n] + W_1_2[n] * r_1_muD_1[J_1_2[n]] * Z_1_muD_1_2[n] + W_1_3[n] * r_1_muD_1[J_1_3[n]] * Z_1_muD_1_3[n] + W_1_4[n] * r_1_muD_1[J_1_4[n]] * Z_1_muD_1_4[n] + W_1_5[n] * r_1_muD_1[J_1_5[n]] * Z_1_muD_1_5[n] + W_1_6[n] * r_1_muD_1[J_1_6[n]] * Z_1_muD_1_6[n] + W_1_7[n] * r_1_muD_1[J_1_7[n]] * Z_1_muD_1_7[n] + W_1_8[n] * r_1_muD_1[J_1_8[n]] * Z_1_muD_1_8[n] + W_1_9[n] * r_1_muD_1[J_1_9[n]] * Z_1_muD_1_9[n] + W_1_10[n] * r_1_muD_1[J_1_10[n]] * Z_1_muD_1_10[n] + W_1_11[n] * r_1_muD_1[J_1_11[n]] * Z_1_muD_1_11[n] + W_1_12[n] * r_1_muD_1[J_1_12[n]] * Z_1_muD_1_12[n] + W_1_13[n] * r_1_muD_1[J_1_13[n]] * Z_1_muD_1_13[n] + W_1_14[n] * r_1_muD_1[J_1_14[n]] * Z_1_muD_1_14[n] + r_2_muD_1[J_2[n]] * Z_2_muD_1[n];
    }
    for (n in 1:N) {
      // add more terms to the linear predictor
      muR[n] += W_3_1[n] * r_3_muR_1[J_3_1[n]] * Z_3_muR_1_1[n] + W_3_2[n] * r_3_muR_1[J_3_2[n]] * Z_3_muR_1_2[n] + W_3_3[n] * r_3_muR_1[J_3_3[n]] * Z_3_muR_1_3[n] + W_3_4[n] * r_3_muR_1[J_3_4[n]] * Z_3_muR_1_4[n] + W_3_5[n] * r_3_muR_1[J_3_5[n]] * Z_3_muR_1_5[n] + W_3_6[n] * r_3_muR_1[J_3_6[n]] * Z_3_muR_1_6[n] + W_3_7[n] * r_3_muR_1[J_3_7[n]] * Z_3_muR_1_7[n] + W_3_8[n] * r_3_muR_1[J_3_8[n]] * Z_3_muR_1_8[n] + W_3_9[n] * r_3_muR_1[J_3_9[n]] * Z_3_muR_1_9[n] + W_3_10[n] * r_3_muR_1[J_3_10[n]] * Z_3_muR_1_10[n] + W_3_11[n] * r_3_muR_1[J_3_11[n]] * Z_3_muR_1_11[n] + W_3_12[n] * r_3_muR_1[J_3_12[n]] * Z_3_muR_1_12[n] + W_3_13[n] * r_3_muR_1[J_3_13[n]] * Z_3_muR_1_13[n] + W_3_14[n] * r_3_muR_1[J_3_14[n]] * Z_3_muR_1_14[n] + r_4_muR_1[J_4[n]] * Z_4_muR_1[n];
    }
    for (n in 1:N) {
      // add more terms to the linear predictor
      muOther[n] += W_5_1[n] * r_5_muOther_1[J_5_1[n]] * Z_5_muOther_1_1[n] + W_5_2[n] * r_5_muOther_1[J_5_2[n]] * Z_5_muOther_1_2[n] + W_5_3[n] * r_5_muOther_1[J_5_3[n]] * Z_5_muOther_1_3[n] + W_5_4[n] * r_5_muOther_1[J_5_4[n]] * Z_5_muOther_1_4[n] + W_5_5[n] * r_5_muOther_1[J_5_5[n]] * Z_5_muOther_1_5[n] + W_5_6[n] * r_5_muOther_1[J_5_6[n]] * Z_5_muOther_1_6[n] + W_5_7[n] * r_5_muOther_1[J_5_7[n]] * Z_5_muOther_1_7[n] + W_5_8[n] * r_5_muOther_1[J_5_8[n]] * Z_5_muOther_1_8[n] + W_5_9[n] * r_5_muOther_1[J_5_9[n]] * Z_5_muOther_1_9[n] + W_5_10[n] * r_5_muOther_1[J_5_10[n]] * Z_5_muOther_1_10[n] + W_5_11[n] * r_5_muOther_1[J_5_11[n]] * Z_5_muOther_1_11[n] + W_5_12[n] * r_5_muOther_1[J_5_12[n]] * Z_5_muOther_1_12[n] + W_5_13[n] * r_5_muOther_1[J_5_13[n]] * Z_5_muOther_1_13[n] + W_5_14[n] * r_5_muOther_1[J_5_14[n]] * Z_5_muOther_1_14[n] + r_6_muOther_1[J_6[n]] * Z_6_muOther_1[n];
    }
    for (n in 1:N) {
      mu[n] = transpose([muD[n], muR[n], muOther[n], muDidNotVote[n]]);
    }
    for (n in 1:N) {
      target += dirichlet_multinomial_logit2_lpmf(Y[n] | mu[n], phi);
    }
  }
  // priors including constants
  target += lprior;
  target += std_normal_lpdf(z_1[1]);
  target += std_normal_lpdf(z_2[1]);
  target += std_normal_lpdf(z_3[1]);
  target += std_normal_lpdf(z_4[1]);
  target += std_normal_lpdf(z_5[1]);
  target += std_normal_lpdf(z_6[1]);
}
generated quantities {
  // actual population-level intercept
  real b_muD_Intercept = Intercept_muD - dot_product(means_X_muD, b_muD);
  // actual population-level intercept
  real b_muR_Intercept = Intercept_muR - dot_product(means_X_muR, b_muR);
  // actual population-level intercept
  real b_muOther_Intercept = Intercept_muOther - dot_product(means_X_muOther, b_muOther);
}
