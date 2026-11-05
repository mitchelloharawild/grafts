# Where each time sits in its seasonal cycle, for season plots. The period is
# the tsibble's yearly one where it has one (quarters, months, weeks, days),
# unless `season` names another of its periods.
season_info <- function(grid, data, season = NULL) {
  if (isFALSE(season)) return(NULL)
  p <- fabletools::common_periods(data)
  p <- p[p > 1]
  if (!is.null(season) && !season %in% names(p)) {
    abort(c(
      paste0("`season` \"", season, "\" is not a period of `data`."),
      i = if (length(p)) paste("Available periods:", paste0("\"", names(p), "\"", collapse = ", ")) else "`data` has no seasonal periods."
    ))
  }
  if (!length(p)) return(NULL)
  name <- season %||% if ("year" %in% names(p)) "year" else names(p)[[1]]
  d <- tryCatch(as.Date(grid), error = function(e) NULL)
  week <- c("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")
  s <- if (is.null(d)) NULL else if (name == "year") {
    if (inherits(grid, "yearquarter")) list(lubridate::quarter(d), paste0("Q", 1:4), lubridate::year(d))
    else if (inherits(grid, "yearmonth")) list(lubridate::month(d), month.abb, lubridate::year(d))
    else if (inherits(grid, "yearweek")) list(lubridate::isoweek(d), NULL, lubridate::isoyear(d))
    else list(lubridate::yday(d), NULL, lubridate::year(d))
  } else if (name == "week" && inherits(grid, "Date")) {
    list(lubridate::wday(d, week_start = 1), week, format(lubridate::floor_date(d, "week", week_start = 1)))
  }
  if (is.null(s)) {
    m <- round(p[[name]])
    i <- seq_along(grid) - 1L
    s <- list(i %% m + 1L, NULL, i %/% m + 1L)
  }
  pos <- s[[1]]; labs <- s[[2]]; cycle <- s[[3]]
  list(name = name, period = max(pos), pos = I(pos), cycle = I(as.character(cycle)), labels = if (length(labs)) I(labs))
}

# The minimum and maximum of each block of `step` times, in time order. The app
# places them at the first and last time of their block; empty blocks become a
# gap.
reduce_minmax <- function(y, max_points) {
  n <- length(y)
  step <- ceiling(2 * n / max_points)
  b <- matrix(c(y, rep(NA, (-n) %% step)), ncol = step, byrow = TRUE)
  lo <- max.col(-replace(b, is.na(b), Inf), "first")
  hi <- max.col(replace(b, is.na(b), -Inf), "first")
  i <- seq_len(nrow(b))
  list(y = c(rbind(b[cbind(i, pmin(lo, hi))], b[cbind(i, pmax(lo, hi))])), step = step, n = n)
}
