# deployme.R - deploy app/ to Posit Connect from your machine.
# Run from the repo root:  Rscript app/deployme.R
# The server and key come from the environment (or a gitignored .env file in
# the repo root with lines CONNECT_SERVER=... and CONNECT_API_KEY=...).
# Never write them into a file that is committed.

if (!requireNamespace("rsconnect", quietly = TRUE)) {
  stop("Please install 'rsconnect' first: install.packages('rsconnect')")
}

args <- commandArgs(trailingOnly = FALSE)
file_arg <- sub("^--file=", "", args[grepl("^--file=", args)])
app_dir <- if (length(file_arg) > 0) dirname(normalizePath(file_arg)) else getwd()

# Read .env if present (simple KEY=VALUE lines).
env_file <- file.path(dirname(app_dir), ".env")
if (file.exists(env_file)) {
  for (line in readLines(env_file, warn = FALSE)) {
    kv <- regmatches(line, regexec("^\\s*([A-Za-z_]+)\\s*=\\s*(.*)$", line))[[1]]
    if (length(kv) == 3 && Sys.getenv(kv[2]) == "") {
      do.call(Sys.setenv, setNames(list(kv[3]), kv[2]))
    }
  }
}

server_url <- Sys.getenv("CONNECT_SERVER")
api_key <- Sys.getenv("CONNECT_API_KEY")
if (server_url == "" || api_key == "") {
  stop("Set CONNECT_SERVER and CONNECT_API_KEY in the environment or in a gitignored .env file.")
}

rsconnect::addServer(url = paste0(sub("/$", "", server_url), "/__api__"), name = "hackathon-connect")
rsconnect::connectApiUser(server = "hackathon-connect", apiKey = api_key)
rsconnect::writeManifest(appDir = app_dir, appPrimaryDoc = "app.R")
rsconnect::deployApp(appDir = app_dir, server = "hackathon-connect", appPrimaryDoc = "app.R")
