# app/helpers.R - data loading and checking for the Shiny app.
# NO statistics here. Statistics live only in qc.R.

COUPON_COLS <- c("build_id", "coupon_id", "yield_strength_mpa", "uts_mpa",
                 "elongation_pct", "porosity_pct")
TELEMETRY_COLS <- c("build_id", "printer_id", "layer_num",
                    "chamber_o2_ppm", "bed_temp_c")

# Read a CSV and stop with a plain message if columns are missing or not numeric.
read_checked_csv <- function(path, required, numeric_cols) {
  d <- tryCatch(
    read.csv(path, stringsAsFactors = FALSE),
    error = function(e) stop("could not read the file as a CSV: ", conditionMessage(e), call. = FALSE)
  )
  missing_cols <- setdiff(required, names(d))
  if (length(missing_cols) > 0) {
    stop("missing column(s): ", paste(missing_cols, collapse = ", "),
         ". Expected: ", paste(required, collapse = ", "), call. = FALSE)
  }
  if (nrow(d) == 0) stop("the file has no rows", call. = FALSE)
  for (col in numeric_cols) {
    if (!is.numeric(d[[col]])) {
      stop("column '", col, "' must be numbers", call. = FALSE)
    }
  }
  d
}

load_coupons <- function(path) {
  d <- read_checked_csv(path, COUPON_COLS, COUPON_COLS[3:6])
  d$build_id <- as.character(d$build_id)
  d
}

load_telemetry <- function(path) {
  d <- read_checked_csv(path, TELEMETRY_COLS,
                        c("layer_num", "chamber_o2_ppm", "bed_temp_c"))
  d$build_id <- as.character(d$build_id)
  d$printer_id <- as.character(d$printer_id)
  # Phase I baseline: use the 'baseline' column; if absent, the first 20 builds.
  if ("baseline" %in% names(d)) {
    d$baseline <- as.logical(d$baseline)
    d$baseline[is.na(d$baseline)] <- FALSE
  } else {
    d$baseline <- d$build_id %in% head(unique(d$build_id), 20)
  }
  d[order(d$build_id, d$layer_num), ]
}

# Mean and sd of the Phase I baseline rows (the EWMA mu0 and sigma, SPEC 4c).
# These are the only two numbers computed outside qc.R; they are the
# definition of the baseline, not a new statistic.
baseline_params <- function(tel, var) {
  v <- tel[[var]][tel$baseline]
  if (length(v) < 2) stop("need at least 2 baseline layers (baseline == TRUE)")
  c(mu0 = mean(v), sigma = sd(v))
}

# Run an expression; return list(value, error) instead of crashing.
safely <- function(expr) {
  tryCatch(list(value = expr, error = NULL),
           error = function(e) list(value = NULL, error = conditionMessage(e)))
}

PROPERTIES <- list(
  yield = list(label = "Yield strength (MPa)", col = "yield_strength_mpa",
               side = "lsl", limit = 1050),
  uts = list(label = "UTS (MPa)", col = "uts_mpa", side = "lsl", limit = 1150),
  elong = list(label = "Elongation (%)", col = "elongation_pct",
               side = "lsl", limit = 8),
  poro = list(label = "Porosity (%)", col = "porosity_pct",
              side = "usl", limit = 0.2)
)
