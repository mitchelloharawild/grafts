test_that("data must be an aggregated tsibble with numeric measures", {
  expect_error(model_of(as.data.frame(small)), "must be a tsibble")
  expect_error(model_of(small), "must be aggregated")
  agg <- fabletools::aggregate_key(small, State / Region, y = sum(y))
  expect_error(explore_model(agg, rlang::quo(z), NULL, 80, 1000), "numeric measured variable")
})

test_that("series are sent with their history's total", {
  m <- model_of(fabletools::aggregate_key(small, State / Region, y = sum(y)))
  s <- explore_series(m, "y", c(0L, 1L))
  expect_named(s, c("0", "1"))
  expect_length(s[["0"]]$y, 8)
  expect_equal(s[["0"]]$sum, sum(small$y))
})

test_that("forecasts are matched to series by key, per model", {
  skip_if_not_installed("fable")
  agg <- fabletools::aggregate_key(small, State / Region, y = sum(y))
  fc <- fabletools::forecast(fabletools::model(agg, naive = fable::NAIVE(y), mean = fable::MEAN(y)), h = 4)
  m <- explore_model(agg, rlang::quo(NULL), fc, c(80, 95), 1000)
  expect_equal(m$spec$forecast$models, I(c("naive", "mean")))
  expect_length(m$spec$times, 12)
  s <- explore_series(m, "y", 0L)[["0"]]
  expect_named(s$fc, c("mean", "naive"))
  expect_equal(s$fc$naive$x, 8:11)
  expect_length(s$fc$naive$lo, 2)
})
