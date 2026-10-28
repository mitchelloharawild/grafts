test_that("crossed chains are found from the key combinations", {
  m <- model_of(fabletools::aggregate_key(small, Purpose * (State / Region), y = sum(y)))
  expect_equal(m$spec$structure, "Purpose * (State / Region)")
  expect_equal(lapply(m$spec$chains, unclass), list("Purpose", c("State", "Region")))
  expect_equal(m$n, 18)
  expect_length(m$spec$dims$nodes, 6)
  expect_length(m$spec$dims$edges, 7)
})

test_that("a single chain is a hierarchy", {
  m <- model_of(fabletools::aggregate_key(small, State / Region, y = sum(y)))
  expect_equal(m$spec$structure, "State / Region")
  expect_equal(m$n, 6)
  expect_equal(vapply(m$spec$dims$nodes, `[[`, "", "name"), c("Total", "State", "State / Region"))
})

test_that("combinations that aren't crossed chains are listed as terms", {
  m <- model_of(fabletools::aggregate_key(small, (State / Region) + Purpose, y = sum(y)))
  expect_null(m$spec$chains)
  expect_equal(m$spec$structure, "State + Purpose + State:Region")
  expect_equal(m$n, 8)
  expect_length(m$spec$dims$nodes, 4)
})
