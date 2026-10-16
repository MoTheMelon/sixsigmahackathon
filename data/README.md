# Test data and codebook: AeroPrint SPC

**All data here are INVENTED.** They are simulated by `data/make_data.R` (base R, fixed seed 7) to look
like laser powder-bed-fusion (LPBF) Ti-6Al-4V field data. They are not from any real printer, lab or customer.
To rebuild them identically, run from the repo root: `Rscript data/make_data.R`

## Spec limits used with these data (editable in the tool)

| Property | Limit |
|---|---|
| Yield strength | LSL 1050 MPa |
| UTS | LSL 1150 MPa |
| Elongation | LSL 8 % |
| Porosity | USL 0.2 % |
| Cpk target | 1.33 (1.67 safety-critical) |

All four specs are one-sided, so Cp and Pp are "n/a: one-sided spec".

## telemetry.csv (6000 rows: 30 builds x 200 layers)

Shows: EWMA charts of per-layer chamber O2 and bed temperature, and a drift that EWMA catches.

| Column | Type | Units | Meaning |
|---|---|---|---|
| `build_id` | text | none | Build, `B-01` to `B-30` |
| `printer_id` | text | none | Printer `A`-`D`, rotating by build (B-01 = A, B-02 = B, ... B-27 = C) |
| `layer_num` | integer | layer | Layer number, 1 to 200 |
| `chamber_o2_ppm` | number | ppm | Layer-average chamber oxygen, 1 decimal |
| `bed_temp_c` | number | deg C | Layer-average bed temperature, 2 decimals |
| `baseline` | logical | TRUE/FALSE | TRUE for B-01 to B-20: the Phase I in-control reference builds |

In control: O2 ~ N(150, 20) ppm, bed temp ~ N(200, 1.5) C, independent per layer.
**Planted signal:** build **B-27** (printer C): from layer 120, O2 rises linearly, reaching about +150 ppm
at layer 200 (mean of layers 180-200 is about 283 ppm vs about 151 before layer 120). Bed temp and all other builds stay in control.

## coupons.csv (150 rows: 30 builds x 5 coupons)

Shows: a capable process (Cpk about 1.5-2 for yield, UTS and elongation, higher for porosity) with one bad build.

| Column | Type | Units | Meaning |
|---|---|---|---|
| `build_id` | text | none | Build, `B-01` to `B-30` (the subgroup) |
| `coupon_id` | text | none | Coupon, e.g. `B-01-C1` to `B-01-C5` |
| `yield_strength_mpa` | number | MPa | Yield strength, 1 decimal |
| `uts_mpa` | number | MPa | Ultimate tensile strength, 1 decimal |
| `elongation_pct` | number | % | Elongation at break, 1 decimal |
| `porosity_pct` | number | % | Porosity, 3 decimals (skewed, bounded at 0) |

In control: yield ~ 1102 + small build effect (sd 2) + N(0, 10); UTS ~ yield + 110 + N(0, 8);
elongation ~ N(11, 0.6); porosity lognormal, median 0.05 %.
**Planted signal:** build **B-27** has yield mean about 1066 (target 1060), elongation about 8.5 and porosity about 0.18,
so its yield mean falls below the X-bar LCL (Nelson rule 1) and the capability banner reads "NOT INTERPRETABLE".
Note: the build effect is kept small (sd 2, not 8) because X-bar limits use within-build spread; a larger build
effect would make healthy builds trip rule 1.

## edge_case.csv (6 rows)

Shows: the clear error messages. Same columns and units as `coupons.csv`.

- **E-01**: 5 coupons, all exactly 1100 / 1200 / 10 / 0.05 (constant), so s = 0 and
  Cpk/Ppk must say "zero variation: capability undefined".
- **E-02**: a single coupon, so the tool must say "need at least 2 coupons per build".

## How this would be collected for real

- **Telemetry:** export the printer controller log (about 1 Hz oxygen sensor and bed thermocouple
  readings), then average the readings within each layer.
- **Coupons:** tensile coupons printed in the same build, tested to ASTM E8 (yield, UTS, elongation).
- **Porosity:** Archimedes density measurement or micro-CT of the same coupons.
- **Baseline:** the engineer's record of the first 20 qualified, in-control builds.
