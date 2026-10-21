# docs.R - the in-app Docs tab. Text only: no statistics here.
# Numbers quoted below come from qc.R on the bundled data (see demo/README.md).

REPO_URL <- "https://github.com/MoTheMelon/sixsigmahackathon"

docs_link <- function(label, path, ...) {
  tags$a(label, href = paste0(REPO_URL, "/blob/main/", path), target = "_blank", ...)
}

docs_panel <- function() {
  nav_panel(
    "Docs",
    div(
      class = "container-md py-3", style = "max-width: 860px;",

      h2("AeroPrint SPC: how to use it"),
      p("AeroPrint SPC is for aerospace quality engineers and additive manufacturing technicians",
        "printing Ti-6Al-4V brackets. It answers two questions:"),
      tags$ol(
        tags$li(strong("During a build:"), " has chamber O2 or bed temperature drifted enough to abort this build?"),
        tags$li(strong("After coupon testing:"), " is the process capable of meeting the flight spec, so the batch can be released?")
      ),
      p("The app opens with bundled, invented test data. More detail is in the ",
        docs_link("README", "README.md"), " and the step-by-step ",
        docs_link("demo walkthrough", "demo/README.md", .noWS = "after"), "."),

      h3("Quick start"),
      tags$ol(
        tags$li(strong("SPC Monitor:"), " pick a printer and a build. Read the ", strong("ABORT BUILD"),
                " line and the ", strong("This build"), " box. Try B-27 (drifts) and B-01 (healthy)."),
        tags$li(strong("Capability Hub:"), " pick a property (yield, UTS, elongation, porosity). Read the banner first, then Cpk."),
        tags$li(strong("Your own data:"), " use the Data sidebar to upload a coupons CSV and/or a telemetry CSV. ",
                "Reset to bundled data returns to the demo.")
      ),

      h3("Your data"),
      tags$ul(
        tags$li(strong("Telemetry CSV"), " (one row per build layer): ",
                code("build_id, printer_id, layer_num, chamber_o2_ppm, bed_temp_c, baseline"),
                ". ", code("baseline"), " is TRUE for builds known to be in control; the EWMA centre and sigma come from them."),
        tags$li(strong("Coupons CSV"), " (one row per tensile coupon): ",
                code("build_id, coupon_id, yield_strength_mpa, uts_mpa, elongation_pct, porosity_pct"),
                ". Every build needs the same number of coupons, at least 2."),
        tags$li(strong("Spec limits"), " (editable on the Capability Hub): yield LSL 1050 MPa, UTS LSL 1150 MPa, ",
                "elongation LSL 8 %, porosity USL 0.2 %. Cpk target 1.33 (1.67 for safety-critical parts).")
      ),

      h3("How to read each output"),
      tags$dl(
        tags$dt("EWMA chart (SPC Monitor)"),
        tags$dd("A smoothed average of each layer. Red points are layers beyond the dashed control limits, ",
                "which are set from the in-control baseline builds."),
        tags$dt("ABORT BUILD"),
        tags$dd("YES only after 5 out-of-control layers in a row. One red point can be chance: with a 200-layer build, ",
                "10 of 29 clean builds had a lone O2 red point, but none had 5 in a row. B-27 aborts at layer 139."),
        tags$dt("This build box"),
        tags$dd("RED = abort rule met. AMBER = some red points, but no abort: keep watching. GREEN = no red points."),
        tags$dt("Fleet box"),
        tags$dd("RED if any build breaks a Nelson rule on yield, or fleet yield Cpk is below 1.33. ",
                "AMBER if Cpk is below 1.67. It is about all builds, not the one you picked."),
        tags$dt("Capability banner"),
        tags$dd(strong("NOT INTERPRETABLE"), " = a build is out of control, so Cpk does not describe one stable process; ",
                "fix or exclude that build first. ", strong("AEROSPACE CAPABLE"), " = Cpk at or above the target. ",
                strong("NON-CONFORMANT"), " = Cpk below the target."),
        tags$dt("Cpk and Ppk"),
        tags$dd("How many sigmas fit between the mean and the spec limit, divided by 3. Cpk 1.33 means the limit is ",
                "4 sigma away. Cpk uses spread within builds (short term); Ppk uses all coupons together (long term). ",
                "Ppk well below Cpk means builds differ from each other."),
        tags$dt("Cp and Pp show \"n/a\""),
        tags$dd("Cp and Pp need both a lower and an upper limit. Every spec here is one-sided, so they do not exist."),
        tags$dt("X-bar and S charts"),
        tags$dd("Each point is one build: its mean (X-bar) or its standard deviation (S). Red points break a Nelson rule."),
        tags$dt("Shapiro-Wilk p-value"),
        tags$dd("Checks whether the coupons look normally distributed. Below 0.05, Cpk may be unreliable. ",
                "Porosity is bounded at 0 and often skewed, so read its Cpk with care.")
      ),

      accordion(
        open = FALSE,
        accordion_panel(
          "The math (formulas)",
          tags$ul(
            tags$li("Within-build sigma: ", code("sigma_within = s-bar / c4(n)"), ", with ",
                    code("c4(n) = sqrt(2/(n-1)) * Gamma(n/2) / Gamma((n-1)/2)"), ". Overall sigma: ",
                    code("sigma_overall = sd(all coupons)"), "."),
            tags$li("One-sided capability: ", code("Cpk = (mean - LSL) / (3 sigma_within)"), " or ",
                    code("(USL - mean) / (3 sigma_within)"), ". Ppk is the same with sigma_overall."),
            tags$li("X-bar chart: ", code("CL +/- A3 * s-bar"), ", ", code("A3 = 3 / (c4 sqrt(n))"),
                    ". S chart: ", code("B3 * s-bar"), " to ", code("B4 * s-bar"), ", ",
                    code("B3, B4 = 1 -/+ 3 sqrt(1 - c4^2) / c4"), " (B3 floored at 0)."),
            tags$li("Nelson rules: (1) a point beyond 3 sigma; (2) 9 in a row on one side of the centre; ",
                    "(3) 6 in a row steadily up or down; (4) 14 in a row alternating up and down. ",
                    "Sigma is the sigma of a build mean, (UCL - CL) / 3."),
            tags$li("EWMA: ", code("z_i = 0.2 x_i + 0.8 z_(i-1)"), ", ", code("z_0 = mu0"), "; limits ",
                    code("mu0 +/- 3 sigma sqrt(0.2/1.8 * (1 - 0.8^(2i)))"),
                    ". mu0 and sigma are the mean and sd of the baseline builds."),
            tags$li("Known-answer check (in the tests): 3 builds x 3 coupons, 1100/1110/1120, 1090/1100/1110, ",
                    "1110/1120/1130, LSL 1050 gives Cpk 1.772 and Ppk 1.633.")
          )
        ),
        accordion_panel(
          "Assumptions and limits",
          tags$ul(
            tags$li("Capability means something only when the process is in control; the banner enforces this."),
            tags$li("Coupon properties are treated as roughly normal (checked with Shapiro-Wilk)."),
            tags$li("Layers are treated as independent; real layer averages may be autocorrelated, which raises false alarms."),
            tags$li("The EWMA sigma pools all baseline layers, so it includes build-to-build variation."),
            tags$li("The bundled data are invented, shaped like real LPBF telemetry and ASTM E8 tensile tests.")
          )
        )
      ),

      h3("Who made this", class = "mt-4"),
      p(strong("Madeline Ortiz"), " (GitHub ",
        tags$a("@MoTheMelon", href = "https://github.com/MoTheMelon", target = "_blank"), "), ",
        "for the Cornell University Systems Engineering Six Sigma Hackathon: ",
        "Virtual DL Challenge 1, \"Industrial Systems: 3D Printing for Aerospace\"."),
      p("Source code, tests and data: ", tags$a(REPO_URL, href = REPO_URL, target = "_blank"), "."),
      p(class = "small text-muted",
        "Built with R, Shiny, bslib and plotly; statistics in base R, cross-checked against the qcc package. ",
        "Methods follow the SYSEN 5300 textbook (timothyfraser.com/sigma), Nelson (1984, Journal of Quality Technology) ",
        "and Montgomery, Introduction to Statistical Quality Control. Built with help from Claude Code agents, ",
        "steered by tests against hand-worked answers.")
    )
  )
}
