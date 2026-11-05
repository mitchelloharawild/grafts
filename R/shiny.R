# The explorer in Shiny. renderGrafts() shows an explorer from grafts(); the
# widget tells the app what it shows (the inputs <id>_focus and so on), and
# graftsProxy() steers it and replaces its data without drawing it again. Small
# data are written into the page; large data stay in R, which serves a series
# at a time through the session (shiny_data()).

#' Shiny bindings for grafts()
#'
#' Shows an explorer from [grafts()] in Shiny. The explorer tells the app what
#' it shows, through inputs named after its output, and [graftsProxy()] lets
#' the app steer it and replace its data.
#'
#' Small data are written into the page. Large data stay in R, which serves
#' each series through the Shiny session when it is drawn, as the console and
#' [grafts_api()] do. By default data with more than 250,000 values are
#' served; set `lazy` to choose.
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
#' @param lazy Serve each series through the session when it is drawn, rather
#'   than writing them all into the page. `NULL` (the default) serves data
#'   with more than 250,000 values.
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
renderGrafts <- function(expr, env = parent.frame(), quoted = FALSE, lazy = NULL) {
  if (!quoted) expr <- substitute(expr)
  # The explorer becomes a widget once evaluated
  expr <- as.call(list(shiny_widget, expr, lazy))
  htmlwidgets::shinyRenderWidget(expr, graftsOutput, env, quoted = TRUE)
}

shiny_widget <- function(x, lazy = NULL) {
  if (inherits(x, "htmlwidget")) return(x)
  x <- check_explorer(x, "x")
  as_widget(x, shiny_payload(x, lazy))
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
#' @inheritParams grafts-shiny
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
  if (!is.null(view)) view <- arg_match(view, grafts_views)
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
grafts_update <- function(proxy, explorer, lazy = NULL) {
  explorer <- check_explorer(explorer)
  payload <- shiny_payload(explorer, lazy, proxy$session)
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
  invisible()
}

# ---- Data --------------------------------------------------------------------

# Data with more values than this are served through the session, not written
# into the page (the 250,000 in the docs of `lazy`)
lazy_threshold <- 2.5e5

# The JSON the widget reads: the structure and every series, or the structure
# and the url that the session serves series from. `lazy` defaults to data too
# large to write into the page; without a session there is nothing to serve.
shiny_payload <- function(x, lazy = NULL, session = shiny::getDefaultReactiveDomain()) {
  model <- x$model
  if (!(is.null(lazy) || isTRUE(lazy) || isFALSE(lazy))) abort("`lazy` must be `NULL`, `TRUE` or `FALSE`.")
  lazy <- lazy %||% (sum(lengths(model$values)) > lazy_threshold)
  if (lazy && !is.null(session)) {
    url <- shiny_data(model, session)
    return(escape_json(to_json(list(spec = model$spec, url = url))))
  }
  json <- explore_payload(model)
  check_payload_size(json, fix = "Set {.code lazy = TRUE} in {.fn renderGrafts} to send a series at a time.")
  json
}

# Serve the series of a model through the session, as {path}api/series does,
# and return the url (which already has a query) that asks for them. The same
# data keep the same name, so drawing them again doesn't register them again.
shiny_data <- function(model, session, max_ids = 1000) {
  name <- paste0("grafts-", substr(model$version, 1, 16))
  session$registerDataObj(name, model, function(data, req) {
    query <- shiny::parseQueryString(req$QUERY_STRING)
    q <- series_query(data, query, max_ids)
    if (!is.null(q$error)) {
      return(shiny::httpResponse(400L, "application/json", to_json(list(error = q$error))))
    }
    shiny::httpResponse(
      200L, "application/json", to_json(explore_series(data, q$measure, q$ids, q$raw)),
      headers = list("Cache-Control" = "private, no-store")
    )
  })
}
