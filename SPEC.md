# SPEC: Six Sigma Hackathon team project

What your tool IS. Your agent reads this before every task. Where the code and this file
disagree, the code is the bug: change this file first, then the code.

Most of this page is already decided by the event and the [rubric](docs/criteria.md).
**Only the `FILL IN` lines change, and you do not have to write them by hand:** describe your app and ask your agent to update them. They depend on the prompt your team picks at kickoff
(prompts are secret until then, see [`docs/prompts.md`](docs/prompts.md)) and on your team.
The examples after each `FILL IN` show the shape of an answer. They are not hints about the prompts.

## 1. Team and prompt
- **Team name:** Just Madeline
- **Track:** Virtual DL Challenge (7 days). See [`docs/schedule.md`](docs/schedule.md).
- **Prompt we chose:** Virtual DL Challenge 1, "Industrial Systems: 3D Printing for Aerospace"
- **Our public repo:** https://github.com/MoTheMelon/sixsigmahackathon

## 2. User and use case (rubric: scope 5, user and use case 5)
- **User:** the aerospace quality engineer who signs off each laser powder-bed-fusion (LPBF) Ti-6Al-4V bracket batch, together with the additive manufacturing (AM) technician running the printers. Tool name: **AeroPrint SPC**.
- **Decision the tool helps them make, and when:** (1) during a build: whether chamber O2 or bed temperature has drifted out of control, so the build should be aborted and that printer recalibrated; (2) after the tensile coupons are tested: whether the batch's process is capable of meeting the flight spec (Cpk >= 1.33 standard, >= 1.67 safety-critical) and can be released.
- **Why this matches the prompt:** it applies SPC and process capability to the two quality risks of 3D-printing flight hardware: in-build process drift (chamber O2, bed temperature) and whether the finished parts' tensile properties reliably clear aerospace spec limits.

## 3. Inputs (rubric: minimal inputs 5)
Only what this user can actually measure or already knows. Fewer is better; every input a user
cannot measure costs points.

| Input | Type and units | Where the user gets it |
|---|---|---|
| `telemetry.csv`, one row per build layer: `build_id`, `printer_id` (A-D), `layer_num`, `chamber_o2_ppm`, `bed_temp_c` | text, factor, integer, ppm, deg C | printer controller log (1 Hz, averaged per layer) |
| `coupons.csv`, one row per tensile coupon: `build_id`, `coupon_id`, `yield_strength_mpa`, `uts_mpa`, `elongation_pct`, `porosity_pct` | text, text, MPa, MPa, %, % | tensile test report (ASTM E8) and Archimedes/CT porosity |
| Spec limits (defaults, editable): yield LSL 1050 MPa, UTS LSL 1150 MPa, elongation LSL 8 %, porosity USL 0.2 %; Cpk target 1.33 | MPa / % | the part drawing / material spec |
| Phase I baseline: which builds count as the in-control reference (default: the first 20 builds flagged `baseline`) | build ids | the engineer's record of qualified builds |

## 4. The statistics, and why (rubric: valid QC analysis 25)
Say the method in words before any code exists. Load the `stats-first-steering` skill first.
- **Method:** (a) **Process capability** for each mechanical property: subgroups = the coupons from one build. sigma_within = s-bar / c4(n); sigma_overall = sample s of all coupons. All four specs are one-sided, so Cpk = (mean - LSL) / (3 sigma_within) (or (USL - mean) / (3 sigma_within) for porosity), Ppk uses sigma_overall, and **Cp and Pp show as "n/a: one-sided spec"**. (b) **X-bar and S chart** of coupon properties by build: CL = grand mean, limits = X-double-bar +/- A3 s-bar; S limits B3 s-bar, B4 s-bar. (c) **EWMA chart** of per-layer chamber O2 and bed temp within a build: lambda = 0.2, L = 3, z_i = lambda x_i + (1 - lambda) z_(i-1), z_0 = mu0, limits mu0 +/- L sigma sqrt(lambda/(2-lambda) [1 - (1-lambda)^(2i)]), with mu0 and sigma from the Phase I baseline builds. **Abort rule:** a 200-layer build gives a 3-sigma EWMA many chances for a chance alarm (10 of 29 clean builds had at least one O2 out point), so the tool says ABORT only after **5 consecutive out-of-control layers** (0 of 29 clean builds abort; B-27 aborts at layer 139). (d) **Nelson rules 1-4** on the X-bar chart: 1 point beyond 3 sigma; 9 in a row on one side of CL; 6 in a row steadily increasing or decreasing; 14 in a row alternating up and down.
- **Why it fits the use case:** EWMA catches the small, slow O2 and thermal drifts that ruin a build before a Shewhart chart would, X-bar/S plus Nelson rules shows whether the build-to-build process is stable, and Cpk/Ppk against the one-sided flight specs gives the release yes/no.
- **Assumptions and how the tool checks them:** normality of each property (histogram + density on page 2, plus a Shapiro-Wilk p-value; porosity is bounded at 0 and often skewed, so the tool warns when p < 0.05); the process is in control before capability means anything (the capability banner says "not interpretable" if any Nelson rule fires on the X-bar/S chart); equal coupons per build (at least 2; the tool errors otherwise); EWMA baseline built only from in-control Phase I builds; layers treated as independent (stated as a limitation).
- **Known-answer check:** hand-worked, in `tests/`.
  - *Capability:* yield strength, 3 builds x 3 coupons: B1 = 1100, 1110, 1120; B2 = 1090, 1100, 1110; B3 = 1110, 1120, 1130; LSL = 1050. Build means 1110, 1100, 1120, grand mean 1110. Each build s = 10, so s-bar = 10. c4(3) = 0.8862, sigma_within = 10 / 0.8862 = 11.284, **Cpk = 60 / 33.851 = 1.772**. Overall: squared deviations from 1110 sum to 1200, s = sqrt(1200/8) = 12.247, **Ppk = 60 / 36.742 = 1.633**. Cp = Pp = n/a. X-bar limits = 1110 +/- 1.954 x 10 = **1090.46 / 1129.54**; S limits B3 = 0, **B4 s-bar = 25.68**.
  - *EWMA:* mu0 = 100, sigma = 10, lambda = 0.2, L = 3, x = 100, 100, 150. z = 100, 100, **110**. UCL_1 = 100 + 30 sqrt(0.1111 x 0.36) = **106.00**; UCL_3 = 100 + 30 sqrt(0.1111 x (1 - 0.8^6)) = **108.59**. Point 3 is flagged (110 > 108.59).
  - *Abort rule:* out flags F, T, F, T, T, T, T, T, T with k = 5 abort at point 8 (the 5th of the run starting at 4); a run of 4 never aborts; all-F gives NA.
  - *Nelson:* a planted series (9 points above CL at positions 11-19) flags rule 2 at point 19 and nowhere else.
  - *Degenerate:* constant coupons (all 1100) give s = 0, so Cpk/Ppk return NA with the message "zero variation: capability undefined"; one coupon per build gives an error "need at least 2 coupons per build".

Fixed for every team:
- The statistic lives in **one plain, tested function** (`app/qc.py` or `app/qc.R`). The API, app or
  package only calls it and displays the result. No statistics inside UI code.
- Every statistic has a test against a known answer and a degenerate case (constant data, n = 1, missing values).
- You can explain every number the tool prints. If you cannot, it is not done.

## 5. Delivery (rubric: working tool 25)
- **Stack:** dashboard in R Shiny + bslib (Bootstrap 5), plotly charts, DT tables; statistics in plain base R in `app/qc.R`, tested with testthat (qcc used only as a cross-check in the tests, never in the app).
- **Starting demo:** `demos/shinyapp/`

Fixed for every team:
- Start from **one** demo in `demos/`, copied to `app/`. Keep its four-script contract
  (`testme`, `manifestme`, `deployme`, `README.md`); `testme` starts the tool with one command.
- Deployed on the course **Posit Connect** server with a public URL (publisher key handed out at the
  event). Deploy early: copy one workflow from
  [`.claude/skills/connect-publish/workflows/`](.claude/skills/connect-publish/workflows/).
- A small tool that runs beats a large tool that does not.

## 6. Outputs
- **What the user sees:**
  - *Page 1, SPC monitor:* printer selector and build selector; KPI cards (builds loaded, fleet Cpk for yield, active alarms with a red/amber/green badge); EWMA charts of chamber O2 (ppm) and bed temp (deg C) per layer with UCL/LCL and violating points in red; "ABORT BUILD: yes/no"; a download of the flagged-layer log as CSV. *How to read it:* a red point means the layer average has drifted beyond what in-control builds produce, so abort and recalibrate.
  - *Page 2, capability hub:* property toggle (yield, UTS, elongation, porosity); mean, sigma_within, sigma_overall, Cpk, Ppk (Cp/Pp "n/a: one-sided spec"); a banner "AEROSPACE CAPABLE: Cpk >= 1.33", "NON-CONFORMANT: Cpk < 1.33" or "NOT INTERPRETABLE: process out of control"; histogram + density with the spec limit line; X-bar and S charts with Nelson-rule flags; Shapiro-Wilk p-value. *How to read it:* Cpk 1.33 means the nearest spec limit is 4 within-build sigmas from the mean.
  - *Page 3 (stretch, only after H-03 to H-06 pass):* table of non-conforming builds with the rule that fired and a suggested check (for example "O2 drift: check inert gas recirculation seal"), plus a scatter of build mean O2 vs yield strength.

## 7. Test datasets and codebook (rubric: demo 10, datasets 5, codebook 5)
2-3 small CSVs in `data/`, invented but shaped like real field data, each showing one behavior.
`data/README.md` is the codebook: every file, every column with units, and what it would take to
collect this data for real.
- **Datasets:** `telemetry.csv` (30 builds x 4 printers' worth of layers; builds 1-20 are the in-control baseline; Machine C's build B-27 has a planted O2 ramp from layer 120), `coupons.csv` (5 coupons per build; capable overall, with B-27's coupons low in yield and elongation so it trips Nelson rule 1), `edge_case.csv` (one build, constant values, plus a build with one coupon, to show the clear error messages).

## 8. Documentation and reproducibility (rubric: docs 10, public repo 5)
- `README.md` says what the tool does, for whom, every input and parameter, how to run it in one
  command, and walks through the demo on each test dataset.
- Public GitHub repo; a fresh clone runs `testme` and the tests pass with no extra steps.
- Submit on Devpost: the repo link plus a demo.

## 9. Out of scope
What we will NOT build, so nobody (human or agent) builds it by accident.
- Default: logins, databases, real customer data, a second statistic before the first one is tested.
- No live data feed (the tool reads CSVs; "live" means replaying a build layer by layer). No Lasso, ridge or random forest. No PDF report generator (CSV export only). No humidity, pressure, recoater or laser-energy charts in the core (they can be added as optional columns to the page 3 stretch). No date-range picker.
