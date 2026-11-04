#' Options for the explorer
#'
#' Chooses which views the explorer offers and how it starts, for
#' [graph_explore()], [api_graph_explore()], [graph_save()] and
#' [graph_widget()].
#'
#' The Stacked view and the grid's share-of-parent scale only make sense when
#' each series is the sum of the series it splits into. With `additive = NULL`
#' this is checked on `data` (for every split of every series, at the times
#' where all the parts are observed), so means or other non-additive
#' aggregates lose those options automatically.
#'
#' @param views The view tabs offered, in order: any of `"grid"`, `"overlay"`,
#'   `"stacked"` and `"season"`.
#' @param view The tab shown first. Defaults to the first of `views`.
#' @param additive Whether each series is the sum of its children. `NULL`
#'   detects it. When not additive, the Stacked view and the share scales are
#'   removed.
#' @param season The seasonal period of the Season view: `NULL` for the
#'   automatic one (the year, where the data has one), `FALSE` for no Season
#'   view, or the name of one of `fabletools::common_periods(data)`, such as
#'   `"week"` for daily data.
#' @param theme The theme at first, for visitors who haven't chosen one:
#'   `"system"` follows their device.
#' @param remember Whether the explorer saves the visitor's choices (tab,
#'   scales, layout and theme) in their browser. Use `FALSE` for a fixed
#'   starting view, such as in documentation. When `TRUE`, saved choices that
#'   the options don't allow fall back to `view` and each tab's default scale.
#' @return A `graph_options` list, for the `options` argument of
#'   [graph_explore()] and friends.
#' @examples
#' # A grid and season plots only, always starting dark and fresh
#' graph_options(views = c("grid", "season"), theme = "dark", remember = FALSE)
#'
#' # Weekly seasons for daily data, instead of yearly ones
#' graph_options(season = "week", view = "season")
#'
#' # No Season view, and a mean-aggregated tsibble known to be non-additive
#' graph_options(season = FALSE, additive = FALSE)
#' @export
graph_options <- function(views = c("grid", "overlay", "stacked", "season"), view = NULL,
                          additive = NULL, season = NULL, theme = c("system", "light", "dark"),
                          remember = TRUE) {
  explicit <- !missing(views)
  views <- arg_match(views, c("grid", "overlay", "stacked", "season"), multiple = TRUE)
  views <- unique(views)
  view <- if (is.null(view)) views[[1]] else arg_match(view, views)
  if (!is.null(additive) && !(is.logical(additive) && length(additive) == 1 && !is.na(additive))) {
    abort("`additive` must be `TRUE`, `FALSE` or `NULL`.")
  }
  if (!(is.null(season) || isFALSE(season) || (is.character(season) && length(season) == 1 && !is.na(season)))) {
    abort("`season` must be `NULL`, `FALSE` or the name of a period, such as \"week\".")
  }
  theme <- arg_match(theme)
  if (!(is.logical(remember) && length(remember) == 1 && !is.na(remember))) abort("`remember` must be `TRUE` or `FALSE`.")
  structure(
    list(views = views, view = view, additive = additive, season = season, theme = theme,
         remember = remember, explicit_views = explicit),
    class = "graph_options"
  )
}

#' @export
print.graph_options <- function(x, ...) {
  cat("<graph_options> views: ", paste(x$views, collapse = ", "), " (starting at ", x$view, ")\n", sep = "")
  invisible(x)
}

# The options as the app reads them (spec$options), settled against the data:
# additivity detected unless given, and views the data can't support removed
resolve_options <- function(options, data, values, s, fixed, combos, dims, season) {
  if (!inherits(options, "graph_options")) abort("`options` must be made by `graph_options()`.")
  additive <- options$additive %||% is_additive(values, s, fixed, combos, dims$edges)
  views <- options$views
  drop <- character()
  if (!additive) drop <- c(drop, "stacked")
  if (is.null(season)) drop <- c(drop, "season")
  if (options$explicit_views && !additive && "stacked" %in% views) {
    cli::cli_inform(c(i = "Dropping the Stacked view: the series don't add up to their parents.",
                      "*" = "Set `additive = TRUE` in {.fn graph_options} to keep it."))
  }
  views <- setdiff(views, drop)
  if (!length(views)) abort("No views are left to offer.", i = "The data has no seasonal period or isn't additive.")
  list(
    views = I(views), view = if (options$view %in% views) options$view else views[[1]],
    additive = additive, season = season$name, theme = options$theme, remember = options$remember
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
    id <- function(r) do.call(paste, c(unname(as.list(s[r, cols, drop = FALSE])), sep = "\r"))
    g <- match(id(kid), id(par))
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
