test_that("quarterly series have a yearly season", {
  m <- model_of(fabletools::aggregate_key(small, State / Region, y = sum(y)))
  season <- m$spec$season
  expect_equal(season$name, "year")
  expect_equal(season$period, 4)
  expect_equal(unclass(season$labels), paste0("Q", 1:4))
  expect_equal(unclass(season$pos), rep(1:4, 2))
})

test_that("long series keep each block's minimum and maximum in time order", {
  r <- reduce_minmax(c(1, 5, 2, 8, 3, NA, 7, 0), 4)
  expect_equal(r$y, c(1, 8, 7, 0))
  expect_equal(r$step, 4)
  expect_equal(r$n, 8)
})
