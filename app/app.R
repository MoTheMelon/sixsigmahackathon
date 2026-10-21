# app.R - AeroPrint SPC dashboard (Shiny + bslib + plotly).
# Every statistic comes from qc.R. This file only loads data, calls those
# functions and draws the results.

library(shiny)
library(bslib)
library(plotly)

# Paths are relative to the app folder: shiny::runApp("app") and Posit Connect
# both set the working directory to the folder that holds app.R.
source("qc.R")
source("helpers.R")
source("docs.R")

DEFAULT_COUPONS <- "data/coupons.csv"
DEFAULT_TELEMETRY <- "data/telemetry.csv"
EWMA_VARS <- c(o2 = "chamber_o2_ppm", temp = "bed_temp_c")
EWMA_LABELS <- c(chamber_o2_ppm = "O2", bed_temp_c = "bed temp")
YIELD_LSL <- 1050
ABORT_RUN <- 5   # abort after 5 consecutive EWMA out-of-control layers

# Run the Shewhart X-bar / S limits and the Nelson rules on build means.
# sigma for Nelson is the sigma of a build MEAN: (UCL - CL) / 3.
analyse_chart <- function(x, build) {
  lim <- xbar_s_limits(x, build)
  cl <- unname(lim$xbar["cl"])
  sigma_mean <- (unname(lim$xbar["ucl"]) - cl) / 3
  nl <- NULL
  flag <- rep(FALSE, nrow(lim$builds))
  if (sigma_mean > 0) {   # zero spread: no chart rules; capability reports it
    nl <- nelson_rules(lim$builds$mean, cl, sigma_mean)
    flag <- nl$rule1 | nl$rule2 | nl$rule3 | nl$rule4
  }
  list(lim = lim, nl = nl, flag = flag, flagged = lim$builds$build[flag])
}

fmt <- function(v, digits = 4) if (is.na(v)) "NA" else sprintf(paste0("%.", digits, "f"), v)

how_to <- function(...) p(class = "text-muted small", "How to read this: ", ...)

# ------------------------------------------------------------------ plots --
plot_ewma <- function(d, mu0, title, ylab) {
  out <- d[d$out, ]
  plot_ly(d, x = ~layer) |>
    add_lines(y = ~z, name = "EWMA z", line = list(color = "#1f77b4")) |>
    add_lines(y = ~ucl, name = "UCL", line = list(color = "grey", dash = "dash")) |>
    add_lines(y = ~lcl, name = "LCL", line = list(color = "grey", dash = "dash")) |>
    add_lines(y = mu0, name = "center mu0", line = list(color = "black", dash = "dot")) |>
    add_markers(data = out, x = ~layer, y = ~z, name = "out of control",
                marker = list(color = "red", size = 7)) |>
    layout(title = title, xaxis = list(title = "layer"), yaxis = list(title = ylab))
}

plot_xbar_like <- function(builds, y, cl, ucl, lcl, flag, title, ylab) {
  d <- data.frame(build = factor(builds, levels = builds), y = y, flag = flag)
  plot_ly(d, x = ~build) |>
    add_lines(y = ~y, name = ylab, line = list(color = "#1f77b4")) |>
    add_markers(y = ~y, name = ylab, showlegend = FALSE,
                marker = list(color = ifelse(flag, "red", "#1f77b4"), size = 7)) |>
    add_lines(y = ucl, name = "UCL", line = list(color = "grey", dash = "dash")) |>
    add_lines(y = lcl, name = "LCL", line = list(color = "grey", dash = "dash")) |>
    add_lines(y = cl, name = "CL", line = list(color = "black", dash = "dot")) |>
    layout(title = title, xaxis = list(title = "build"), yaxis = list(title = ylab))
}

# ------------------------------------------------------------------- UI ----
ui <- page_navbar(
  title = "AeroPrint SPC",
  theme = bs_theme(version = 5),
  sidebar = sidebar(
    title = "Data",
    p(class = "small text-muted",
      "Bundled invented data is loaded. Upload a CSV to replace it."),
    fileInput("up_coupons", "Coupons CSV", accept = ".csv"),
    fileInput("up_tel", "Telemetry CSV", accept = ".csv"),
    actionButton("reset", "Reset to bundled data")
  ),

  nav_panel(
    "SPC Monitor",
    layout_sidebar(
      sidebar = sidebar(
        selectInput("printer", "Printer", c("All", "A", "B", "C", "D")),
        selectInput("build", "Build", choices = "B-27", selected = "B-27"),
        downloadButton("dl_flags", "Export flagged layer log")
      ),
      layout_columns(
        col_widths = c(3, 3, 3, 3), fill = FALSE,
        uiOutput("kpi_builds"),
        uiOutput("kpi_cpk"),
        uiOutput("kpi_build_alarm"),
        uiOutput("kpi_fleet_alarm")
      ),
      h4(textOutput("abort_text")),
      layout_columns(
        col_widths = c(6, 6),
        card(card_header("Chamber O2 (ppm), EWMA"), plotlyOutput("ewma_o2"),
             how_to("a red point means the smoothed layer average is beyond what in-control builds produce; one red point can be chance, 5 in a row means abort and recalibrate.")),
        card(card_header("Bed temperature (deg C), EWMA"), plotlyOutput("ewma_temp"),
             how_to("the blue line is the smoothed layer value (lambda 0.2); the dashed lines widen at first, then settle at 3 sigma limits from the baseline builds."))
      )
    )
  ),

  nav_panel(
    "Capability Hub",
    layout_sidebar(
      sidebar = sidebar(
        radioButtons("prop", "Property",
                     choices = c("Yield (LSL 1050)" = "yield", "UTS (LSL 1150)" = "uts",
                                 "Elongation (LSL 8)" = "elong", "Porosity (USL 0.2)" = "poro")),
        numericInput("spec", "Spec limit", value = 1050),
        numericInput("target", "Cpk target", value = 1.33, step = 0.01),
        p(class = "small text-muted", "Safety-critical parts: target 1.67."),
        checkboxInput("excl", "Exclude flagged builds", value = FALSE)
      ),
      uiOutput("banner"),
      layout_columns(
        col_widths = c(5, 7),
        card(card_header("Capability"), uiOutput("cap_table"),
             how_to("Cpk 1.33 means the nearest spec limit is 4 within-build sigmas from the mean (3 x 1.33). Cpk uses within-build sigma; Ppk uses overall sigma.")),
        card(card_header("Distribution"), plotlyOutput("hist"),
             textOutput("shapiro"),
             how_to("bars and curve should look like one bell; the red line is the spec limit and the mean should sit well away from it."))
      ),
      layout_columns(
        col_widths = c(6, 6),
        card(card_header("X-bar chart (build means)"), plotlyOutput("xbar"),
             textOutput("flag_text"),
             how_to("each point is one build; red points break a Nelson rule, so that build is not behaving like the others.")),
        card(card_header("S chart (build standard deviations)"), plotlyOutput("schart"),
             how_to("this watches spread inside a build; a point above the UCL means a build was unusually scattered."))
      )
    )
  ),

  docs_panel()
)

# --------------------------------------------------------------- server ----
server <- function(input, output, session) {

  coupons <- reactiveVal(load_coupons(DEFAULT_COUPONS))
  tel <- reactiveVal(load_telemetry(DEFAULT_TELEMETRY))

  # ---- uploads: validate, never crash
  observeEvent(input$up_coupons, {
    r <- safely(load_coupons(input$up_coupons$datapath))
    if (!is.null(r$error)) {
      showNotification(paste("Coupons file rejected:", r$error), type = "error", duration = 10)
    } else {
      coupons(r$value)
      showNotification("Coupons file loaded.", type = "message")
    }
  })
  observeEvent(input$up_tel, {
    r <- safely(load_telemetry(input$up_tel$datapath))
    if (!is.null(r$error)) {
      showNotification(paste("Telemetry file rejected:", r$error), type = "error", duration = 10)
    } else {
      tel(r$value)
      showNotification("Telemetry file loaded.", type = "message")
    }
  })
  observeEvent(input$reset, {
    coupons(load_coupons(DEFAULT_COUPONS))
    tel(load_telemetry(DEFAULT_TELEMETRY))
    showNotification("Bundled data restored.", type = "message")
  })

  # ---- page 1: build selector follows the printer selector
  observe({
    t <- tel()
    ids <- unique(t$build_id[input$printer == "All" | t$printer_id == input$printer])
    keep <- isolate(input$build)
    sel <- if (!is.null(keep) && keep %in% ids) keep else if ("B-27" %in% ids) "B-27" else ids[1]
    updateSelectInput(session, "build", choices = ids, selected = sel)
  })

  # Phase I baseline mu0 and sigma, computed once per telemetry file
  baseline <- reactive({
    safely(lapply(setNames(nm = EWMA_VARS), function(v) baseline_params(tel(), v)))
  })

  ewma_res <- reactive({
    req(input$build)
    d <- tel()[tel()$build_id == input$build, ]
    b <- baseline()
    lapply(setNames(nm = EWMA_VARS), function(v) {
      if (!is.null(b$error)) return(list(value = NULL, error = b$error))
      safely({
        bp <- b$value[[v]]
        r <- ewma_chart(d[[v]], unname(bp["mu0"]), unname(bp["sigma"]))
        r$layer <- d$layer_num
        r$mu0 <- unname(bp["mu0"])
        r
      })
    })
  })

  # abort layer over both variables: the 5th of 5 consecutive EWMA out layers
  # (abort_index in qc.R); list(layer, label) or NULL
  first_flag <- reactive({
    best <- NULL
    for (nm in names(EWMA_VARS)) {
      r <- ewma_res()[[EWMA_VARS[[nm]]]]
      idx <- if (is.null(r$value)) NA_integer_ else abort_index(r$value$out, k = ABORT_RUN)
      if (!is.na(idx)) {
        layer <- r$value$layer[idx]
        if (is.null(best) || layer < best$layer) {
          best <- list(layer = layer, label = EWMA_LABELS[[EWMA_VARS[[nm]]]])
        }
      }
    }
    best
  })

  fleet <- reactive(safely(capability(coupons()$yield_strength_mpa, coupons()$build_id, lsl = YIELD_LSL)))
  yield_chart <- reactive(safely(analyse_chart(coupons()$yield_strength_mpa, coupons()$build_id)))

  n_ewma_out <- reactive({
    sum(vapply(ewma_res(), function(r) if (is.null(r$value)) 0L else sum(r$value$out), integer(1)))
  })

  badge <- function(red, amber) {
    list(level = if (red) "RED" else if (amber) "AMBER" else "GREEN",
         theme = if (red) "danger" else if (amber) "warning" else "success")
  }

  # this build: RED = abort rule met; AMBER = a single EWMA out point (can be chance)
  build_alarm <- reactive({
    b <- badge(!is.null(first_flag()), n_ewma_out() > 0)
    b$why <- sprintf("%d EWMA out-of-control layer(s); abort needs %d in a row", n_ewma_out(), ABORT_RUN)
    b
  })

  # fleet: RED = a yield build breaks a Nelson rule or fleet Cpk < 1.33; AMBER = Cpk < 1.67 or unknown
  fleet_alarm <- reactive({
    n_nelson <- if (is.null(yield_chart()$value)) 0L else length(yield_chart()$value$flagged)
    cpk <- if (is.null(fleet()$value)) NA_real_ else fleet()$value$cpk
    b <- badge(n_nelson > 0 || (!is.na(cpk) && cpk < 1.33), is.na(cpk) || cpk < 1.67)
    b$why <- sprintf("%d yield build(s) with a Nelson flag; fleet Cpk %s", n_nelson, fmt(cpk, 3))
    b
  })

  output$kpi_builds <- renderUI(
    value_box("Builds loaded", length(unique(tel()$build_id)),
              p(class = "small", paste(length(unique(coupons()$build_id)), "builds with coupons")))
  )
  output$kpi_cpk <- renderUI({
    f <- fleet()
    value_box("Fleet Cpk (yield, LSL 1050)",
              if (is.null(f$value)) "NA" else fmt(f$value$cpk, 3),
              p(class = "small", if (is.null(f$value)) f$error else f$value$message))
  })
  output$kpi_build_alarm <- renderUI({
    a <- build_alarm()
    value_box(paste0("This build (", input$build, ")"), a$level, p(class = "small", a$why), theme = a$theme)
  })
  output$kpi_fleet_alarm <- renderUI({
    a <- fleet_alarm()
    value_box("Fleet", a$level, p(class = "small", a$why), theme = a$theme)
  })

  output$abort_text <- renderText({
    ff <- first_flag()
    if (is.null(ff)) "ABORT BUILD: NO"
    else sprintf("ABORT BUILD: YES - %d consecutive out-of-control layers ending at layer %d (%s)",
                 ABORT_RUN, ff$layer, ff$label)
  })

  draw_ewma <- function(var, title, ylab) renderPlotly({
    r <- ewma_res()[[var]]
    validate(need(is.null(r$error), r$error))
    plot_ewma(r$value, r$value$mu0[1], title, ylab)
  })
  output$ewma_o2 <- draw_ewma("chamber_o2_ppm", "Chamber O2", "ppm")
  output$ewma_temp <- draw_ewma("bed_temp_c", "Bed temperature", "deg C")

  output$dl_flags <- downloadHandler(
    filename = function() paste0("flagged_layers_", input$build, ".csv"),
    content = function(file) {
      rows <- lapply(EWMA_VARS, function(v) {
        r <- ewma_res()[[v]]$value
        if (is.null(r) || !any(r$out)) return(NULL)
        r <- r[r$out, ]
        data.frame(build = input$build, layer = r$layer, variable = v,
                   x = r$x, z = r$z, ucl = r$ucl, lcl = r$lcl)
      })
      log <- do.call(rbind, rows)
      if (is.null(log)) {
        log <- data.frame(build = character(), layer = integer(), variable = character(),
                          x = numeric(), z = numeric(), ucl = numeric(), lcl = numeric())
      }
      write.csv(log, file, row.names = FALSE)
    }
  )

  # ---- page 2
  observeEvent(input$prop, {
    updateNumericInput(session, "spec", value = PROPERTIES[[input$prop]]$limit)
  })

  p2 <- reactive({
    pr <- PROPERTIES[[input$prop]]
    req(input$spec)
    x <- coupons()[[pr$col]]
    b <- coupons()$build_id
    withCallingHandlers({
      ana <- safely(analyse_chart(x, b))
      if (isTRUE(input$excl) && !is.null(ana$value)) {
        keep <- !(b %in% ana$value$flagged)
        x <- x[keep]; b <- b[keep]
        ana <- if (length(x) == 0) list(value = NULL, error = "no builds left after excluding flagged builds")
               else safely(analyse_chart(x, b))
      }
      lsl <- if (pr$side == "lsl") input$spec else NA
      usl <- if (pr$side == "usl") input$spec else NA
      cap <- safely(capability(x, b, lsl = lsl, usl = usl))
    }, warning = function(w) {
      showNotification(conditionMessage(w), type = "warning")
      invokeRestart("muffleWarning")
    })
    # if the whole file cannot be analysed, say what is wrong in each build
    diag <- NULL
    if (!is.null(ana$error) || !is.null(cap$error)) {
      diag <- unlist(lapply(unique(b), function(id) {
        r <- safely(capability(x[b == id], b[b == id], lsl = lsl, usl = usl))
        m <- if (!is.null(r$error)) r$error else r$value$message
        if (identical(m, "ok") || grepl("^Cp/Pp n/a: one-sided spec$", m)) NULL else paste0(id, ": ", m)
      }))
    }
    list(pr = pr, x = x, b = b, ana = ana, cap = cap, diag = diag)
  })

  observeEvent(p2(), {
    s <- p2()
    err <- c(s$ana$error, s$cap$error)
    if (length(err) > 0) {
      showNotification(HTML(paste(c(paste("Cannot compute capability:", unique(err)), s$diag),
                                  collapse = "<br>")),
                       type = "error", duration = 15)
    } else if (!is.null(s$cap$value) && grepl("zero variation", s$cap$value$message)) {
      showNotification(s$cap$value$message, type = "warning", duration = 10)
    }
  })

  output$banner <- renderUI({
    s <- p2()
    err <- c(s$ana$error, s$cap$error)
    if (length(err) > 0) {
      return(div(class = "alert alert-secondary",
                 strong("CANNOT COMPUTE: "), unique(err)[1],
                 lapply(s$diag, function(m) div(m))))
    }
    flagged <- s$ana$value$flagged
    cpk <- s$cap$value$cpk
    if (length(flagged) > 0) {
      div(class = "alert alert-warning",
          strong(paste0("NOT INTERPRETABLE: process out of control (builds ",
                        paste(flagged, collapse = ", "), ")")))
    } else if (is.na(cpk)) {
      div(class = "alert alert-secondary", strong(s$cap$value$message))
    } else if (cpk >= input$target) {
      div(class = "alert alert-success",
          strong(sprintf("AEROSPACE CAPABLE: Cpk >= %s", format(input$target))))
    } else {
      div(class = "alert alert-danger",
          strong(sprintf("NON-CONFORMANT: Cpk < %s", format(input$target))))
    }
  })

  output$cap_table <- renderUI({
    s <- p2()
    validate(need(is.null(s$cap$error), s$cap$error))
    v <- s$cap$value
    na_or <- function(val) if (is.na(val)) "n/a: one-sided spec" else fmt(val)
    rows <- list(
      c("Mean", fmt(v$mean)), c("sigma_within", fmt(v$sigma_within)),
      c("sigma_overall", fmt(v$sigma_overall)), c("Cpk", fmt(v$cpk)),
      c("Ppk", fmt(v$ppk)), c("Cp", na_or(v$cp)), c("Pp", na_or(v$pp))
    )
    tagList(
      tags$table(class = "table table-sm",
                 lapply(rows, function(r) tags$tr(tags$td(r[1]), tags$td(r[2])))),
      p(class = "small", paste0("Builds: ", v$n_builds, ", coupons per build: ",
                                v$n_per_build, ". ", v$message))
    )
  })

  output$shapiro <- renderText({
    s <- p2()
    validate(need(length(s$x) > 0, "no data"))
    nc <- normality_check(s$x)
    paste0("Shapiro-Wilk p-value: ", fmt(nc$p_value, 4), ". ", nc$message)
  })

  output$hist <- renderPlotly({
    s <- p2()
    validate(need(length(s$x) > 0, "no data"))
    dens <- tryCatch(density(s$x), error = function(e) NULL)
    p <- plot_ly() |>
      add_histogram(x = s$x, histnorm = "probability density", name = "coupons",
                    marker = list(color = "#9ecae1"))
    if (!is.null(dens)) p <- add_lines(p, x = dens$x, y = dens$y, name = "density",
                                       line = list(color = "#08519c"))
    p |> layout(
      xaxis = list(title = s$pr$label), yaxis = list(title = "density"),
      shapes = list(list(type = "line", x0 = input$spec, x1 = input$spec,
                         yref = "paper", y0 = 0, y1 = 1,
                         line = list(color = "red", width = 3))),
      annotations = list(list(x = input$spec, y = 1, yref = "paper",
                              text = "spec limit", showarrow = FALSE,
                              font = list(color = "red"), xanchor = "left"))
    )
  })

  output$xbar <- renderPlotly({
    s <- p2()
    validate(need(is.null(s$ana$error), s$ana$error))
    a <- s$ana$value
    plot_xbar_like(a$lim$builds$build, a$lim$builds$mean, a$lim$xbar["cl"],
                   a$lim$xbar["ucl"], a$lim$xbar["lcl"], a$flag,
                   "X-bar chart", s$pr$label)
  })
  output$schart <- renderPlotly({
    s <- p2()
    validate(need(is.null(s$ana$error), s$ana$error))
    a <- s$ana$value
    plot_xbar_like(a$lim$builds$build, a$lim$builds$sd, a$lim$s["cl"],
                   a$lim$s["ucl"], a$lim$s["lcl"],
                   a$lim$builds$sd > a$lim$s["ucl"] | a$lim$builds$sd < a$lim$s["lcl"],
                   "S chart", "build sd")
  })
  output$flag_text <- renderText({
    a <- p2()$ana$value
    if (is.null(a)) return("")
    if (is.null(a$nl)) return("No Nelson rules applied: the chart has zero spread.")
    if (length(a$flagged) == 0) return("Nelson rules 1-4: no flags.")
    paste(vapply(which(a$flag), function(i) {
      rules <- which(unlist(a$nl[i, c("rule1", "rule2", "rule3", "rule4")]))
      paste0(a$lim$builds$build[i], " (rule ", paste(rules, collapse = ", "), ")")
    }, character(1)), collapse = "; ") |> (\(m) paste("Nelson flags:", m))()
  })
}

shinyApp(ui, server)
