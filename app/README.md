# app/ - AeroPrint SPC dashboard

This folder is the whole Shiny app, and the only folder deployed to Posit Connect. Full documentation (inputs,
methods, function reference, pages) is in the [root README](../README.md).

## The four scripts

| File | Job |
|---|---|
| `testme.R` | run the app locally: from the repo root, `Rscript app/testme.R`, then open http://127.0.0.1:8080 |
| `manifestme.R` | write `manifest.json` for Posit Connect (re-run after adding a package) |
| `deployme.R` | deploy to Posit Connect from your machine (needs `CONNECT_SERVER` and `CONNECT_API_KEY` in the environment or a gitignored `.env`) |
| `README.md` | this file |

## Other files

- `app.R` the dashboard; `qc.R` the statistics (base R); `helpers.R` CSV loading and checking (no statistics).
- `data/` is a copy of the root `data/` files (`telemetry.csv`, `coupons.csv`, `edge_case.csv`), because Connect deploys only `app/`.
  Codebook: [../data/README.md](../data/README.md).
