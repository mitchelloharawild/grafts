# Everything the server needs, computed once
explore_model <- function(data, value, forecasts, level, max_points) {
  if (!tsibble::is_tsibble(data)) abort("`data` must be a tsibble.")
  keys <- tsibble::key_vars(data)
  plain <- keys[!map_lgl(keys, function(k) inherits(data[[k]], "agg_vec"))]
  if (length(keys) == 0 || length(plain)) {
    abort(c(
      "Every key of `data` must be aggregated.",
      i = "Use `fabletools::aggregate_key()` first.",
      if (length(plain)) x = paste("Not aggregated:", paste(plain, collapse = ", "))
    ))
  }
  measures <- keep(tsibble::measured_vars(data), function(v) is.numeric(data[[v]]))
  if (!length(measures)) abort("`data` has no numeric measured variables.")
  measure <- if (quo_is_null(value)) measures[[1]] else as_name(value)
  if (!measure %in% measures) abort("`value` must be a numeric measured variable of `data`.")

  index <- tsibble::index_var(data)
  tb <- key_strings(tsibble::as_tibble(data), keys)
  # One row per series, ordered by depth, then key values
  s <- vctrs::vec_unique(tb[keys])
  fixed <- !is.na(as.matrix(s))
  ord <- do.call(order, c(list(rowSums(fixed)), unname(as.list(s))))
  s <- s[ord, , drop = FALSE]
  fixed <- fixed[ord, , drop = FALSE]

  # The patterns of fixed keys are the key combinations given to aggregate_key()
  combos <- unique(fixed)
  chains <- combo_chains(combos, keys)

  fc <- if (!is.null(forecasts)) forecast_model(forecasts, keys, measures, level)
  grid <- vctrs::vec_sort(vctrs::vec_unique(vctrs::vec_c(data[[index]], fc$times)))
  history <- max(vctrs::vec_match(data[[index]], grid))

  # A series x time matrix per measure, NA where a series has no observation
  row <- vctrs::vec_match(tb[keys], s)
  col <- vctrs::vec_match(tb[[index]], grid)
  values <- map(set_names(measures), function(m) {
    out <- matrix(NA_real_, nrow(s), history)
    out[cbind(row, col)] <- tb[[m]]
    out
  })
  if (!is.null(fc)) {
    series <- vctrs::vec_match(fc$keys, s)
    # Each series' forecast rows, by model
    fc$rows <- map(split(seq_along(series), factor(series, seq_len(nrow(s)))), function(r) split(r, fc$model[r]))
    fc$x <- vctrs::vec_match(fc$times, grid) - 1L
  }

  spec <- list(
    structure = if (is.null(chains)) combos_text(combos, keys) else chains_text(chains),
    keys = I(keys),
    chains = if (!is.null(chains)) map(chains, I),
    measures = I(measures),
    measure = measure,
    times = I(format(grid)),
    history = history,
    season = season_info(grid, data),
    dims = dimension_graph(combos, fixed, keys, chains),
    series = map(seq_len(nrow(s)), function(i) unname(as.list(s[i, keys]))),
    forecast = if (!is.null(fc)) list(measure = fc$measure, models = I(fc$models), level = I(level))
  )
  list(spec = spec, n = nrow(s), values = values, fc = fc, max_points = max_points)
}

# Series `ids` (0-based) of `measure`, keyed by id, each with its history's
# total. Series well over `max_points` are reduced unless `raw`; forecasts come
# with the measure they forecast.
explore_series <- function(model, measure, ids, raw = FALSE) {
  fc <- model$fc
  out <- map(ids + 1L, function(i) {
    y <- model$values[[measure]][i, ]
    y <- signif(y[seq_len(max(c(0, which(!is.na(y)))))], 6)
    s <- if (raw || length(y) <= 2 * model$max_points) list(y = y) else reduce_minmax(y, model$max_points)
    s$sum <- sum(y, na.rm = TRUE)
    if (!is.null(fc) && identical(fc$measure, measure)) {
      s$fc <- map(fc$rows[[i]], function(r) list(
        x = fc$x[r], mean = signif(fc$mean[r], 6),
        lo = map(fc$lo, function(q) signif(q[r], 6)), hi = map(fc$hi, function(q) signif(q[r], 6))
      ))
    }
    s
  })
  set_names(out, ids)
}

# Forecast means and interval bounds, one row per series, model and time
forecast_model <- function(forecasts, keys, measures, level) {
  if (!fabletools::is_fable(forecasts)) abort("`forecasts` must be a fable.")
  measure <- fabletools::response_vars(forecasts)
  if (length(measure) != 1 || !measure %in% measures) {
    abort("The response of `forecasts` must be one measured variable of `data`.")
  }
  fkeys <- setdiff(tsibble::key_vars(forecasts), ".model")
  if (!setequal(fkeys, keys)) abort("`forecasts` must have the same keys as `data` (plus `.model`).")
  tb <- key_strings(tsibble::as_tibble(forecasts), keys)
  d <- tb[[fabletools::distribution_var(forecasts)]]
  list(
    measure = measure,
    keys = tb[keys],
    model = if (".model" %in% names(tb)) as.character(tb$.model) else rep("forecast", nrow(tb)),
    models = unique(if (".model" %in% names(tb)) as.character(tb$.model) else "forecast"),
    times = tb[[tsibble::index_var(forecasts)]],
    mean = mean(d),
    lo = map(level, function(l) unname(quantile(d, (1 - l / 100) / 2))),
    hi = map(level, function(l) unname(quantile(d, 1 - (1 - l / 100) / 2)))
  )
}

# Key columns as character, with aggregated values as NA
key_strings <- function(tb, keys) {
  for (k in keys) tb[[k]] <- ifelse(fabletools::is_aggregated(tb[[k]]), NA_character_, as.character(tb[[k]]))
  tb
}
