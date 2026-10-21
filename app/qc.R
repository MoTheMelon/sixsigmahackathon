# app/qc.R - AeroPrint SPC statistics, plain base R (no packages).
# One small function per statistic. The Shiny app only calls these.
# Formulas follow SPEC.md section 4.

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

#' c4(n): bias-correction constant for the sample standard deviation.
#' c4(n) = sqrt(2 / (n - 1)) * Gamma(n / 2) / Gamma((n - 1) / 2)
#' E[s] = c4 * sigma for a normal sample of size n. c4(3) = 0.8862.
c4 <- function(n) {
  if (length(n) != 1 || is.na(n) || n < 2) {
    stop("need at least 2 coupons per build")
  }
  # lgamma avoids overflow for large n
  sqrt(2 / (n - 1)) * exp(lgamma(n / 2) - lgamma((n - 1) / 2))
}

# Internal: drop NA rows (with a warning), check equal subgroup sizes >= 2.
# Returns list(x, build, n, sizes).
.prepare_subgroups <- function(x, build) {
  if (length(x) != length(build)) {
    stop("x and build must have the same length")
  }
  keep <- !is.na(x) & !is.na(build)
  if (any(!keep)) {
    warning(sprintf("dropped %d row(s) with missing values", sum(!keep)))
  }
  x <- as.numeric(x[keep])
  build <- as.character(build[keep])
  if (length(x) == 0) stop("no data left after dropping missing values")

  sizes <- table(factor(build, levels = unique(build)))
  if (any(sizes < 2)) stop("need at least 2 coupons per build")
  if (length(unique(as.vector(sizes))) != 1) {
    stop("unequal coupons per build: every build needs the same number of coupons")
  }
  list(x = x, build = build, n = as.integer(sizes[[1]]), sizes = sizes)
}

# Internal: per-build mean and sd, in order of first appearance.
.build_summary <- function(p) {
  ids <- names(p$sizes)
  data.frame(
    build = ids,
    mean = vapply(ids, function(b) mean(p$x[p$build == b]), numeric(1)),
    sd = vapply(ids, function(b) sd(p$x[p$build == b]), numeric(1)),
    row.names = NULL,
    stringsAsFactors = FALSE
  )
}

# ---------------------------------------------------------------------------
# Process capability
# ---------------------------------------------------------------------------

#' capability(): Cp, Cpk, Pp, Ppk with subgroups = builds.
#'   sigma_within  = s-bar / c4(n)     (s-bar = mean of the build sds)
#'   sigma_overall = sd of all coupons (n - 1 denominator)
#'   Cpk = min(mean - LSL, USL - mean) / (3 sigma_within)   (limits given only)
#'   Ppk = same, with sigma_overall
#'   Cp  = (USL - LSL) / (6 sigma_within), Pp the same with sigma_overall;
#'         NA with "one-sided spec" unless both limits are given.
#' Zero variation gives NA and "zero variation: capability undefined".
capability <- function(x, build, lsl = NA, usl = NA) {
  p <- .prepare_subgroups(x, build)
  sm <- .build_summary(p)

  mean_all <- mean(p$x)
  sigma_within <- mean(sm$sd) / c4(p$n)
  sigma_overall <- sd(p$x)

  have_lsl <- !is.na(lsl)
  have_usl <- !is.na(usl)
  msg <- character(0)

  # distance from the mean to the nearest given spec limit
  dists <- c(if (have_lsl) mean_all - lsl, if (have_usl) usl - mean_all)

  index_k <- function(sigma) {
    if (is.na(sigma) || sigma <= 0) return(NA_real_)
    if (length(dists) == 0) return(NA_real_)
    min(dists) / (3 * sigma)
  }
  index_p <- function(sigma) {
    if (!(have_lsl && have_usl)) return(NA_real_)
    if (is.na(sigma) || sigma <= 0) return(NA_real_)
    (usl - lsl) / (6 * sigma)
  }

  cpk <- index_k(sigma_within)
  ppk <- index_k(sigma_overall)
  cp <- index_p(sigma_within)
  pp <- index_p(sigma_overall)

  if (is.na(sigma_within) || sigma_within <= 0 || sigma_overall <= 0) {
    msg <- c(msg, "zero variation: capability undefined")
  }
  if (length(dists) == 0) {
    msg <- c(msg, "no spec limit given: capability undefined")
  } else if (!(have_lsl && have_usl)) {
    msg <- c(msg, "Cp/Pp n/a: one-sided spec")
  }
  if (length(msg) == 0) msg <- "ok"

  list(
    mean = mean_all,
    sigma_within = sigma_within,
    sigma_overall = sigma_overall,
    cp = cp, cpk = cpk, pp = pp, ppk = ppk,
    n_builds = length(sm$build),
    n_per_build = p$n,
    message = paste(msg, collapse = "; ")
  )
}

# ---------------------------------------------------------------------------
# X-bar and S chart
# ---------------------------------------------------------------------------

#' xbar_s_limits(): X-bar and S chart limits, subgroups = builds.
#'   X-bar: CL = mean of build means; limits CL +/- A3 s-bar, A3 = 3 / (c4 sqrt(n))
#'   S:     CL = s-bar; LCL = B3 s-bar, UCL = B4 s-bar
#'          B3 = max(0, 1 - 3 sqrt(1 - c4^2) / c4), B4 = 1 + 3 sqrt(1 - c4^2) / c4
xbar_s_limits <- function(x, build) {
  p <- .prepare_subgroups(x, build)
  sm <- .build_summary(p)
  n <- p$n
  k <- c4(n)

  a3 <- 3 / (k * sqrt(n))
  spread <- 3 * sqrt(1 - k^2) / k
  b3 <- max(0, 1 - spread)
  b4 <- 1 + spread

  grand_mean <- mean(sm$mean)
  s_bar <- mean(sm$sd)

  list(
    builds = sm,
    n = n,
    constants = c(A3 = a3, B3 = b3, B4 = b4, c4 = k),
    xbar = c(cl = grand_mean, ucl = grand_mean + a3 * s_bar, lcl = grand_mean - a3 * s_bar),
    s = c(cl = s_bar, ucl = b4 * s_bar, lcl = b3 * s_bar)
  )
}

# ---------------------------------------------------------------------------
# Nelson rules 1-4
# ---------------------------------------------------------------------------

#' nelson_rules(): one row per point, one logical column per rule.
#'   rule1: |x - cl| > 3 sigma
#'   rule2: 9 in a row on the same side of cl (a point exactly on cl breaks
#'          the run); flags the 9th point and every later point of the run
#'   rule3: 6 in a row steadily increasing or decreasing; flags the 6th onward
#'   rule4: 14 in a row alternating up and down; flags the 14th onward
nelson_rules <- function(x, cl, sigma) {
  if (anyNA(x)) stop("x contains missing values")
  if (is.na(sigma) || sigma <= 0) stop("sigma must be positive")
  n <- length(x)

  rule1 <- abs(x - cl) > 3 * sigma

  # Rule 2: run length on one side of the centre line
  side <- sign(x - cl)
  rule2 <- rep(FALSE, n)
  run <- 0
  for (i in seq_len(n)) {
    if (side[i] == 0) {
      run <- 0
    } else if (i > 1 && side[i] == side[i - 1]) {
      run <- run + 1
    } else {
      run <- 1
    }
    rule2[i] <- run >= 9
  }

  # Rules 3 and 4 look at the direction of each step
  step <- sign(diff(x))            # +1 up, -1 down, 0 flat
  rule3 <- rep(FALSE, n)
  rule4 <- rep(FALSE, n)
  same_run <- 0                    # steps in a row with the same direction
  alt_run <- 0                     # steps in a row that alternate direction
  for (j in seq_along(step)) {
    if (step[j] != 0 && j > 1 && step[j] == step[j - 1]) {
      same_run <- same_run + 1
    } else if (step[j] != 0) {
      same_run <- 1
    } else {
      same_run <- 0
    }
    if (step[j] != 0 && j > 1 && step[j] == -step[j - 1]) {
      alt_run <- alt_run + 1
    } else if (step[j] != 0) {
      alt_run <- 1
    } else {
      alt_run <- 0
    }
    # step j joins points j and j + 1; k steps in a row = k + 1 points
    rule3[j + 1] <- same_run >= 5
    rule4[j + 1] <- alt_run >= 13
  }

  data.frame(i = seq_len(n), x = x, rule1 = rule1, rule2 = rule2,
             rule3 = rule3, rule4 = rule4)
}

# ---------------------------------------------------------------------------
# EWMA chart
# ---------------------------------------------------------------------------

#' ewma_chart(): exponentially weighted moving average chart.
#'   z_i = lambda x_i + (1 - lambda) z_(i-1), z_0 = mu0
#'   limits mu0 +/- L sigma sqrt(lambda / (2 - lambda) * (1 - (1 - lambda)^(2 i)))
#'   out = z outside the limits
ewma_chart <- function(x, mu0, sigma, lambda = 0.2, L = 3) {
  if (is.na(sigma) || sigma <= 0) stop("sigma must be positive")
  if (anyNA(x)) stop("x contains missing values")
  if (lambda <= 0 || lambda > 1) stop("lambda must be in (0, 1]")
  n <- length(x)
  z <- numeric(n)
  prev <- mu0
  for (i in seq_len(n)) {
    z[i] <- lambda * x[i] + (1 - lambda) * prev
    prev <- z[i]
  }
  i <- seq_len(n)
  width <- L * sigma * sqrt(lambda / (2 - lambda) * (1 - (1 - lambda)^(2 * i)))
  ucl <- mu0 + width
  lcl <- mu0 - width
  data.frame(i = i, x = x, z = z, ucl = ucl, lcl = lcl,
             out = z > ucl | z < lcl)
}

#' abort_index(): run rule on EWMA out flags. One flagged layer in a 200-layer
#'   build is often a false alarm at L = 3, so abort only when k consecutive
#'   points are out. Returns the index of the k-th point of the first such run,
#'   or NA if there is none.
abort_index <- function(out, k = 5) {
  if (k < 1) stop("k must be at least 1")
  if (anyNA(out)) stop("out contains missing values")
  run <- 0L
  for (i in seq_along(out)) {
    run <- if (out[i]) run + 1L else 0L
    if (run >= k) return(i)
  }
  NA_integer_
}

# ---------------------------------------------------------------------------
# Normality
# ---------------------------------------------------------------------------

#' normality_check(): Shapiro-Wilk test of normality.
#' Needs 3 to 5000 non-missing points and some spread; otherwise p is NA.
normality_check <- function(x) {
  x <- x[!is.na(x)]
  if (length(x) < 3 || length(x) > 5000) {
    return(list(p_value = NA_real_,
                message = "Shapiro-Wilk needs between 3 and 5000 points"))
  }
  if (length(unique(x)) < 2) {
    return(list(p_value = NA_real_,
                message = "zero variation: normality test undefined"))
  }
  p <- shapiro.test(x)$p.value
  msg <- if (p < 0.05) {
    "warning: data look non-normal (p < 0.05); Cpk may be unreliable"
  } else {
    "no evidence against normality (p >= 0.05)"
  }
  list(p_value = p, message = msg)
}
