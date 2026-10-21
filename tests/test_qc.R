# Tests for app/qc.R. Run from the repo root:
#   Rscript -e "testthat::test_dir('tests')"
library(testthat)

# test_dir() runs from tests/, Rscript from the root: try both paths.
qc_path <- c("app/qc.R", "../app/qc.R", "../../app/qc.R")
qc_path <- qc_path[file.exists(qc_path)][1]
source(qc_path)

# Hand-worked data from SPEC.md section 4 (yield strength, MPa)
yield <- c(1100, 1110, 1120, 1090, 1100, 1110, 1110, 1120, 1130)
build <- rep(c("B1", "B2", "B3"), each = 3)

test_that("c4(3) is 0.8862", {
  expect_equal(c4(3), 0.8862, tolerance = 1e-4)
})

test_that("capability reproduces the SPEC known answer", {
  r <- capability(yield, build, lsl = 1050)
  expect_equal(r$mean, 1110)
  expect_equal(r$sigma_within, 11.284, tolerance = 0.001)
  expect_equal(r$sigma_overall, sqrt(1200 / 8), tolerance = 1e-9)
  expect_equal(r$cpk, 1.772, tolerance = 0.001)
  expect_equal(r$ppk, 1.633, tolerance = 0.001)
  expect_true(is.na(r$cp))
  expect_true(is.na(r$pp))
  expect_match(r$message, "one-sided spec")
  expect_equal(r$n_builds, 3)
  expect_equal(r$n_per_build, 3)
})

test_that("upper-only spec uses USL; two-sided gives Cp", {
  r <- capability(yield, build, usl = 1170)
  expect_equal(r$cpk, 60 / (3 * r$sigma_within), tolerance = 1e-9)
  r2 <- capability(yield, build, lsl = 1050, usl = 1170)
  expect_equal(r2$cp, 120 / (6 * r2$sigma_within), tolerance = 1e-9)
  expect_equal(r2$pp, 120 / (6 * r2$sigma_overall), tolerance = 1e-9)
})

test_that("X-bar and S limits reproduce the SPEC known answer", {
  r <- xbar_s_limits(yield, build)
  expect_equal(unname(r$xbar["cl"]), 1110, tolerance = 0.01)
  expect_equal(unname(r$xbar["ucl"]), 1129.54, tolerance = 0.01)
  expect_equal(unname(r$xbar["lcl"]), 1090.46, tolerance = 0.01)
  expect_equal(unname(r$s["ucl"]), 25.68, tolerance = 0.01)
  expect_equal(unname(r$s["lcl"]), 0, tolerance = 0.01)
  expect_equal(r$builds$mean, c(1110, 1100, 1120))
  expect_equal(r$builds$sd, c(10, 10, 10))
})

test_that("EWMA reproduces the SPEC known answer", {
  r <- ewma_chart(c(100, 100, 150), mu0 = 100, sigma = 10)
  expect_equal(r$z, c(100, 100, 110))
  expect_equal(r$ucl[1], 106.00, tolerance = 0.01)
  expect_equal(r$ucl[3], 108.59, tolerance = 0.01)
  expect_equal(r$lcl[1], 94.00, tolerance = 0.01)
  expect_equal(r$out, c(FALSE, FALSE, TRUE))
})

# Planted Nelson series. Positions 1-10 alternate +0.5/-0.5, 11-19 sit at
# +0.5 (nine above CL), 20-24 alternate again starting with -0.5. Alternating
# fillers never run 14 long (the flat run at 11-19 breaks it) and never rise
# or fall for 6 steps, so only rule 2 fires, at point 19.
test_that("Nelson rule 2 flags point 19 only; rules 1, 3, 4 stay silent", {
  s <- c(rep(c(0.5, -0.5), 5), rep(0.5, 9), c(-0.5, 0.5, -0.5, 0.5, -0.5))
  expect_length(s, 24)
  r <- nelson_rules(s, cl = 0, sigma = 1)
  expect_equal(which(r$rule2), 19)
  expect_false(any(r$rule1))
  expect_false(any(r$rule3))
  expect_false(any(r$rule4))
})

test_that("Nelson rule 2: a 10th point is flagged too; a point on CL breaks the run", {
  r <- nelson_rules(c(rep(1, 10)), cl = 0, sigma = 5)
  expect_equal(which(r$rule2), c(9, 10))
  r2 <- nelson_rules(c(rep(1, 5), 0, rep(1, 8)), cl = 0, sigma = 5)
  expect_false(any(r2$rule2))
})

test_that("Nelson rule 1 flags one point at +3.5 sigma", {
  s <- c(0.5, -0.5, 3.5, -0.5, 0.5)
  r <- nelson_rules(s, cl = 0, sigma = 1)
  expect_equal(which(r$rule1), 3)
})

test_that("Nelson rule 3 flags the 6th point of a steady climb", {
  r <- nelson_rules(c(0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.4), cl = 0, sigma = 5)
  expect_equal(which(r$rule3), 6)
  r5 <- nelson_rules(c(0, 0.1, 0.2, 0.3, 0.4, 0.3), cl = 0, sigma = 5)
  expect_false(any(r5$rule3))
})

test_that("Nelson rule 4 flags the 14th alternating point", {
  s <- rep(c(1, -1), 7)           # 14 alternating points
  r <- nelson_rules(s, cl = 0, sigma = 5)
  expect_equal(which(r$rule4), 14)
  r13 <- nelson_rules(s[1:13], cl = 0, sigma = 5)
  expect_false(any(r13$rule4))
})

# qcc cross-check. Skipped (not fudged) if qcc is not installed.
test_that("xbar_s_limits agrees with qcc", {
  skip_if_not_installed("qcc")
  m <- matrix(yield, nrow = 3, byrow = TRUE)
  # "UWAVE-SD" = mean of subgroup sds / c4, the same sigma-hat as ours
  qx <- qcc::qcc(m, type = "xbar", std.dev = "UWAVE-SD", plot = FALSE)
  r <- xbar_s_limits(yield, build)
  expect_equal(unname(qx$limits[1, "LCL"]), unname(r$xbar["lcl"]), tolerance = 1e-6)
  expect_equal(unname(qx$limits[1, "UCL"]), unname(r$xbar["ucl"]), tolerance = 1e-6)
  qs <- qcc::qcc(m, type = "S", plot = FALSE)
  expect_equal(unname(qs$limits[1, "UCL"]), unname(r$s["ucl"]), tolerance = 1e-6)
  expect_equal(unname(qs$limits[1, "LCL"]), unname(r$s["lcl"]), tolerance = 1e-6)
})

test_that("ewma_chart agrees with qcc::ewma", {
  skip_if_not_installed("qcc")
  x <- c(100, 100, 150)
  q <- qcc::ewma(x, center = 100, std.dev = 10, lambda = 0.2, nsigmas = 3, plot = FALSE)
  r <- ewma_chart(x, mu0 = 100, sigma = 10)
  expect_equal(as.numeric(q$y), r$z, tolerance = 1e-9)
  expect_equal(as.numeric(q$limits[, "UCL"]), r$ucl, tolerance = 1e-6)
  expect_equal(as.numeric(q$limits[, "LCL"]), r$lcl, tolerance = 1e-6)
})

test_that("normality_check returns a p-value, or NA with a message", {
  set.seed(1)
  ok <- normality_check(rnorm(50))
  expect_true(ok$p_value >= 0 && ok$p_value <= 1)
  expect_true(is.na(normality_check(c(1, 2))$p_value))
  expect_match(normality_check(c(1, 2))$message, "3 and 5000")
  expect_true(is.na(normality_check(rep(1, 10))$p_value))
})

# ---- Degenerate cases ------------------------------------------------------

test_that("constant data: Cpk and Ppk are NA with a clear message", {
  r <- capability(rep(1100, 9), build, lsl = 1050)
  expect_true(is.na(r$cpk))
  expect_true(is.na(r$ppk))
  expect_match(r$message, "zero variation: capability undefined")
})

test_that("one coupon per build errors", {
  expect_error(capability(c(1, 2, 3), c("a", "b", "c"), lsl = 0),
               "need at least 2 coupons per build")
  expect_error(xbar_s_limits(c(1, 2, 3), c("a", "b", "c")),
               "need at least 2 coupons per build")
})

test_that("unequal build sizes error", {
  expect_error(capability(c(1, 2, 3, 4, 5), c("a", "a", "a", "b", "b"), lsl = 0),
               "unequal")
})

test_that("EWMA with sigma 0 errors", {
  expect_error(ewma_chart(c(1, 2, 3), mu0 = 2, sigma = 0), "sigma")
})

test_that("NA values are dropped with a warning and the answer is unchanged", {
  y2 <- c(yield, NA)
  b2 <- c(build, "B3")
  expect_warning(r <- capability(y2, b2, lsl = 1050), "missing")
  expect_equal(r$cpk, capability(yield, build, lsl = 1050)$cpk)
  expect_warning(l <- xbar_s_limits(y2, b2), "missing")
  expect_equal(l$xbar, xbar_s_limits(yield, build)$xbar)
})

test_that("abort_index fires on the k-th point of the first run of k out points", {
  out <- c(FALSE, TRUE, FALSE, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE)
  expect_equal(abort_index(out, k = 5), 8)   # run starts at 4, 5th out point is 8
  expect_equal(abort_index(out, k = 1), 2)
  # a run of 4 is not enough
  expect_true(is.na(abort_index(c(TRUE, TRUE, TRUE, TRUE, FALSE), k = 5)))
})

test_that("abort_index degenerate cases", {
  expect_true(is.na(abort_index(rep(FALSE, 200))))
  expect_true(is.na(abort_index(logical(0))))
  expect_error(abort_index(c(TRUE, NA)), "missing")
  expect_error(abort_index(TRUE, k = 0), "at least 1")
})
