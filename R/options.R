# The views the explorer can offer
grafts_views <- c("grid", "overlay", "stacked", "season")

#' Options for the explorer
#'
#' Chooses which views the explorer offers, how it starts, how its data are
#' sent and how big it is when embedded, for the `options` argument of
#' [grafts()].
#'
#' The Stacked view and the grid's share-of-parent scale only make sense when
#' each series is the sum of the series it splits into. With `additive = NULL`
#' this is checked on `data` (for every split of every series, at the times
#' where all the parts are observed), so means or other non-additive
#' aggregates lose those options automatically.
#'
#' @param views The view tabs offered, in order: any of `"grid"`, `"overlay"`,
#'   `"stacked"` and `"season"`. The first is shown at the start.
#' @param additive Whether each series is the sum of its children. `NULL`
#'   detects it. When not additive, the Stacked view and the share scales are
#'   removed.
#' @param season The seasonal period of the Season view: `NULL` for the
#'   automatic one (the year, where the data has one), `FALSE` for no Season
#'   view, or the name of one of `fabletools::common_periods(data)`, such as
#'   `"week"` for daily data.
#' @param theme The theme at first, for visitors who haven't chosen one:
#'   `"system"` follows their device.
#' @param persist Whether the explorer saves the visitor's choices (tab,
#'   scales, layout and theme) in their browser. Use `FALSE` for a fixed
#'   starting view, such as in documentation. When `TRUE`, saved choices that
#'   the options don't allow fall back to the first of `views` and each tab's default scale.
#' @param max_points Series more than twice this long are sent to the app as
#'   the minimum and maximum of blocks of time, about `max_points` values, so
#'   spikes stay visible. The season and stacked plots always get the full
#'   series, and an explorer written into a page ([grafts_save()], documents
#'   and Shiny) always has the full series.
#' @param width,height Size of the explorer when written into a page, in
#'   pixels or as a CSS length. In documents and Shiny the height defaults to
#'   600px, and a page from [grafts_save()] fills the window.
#' @param title The title of the page, for the browser's tab: served by
#'   [grafts_serve()] and [grafts_api()], and written by [grafts_save()].
#' @param element_id An id for the explorer's element in a document.
#' @return A `grafts_options` list, for the `options` argument of
#'   [grafts()].
#' @examples
#' # A grid and season plots only, always starting dark and fresh
#' grafts_options(views = c("grid", "season"), theme = "dark", persist = FALSE)
#'
#' # Weekly seasons for daily data, instead of yearly ones
#' grafts_options(views = c("season", "grid", "overlay"), season = "week")
#'
#' # No Season view, and a mean-aggregated tsibble known to be non-additive
#' grafts_options(season = FALSE, additive = FALSE)
#' @export
grafts_options <- function(views = c("grid", "overlay", "stacked", "season"),
                           additive = NULL, season = NULL, theme = c("system", "light", "dark"),
                           persist = TRUE, max_points = 1000,
                           width = NULL, height = NULL, element_id = NULL,
                           title = "Graph explorer") {
  explicit <- !missing(views)
  views <- unique(arg_match(views, grafts_views, multiple = TRUE))
  if (!length(views)) abort("`views` must name at least one view.")
  check_flag(additive, null = TRUE)
  if (!(is.null(season) || isFALSE(season) || is_string(season))) {
    abort("`season` must be `NULL`, `FALSE` or the name of a period, such as \"week\".")
  }
  theme <- arg_match(theme)
  check_flag(persist)
  if (!is_number(max_points) || max_points < 2) abort("`max_points` must be a number, at least 2.")
  check_size(width)
  check_size(height)
  if (!is_string(title)) abort("`title` must be a string.")
  if (!(is.null(element_id) || is_string(element_id))) abort("`element_id` must be `NULL` or a string.")
  structure(
    list(views = views, additive = additive, season = season, theme = theme,
         persist = persist, max_points = max_points,
         width = width, height = height, element_id = element_id, title = title),
    explicit_views = explicit,
    class = "grafts_options"
  )
}

is_scalar <- function(x, test) test(x) && length(x) == 1 && !is.na(x)
is_string <- function(x) is_scalar(x, is.character)
is_number <- function(x) is_scalar(x, is.numeric)

check_flag <- function(x, null = FALSE, arg = rlang::caller_arg(x), call = rlang::caller_env()) {
  if (null && is.null(x)) return(invisible(x))
  if (!is_scalar(x, is.logical)) {
    abort(paste0("`", arg, "` must be `TRUE` or `FALSE`", if (null) " or `NULL`", "."), call = call)
  }
  invisible(x)
}

# A size in pixels, or as a CSS length
check_size <- function(x, arg = rlang::caller_arg(x), call = rlang::caller_env()) {
  if (!(is.null(x) || (is_number(x) && x > 0) || is_string(x))) {
    abort(paste0("`", arg, "` must be `NULL`, a number of pixels or a CSS length."), call = call)
  }
  invisible(x)
}

#' @export
print.grafts_options <- function(x, ...) {
  cat("<grafts_options> views: ", paste(x$views, collapse = ", "), " (starting at ", x$views[[1]], ")\n", sep = "")
  invisible(x)
}

# The options as the app reads them (spec$options), settled against the data:
# additivity detected unless given, and views the data can't support removed
resolve_options <- function(options, data, values, s, fixed, combos, dims, season) {
  if (!inherits(options, "grafts_options")) abort("`options` must be made by `grafts_options()`.")
  additive <- options$additive %||% is_additive(values, s, fixed, combos, dims$edges)
  views <- options$views
  drop <- character()
  if (!additive) drop <- c(drop, "stacked")
  if (is.null(season)) drop <- c(drop, "season")
  if (isTRUE(attr(options, "explicit_views")) && !additive && "stacked" %in% views) {
    cli::cli_inform(c(i = "Dropping the Stacked view: the series don't add up to their parents.",
                      "*" = "Set `additive = TRUE` in {.fn grafts_options} to keep it."))
  }
  views <- setdiff(views, drop)
  if (!length(views)) abort("No views are left to offer.", i = "The data has no seasonal period or isn't additive.")
  list(
    views = I(views), additive = additive, season = season$name, theme = options$theme,
    persist = options$persist
  )
}

# Whether every series is the sum of its children along every way it splits,
# wherever the series and all its children are observed. A child along an edge
# fixes the edge's keys and keeps its parent's, so children are grouped by the
# parent's fixed keys.
is_additive <- function(values, s, fixed, combos, edges, tol = 1e-6) {
  pat <- pattern(fixed)
  cpat <- pattern(combos)
  keys <- colnames(combos)
  for (e in edges) {
    cols <- keys[combos[e$from + 1L, ]]
    par <- which(pat == cpat[e$from + 1L])
    kid <- which(pat == cpat[e$to + 1L])
    # The Total fixes no keys, so every series is its child
    id <- if (length(cols)) vctrs::vec_group_id(vctrs::vec_slice(s[cols], c(par, kid))) else rep(1L, length(par) + length(kid))
    g <- match(id[length(par) + seq_along(kid)], id[seq_along(par)])
    ok <- !is.na(g)
    kid <- kid[ok]; g <- g[ok]
    if (!length(kid)) next
    n <- tabulate(g, length(par))
    for (v in values) {
      k <- v[kid, , drop = FALSE]
      seen <- rowsum(+!is.na(k), g)
      total <- rowsum(replace(k, is.na(k), 0), g)
      rows <- as.integer(rownames(total))
      p <- v[par[rows], , drop = FALSE]
      all_seen <- seen == n[rows] & !is.na(p)
      if (any(abs(total - p)[all_seen] > tol * pmax(abs(p), abs(total))[all_seen])) return(FALSE)
    }
  }
  TRUE
}
