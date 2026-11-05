test_that("input handlers make data frames of series and vectors of names", {
  skip_if_not_installed("shiny")
  register_input_handlers()
  series <- shiny:::inputHandlers$get("grafts.series")
  x <- jsonlite::fromJSON('{"keys":["State","Region"],"rows":[["A",null],["B","b1"]]}', simplifyVector = FALSE)
  expect_equal(series(x, NULL, "x"), data.frame(State = c("A", "B"), Region = c(NA, "b1")))
  none <- series(list(keys = list("State", "Region"), rows = list()), NULL, "x")
  expect_equal(dim(none), c(0L, 2L))
  expect_equal(names(none), c("State", "Region"))
  expect_equal(shiny:::inputHandlers$get("grafts.names")(list("State", "Region"), NULL, "x"), c("State", "Region"))
  expect_equal(shiny:::inputHandlers$get("grafts.names")(list(), NULL, "x"), character())
})

