# make_data.R - writes the three INVENTED test datasets for AeroPrint SPC.
# Run from the repo root:  Rscript data/make_data.R
# Base R only. The seed is fixed, so every run writes identical files.
set.seed(7)

builds  <- sprintf("B-%02d", 1:30)
printer <- c("A", "B", "C", "D")[(1:30 - 1) %% 4 + 1]   # rotate A,B,C,D; B-27 is on C

# ---- telemetry.csv: 30 builds x 200 layers --------------------------------
tel <- data.frame(
  build_id   = rep(builds, each = 200),
  printer_id = rep(printer, each = 200),
  layer_num  = rep(1:200, times = 30)
)
tel$chamber_o2_ppm <- rnorm(nrow(tel), mean = 150, sd = 20)   # in control
tel$bed_temp_c     <- rnorm(nrow(tel), mean = 200, sd = 1.5)  # in control
# Planted signal: B-27 O2 ramps linearly from layer 120, reaching +150 ppm at layer 200.
ramp <- tel$build_id == "B-27" & tel$layer_num >= 120
tel$chamber_o2_ppm[ramp] <- tel$chamber_o2_ppm[ramp] +
  150 * (tel$layer_num[ramp] - 120) / 80
tel$chamber_o2_ppm <- round(tel$chamber_o2_ppm, 1)
tel$bed_temp_c     <- round(tel$bed_temp_c, 2)
tel$baseline <- tel$build_id %in% builds[1:20]   # TRUE for B-01..B-20
write.csv(tel, "data/telemetry.csv", row.names = FALSE)

# ---- coupons.csv: 5 tensile coupons per build ------------------------------
cp <- data.frame(
  build_id  = rep(builds, each = 5),
  coupon_id = paste0(rep(builds, each = 5), "-C", rep(1:5, times = 30))
)
build_effect <- rep(rnorm(30, 0, 2), each = 5)   # small build-to-build shift
cp$yield_strength_mpa <- 1102 + build_effect + rnorm(150, 0, 10)
cp$uts_mpa            <- cp$yield_strength_mpa + 110 + rnorm(150, 0, 8)
cp$elongation_pct     <- rnorm(150, 11, 0.6)
cp$porosity_pct       <- rlnorm(150, meanlog = log(0.05), sdlog = 0.35)
# Planted signal: build B-27 (the O2 ramp build) has weak, porous coupons.
b27 <- cp$build_id == "B-27"
cp$yield_strength_mpa[b27] <- rnorm(5, 1060, 10)
cp$uts_mpa[b27]            <- cp$yield_strength_mpa[b27] + 110 + rnorm(5, 0, 8)
cp$elongation_pct[b27]     <- rnorm(5, 8.5, 0.4)
cp$porosity_pct[b27]       <- rlnorm(5, meanlog = log(0.18), sdlog = 0.15)
cp$yield_strength_mpa <- round(cp$yield_strength_mpa, 1)
cp$uts_mpa            <- round(cp$uts_mpa, 1)
cp$elongation_pct     <- round(cp$elongation_pct, 1)
cp$porosity_pct       <- round(cp$porosity_pct, 3)
write.csv(cp, "data/coupons.csv", row.names = FALSE)

# ---- edge_case.csv: constant build + single-coupon build ------------------
edge <- data.frame(
  build_id  = c(rep("E-01", 5), "E-02"),
  coupon_id = c(paste0("E-01-C", 1:5), "E-02-C1"),
  yield_strength_mpa = c(rep(1100, 5), 1100),
  uts_mpa            = c(rep(1200, 5), 1200),
  elongation_pct     = c(rep(10, 5), 10),
  porosity_pct       = c(rep(0.05, 5), 0.05)
)
write.csv(edge, "data/edge_case.csv", row.names = FALSE)
cat("wrote data/telemetry.csv, data/coupons.csv, data/edge_case.csv\n")
