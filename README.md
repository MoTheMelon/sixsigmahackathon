# AeroPrint SPC

**Live app (public): https://connect.systems-apps.com/content/894bc570-5881-4080-a60a-9650c3dafcfb/**

AeroPrint SPC is a Shiny dashboard for laser powder-bed-fusion (LPBF) Ti-6Al-4V aerospace brackets. It is for
the aerospace quality engineer who signs off each build batch and the additive-manufacturing (AM) technician
running the printers. It supports two decisions: (1) **during a build**, has chamber O2 or bed temperature
drifted out of control, so the build should be aborted and the printer recalibrated; (2) **after tensile
testing**, is the batch process capable of the flight spec (Cpk >= 1.33 standard, >= 1.67 safety-critical),
so it can be released. Team: Just Madeline. Prompt: Virtual DL Challenge 1, "Industrial Systems: 3D Printing
for Aerospace". **All bundled data are invented.**

Walkthrough of each test dataset: [demo/README.md](demo/README.md). Dataset codebook: [data/README.md](data/README.md).

## 1. Quick start

Needs R (developed on R 4.6.1). From the repo root:

```r
install.packages(c("shiny", "bslib", "plotly"))              # to run the app
install.packages(c("testthat", "qcc"))                         # to run the tests
install.packages("rsconnect")                                  # to write the manifest / deploy
```

```
Rscript app/testme.R
```

Then open http://127.0.0.1:8080. The statistics (`app/qc.R`) use base R only.

## 2. Inputs

**Telemetry CSV**, one row per build layer (upload in the sidebar, or use `data/telemetry.csv`):

| Column | Type / units | Meaning |
|---|---|---|
| `build_id` | text | build, e.g. `B-27` |
| `printer_id` | text | printer `A`-`D` |
| `layer_num` | integer | layer number |
| `chamber_o2_ppm` | number, ppm | layer-average chamber oxygen |
| `bed_temp_c` | number, deg C | layer-average bed temperature |
| `baseline` | optional TRUE/FALSE | Phase I in-control reference builds. If the column is missing, the first 20 builds (in file order) are the baseline |

**Coupons CSV**, one row per tensile coupon (`data/coupons.csv`):

| Column | Type / units | Meaning |
|---|---|---|
| `build_id` | text | build (the subgroup) |
| `coupon_id` | text | coupon, e.g. `B-01-C1` |
| `yield_strength_mpa` | number, MPa | yield strength |
| `uts_mpa` | number, MPa | ultimate tensile strength |
| `elongation_pct` | number, % | elongation at break |
| `porosity_pct` | number, % | porosity |

**Spec limits** (defaults, editable on page 2): yield LSL 1050 MPa, UTS LSL 1150 MPa, elongation LSL 8 %,
porosity USL 0.2 %. **Cpk target:** 1.33 (editable; use 1.67 for safety-critical parts).
**Phase I baseline:** builds B-01 to B-20 (`baseline == TRUE`); their layers give the EWMA centre mu0 and sigma.

**Upload rules:** all required columns must exist and the measurement columns must be numbers. Capability and
X-bar/S need **the same number of coupons in every build, and at least 2**; otherwise the app shows a message
(for example "need at least 2 coupons per build") instead of a number. Bad files are rejected with a message
and the previous data stay loaded.

## 3. Methods

Every formula below is exactly what `app/qc.R` computes.

- **c4(n)** = sqrt(2 / (n - 1)) * Gamma(n/2) / Gamma((n - 1)/2). c4(3) = 0.8862. Needs n >= 2.
- **sigma_within** = s-bar / c4(n), where s-bar is the mean of the per-build sample standard deviations
  (subgroup = one build, n = coupons per build).
- **sigma_overall** = sample standard deviation of all coupons (n - 1 denominator).
- **Cpk** = min(mean - LSL, USL - mean) / (3 sigma_within), using only the limits given. **Ppk** is the same with sigma_overall.
  All four specs are one-sided, so **Cp and Pp are "n/a: one-sided spec"** (they need both limits: (USL - LSL) / (6 sigma)).
  No upper limit is invented. If sigma is 0, Cpk/Ppk are NA with "zero variation: capability undefined".
- **X-bar chart:** CL = mean of build means; limits CL +/- A3 s-bar, A3 = 3 / (c4 sqrt(n)).
  **S chart:** CL = s-bar; LCL = B3 s-bar, UCL = B4 s-bar, with B3 = max(0, 1 - 3 sqrt(1 - c4^2) / c4), B4 = 1 + 3 sqrt(1 - c4^2) / c4.
- **Nelson rules 1-4** on the X-bar chart (sigma of a build mean = (UCL - CL) / 3): rule 1, one point more than 3 sigma from CL;
  rule 2, 9 in a row on the same side of CL; rule 3, 6 in a row steadily increasing or decreasing; rule 4, 14 in a row alternating up and down.
  A point exactly on CL breaks a rule 2 run.
- **EWMA** (chamber O2 and bed temperature, per layer): z_i = lambda x_i + (1 - lambda) z_(i-1), z_0 = mu0, **lambda = 0.2, L = 3**;
  time-varying limits mu0 +/- L sigma sqrt(lambda / (2 - lambda) * (1 - (1 - lambda)^(2i))). mu0 and sigma are the mean and standard deviation of the baseline layers
  (O2: 150.156 and 19.929 ppm; bed temp: 199.9999 and 1.5206 deg C on the bundled data). A layer is "out" when z is beyond the limits.
- **Abort rule:** the tool says ABORT only after **5 consecutive out layers** (`abort_index`, k = 5). Reason, measured on the bundled data:
  with L = 3 over 200 layers, **10 of 29** clean builds (all except B-27) had at least one O2 point out, so a single alarm is often chance;
  with the 5-in-a-row rule **0 of 29** clean builds abort, and B-27 (planted O2 ramp from layer 120) aborts at layer 139.
- **Shapiro-Wilk** p-value on the plotted values (3 to 5000 points); a warning appears when p < 0.05.

## 4. Assumptions and limitations

- Each property is assumed normal. **Porosity is bounded at 0 and skewed**, so its Cpk is approximate; the tool shows the Shapiro-Wilk warning but does not transform the data.
- Capability only means something when the process is in control. The banner says "NOT INTERPRETABLE" if any Nelson rule fires on the X-bar chart.
- Layers are treated as independent; real layer averages may be autocorrelated, which makes false alarms more likely.
- The EWMA baseline is pooled across the baseline builds (one mu0 and sigma for all printers), so printer-to-printer differences widen sigma.
- Equal coupons per build (at least 2). Only Nelson rules 1-4 are implemented. No live feed: "live" means replaying a stored build.
- All data are invented to look like field data; nothing here has been validated on a real printer.

## 5. Function reference (`app/qc.R`)

All functions are plain base R. Errors are `stop()` messages; the app catches them and shows the text.

| Function | Arguments | Returns | Errors / edge cases |
|---|---|---|---|
| `c4(n)` | `n` one number >= 2 | the constant c4 | `need at least 2 coupons per build` |
| `capability(x, build, lsl = NA, usl = NA)` | `x` values, `build` same-length build ids, spec limits | list: `mean`, `sigma_within`, `sigma_overall`, `cp`, `cpk`, `pp`, `ppk`, `n_builds`, `n_per_build`, `message` | error if lengths differ, a build has < 2 coupons, or builds are unequal; NA rows dropped with a warning; zero variation gives NA + `zero variation: capability undefined`; Cp/Pp NA + `Cp/Pp n/a: one-sided spec` |
| `xbar_s_limits(x, build)` | same as above | list: `builds` (mean, sd per build), `n`, `constants` (A3, B3, B4, c4), `xbar` (cl, ucl, lcl), `s` (cl, ucl, lcl) | same checks as `capability` |
| `nelson_rules(x, cl, sigma)` | `x` points in time order, centre line, sigma of a point | data frame: `i`, `x`, `rule1`..`rule4` (TRUE = flagged) | error on NA in `x` or `sigma <= 0` |
| `ewma_chart(x, mu0, sigma, lambda = 0.2, L = 3)` | per-layer values, baseline mean and sd | data frame: `i`, `x`, `z`, `ucl`, `lcl`, `out` | error on `sigma <= 0`, NA in `x`, or `lambda` outside (0, 1] |
| `abort_index(out, k = 5)` | logical `out` flags, run length `k` | index of the k-th point of the first run of k out points, or `NA` | error if `k < 1` or NA in `out` |
| `normality_check(x)` | numeric vector | list: `p_value`, `message` | p is NA with a message if fewer than 3 or more than 5000 points, or constant data |

`app/helpers.R` holds CSV loading/checking and the baseline mean/sd; it contains no statistics beyond those two numbers.

## 6. Pages

**SPC Monitor (page 1)**
- Controls: *Printer* (All, A-D) filters the *Build* list (default B-27); *Export flagged layer log* downloads a CSV (build, layer, variable, x, z, ucl, lcl) of out-of-control layers.
- KPI cards: builds loaded; fleet yield Cpk (all builds, LSL 1050); two status badges.
- **This build** badge: **RED** if the selected build meets the abort rule (5 EWMA out layers in a row); **AMBER** if it has any single EWMA out point; otherwise **GREEN**. On the bundled data: 12 GREEN, 17 AMBER, 1 RED (B-27).
- **Fleet** badge: **RED** if any yield build breaks a Nelson rule or fleet Cpk < 1.33; **AMBER** if fleet Cpk < 1.67 (or is NA); otherwise **GREEN**.
- Headline: "ABORT BUILD: NO", or "ABORT BUILD: YES - 5 consecutive out-of-control layers ending at layer N (O2 or bed temp)".
- Two EWMA charts (O2 ppm, bed temp deg C) with UCL/LCL, the centre line mu0, and out points in red.

**Capability Hub (page 2)**
- Controls: *Property* (yield, UTS, elongation, porosity); *Spec limit* (resets to the property default when you switch); *Cpk target* (default 1.33); *Exclude flagged builds* (drops builds that break a Nelson rule, then recomputes).
- Outputs: mean, sigma_within, sigma_overall, Cpk, Ppk, Cp/Pp ("n/a: one-sided spec"); histogram with density and the red spec-limit line; Shapiro-Wilk p-value and message; X-bar chart and S chart with flagged builds in red and the Nelson rule numbers listed.
- Banner, in this order: *CANNOT COMPUTE* (error message) -> **NOT INTERPRETABLE: process out of control** (any Nelson flag) -> grey message if Cpk is NA -> **AEROSPACE CAPABLE: Cpk >= target** -> **NON-CONFORMANT: Cpk < target**.

The sidebar on both pages uploads your own coupons or telemetry CSV, or resets to the bundled data.

## 7. Test datasets (details in [data/README.md](data/README.md))

- `data/telemetry.csv`: 30 builds x 200 layers; B-27 has a planted O2 ramp from layer 120 (EWMA catches it).
- `data/coupons.csv`: 30 builds x 5 coupons; capable overall, but B-27's yield and elongation are low so it trips Nelson rule 1.
- `data/edge_case.csv`: one constant build (E-01, "zero variation") and a one-coupon build (E-02, "need at least 2 coupons per build").

Rebuild them with `Rscript data/make_data.R` (seeded). `app/data/` is a copy for deployment.

## 8. Demo

Step-by-step walkthrough on each dataset: [demo/README.md](demo/README.md).

## 9. Tests

```
Rscript -e "testthat::test_dir('tests')"
```

Currently 67 expectations, all passing. The known-answer test (`tests/test_qc.R`) uses hand-worked data from SPEC section 4: yield
strength, 3 builds x 3 coupons (1100/1110/1120, 1090/1100/1110, 1110/1120/1130), LSL 1050. It checks c4(3) = 0.8862,
sigma_within = 11.284, **Cpk = 1.772**, sigma_overall = 12.247, **Ppk = 1.633**, Cp = Pp = NA, X-bar limits **1090.46 / 1129.54**,
S limits 0 / **25.68**; EWMA (mu0 100, sigma 10, x = 100, 100, 150) z_3 = 110 > UCL_3 = 108.59 and UCL_1 = 106.00; the abort rule
(F,T,F,T,T,T,T,T,T gives index 8); a planted 9-in-a-row run flags Nelson rule 2 at point 19 only; the degenerate cases
(constant coupons give NA + "zero variation: capability undefined"; one coupon per build errors). `qcc` is used only as a cross-check inside the tests.

## 10. Deploy

Pushing to `main` runs `.github/workflows/deploy-shiny-r.yml`, which publishes `app/` to Posit Connect. It needs two GitHub repo secrets,
`CONNECT_SERVER` and `CONNECT_API_KEY` (names only; never put values in a file). After adding or updating an R package, re-run
`Rscript app/manifestme.R` and commit `app/manifest.json`. To deploy by hand, `Rscript app/deployme.R` (reads the same two names from the environment or a gitignored `.env`).

## 11. Repo layout

```
app/        app.R (dashboard), qc.R (statistics), helpers.R (CSV loading), testme.R, manifestme.R, deployme.R, manifest.json, data/
data/       telemetry.csv, coupons.csv, edge_case.csv, make_data.R, README.md (codebook)
tests/      test_qc.R (testthat)
demo/       demo walkthrough
docs/       hackathon event pages, rubric (criteria.md)
SPEC.md, CONTRACT.yaml, docs/plan.md   what the tool is, task ledger, plan
.github/workflows/deploy-shiny-r.yml   deploy on push to main
```

## 12. AI use and citations

Built with Claude Code agents, one CONTRACT task at a time. The human steered by writing the known-answer and degenerate tests first
(SPEC section 4) and reviewing every statistic against hand calculations. Sources:
- `qcc` R package, used only to cross-check results in the tests.
- Fraser, T., course textbook: https://timothyfraser.com/sigma/
- Nelson, L. S. (1984). The Shewhart control chart: tests for special causes. *Journal of Quality Technology*, 16(4).
- Montgomery, D. C. *Introduction to Statistical Quality Control* (X-bar/S constants, EWMA chart, capability indices).

---
Built from the hackathon template [timothyfraser/sixsigmahackathon](https://github.com/timothyfraser/sixsigmahackathon) (MIT license, see [LICENSE](LICENSE)). Event info: [docs/](docs/).
