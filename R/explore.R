# grafts_explore() serves a browser app with plumber2. The left column holds the
# series graph (one node per series, drawn on demand) above the dimension graph
# (one node per combination of keys). The right column plots the series the
# explorer has reached, with forecasts when a fable is given.
#
# R holds the data. The app gets the structure once (/api/spec) and asks for
# the series it draws (/api/series), so the page stays small for large
# structures. The front end lives in inst/www.

#' Explore an aggregated tsibble through its series and dimension graphs
#'
#' Serves a browser app for exploring an aggregated tsibble. The left column
#' holds the series graph, drawn on demand, above the dimension graph of the
#' key combinations given to [fabletools::aggregate_key()]. The right column
#' plots the focused series, with forecasts when a fable is given, above a view
#' of its children or of the pinned series.
#'
#' `grafts_explore()` starts a local server for the console. To deploy the app,
#' add it to a plumber2 api with `api_grafts()`, which adds the routes
#' `{path}api/spec` and `{path}api/series` and the app's static files. The page
#' uses relative urls, so open it at the trailing slash (`/tourism/`).
#' plumber2 also serves the page at `/tourism`, but there its api calls
#' resolve against `/` and fail, so link to the slash form.
#'
#' @param data An aggregated tsibble, as produced by `fabletools::aggregate_key()`.
#' @param value The measured variable shown first. Every numeric measured
#'   variable can be chosen in the app. Defaults to the first.
#' @param forecasts A fable of forecasts for `data`, with the same keys (and
#'   optionally `.model`). Its response variable must be a measured variable of
#'   `data`. Each model's mean and intervals are drawn after the data.
#' @param level Interval levels drawn for `forecasts`.
#' @param max_points Series more than twice this long are sent as the minimum
#'   and maximum of blocks of time, about `max_points` values, so spikes stay
#'   visible. The season and stacked plots always get the full series.
#' @param options Which views the explorer offers and how it starts, from
#'   [grafts_options()].
#' @param port,host Where the app is served. Use `host = "0.0.0.0"` to accept
#'   connections from other machines, such as from a container.
#' @param launch Open the app in a browser.
#' @param block Block the R session while serving. When `FALSE`, stop the app
#'   with `plumber2::api_stop()` on the returned api.
#' @return `grafts_explore()` returns the plumber2 api, invisibly.
#'   `api_grafts()` returns `api` with the explorer added.
#' @examples
#' if (interactive()) {
#'   library(fable)
#'   tourism_agg <- aggregate_key(
#'     tsibble::tourism, Purpose * (State / Region), Trips = sum(Trips)
#'   )
#'
#'   # The structure is inferred from the keys: Purpose * (State / Region)
#'   app <- grafts_explore(tourism_agg)
#'   plumber2::api_stop(app)
#'
#'   # With forecasts, drawn after the data with their intervals
#'   tourism_fit <- model(tourism_agg, ets = ETS(Trips), snaive = SNAIVE(Trips))
#'   tourism_fc <- forecast(tourism_fit, h = "2 years")
#'   app <- grafts_explore(tourism_agg, forecasts = tourism_fc)
#'   plumber2::api_stop(app)
#' }
#' @export
grafts_explore <- function(data, value = NULL, forecasts = NULL,
                           level = c(80, 95), max_points = 1000,
                           options = grafts_options(), port = httpuv::randomPort(), host = "127.0.0.1",
                           launch = interactive(), block = !interactive()) {
  value <- enquo(value)
  api <- plumber2::api(host = host, port = port, doc_type = NULL)
  api <- api_grafts(api, data, !!value, forecasts, level, max_points, options)

  # Announce before running, as a blocking server only returns once stopped
  open_host <- if (host %in% c("0.0.0.0", "::")) "127.0.0.1" else host
  cli::cli_inform(c(
    "Exploring {attr(api, 'grafts_n')} series at {.url http://{open_host}:{port}}",
    if (open_host != host) c(i = "Listening on all interfaces ({host})."),
    if (!block) c(i = "Stop it with {.code plumber2::api_stop(<api>)}")
  ))
  plumber2::api_run(api, block = block, showcase = launch, silent = TRUE)
  invisible(api)
}

#' @rdname grafts_explore
#' @param api A plumber2 api, such as from `plumber2::api()`.
#' @param path Where the explorer is mounted on `api`. Mount several explorers
#'   at different paths, such as `"/tourism/"` and `"/retail/"`.
#' @param max_ids The most series that one request to `api/series` may ask for.
#'   The app asks for up to 200 at a time.
#' @examplesIf FALSE
#' # A plumber2 file (plumber.R), for Posit Connect or plumber2::api("plumber.R")
#' #* @plumber
#' function(api) {
#'   data <- readRDS("tourism_agg.rds")
#'   api_grafts(api, data)
#' }
#'
#' # In Docker, from the command line
#' # Rscript -e 'readRDS("tourism_agg.rds") |>
#' #   grafts::grafts_explore(host = "0.0.0.0", port = 8000, launch = FALSE)'
#'
#' # Several datasets on one api, at /tourism/ and /retail/
#' plumber2::api() |>
#'   api_grafts(tourism_agg, path = "/tourism/") |>
#'   api_grafts(retail_agg, path = "/retail/") |>
#'   plumber2::api_run()
#' @export
api_grafts <- function(api, data, value = NULL, forecasts = NULL,
                       level = c(80, 95), max_points = 1000,
                       options = grafts_options(), path = "/", max_ids = 1000) {
  value <- enquo(value)
  model <- explore_model(data, value, forecasts, level, max_points, options)
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
  api <- plumber2::api_statics(api, path, system.file("www", package = "grafts"), fallthrough = TRUE)
  attr(api, "grafts_n") <- model$n
  api
}

# NA stays NA, so missing values and absent spec fields reach JavaScript as null
to_json <- function(x) {
  as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", na = "null", digits = NA))
}
json_serializer <- list("application/json" = to_json)
