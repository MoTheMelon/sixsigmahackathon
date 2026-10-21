# AeroPrint SPC (Shiny dashboard)

For the aerospace quality engineer and AM technician. Page 1 "SPC Monitor" shows EWMA charts of
chamber O2 and bed temperature per build layer and says whether to abort the build. Page 2
"Capability Hub" shows Cpk/Ppk, X-bar and S charts, Nelson-rule flags and a release banner for
yield, UTS, elongation and porosity. All statistics are in `qc.R` (tested in `tests/`); `app.R`
only calls them.

## Run (from the repo root, one command)

    Rscript app/testme.R

Then open http://127.0.0.1:8080. Needs R packages shiny, bslib, plotly.

## Files

- `app.R` the dashboard; `qc.R` the statistics; `helpers.R` CSV loading and checking (no statistics)
- `testme.R` run locally; `manifestme.R` write `manifest.json`; `deployme.R` deploy to Posit Connect
  (reads `CONNECT_SERVER` and `CONNECT_API_KEY` from the environment or a gitignored `.env`)

## Data

`app/data/` holds copies of `data/telemetry.csv`, `data/coupons.csv` and `data/edge_case.csv`
(Posit Connect deploys only `app/`). The codebook is `data/README.md`. The sidebar lets you upload your own
coupons or telemetry CSV (same columns) to replace the bundled data; bad files give an error message.
