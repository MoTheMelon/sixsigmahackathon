# testme.R - run the AeroPrint SPC dashboard locally on port 8080.
# One command, no arguments, from the repo root:  Rscript app/testme.R
# Then open http://127.0.0.1:8080

args <- commandArgs(trailingOnly = FALSE)
file_arg <- sub("^--file=", "", args[grepl("^--file=", args)])
app_dir <- if (length(file_arg) > 0) dirname(normalizePath(file_arg)) else getwd()

shiny::runApp(app_dir, host = "127.0.0.1", port = 8080, launch.browser = FALSE)
