# graph_explore() serves a browser app with plumber2. The left column holds the
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
#' @param port,host Where the app is served.
#' @param launch Open the app in a browser.
#' @param block Block the R session while serving. When `FALSE`, stop the app
#'   with `plumber2::api_stop()` on the returned api.
#' @return The plumber2 api, invisibly.
#' @examples
#' if (interactive()) {
#'   library(fable)
#'   tourism_agg <- tsibble::tourism |>
#'     aggregate_key(Purpose * (State / Region), Trips = sum(Trips))
#'
#'   # The structure is inferred from the keys: Purpose * (State / Region)
#'   app <- graph_explore(tourism_agg)
#'   plumber2::api_stop(app)
#'
#'   # With forecasts, drawn after the data with their intervals
#'   tourism_fc <- tourism_agg |>
#'     model(ets = ETS(Trips), snaive = SNAIVE(Trips)) |>
#'     forecast(h = "2 years")
#'   app <- graph_explore(tourism_agg, forecasts = tourism_fc)
#'   plumber2::api_stop(app)
#' }
#' @export
graph_explore <- function(data, value = NULL, forecasts = NULL,
                          level = c(80, 95), max_points = 1000,
                          port = httpuv::randomPort(), host = "127.0.0.1",
                          launch = interactive(), block = !interactive()) {
  value <- enquo(value)
  model <- explore_model(data, value, forecasts, level, max_points)

  api <- plumber2::api(host = host, port = port, doc_type = NULL)
  api <- plumber2::api_get(api, "/api/spec", function() model$spec, serializers = json_serializer)
  api <- plumber2::api_get(api, "/api/series", function(query, response) {
    measure <- query$measure %||% model$spec$measure
    ids <- suppressWarnings(as.integer(strsplit(query$ids %||% "", ",", fixed = TRUE)[[1]]))
    if (!measure %in% model$spec$measures || anyNA(ids) || any(ids < 0 | ids >= model$n)) {
      response$status <- 400L
      return(list(error = "Unknown measure or series"))
    }
    explore_series(model, measure, ids, raw = identical(query$raw, "1"))
  }, serializers = json_serializer)
  api <- plumber2::api_statics(api, "/", system.file("www", package = "grafts"), fallthrough = TRUE)

  plumber2::api_run(api, block = block, showcase = launch, silent = TRUE)
  cli::cli_inform(c(
    "Exploring {model$n} series at {.url http://{host}:{port}}",
    if (!block) c(i = "Stop it with {.code plumber2::api_stop(<api>)}")
  ))
  invisible(api)
}

# NA stays NA, so missing values and absent spec fields reach JavaScript as null
json_serializer <- list("application/json" = function(x) {
  as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", na = "null", digits = NA))
})
