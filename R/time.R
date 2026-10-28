# Where each time sits in its seasonal cycle, for season plots. The period is
# the tsibble's yearly one where it has one (quarters, months, weeks, days).
season_info <- function(grid, data) {
  p <- fabletools::common_periods(data)
  p <- p[p > 1]
  if (!length(p)) return(NULL)
  name <- if ("year" %in% names(p)) "year" else names(p)[[1]]
  d <- tryCatch(as.Date(grid), error = function(e) NULL)
  if (!is.null(d) && name == "year") {
    if (inherits(grid, "yearquarter")) {
      pos <- lubridate::quarter(d); labs <- paste0("Q", 1:4)
    } else if (inherits(grid, "yearmonth")) {
      pos <- lubridate::month(d); labs <- month.abb
    } else if (inherits(grid, "yearweek")) {
      pos <- lubridate::isoweek(d); labs <- NULL
    } else {
      pos <- lubridate::yday(d); labs <- NULL
    }
    cycle <- if (inherits(grid, "yearweek")) lubridate::isoyear(d) else lubridate::year(d)
  } else if (!is.null(d) && name == "week" && inherits(grid, "Date")) {
    pos <- lubridate::wday(d, week_start = 1); labs <- c("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")
    cycle <- format(lubridate::floor_date(d, "week", week_start = 1))
  } else {
    m <- round(p[[name]])
    pos <- (seq_along(grid) - 1L) %% m + 1L; labs <- NULL
    cycle <- (seq_along(grid) - 1L) %/% m + 1L
  }
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
