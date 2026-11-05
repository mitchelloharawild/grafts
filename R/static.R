# grafts_save(), and an explorer knitted or in Shiny, write every series into a
# static page, with no R process behind it. Every series is sent at once, at
# full length, as the inline payload {spec, series: {measure: {id: data}}}
# that Grafts.inline() in inst/www/grafts.js reads. Suited to small data;
# grafts_api() serves large data a series at a time.

#' Save the explorer as a static web page
#'
#' Writes an explorer from [grafts()] to an HTML file that needs no R session,
#' for sharing or publishing on a static site (such as GitHub Pages or a
#' pkgdown site). Every series, and its forecasts, is written into the page,
#' so it suits small data: for large data use [grafts_api()], which serves
#' each series only when it is drawn.
#'
#' @inheritParams grafts_api
#' @param file The HTML file to write.
#' @param self_contained Write a single file holding the explorer's script,
#'   styles and data. When `FALSE`, `file` loads `grafts.js` and
#'   `grafts.css` written beside it, and its data from a `.json` file named
#'   after `file` (`page.html` loads `page-data.json`), so pages in one
#'   directory share the script and styles but not their data. Browsers only
#'   load the data when the page is served over http(s), not opened from disk.
#' @return `file`, invisibly.
#' @examples
#' tourism_agg <- fabletools::aggregate_key(
#'   tsibble::tourism, Purpose * (State / Region), Trips = sum(Trips)
#' )
#' file <- grafts_save(grafts(tourism_agg), tempfile(fileext = ".html"))
#' if (interactive()) utils::browseURL(file)
#'
#' # The page's height, rather than the window's
#' grafts(tourism_agg, options = grafts_options(height = 500)) |>
#'   grafts_save(tempfile(fileext = ".html"))
#' @export
grafts_save <- function(explorer, file, self_contained = TRUE) {
  x <- check_explorer(explorer)
  json <- explore_payload(x$model)
  check_payload_size(json)
  www <- system.file("www", package = "grafts")
  page <- function(head, body) {
    c(
      "<!doctype html>", "<html lang=\"en\">", "<head>", "<meta charset=\"utf-8\">",
      "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
      paste0("<title>", escape_html(x$options$title), "</title>"), head,
      "<style>",
      "  html, body { margin: 0; background: #F6F7F9; }",
      "  @media (prefers-color-scheme: dark) { html, body { background: #0F1115; } }",
      paste0("  body > .grafts-root { height: ", css_length(x$options$height, "100vh"), "; }"),
      "</style>", "</head>", "<body>", "<div id=\"grafts-root\" class=\"grafts-root\"></div>", body, "</body>", "</html>"
    )
  }
  mount <- function(source) {
    c("<script>", paste0("  Grafts.mount(document.getElementById('grafts-root'), { source: Grafts.inline(", source, ") });"), "</script>")
  }
  if (self_contained) {
    html <- page(
      c("<style>", read_text(file.path(www, "grafts.css")), "</style>"),
      c(
        paste0("<script type=\"application/json\" id=\"grafts-data\">", json, "</script>"),
        "<script>", escape_script(read_text(file.path(www, "grafts.js"))), "</script>",
        mount("document.getElementById('grafts-data').textContent")
      )
    )
  } else {
    dir <- dirname(file)
    file.copy(file.path(www, c("grafts.js", "grafts.css")), dir, overwrite = TRUE)
    data_file <- paste0(tools::file_path_sans_ext(basename(file)), "-data.json")
    write_text(json, file.path(dir, data_file))
    html <- page(
      "<link rel=\"stylesheet\" href=\"grafts.css\">",
      c(
        "<script src=\"grafts.js\"></script>",
        mount(paste0("fetch(", to_json(utils::URLencode(data_file, reserved = TRUE)), ").then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })"))
      )
    )
  }
  write_text(html, file)
  invisible(file)
}

# The htmlwidget of an explorer, as knitted or rendered in Shiny
as_widget <- function(x) {
  if (inherits(x, "htmlwidget")) return(x)
  x <- check_explorer(x, "x")
  json <- explore_payload(x$model)
  check_payload_size(json)
  # The payload is already JSON, which htmlwidgets writes as it is
  payload <- list(payload = structure(json, class = "json"))
  htmlwidgets::createWidget(
    "grafts", payload, width = x$options$width, height = x$options$height, package = "grafts",
    elementId = x$options$element_id, dependencies = grafts_dependency(),
    sizingPolicy = htmlwidgets::sizingPolicy(
      defaultWidth = "100%", defaultHeight = 600, padding = 0,
      browser.fill = TRUE, viewer.fill = TRUE, knitr.figure = FALSE
    )
  )
}

#' Shiny bindings for grafts()
#'
#' Shows an explorer from [grafts()] in Shiny, with every series written into
#' the page.
#'
#' @param outputId Output variable to read from.
#' @param width,height A CSS length for the explorer.
#' @param expr An expression that returns an explorer from [grafts()].
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
  # The explorer becomes a widget once evaluated
  expr <- as.call(list(as_widget, expr))
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
grafts_dependency <- function() {
  list(htmltools::htmlDependency(
    "grafts", as.character(utils::packageVersion("grafts")),
    src = "www", package = "grafts",
    script = "grafts.js", stylesheet = "grafts.css", all_files = FALSE
  ))
}

check_payload_size <- function(json, max = 5e6) {
  size <- nchar(json, type = "bytes")
  if (size > max) {
    cli::cli_warn(c(
      "The explorer's data take {prettyNum(round(size / 1e6, 1))} MB, which is slow to load in a page.",
      i = "Serve large data a series at a time with {.fn grafts_api}, or by printing the explorer in the console."
    ))
  }
}

escape_html <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  gsub(">", "&gt;", x, fixed = TRUE)
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
