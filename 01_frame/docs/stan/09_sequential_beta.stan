// generated with brms 2.23.0
functions {
  /* integer sequence of values
   * Args:
   *   start: starting integer
   *   end: ending integer
   * Returns:
   *   an integer sequence from start to end
   */
  array[] int sequence(int start, int end) {
    array[end - start + 1] int seq;
    for (n in 1:num_elements(seq)) {
      seq[n] = n + start - 1;
    }
    return seq;
  }
  // compute partial sums of the log-likelihood
  real partial_log_lik_lpmf(array[] int seq, int start, int end, data vector Y, data matrix Xc, vector b, real Intercept, data matrix Xs, vector bs, data matrix Zs_1_1, vector s_1_1, real phi, data array[] int J_1_1, data array[] real W_1_1, data array[] int J_1_2, data array[] real W_1_2, data array[] int J_1_3, data array[] real W_1_3, data array[] int J_1_4, data array[] real W_1_4, data array[] int J_1_5, data array[] real W_1_5, data array[] int J_1_6, data array[] real W_1_6, data array[] int J_1_7, data array[] real W_1_7, data array[] int J_1_8, data array[] real W_1_8, data array[] int J_1_9, data array[] real W_1_9, data array[] int J_1_10, data array[] real W_1_10, data array[] int J_1_11, data array[] real W_1_11, data array[] int J_1_12, data array[] real W_1_12, data array[] int J_1_13, data array[] real W_1_13, data vector Z_1_1_1, data vector Z_1_1_2, data vector Z_1_1_3, data vector Z_1_1_4, data vector Z_1_1_5, data vector Z_1_1_6, data vector Z_1_1_7, data vector Z_1_1_8, data vector Z_1_1_9, data vector Z_1_1_10, data vector Z_1_1_11, data vector Z_1_1_12, data vector Z_1_1_13, vector r_1_1, data array[] int J_2_1, data array[] real W_2_1, data array[] int J_2_2, data array[] real W_2_2, data array[] int J_2_3, data array[] real W_2_3, data array[] int J_2_4, data array[] real W_2_4, data array[] int J_2_5, data array[] real W_2_5, data vector Z_2_1_1, data vector Z_2_1_2, data vector Z_2_1_3, data vector Z_2_1_4, data vector Z_2_1_5, vector r_2_1, data array[] int J_3, data vector Z_3_1, vector r_3_1) {
    real ptarget = 0;
    int N = end - start + 1;
    // initialize linear predictor term
    vector[N] mu = rep_vector(0.0, N);
    mu += Intercept + Xc[start:end] * b + Xs[start:end] * bs + Zs_1_1[start:end] * s_1_1;
    for (n in 1:N) {
      // add more terms to the linear predictor
      int nn = n + start - 1;
      mu[n] += W_1_1[nn] * r_1_1[J_1_1[nn]] * Z_1_1_1[nn] + W_1_2[nn] * r_1_1[J_1_2[nn]] * Z_1_1_2[nn] + W_1_3[nn] * r_1_1[J_1_3[nn]] * Z_1_1_3[nn] + W_1_4[nn] * r_1_1[J_1_4[nn]] * Z_1_1_4[nn] + W_1_5[nn] * r_1_1[J_1_5[nn]] * Z_1_1_5[nn] + W_1_6[nn] * r_1_1[J_1_6[nn]] * Z_1_1_6[nn] + W_1_7[nn] * r_1_1[J_1_7[nn]] * Z_1_1_7[nn] + W_1_8[nn] * r_1_1[J_1_8[nn]] * Z_1_1_8[nn] + W_1_9[nn] * r_1_1[J_1_9[nn]] * Z_1_1_9[nn] + W_1_10[nn] * r_1_1[J_1_10[nn]] * Z_1_1_10[nn] + W_1_11[nn] * r_1_1[J_1_11[nn]] * Z_1_1_11[nn] + W_1_12[nn] * r_1_1[J_1_12[nn]] * Z_1_1_12[nn] + W_1_13[nn] * r_1_1[J_1_13[nn]] * Z_1_1_13[nn] + W_2_1[nn] * r_2_1[J_2_1[nn]] * Z_2_1_1[nn] + W_2_2[nn] * r_2_1[J_2_2[nn]] * Z_2_1_2[nn] + W_2_3[nn] * r_2_1[J_2_3[nn]] * Z_2_1_3[nn] + W_2_4[nn] * r_2_1[J_2_4[nn]] * Z_2_1_4[nn] + W_2_5[nn] * r_2_1[J_2_5[nn]] * Z_2_1_5[nn] + r_3_1[J_3[nn]] * Z_3_1[nn];
    }
    mu = inv_logit(mu);
    ptarget += beta_lpdf(Y[start:end] | mu .* phi, (1 - mu) .* phi);
    return ptarget;
  }
}
data {
  int<lower=1> N;  // total number of observations
  vector[N] Y;  // response variable
  int<lower=1> K;  // number of population-level effects
  matrix[N, K] X;  // population-level design matrix
  int<lower=1> Kc;  // number of population-level effects after centering
  // data for splines
  int Ks;  // number of linear effects
  matrix[N, Ks] Xs;  // design matrix for the linear effects
  // data for spline 1
  int nb_1;  // number of bases
  array[nb_1] int knots_1;  // number of knots
  // basis function matrices
  matrix[N, knots_1[1]] Zs_1_1;
  int grainsize;  // grainsize for threading
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
  // group-level predictor values
  vector[N] Z_1_1_1;
  vector[N] Z_1_1_2;
  vector[N] Z_1_1_3;
  vector[N] Z_1_1_4;
  vector[N] Z_1_1_5;
  vector[N] Z_1_1_6;
  vector[N] Z_1_1_7;
  vector[N] Z_1_1_8;
  vector[N] Z_1_1_9;
  vector[N] Z_1_1_10;
  vector[N] Z_1_1_11;
  vector[N] Z_1_1_12;
  vector[N] Z_1_1_13;
  // data for group-level effects of ID 2
  int<lower=1> N_2;  // number of grouping levels
  int<lower=1> M_2;  // number of coefficients per level
  array[N] int<lower=1> J_2_1;  // grouping indicator per observation
  array[N] real W_2_1;  // multi-membership weights
  array[N] int<lower=1> J_2_2;  // grouping indicator per observation
  array[N] real W_2_2;  // multi-membership weights
  array[N] int<lower=1> J_2_3;  // grouping indicator per observation
  array[N] real W_2_3;  // multi-membership weights
  array[N] int<lower=1> J_2_4;  // grouping indicator per observation
  array[N] real W_2_4;  // multi-membership weights
  array[N] int<lower=1> J_2_5;  // grouping indicator per observation
  array[N] real W_2_5;  // multi-membership weights
  // group-level predictor values
  vector[N] Z_2_1_1;
  vector[N] Z_2_1_2;
  vector[N] Z_2_1_3;
  vector[N] Z_2_1_4;
  vector[N] Z_2_1_5;
  // data for group-level effects of ID 3
  int<lower=1> N_3;  // number of grouping levels
  int<lower=1> M_3;  // number of coefficients per level
  array[N] int<lower=1> J_3;  // grouping indicator per observation
  // group-level predictor values
  vector[N] Z_3_1;
  int prior_only;  // should the likelihood be ignored?
}
transformed data {
  matrix[N, Kc] Xc;  // centered version of X without an intercept
  vector[Kc] means_X;  // column means of X before centering
  array[N] int seq = sequence(1, N);
  for (i in 2:K) {
    means_X[i - 1] = mean(X[, i]);
    Xc[, i - 1] = X[, i] - means_X[i - 1];
  }
}
parameters {
  vector[Kc] b;  // regression coefficients
  real Intercept;  // temporary intercept for centered predictors
  vector[Ks] bs;  // unpenalized spline coefficients
  // parameters for spline 1
  // standardized penalized spline coefficients
  vector[knots_1[1]] zs_1_1;
  vector<lower=0>[nb_1] sds_1;  // SDs of penalized spline coefficients
  real<lower=0> phi;  // precision parameter
  vector<lower=0>[M_1] sd_1;  // group-level standard deviations
  array[M_1] vector[N_1] z_1;  // standardized group-level effects
  vector<lower=0>[M_2] sd_2;  // group-level standard deviations
  array[M_2] vector[N_2] z_2;  // standardized group-level effects
  vector<lower=0>[M_3] sd_3;  // group-level standard deviations
  array[M_3] vector[N_3] z_3;  // standardized group-level effects
}
transformed parameters {
  // penalized spline coefficients
  vector[knots_1[1]] s_1_1;
  vector[N_1] r_1_1;  // actual group-level effects
  vector[N_2] r_2_1;  // actual group-level effects
  vector[N_3] r_3_1;  // actual group-level effects
  // prior contributions to the log posterior
  real lprior = 0;
  // compute penalized spline coefficients
  s_1_1 = sds_1[1] * zs_1_1;
  r_1_1 = (sd_1[1] * (z_1[1]));
  r_2_1 = (sd_2[1] * (z_2[1]));
  r_3_1 = (sd_3[1] * (z_3[1]));
  lprior += student_t_lpdf(b | 4, 0, 2.5);
  lprior += student_t_lpdf(Intercept | 4, 0, 3);
  lprior += student_t_lpdf(bs | 4, 0, 2.5);
  lprior += student_t_lpdf(sds_1 | 4, 0, 1)
    - 1 * student_t_lccdf(0 | 4, 0, 1);
  lprior += lognormal_lpdf(phi | 3, 1.5);
  lprior += student_t_lpdf(sd_1 | 4, 0, 1)
    - 1 * student_t_lccdf(0 | 4, 0, 1);
  lprior += student_t_lpdf(sd_2 | 4, 0, 1)
    - 1 * student_t_lccdf(0 | 4, 0, 1);
  lprior += student_t_lpdf(sd_3 | 4, 0, 1)
    - 1 * student_t_lccdf(0 | 4, 0, 1);
}
model {
  // likelihood including constants
  if (!prior_only) {
    target += reduce_sum_static(partial_log_lik_lpmf, seq, grainsize, Y, Xc, b, Intercept, Xs, bs, Zs_1_1, s_1_1, phi, J_1_1, W_1_1, J_1_2, W_1_2, J_1_3, W_1_3, J_1_4, W_1_4, J_1_5, W_1_5, J_1_6, W_1_6, J_1_7, W_1_7, J_1_8, W_1_8, J_1_9, W_1_9, J_1_10, W_1_10, J_1_11, W_1_11, J_1_12, W_1_12, J_1_13, W_1_13, Z_1_1_1, Z_1_1_2, Z_1_1_3, Z_1_1_4, Z_1_1_5, Z_1_1_6, Z_1_1_7, Z_1_1_8, Z_1_1_9, Z_1_1_10, Z_1_1_11, Z_1_1_12, Z_1_1_13, r_1_1, J_2_1, W_2_1, J_2_2, W_2_2, J_2_3, W_2_3, J_2_4, W_2_4, J_2_5, W_2_5, Z_2_1_1, Z_2_1_2, Z_2_1_3, Z_2_1_4, Z_2_1_5, r_2_1, J_3, Z_3_1, r_3_1);
  }
  // priors including constants
  target += lprior;
  target += std_normal_lpdf(zs_1_1);
  target += std_normal_lpdf(z_1[1]);
  target += std_normal_lpdf(z_2[1]);
  target += std_normal_lpdf(z_3[1]);
}
generated quantities {
  // actual population-level intercept
  real b_Intercept = Intercept - dot_product(means_X, b);
}