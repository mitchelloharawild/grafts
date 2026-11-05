# The explorer in Shiny. renderGrafts() shows an explorer from grafts(), with
# every series written into the page; the widget tells the app what it shows
# (the inputs <id>_focus and so on).

#' Shiny bindings for grafts()
#'
#' Shows an explorer from [grafts()] in Shiny. The explorer tells the app what
#' it shows, through inputs named after its output.
#'
#' Every series is written into the page, which suits small data: a Shiny app
#' can't send a series at a time, so to explore large data, serve the explorer
#' with [grafts_api()] or [grafts_serve()] and link to it or embed it in an
#' `<iframe>`.
#'
#' For an output `"ts"`, the app can read these inputs:
#'
#' * `input$ts_focus`, the focused series, as a one-row data frame with a
#'   column for each key of the data, and `NA` for the keys it is aggregated
#'   over.
#' * `input$ts_children`, the series of the focus's last split, one row each.
#' * `input$ts_pinned`, the pinned series, one row each.
#' * `input$ts_split`, the keys the children were split by, as a character
#'   vector.
#' * `input$ts_view`, the view shown (`"grid"`, `"overlay"`, `"stacked"` or
#'   `"season"`) and `input$ts_set`, the set it draws (`"children"` or
#'   `"pinned"`).
#' * `input$ts_theme` (`"system"`, `"light"` or `"dark"`) and
#'   `input$ts_measure`.
#'
#' They are `NULL` until the explorer is drawn, and change as the visitor
#' explores. Modules namespace them as for any output.
#'
#' @param outputId Output variable to read from.
#' @param width,height A CSS length for the explorer.
#' @param expr An expression that returns an explorer from [grafts()].
#' @param env The environment in which to evaluate `expr`.
#' @param quoted Is `expr` a quoted expression (with `quote()`)?
#' @examplesIf interactive()
#' library(shiny)
#' tourism_agg <- fabletools::aggregate_key(
#'   tsibble::tourism, Purpose * (State / Region), Trips = sum(Trips)
#' )
#' ui <- fluidPage(graftsOutput("ts"), verbatimTextOutput("focus"))
#' server <- function(input, output, session) {
#'   output$ts <- renderGrafts(grafts(tourism_agg))
#'   output$focus <- renderPrint(input$ts_focus)
#' }
#' shinyApp(ui, server)
#' @name grafts-shiny
#' @export
graftsOutput <- function(outputId, width = "100%", height = "600px") {
  register_input_handlers()
  htmlwidgets::shinyWidgetOutput(outputId, "grafts", width, height, package = "grafts")
}

#' @rdname grafts-shiny
#' @export
renderGrafts <- function(expr, env = parent.frame(), quoted = FALSE) {
  if (!quoted) expr <- substitute(expr)
  # The explorer becomes a widget once evaluated
  expr <- as.call(list(as_widget, expr))
  htmlwidgets::shinyRenderWidget(expr, graftsOutput, env, quoted = TRUE)
}

# ---- Inputs ------------------------------------------------------------------

# Shiny gives inputs of these types to handlers, which make a data frame of
# series from the {keys, rows} the explorer sends, and a character vector
# from a list of names
register_input_handlers <- function() {
  if (isTRUE(.shiny$handlers)) return(invisible())
  shiny::registerInputHandler("grafts.series", function(x, session, name) {
    keys <- as.character(unlist(x$keys))
    cols <- lapply(seq_along(keys), function(j) {
      vapply(x$rows, function(r) if (is.null(r[[j]])) NA_character_ else as.character(r[[j]]), character(1))
    })
    structure(cols, names = keys, class = "data.frame", row.names = seq_along(x$rows))
  }, force = TRUE)
  shiny::registerInputHandler("grafts.names", function(x, session, name) {
    as.character(unlist(x))
  }, force = TRUE)
  .shiny$handlers <- TRUE
  invisible()
}
.shiny <- new.env(parent = emptyenv())
