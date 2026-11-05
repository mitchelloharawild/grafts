# The served explorer: R holds the data, and the app gets the structure once
# ({path}api/spec) and asks for the series it draws ({path}api/series), so the
# page stays small for large structures. The front end lives in inst/www.

#' Serve the explorer with plumber2
#'
#' `grafts_api()` adds an explorer to a plumber2 api, for deploying it (with
#' Docker or Posit Connect, say) or mounting it beside other routes. It adds
#' the routes `{path}api/spec`, `{path}api/series` and `{path}api/health` (for
#' load balancers and containers), and the app's page at `{path}`, which
#' `{path}` without its trailing slash redirects to. Responses are cached
#' privately and revalidated with an `ETag`, so a redeployed dataset is seen
#' at once.
#' `grafts_serve()` runs an explorer on its own server, for scripts and
#' containers. Printing an explorer from [grafts()] in the console runs
#' `grafts_serve()`, blocking the console like a Shiny app until it is stopped.
#'
#' The data stays in R, and the app is sent each series when it is drawn, so
#' data of any size can be explored.
#'
#' @param explorer An explorer from [grafts()], which takes the data, forecasts
#'   and options.
#' @param api A plumber2 api, such as from `plumber2::api()`.
#' @param path Where the explorer is mounted on `api`. Mount several explorers
#'   at different paths, such as `"/tourism/"` and `"/retail/"`.
#' @param max_ids The most series that one request to `api/series` may ask for.
#'   The app asks for up to 200 at a time.
#' @param port,host Where the app is served, by default port 8000 on this
#'   machine only. Set `GRAFTS_PORT` (or `PORT`) and `GRAFTS_HOST`, or the
#'   options `grafts.port` and `grafts.host`, to change the defaults without
#'   editing code. Use `host = "0.0.0.0"` to accept connections from other
#'   machines, such as from a container. The app has no sign-in, so put
#'   anything private behind an authenticating proxy.
#' @param launch Open the app, in the IDE's viewer where there is one, else in
#'   a browser.
#' @param block Block the R session while serving, like a Shiny app. When
#'   `FALSE`, stop the app with `plumber2::api_stop()` on the returned api.
#' @return `grafts_api()` returns `api` with the explorer added.
#'   `grafts_serve()` returns its plumber2 api, invisibly.
#' @examplesIf FALSE
#' # A plumber2 file (plumber.R), for Posit Connect or plumber2::api("plumber.R")
#' #* @plumber
#' function(api) {
#'   data <- readRDS("tourism_agg.rds")
#'   grafts_api(api, grafts(data))
#' }
#'
#' # Several datasets on one api, at /tourism/ and /retail/
#' plumber2::api() |>
#'   grafts_api(grafts(tourism_agg), path = "/tourism/") |>
#'   grafts_api(grafts(retail_agg, forecasts = retail_fc), path = "/retail/") |>
#'   plumber2::api_run()
#'
#' # In Docker, from the command line
#' # Rscript -e 'readRDS("tourism_agg.rds") |> grafts::grafts() |>
#' #   grafts::grafts_serve(host = "0.0.0.0")'
#' @export
grafts_api <- function(api, explorer, path = "/", max_ids = 1000) {
  model <- check_explorer(explorer)$model
  path <- paste0("/", gsub("^/+|/+$", "", path), "/")
  path <- sub("^//$", "/", path)

  # The data is fixed while the server runs, but a redeploy changes it. So
  # responses are cached privately (a shared cache could serve one visitor's
  # data to another), and revalidated with an ETag of the data and request: a
  # redeploy is seen at once, and an unchanged series costs a 304.
  version <- rlang::hash(list(model$spec, model$values, model$fc, model$max_points))
  fresh <- function(request, response, what) {
    etag <- paste0("\"", rlang::hash(list(version, what)), "\"")
    response$set_header("Cache-Control", "private, no-cache")
    response$set_header("ETag", etag)
    if (identical(request$get_header("If-None-Match"), etag)) {
      response$status <- 304L
      return(TRUE)
    }
    FALSE
  }

  api <- plumber2::api_get(api, paste0(path, "api/health"), function() {
    list(status = "ok", series = model$n)
  }, serializers = json_serializer)
  api <- plumber2::api_get(api, paste0(path, "api/spec"), function(request, response) {
    if (fresh(request, response, "spec")) return(NULL)
    model$spec
  }, serializers = json_serializer)
  api <- plumber2::api_get(api, paste0(path, "api/series"), function(request, query, response) {
    measure <- query$measure %||% model$spec$measure
    ids <- suppressWarnings(as.integer(unlist(strsplit(as.character(query$ids), ",", fixed = TRUE))))
    if (!measure %in% model$spec$measures || anyNA(ids) || any(ids < 0 | ids >= model$n)) {
      response$status <- 400L
      return(list(error = "Unknown measure or series"))
    }
    if (length(ids) > max_ids) {
      response$status <- 400L
      return(list(error = paste("At most", max_ids, "series per request")))
    }
    if (fresh(request, response, list(measure, ids, query$raw))) return(NULL)
    explore_series(model, measure, ids, raw = identical(query$raw, "1"))
  }, serializers = json_serializer)

  # The app's files, as routes rather than plumber2 statics, which can't be
  # added once a server runs
  www <- system.file("www", package = "grafts")
  files <- list(
    list(route = path, file = "index.html", type = "text/html"),
    list(route = paste0(path, "grafts.js"), file = "grafts.js", type = "text/javascript"),
    list(route = paste0(path, "grafts.css"), file = "grafts.css", type = "text/css")
  )
  # The font is binary, and served from the app so that no third party is called
  for (w in c(400, 600, 700)) {
    file <- paste0("fonts/source-sans-3-", w, ".woff2")
    files <- c(files, list(list(
      route = paste0(path, file), file = file, type = "font/woff2", binary = TRUE
    )))
  }
  for (f in files) {
    body <- if (isTRUE(f$binary)) read_bytes(file.path(www, f$file)) else read_text(file.path(www, f$file))
    api <- plumber2::api_get(
      api, f$route, local({
        body <- body
        function() body
      }),
      serializers = set_names(list(identity), f$type)
    )
  }
  # The page's urls are relative, so it must be opened at the trailing slash
  if (path != "/") api <- plumber2::api_redirect(api, "get", sub("/$", "", path), path)

  attr(api, "grafts_n") <- model$n
  api
}

#' @rdname grafts_api
#' @export
grafts_serve <- function(explorer, port = serve_port(), host = serve_host(),
                         launch = FALSE, block = TRUE) {
  x <- check_explorer(explorer)
  api <- plumber2::api(host = host, port = port, doc_type = NULL)
  # Without routr's note on making its router
  api <- suppressMessages(grafts_api(api, x))

  # Announce before running, as a blocking server only returns once stopped
  open_host <- if (host %in% c("0.0.0.0", "::")) "127.0.0.1" else host
  url <- paste0("http://", open_host, ":", port, "/")
  cli::cli_inform(c(
    "Exploring {x$model$n} series at {.url {url}}",
    if (open_host != host) c(i = "Listening on all interfaces ({host})."),
    if (open_host != host) c("!" = "There is no sign-in: anyone who can reach this machine can explore the data."),
    i = if (block) "Press {.kbd Ctrl+C} (or {.kbd Esc} in RStudio and Positron) to stop." else "Stop it with {.code plumber2::api_stop(<api>)}."
  ))
  # Opened once the server is up, as a blocking run only returns once stopped
  if (launch) later::later(function() open_url(url))
  tryCatch(
    plumber2::api_run(api, block = block, showcase = FALSE, silent = TRUE),
    # The server stops itself on the way out
    interrupt = function(e) cli::cli_inform("Stopped exploring.")
  )
  invisible(api)
}

# Where an explorer is served by default: the options grafts.port and
# grafts.host, else the environment (GRAFTS_PORT or PORT, as set by hosts
# such as Heroku and Cloud Run, and GRAFTS_HOST), else port 8000 on this
# machine only. The console picks a free port instead, so that explorers
# don't collide.
serve_port <- function(free = FALSE) {
  port <- getOption("grafts.port") %||%
    as.integer(Sys.getenv("GRAFTS_PORT", Sys.getenv("PORT", NA)))
  if (length(port) != 1 || is.na(port)) {
    port <- if (free) httpuv::randomPort() else 8000L
  }
  port
}
serve_host <- function() {
  getOption("grafts.host") %||% (Sys.getenv("GRAFTS_HOST", "") %|% "127.0.0.1")
}
`%|%` <- function(x, y) if (nzchar(x)) x else y

read_bytes <- function(path) readBin(path, "raw", file.size(path))

# The IDE's viewer where there is one, as for a Shiny app, else a browser
open_url <- function(url) {
  viewer <- getOption("viewer")
  if (is.function(viewer)) viewer(url) else utils::browseURL(url)
}

# NA stays NA, so missing values and absent spec fields reach JavaScript as null
to_json <- function(x) {
  as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", na = "null", digits = NA))
}
json_serializer <- list("application/json" = to_json)
