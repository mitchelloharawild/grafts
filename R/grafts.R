# grafts() makes an explorer: the checked structure, series and forecasts of
# an aggregated tsibble. Where the explorer goes decides how its series reach
# the browser. Printed in the console it is served by a local plumber2 server
# a series at a time (serve.R), until stopped. Knitted, in Shiny or saved, every series is
# written into the page (static.R).

#' Explore an aggregated tsibble through its series and dimension graphs
#'
#' Makes an explorer of an aggregated tsibble, drawn in the browser. The left
#' column holds the series graph, drawn on demand, above the dimension graph
#' of the key combinations given to [fabletools::aggregate_key()]. The right
#' column plots the focused series, with forecasts when a fable is given,
#' above a view of its children or of the pinned series.
#'
#' Where the explorer goes decides how its series reach the browser:
#'
#' * Printed in the console, it opens in the viewer or a browser, served by a
#'   local server that sends each series when it is drawn, so data of any size
#'   can be explored. Like a Shiny app, the console waits while it is served:
#'   press Ctrl+C (or Esc in RStudio and Positron) to stop it. Use
#'   [grafts_serve()] to serve it in the background instead.
#' * In R Markdown, Quarto, pkgdown or Shiny ([renderGrafts()]), and in a page
#'   written by [grafts_save()], every series is written into the page, which
#'   needs no R session. This suits small data.
#' * On a server, [api_grafts()] adds it to a plumber2 api and [grafts_serve()]
#'   runs it, sending each series when it is drawn.
#'
#' Embedded explorers use the system's UI font. The served app brings its own
#' copy of Source Sans 3, which a page can load too, for the same look.
#'
#' @param data An aggregated tsibble, as produced by `fabletools::aggregate_key()`.
#' @param value The measured variable shown first. Every numeric measured
#'   variable can be chosen in the app. Defaults to the first.
#' @param forecasts A fable of forecasts for `data`, with the same keys (and
#'   optionally `.model`). Its response variable must be a measured variable of
#'   `data`. Each model's mean and intervals are drawn after the data.
#' @param level Interval levels drawn for `forecasts`.
#' @param options Which views the explorer offers and how it starts, from
#'   [grafts_options()].
#' @param width,height Size of the explorer when written into a page, in
#'   pixels or as a CSS length. In documents and Shiny the height defaults to
#'   600px, and a page from [grafts_save()] fills the window.
#' @param elementId An id for the explorer's element in a document.
#' @return An explorer, of class `grafts`.
#' @examples
#' tourism_agg <- fabletools::aggregate_key(
#'   tsibble::tourism, Purpose * (State / Region), Trips = sum(Trips)
#' )
#' tourism <- grafts(tourism_agg)
#'
#' # Printing opens it, served from this R session
#' if (interactive()) tourism
#'
#' # With forecasts, drawn after the data with their intervals
#' if (requireNamespace("fable", quietly = TRUE)) {
#'   library(fable)
#'   tourism_fc <- tourism_agg |>
#'     model(snaive = SNAIVE(Trips)) |>
#'     forecast(h = "2 years")
#'   grafts(tourism_agg, forecasts = tourism_fc)
#' }
#' @export
grafts <- function(data, value = NULL, forecasts = NULL, level = c(80, 95),
                   options = grafts_options(), width = NULL, height = NULL, elementId = NULL) {
  model <- explore_model(data, enquo(value), forecasts, level, 1000, options)
  structure(
    list(
      model = model, width = width, height = height, elementId = elementId
    ),
    class = "grafts"
  )
}

# The explorer's widget shares its class, and goes to the htmlwidget methods

#' @export
format.grafts <- function(x, ...) {
  if (inherits(x, "htmlwidget")) return(NextMethod())
  spec <- x$model$spec
  c(
    paste0("<grafts explorer> ", x$model$n, " series of ", spec$structure),
    paste0("Measures: ", paste(spec$measures, collapse = ", "), " (showing ", spec$measure, ")"),
    if (!is.null(spec$forecast)) paste0("Forecasts: ", paste(spec$forecast$models, collapse = ", "))
  )
}

#' @export
print.grafts <- function(x, ...) {
  if (inherits(x, "htmlwidget")) return(NextMethod())
  if (interactive()) {
    grafts_serve(x, port = serve_port(free = TRUE), launch = TRUE, block = TRUE)
  } else {
    writeLines(format(x))
  }
  invisible(x)
}

#' @exportS3Method knitr::knit_print
knit_print.grafts <- function(x, ...) {
  if (inherits(x, "htmlwidget")) return(NextMethod())
  knitr::knit_print(as_widget(x), ...)
}

#' @exportS3Method htmltools::as.tags
as.tags.grafts <- function(x, ...) {
  if (inherits(x, "htmlwidget")) return(NextMethod())
  htmltools::as.tags(as_widget(x), ...)
}

# An explorer from `x`, or from data `x` and the arguments of grafts() in `...`
as_grafts <- function(x, ..., call = rlang::caller_env()) {
  if (inherits(x, "grafts") && !inherits(x, "htmlwidget")) {
    if (...length()) {
      abort("Arguments in `...` only apply when `x` is data, not an explorer from `grafts()`.", call = call)
    }
    return(x)
  }
  grafts(x, ...)
}
