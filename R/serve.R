# The served explorer: R holds the data, and the app gets the structure once
# ({path}api/spec) and asks for the series it draws ({path}api/series), so the
# page stays small for large structures. The front end lives in inst/www.

#' Serve the explorer with plumber2
#'
#' `api_grafts()` adds an explorer to a plumber2 api, for deploying it (with
#' Docker or Posit Connect, say) or mounting it beside other routes. It adds
#' the routes `{path}api/spec` and `{path}api/series`, and the app's page at
#' `{path}`, which `{path}` without its trailing slash redirects to.
#' `grafts_serve()` runs an explorer on its own server, for scripts and
#' containers. Printing an explorer from [grafts()] in the console runs
#' `grafts_serve()`, blocking the console like a Shiny app until it is stopped.
#'
#' The data stays in R, and the app is sent each series when it is drawn, so
#' data of any size can be explored.
#'
#' @param x An explorer from [grafts()], or an aggregated tsibble to make one
#'   from, with the arguments of [grafts()] given in `...`.
#' @param ... Arguments of [grafts()], such as `forecasts` or `options`, when
#'   `x` is data.
#' @param api A plumber2 api, such as from `plumber2::api()`.
#' @param path Where the explorer is mounted on `api`. Mount several explorers
#'   at different paths, such as `"/tourism/"` and `"/retail/"`.
#' @param max_points Series more than twice this long are sent as the minimum
#'   and maximum of blocks of time, about `max_points` values, so spikes stay
#'   visible. The season and stacked plots always get the full series.
#' @param max_ids The most series that one request to `api/series` may ask for.
#'   The app asks for up to 200 at a time.
#' @param port,host Where the app is served. Use `host = "0.0.0.0"` to accept
#'   connections from other machines, such as from a container.
#' @param launch Open the app, in the IDE's viewer where there is one, else in
#'   a browser.
#' @param block Block the R session while serving. When `FALSE`, stop the app
#'   with `plumber2::api_stop()` on the returned api.
#' @return `api_grafts()` returns `api` with the explorer added.
#'   `grafts_serve()` returns its plumber2 api, invisibly.
#' @examplesIf FALSE
#' # A plumber2 file (plumber.R), for Posit Connect or plumber2::api("plumber.R")
#' #* @plumber
#' function(api) {
#'   data <- readRDS("tourism_agg.rds")
#'   api_grafts(api, data)
#' }
#'
#' # Several datasets on one api, at /tourism/ and /retail/
#' plumber2::api() |>
#'   api_grafts(tourism_agg, path = "/tourism/") |>
#'   api_grafts(grafts(retail_agg, forecasts = retail_fc), path = "/retail/") |>
#'   plumber2::api_run()
#'
#' # In Docker, from the command line
#' # Rscript -e 'readRDS("tourism_agg.rds") |>
#' #   grafts::grafts_serve(host = "0.0.0.0", port = 8000, launch = FALSE)'
#' @export
api_grafts <- function(api, x, ..., path = "/", max_points = 1000, max_ids = 1000) {
  model <- as_grafts(x, ...)$model
  model$max_points <- max_points
  path <- paste0("/", gsub("^/+|/+$", "", path), "/")
  path <- sub("^//$", "/", path)

  # The data is fixed while the server runs, but a redeploy changes it
  cache <- function(response) response$set_header("Cache-Control", "public, max-age=3600")

  api <- plumber2::api_get(api, paste0(path, "api/spec"), function(response) {
    cache(response)
    model$spec
  }, serializers = json_serializer)
  api <- plumber2::api_get(api, paste0(path, "api/series"), function(query, response) {
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
    cache(response)
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
  for (f in files) {
    text <- read_text(file.path(www, f$file))
    api <- plumber2::api_get(
      api, f$route, local({
        text <- text
        function() text
      }),
      serializers = set_names(list(identity), f$type)
    )
  }
  # The page's urls are relative, so it must be opened at the trailing slash
  if (path != "/") api <- plumber2::api_redirect(api, "get", sub("/$", "", path), path)

  attr(api, "grafts_n") <- model$n
  api
}

#' @rdname api_grafts
#' @export
grafts_serve <- function(x, ..., port = httpuv::randomPort(), host = "127.0.0.1",
                         max_points = 1000, launch = interactive(), block = !interactive()) {
  x <- as_grafts(x, ...)
  api <- plumber2::api(host = host, port = port, doc_type = NULL)
  # Without routr's note on making its router
  api <- suppressMessages(api_grafts(api, x, max_points = max_points))

  # Announce before running, as a blocking server only returns once stopped
  open_host <- if (host %in% c("0.0.0.0", "::")) "127.0.0.1" else host
  url <- paste0("http://", open_host, ":", port, "/")
  cli::cli_inform(c(
    "Exploring {x$model$n} series at {.url {url}}",
    if (open_host != host) c(i = "Listening on all interfaces ({host})."),
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
