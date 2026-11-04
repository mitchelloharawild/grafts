mean_small <- fabletools::aggregate_key(small, Purpose * (State / Region), y = mean(y))
sum_small <- fabletools::aggregate_key(small, Purpose * (State / Region), y = sum(y))

test_that("grafts_options validates", {
  expect_error(grafts_options(views = "map"))
  expect_error(grafts_options(views = character()))
  expect_error(grafts_options(additive = "yes"), "additive")
  expect_error(grafts_options(season = 1), "season")
  expect_error(grafts_options(theme = "pink"))
  expect_error(grafts_options(persist = NA), "persist")
  expect_equal(grafts_options(views = c("season", "grid"))$views, c("season", "grid"))
  expect_error(model_of(sum_small, options = list()), "grafts_options")
})

test_that("additivity is detected", {
  expect_true(model_of(sum_small)$spec$options$additive)
  expect_false(model_of(mean_small)$spec$options$additive)
  # Only the Total's split, which fixes no keys of its parent
  expect_false(model_of(fabletools::aggregate_key(small, State, y = mean(y)))$spec$options$additive)
  expect_true(model_of(fabletools::aggregate_key(small, State, y = sum(y)))$spec$options$additive)
  expect_true(model_of(sum_small, options = grafts_options(additive = TRUE))$spec$options$additive)
  expect_false(model_of(sum_small, options = grafts_options(additive = FALSE))$spec$options$additive)
  # Trusted without checking
  expect_true(model_of(mean_small, options = grafts_options(additive = TRUE))$spec$options$additive)
})

test_that("stacked goes when not additive", {
  o <- model_of(mean_small)$spec$options
  expect_false("stacked" %in% o$views)
  expect_message(
    model_of(mean_small, options = grafts_options(views = c("grid", "stacked"))),
    "Stacked"
  )
  expect_silent(model_of(mean_small))
  expect_true("stacked" %in% model_of(sum_small)$spec$options$views)
})

test_that("season options", {
  expect_null(model_of(sum_small, options = grafts_options(season = FALSE))$spec$season)
  o <- model_of(sum_small, options = grafts_options(season = FALSE))$spec$options
  expect_false("season" %in% o$views)
  expect_null(o$season)
  expect_error(model_of(sum_small, options = grafts_options(season = "week")), "not a period")
  expect_equal(model_of(sum_small)$spec$options$season, "year")
  daily <- tsibble::tsibble(d = as.Date("2020-01-01") + 0:99, g = rep(c("a", "b"), 50), y = 1, key = g, index = d)
  daily <- fabletools::aggregate_key(daily, g, y = sum(y))
  m <- model_of(daily, options = grafts_options(season = "week"))
  expect_equal(m$spec$season$name, "week")
  expect_equal(m$spec$season$period, 7)
})

test_that("options reach the spec and payload", {
  opts <- grafts_options(views = c("grid", "season"), theme = "dark", persist = FALSE)
  o <- model_of(sum_small, options = opts)$spec$options
  expect_equal(as.character(o$views), c("grid", "season"))
  expect_equal(o$theme, "dark")
  expect_false(o$persist)
  api <- api_grafts(plumber2::api(doc_type = NULL), sum_small, options = opts)
  expect_equal(attr(api, "grafts_n"), nrow(unique(tsibble::as_tibble(sum_small)[tsibble::key_vars(sum_small)])))
  f <- grafts_save(sum_small, tempfile(fileext = ".html"), options = opts)
  html <- paste(readLines(f), collapse = "\n")
  expect_match(html, "\"persist\":false", fixed = TRUE)
  expect_match(html, "\"theme\":\"dark\"", fixed = TRUE)
})
