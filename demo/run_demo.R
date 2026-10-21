# demo/run_demo.R - prints every number that demo/README.md quotes.
# Run from the repo root:  Rscript demo/run_demo.R
# It uses the same functions and rules as the app (app/qc.R, app/helpers.R).

source("app/qc.R")
source("app/helpers.R")

ABORT_RUN <- 5   # same abort rule as the app: 5 consecutive out layers
f <- function(v, d = 4) if (is.na(v)) "NA" else sprintf(paste0("%.", d, "f"), v)

# Same chart analysis as the app: X-bar/S limits, Nelson rules on build means.
analyse_chart <- function(x, build) {
  lim <- xbar_s_limits(x, build)
  cl <- unname(lim$xbar["cl"])
  sigma_mean <- (unname(lim$xbar["ucl"]) - cl) / 3
  flag <- rep(FALSE, nrow(lim$builds)); nl <- NULL
  if (sigma_mean > 0) {
    nl <- nelson_rules(lim$builds$mean, cl, sigma_mean)
    flag <- nl$rule1 | nl$rule2 | nl$rule3 | nl$rule4
  }
  list(lim = lim, nl = nl, flag = flag, flagged = lim$builds$build[flag])
}

# ============================================================ telemetry.csv ==
cat("\n==================== data/telemetry.csv ====================\n")
tel <- load_telemetry("data/telemetry.csv")
cat("rows:", nrow(tel), " builds:", length(unique(tel$build_id)), "\n")
vars <- c(o2 = "chamber_o2_ppm", temp = "bed_temp_c")
bp <- lapply(vars, function(v) baseline_params(tel, v))
for (nm in names(vars)) {
  cat(sprintf("baseline %s: mu0 = %s, sigma = %s\n", vars[[nm]],
              f(bp[[nm]]["mu0"]), f(bp[[nm]]["sigma"])))
}

ewma_summary <- function(id) {
  d <- tel[tel$build_id == id, ]
  cat(sprintf("\n-- build %s (printer %s) --\n", id, d$printer_id[1]))
  first_abort <- NULL
  for (nm in names(vars)) {
    r <- ewma_chart(d[[vars[[nm]]]], bp[[nm]]["mu0"], bp[[nm]]["sigma"])
    out_layers <- d$layer_num[r$out]
    ai <- abort_index(r$out, k = ABORT_RUN)
    cat(sprintf("%s: out-of-control layers = %d; first out layer = %s; abort layer = %s\n",
                vars[[nm]], sum(r$out),
                if (any(r$out)) out_layers[1] else "none",
                if (is.na(ai)) "none" else d$layer_num[ai]))
    if (!is.na(ai)) first_abort <- c(first_abort, d$layer_num[ai])
    if (sum(r$out) > 0 && sum(r$out) <= 5) cat("   out layers:", out_layers, "\n")
    if (sum(r$out) > 5) cat("   first 8 out layers:", head(out_layers, 8), "\n")
  }
  cat("ABORT BUILD:", if (is.null(first_abort)) "NO" else
        sprintf("YES (layer %d)", min(first_abort)), "\n")
}
ewma_summary("B-27")
ewma_summary("B-01")

cat("\n-- builds with a lone out layer but no abort (chance alarms) --\n")
lone <- character(0); aborts <- character(0)
for (id in unique(tel$build_id)) {
  d <- tel[tel$build_id == id, ]
  for (nm in names(vars)) {
    r <- ewma_chart(d[[vars[[nm]]]], bp[[nm]]["mu0"], bp[[nm]]["sigma"])
    if (!is.na(abort_index(r$out, k = ABORT_RUN))) aborts <- c(aborts, id)
    else if (any(r$out)) lone <- c(lone, paste0(id, "(", vars[[nm]], ")"))
  }
}
cat("builds that abort:", paste(unique(aborts), collapse = ", "), "\n")
cat("count of builds that abort:", length(unique(aborts)), "of 30\n")
cat("some with out points but no abort:", paste(head(lone, 6), collapse = ", "), "\n")
cat("O2 mean of B-27 layers 1-119:", f(mean(tel$chamber_o2_ppm[tel$build_id == "B-27" & tel$layer_num < 120]), 1), "\n")
cat("O2 mean of B-27 layers 180-200:", f(mean(tel$chamber_o2_ppm[tel$build_id == "B-27" & tel$layer_num >= 180]), 1), "\n")

# ============================================================== coupons.csv ==
cat("\n==================== data/coupons.csv ====================\n")
cp <- load_coupons("data/coupons.csv")
cat("rows:", nrow(cp), " builds:", length(unique(cp$build_id)), "\n")

show_prop <- function(key, exclude) {
  pr <- PROPERTIES[[key]]
  x <- cp[[pr$col]]; b <- cp$build_id
  ana <- analyse_chart(x, b)
  if (exclude) { keep <- !(b %in% ana$flagged); x <- x[keep]; b <- b[keep]
                 ana <- analyse_chart(x, b) }
  cap <- capability(x, b, lsl = if (pr$side == "lsl") pr$limit else NA,
                    usl = if (pr$side == "usl") pr$limit else NA)
  nc <- normality_check(x)
  cat(sprintf("\n[%s] limit %s %s | exclude flagged builds: %s | builds used: %d\n",
              key, toupper(pr$side), pr$limit, exclude, cap$n_builds))
  banner <- if (length(ana$flagged) > 0)
    paste0("NOT INTERPRETABLE: process out of control (builds ",
           paste(ana$flagged, collapse = ", "), ")")
  else if (cap$cpk >= 1.33) "AEROSPACE CAPABLE: Cpk >= 1.33"
  else "NON-CONFORMANT: Cpk < 1.33"
  cat("banner:", banner, "\n")
  cat(sprintf("mean = %s, sigma_within = %s, sigma_overall = %s\n",
              f(cap$mean), f(cap$sigma_within), f(cap$sigma_overall)))
  cat(sprintf("Cpk = %s, Ppk = %s, Cp = %s, Pp = %s (both n/a: one-sided spec)\n",
              f(cap$cpk), f(cap$ppk), f(cap$cp), f(cap$pp)))
  cat(sprintf("Shapiro-Wilk p = %s; %s\n", f(nc$p_value), nc$message))
  if (!is.null(ana$nl) && length(ana$flagged) > 0) {
    for (i in which(ana$flag)) {
      rules <- which(unlist(ana$nl[i, c("rule1", "rule2", "rule3", "rule4")]))
      cat(sprintf("Nelson flag: %s (rule %s), build mean = %s\n",
                  ana$lim$builds$build[i], paste(rules, collapse = ", "),
                  f(ana$lim$builds$mean[i], 2)))
    }
  }
  invisible(ana)
}
for (k in c("yield", "uts", "elong", "poro")) {
  show_prop(k, FALSE)
  show_prop(k, TRUE)
}

ana <- analyse_chart(cp$yield_strength_mpa, cp$build_id)
cat(sprintf("\nyield X-bar chart: CL = %s, UCL = %s, LCL = %s\n",
            f(ana$lim$xbar["cl"], 2), f(ana$lim$xbar["ucl"], 2), f(ana$lim$xbar["lcl"], 2)))
cat(sprintf("yield S chart: CL = %s, UCL = %s\n", f(ana$lim$s["cl"], 2), f(ana$lim$s["ucl"], 2)))
cat("B-27 yield build mean:", f(ana$lim$builds$mean[ana$lim$builds$build == "B-27"], 2), "\n")

# ============================================================ edge_case.csv ==
cat("\n==================== data/edge_case.csv ====================\n")
ed <- load_coupons("data/edge_case.csv")
cat("rows:", nrow(ed), " builds:", paste(unique(ed$build_id), collapse = ", "), "\n")
r <- safely(capability(ed$yield_strength_mpa, ed$build_id, lsl = 1050))
cat("whole file, yield: error =", r$error, "\n")
for (id in unique(ed$build_id)) {
  r <- safely(capability(ed$yield_strength_mpa[ed$build_id == id],
                         ed$build_id[ed$build_id == id], lsl = 1050))
  cat(sprintf("%s alone: %s\n", id,
              if (!is.null(r$error)) r$error else r$value$message))
}
e1 <- ed[ed$build_id == "E-01", ]
r <- capability(e1$yield_strength_mpa, e1$build_id, lsl = 1050)
cat(sprintf("E-01 alone: Cpk = %s, Ppk = %s, message = %s\n", f(r$cpk), f(r$ppk), r$message))

cat("\n==================== known answer (SPEC section 4) ====================\n")
y <- c(1100, 1110, 1120, 1090, 1100, 1110, 1110, 1120, 1130)
b <- rep(c("B1", "B2", "B3"), each = 3)
k <- capability(y, b, lsl = 1050); l <- xbar_s_limits(y, b)
cat(sprintf("Cpk = %s, Ppk = %s, X-bar limits = %s / %s, B4 s-bar = %s\n",
            f(k$cpk, 3), f(k$ppk, 3), f(l$xbar["lcl"], 2), f(l$xbar["ucl"], 2), f(l$s["ucl"], 2)))
e <- ewma_chart(c(100, 100, 150), 100, 10)
cat(sprintf("EWMA z3 = %s, UCL1 = %s, UCL3 = %s, point 3 out = %s\n",
            f(e$z[3], 2), f(e$ucl[1], 2), f(e$ucl[3], 2), e$out[3]))
