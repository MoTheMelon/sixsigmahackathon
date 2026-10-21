# manifestme.R - write manifest.json (the Posit Connect package list) for app/.
# Run from the repo root:  Rscript app/manifestme.R

if (!requireNamespace("rsconnect", quietly = TRUE)) {
  stop("Please install 'rsconnect' first: install.packages('rsconnect')")
}

args <- commandArgs(trailingOnly = FALSE)
file_arg <- sub("^--file=", "", args[grepl("^--file=", args)])
app_dir <- if (length(file_arg) > 0) dirname(normalizePath(file_arg)) else getwd()

rsconnect::writeManifest(appDir = app_dir, appPrimaryDoc = "app.R")
message("Done. manifest.json written in: ", app_dir)
