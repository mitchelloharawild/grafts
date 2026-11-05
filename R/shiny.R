# The explorer in Shiny. renderGrafts() shows an explorer from grafts(), with
# every series written into the page; the widget tells the app what it shows
# (the inputs <id>_focus and so on), and graftsProxy() steers it and replaces
# its data without drawing it again.

#' Shiny bindings for grafts()
#'
#' Shows an explorer from [grafts()] in Shiny. The explorer tells the app what
#' it shows, through inputs named after its output, and [graftsProxy()] lets
#' the app steer it and replace its data.
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
#' @seealso [graftsProxy()] to steer the explorer and update its data.
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

#' Steer an explorer in Shiny
#'
#' `graftsProxy()` points at an explorer drawn by [renderGrafts()], to change
#' what it shows or its data from the server, without drawing it again. The
#' explorer reports what it shows back through inputs (see [graftsOutput()]).
#'
#' * `grafts_focus()` focuses a series, drawing the splits that reach it.
#' * `grafts_pin()` and `grafts_unpin()` pin and unpin series. Unpinning
#'   with no `keys` clears every pin.
#' * `grafts_view()` chooses the view and the set of series it draws.
#' * `grafts_theme()` and `grafts_measure()` choose the theme and measure.
#' * `grafts_reset()` returns the graph to the total.
#' * `grafts_update()` replaces the explorer's data. When the new data have
#'   the same series, the graph, focus, pins, views and layout stay as they
#'   were, so the visitor sees the numbers change. Otherwise the explorer
#'   starts again.
#'
#' Each returns the proxy, invisibly, so that calls can be piped.
#'
#' @param proxy A proxy from `graftsProxy()`.
#' @param keys The series, as a data frame with a column for each key and a row
#'   for each series (such as the rows of the explorer's data, or of the
#'   `input$<id>_focus` it reports), or a named list or vector for one series.
#'   Keys left out, or `NA`, are aggregated over: `list(State = "NSW")` is the
#'   total of New South Wales, and `list()` the total of everything.
#' @param pinned `TRUE` to pin, `FALSE` to unpin.
#' @param view The view to show: `"grid"`, `"overlay"`, `"stacked"` or
#'   `"season"`, among those the explorer offers.
#' @param set The series the view draws: the focus's `"children"` or the
#'   `"pinned"` series.
#' @param theme `"system"`, `"light"` or `"dark"`.
#' @param measure One of the data's numeric measured variables.
#' @param explorer An explorer from [grafts()] with the new data.
#' @param outputId The id of the output, as given to [graftsOutput()] in the
#'   same module or app.
#' @param session The Shiny session, by default the one running the server.
#' @seealso [renderGrafts()]
#' @examplesIf interactive()
#' library(shiny)
#' tourism_agg <- fabletools::aggregate_key(
#'   tsibble::tourism, Purpose * (State / Region), Trips = sum(Trips)
#' )
#' ui <- fluidPage(
#'   actionButton("nsw", "New South Wales"),
#'   actionButton("recent", "Last 10 years"),
#'   graftsOutput("ts")
#' )
#' server <- function(input, output, session) {
#'   output$ts <- renderGrafts(grafts(tourism_agg))
#'   observeEvent(input$nsw, {
#'     graftsProxy("ts") |> grafts_focus(list(State = "New South Wales"))
#'   })
#'   observeEvent(input$recent, {
#'     recent <- tsibble::filter_index(tourism_agg, "2007 Q1" ~ .)
#'     graftsProxy("ts") |> grafts_update(grafts(recent))
#'   })
#' }
#' shinyApp(ui, server)
#' @name grafts-proxy
#' @export
graftsProxy <- function(outputId, session = shiny::getDefaultReactiveDomain()) {
  if (is.null(session)) abort("`graftsProxy()` must be called from a Shiny server function.")
  structure(list(id = session$ns(outputId), session = session), class = "grafts_proxy")
}

#' @rdname grafts-proxy
#' @export
grafts_focus <- function(proxy, keys) {
  rows <- key_rows(keys)
  if (length(rows) != 1) abort("`keys` must give one series to focus.")
  proxy_send(proxy, "focus", list(keys = rows[[1]]))
}

#' @rdname grafts-proxy
#' @export
grafts_pin <- function(proxy, keys, pinned = TRUE) {
  check_flag(pinned)
  proxy_send(proxy, "pin", list(keys = key_rows(keys), pinned = pinned))
}

#' @rdname grafts-proxy
#' @export
grafts_unpin <- function(proxy, keys = NULL) {
  grafts_pin(proxy, keys, pinned = FALSE)
}

#' @rdname grafts-proxy
#' @export
grafts_view <- function(proxy, view = NULL, set = NULL) {
  if (!is.null(view)) view <- arg_match(view, c("grid", "overlay", "stacked", "season"))
  if (!is.null(set)) set <- arg_match(set, c("children", "pinned"))
  proxy_send(proxy, "view", list(view = view, set = set))
}

#' @rdname grafts-proxy
#' @export
grafts_theme <- function(proxy, theme = c("system", "light", "dark")) {
  proxy_send(proxy, "theme", list(theme = arg_match(theme)))
}

#' @rdname grafts-proxy
#' @export
grafts_measure <- function(proxy, measure) {
  if (!is_string(measure)) abort("`measure` must be a string.")
  proxy_send(proxy, "measure", list(measure = measure))
}

#' @rdname grafts-proxy
#' @export
grafts_reset <- function(proxy) proxy_send(proxy, "reset", list())

#' @rdname grafts-proxy
#' @export
grafts_update <- function(proxy, explorer) {
  explorer <- check_explorer(explorer)
  payload <- explore_payload(explorer$model)
  check_payload_size(payload)
  proxy_send(proxy, "update", list(payload = structure(payload, class = "json")))
}

proxy_send <- function(proxy, cmd, args) {
  if (!inherits(proxy, "grafts_proxy")) abort("`proxy` must be made by `graftsProxy()`.")
  proxy$session$sendCustomMessage("grafts", list(id = proxy$id, cmd = cmd, args = args))
  invisible(proxy)
}

# Series as the rows of {key = value}, leaving out the keys that are
# aggregated, for the explorer to find by
key_rows <- function(keys, call = rlang::caller_env()) {
  if (is.null(keys)) return(list())
  if (is.data.frame(keys)) {
    keys <- key_strings(keys, names(keys))
    rows <- lapply(seq_len(nrow(keys)), function(i) as.list(keys[i, , drop = FALSE]))
  } else if (is.atomic(keys) || is.list(keys)) {
    rows <- list(as.list(keys))
  } else {
    abort("`keys` must be a data frame, or a named list or vector.", call = call)
  }
  map(rows, function(r) {
    if (length(r) && (is.null(names(r)) || !all(nzchar(names(r))))) abort("`keys` must be named.", call = call)
    r <- map(r, function(v) if (length(v) == 1 && !is.na(v)) as.character(v))
    compact(r)
  })
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
