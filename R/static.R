# grafts_save() and grafts() embed the explorer of grafts_explore() in a
# static page, with no R process behind it. Every series is sent at once, at
# full length, as the inline payload {spec, series: {measure: {id: data}}}
# that GraphExplore.inline() in inst/www/graph-explore.js reads. Suited to
# small data; grafts_explore() serves large data a series at a time.

#' Save the explorer as a static web page
#'
#' Writes the explorer of [grafts_explore()] to an HTML file that needs no R
#' session, for sharing or publishing on a static site (such as GitHub Pages
#' or a pkgdown site). Every series, and its forecasts, is written into the
#' page, so it suits small data: for large data use [grafts_explore()], which
#' serves each series only when it is drawn.
#'
#' The page uses the system's UI font. The standalone app of [grafts_explore()]
#' loads Source Sans 3 from Google Fonts, which a page can load too, for the
#' same look.
#'
#' @inheritParams grafts_explore
#' @param file The HTML file to write.
#' @param selfcontained Write a single file holding the explorer's script,
#'   styles and data. When `FALSE`, `file` loads `graph-explore.js`,
#'   `graph-explore.css` and `data.json` written beside it. Browsers only load
#'   `data.json` when the page is served over http(s), not opened from disk.
#' @param height Height of the explorer, in pixels or as a CSS length. By
#'   default it fills the window.
#' @return `file`, invisibly.
#' @seealso [grafts()] to embed the explorer in R Markdown, Quarto or
#'   Shiny.
#' @examples
#' tourism_agg <- fabletools::aggregate_key(
#'   tsibble::tourism, Purpose * (State / Region), Trips = sum(Trips)
#' )
#' file <- grafts_save(tourism_agg, tempfile(fileext = ".html"))
#' if (interactive()) utils::browseURL(file)
#' @export
grafts_save <- function(data, file, value = NULL, forecasts = NULL,
                        level = c(80, 95), options = grafts_options(), selfcontained = TRUE, height = NULL) {
  model <- explore_model(data, enquo(value), forecasts, level, Inf, options)
  json <- explore_payload(model)
  check_payload_size(json)
  www <- system.file("www", package = "grafts")
  page <- function(head, body) {
    c(
      "<!doctype html>", "<html lang=\"en\">", "<head>", "<meta charset=\"utf-8\">",
      "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
      "<title>Graph explorer</title>", head,
      "<style>",
      "  html, body { margin: 0; background: #F6F7F9; }",
      "  @media (prefers-color-scheme: dark) { html, body { background: #0F1115; } }",
      paste0("  body > .gx { height: ", css_length(height, "100vh"), "; }"),
      "</style>", "</head>", "<body>", "<div id=\"gx\" class=\"gx\"></div>", body, "</body>", "</html>"
    )
  }
  mount <- function(source) {
    c("<script>", paste0("  GraphExplore.mount(document.getElementById('gx'), { source: GraphExplore.inline(", source, ") });"), "</script>")
  }
  if (selfcontained) {
    html <- page(
      c("<style>", read_text(file.path(www, "graph-explore.css")), "</style>"),
      c(
        paste0("<script type=\"application/json\" id=\"gx-data\">", json, "</script>"),
        "<script>", escape_script(read_text(file.path(www, "graph-explore.js"))), "</script>",
        mount("document.getElementById('gx-data').textContent")
      )
    )
  } else {
    dir <- dirname(file)
    file.copy(file.path(www, c("graph-explore.js", "graph-explore.css")), dir, overwrite = TRUE)
    write_text(json, file.path(dir, "data.json"))
    html <- page(
      "<link rel=\"stylesheet\" href=\"graph-explore.css\">",
      c(
        "<script src=\"graph-explore.js\"></script>",
        mount("fetch('data.json').then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })")
      )
    )
  }
  write_text(html, file)
  invisible(file)
}

#' An htmlwidget of the explorer
#'
#' Embeds the explorer of [grafts_explore()] in R Markdown, Quarto, pkgdown or
#' Shiny, with no R process behind it. Every series, and its forecasts, is
#' written into the page, so it suits small data: for large data use
#' [grafts_explore()], which serves each series only when it is drawn. A page
#' can hold several explorers.
#'
#' The widget uses the system's UI font. The standalone app of
#' [grafts_explore()] loads Source Sans 3 from Google Fonts, which a page can
#' load too, for the same look.
#'
#' @inheritParams grafts_explore
#' @param width,height Size of the widget, in pixels or as a CSS length. The
#'   height defaults to 600px.
#' @param elementId An id for the widget's element.
#' @return An htmlwidget.
#' @seealso [grafts_save()] to write a standalone page.
#' @examples
#' tourism_agg <- fabletools::aggregate_key(
#'   tsibble::tourism, Purpose * (State / Region), Trips = sum(Trips)
#' )
#' grafts(tourism_agg)
#' @export
grafts <- function(data, value = NULL, forecasts = NULL, level = c(80, 95), options = grafts_options(),
                   width = NULL, height = NULL, elementId = NULL) {
  model <- explore_model(data, enquo(value), forecasts, level, Inf, options)
  json <- explore_payload(model)
  check_payload_size(json)
  # The payload is already JSON, which htmlwidgets writes as it is
  x <- list(payload = structure(json, class = "json"))
  htmlwidgets::createWidget(
    "grafts", x, width = width, height = height, package = "grafts",
    elementId = elementId, dependencies = graph_dependency(),
    sizingPolicy = htmlwidgets::sizingPolicy(
      defaultWidth = "100%", defaultHeight = 600, padding = 0,
      browser.fill = TRUE, viewer.fill = TRUE, knitr.figure = FALSE
    )
  )
}

#' Shiny bindings for grafts()
#'
#' @param outputId Output variable to read from.
#' @param width,height A CSS length for the widget.
#' @param expr An expression that returns a [grafts()].
#' @param env The environment in which to evaluate `expr`.
#' @param quoted Is `expr` a quoted expression (with `quote()`)?
#' @name grafts-shiny
#' @export
graftsOutput <- function(outputId, width = "100%", height = "600px") {
  htmlwidgets::shinyWidgetOutput(outputId, "grafts", width, height, package = "grafts")
}

#' @rdname grafts-shiny
#' @export
renderGrafts <- function(expr, env = parent.frame(), quoted = FALSE) {
  if (!quoted) expr <- substitute(expr)
  htmlwidgets::shinyRenderWidget(expr, graftsOutput, env, quoted = TRUE)
}

# The structure and every full series of every measure, as JSON that can sit
# inside a <script> element
explore_payload <- function(model) {
  measures <- as.character(model$spec$measures)
  ids <- seq_len(model$n) - 1L
  series <- map(set_names(measures), function(m) explore_series(model, m, ids, raw = TRUE))
  escape_json(to_json(list(spec = model$spec, series = series)))
}

# The explorer's script and styles, from inst/www
graph_dependency <- function() {
  list(htmltools::htmlDependency(
    "graph-explore", as.character(utils::packageVersion("grafts")),
    src = "www", package = "grafts",
    script = "graph-explore.js", stylesheet = "graph-explore.css", all_files = FALSE
  ))
}

check_payload_size <- function(json, max = 5e6) {
  size <- nchar(json, type = "bytes")
  if (size > max) {
    cli::cli_warn(c(
      "The explorer's data take {prettyNum(round(size / 1e6, 1))} MB, which is slow to load in a page.",
      i = "{.fn grafts_explore} serves large data a series at a time."
    ))
  }
}

# JSON's "<" only appear in strings, where < reads the same, so it can't
# close the <script> holding it
escape_json <- function(x) gsub("<", "\\u003c", x, fixed = TRUE)
escape_script <- function(x) gsub("</", "<\\/", x, fixed = TRUE)

# A number as pixels, or a CSS length as it is
css_length <- function(x, default) {
  if (is.null(x)) default else if (is.numeric(x)) paste0(x, "px") else x
}

read_text <- function(path) paste(readLines(path, encoding = "UTF-8", warn = FALSE), collapse = "\n")
write_text <- function(x, path) writeLines(enc2utf8(x), path, useBytes = TRUE)
