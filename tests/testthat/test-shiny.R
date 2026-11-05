# A session that records what is sent and registered
mock_session <- function() {
  sent <- list()
  objs <- list()
  list(
    ns = function(id) paste0("mod-", id),
    sendCustomMessage = function(type, message) sent[[length(sent) + 1]] <<- list(type = type, message = message),
    registerDataObj = function(name, data, filterFunc) {
      objs[[name]] <<- list(data = data, filter = filterFunc)
      paste0("session/x/dataobj/", name, "?w=&nonce=n")
    },
    sent = function() sent,
    objs = function() objs
  )
}

test_that("keys become rows of the keys a series is fixed at", {
  expect_equal(key_rows(list(State = "A")), list(list(State = "A")))
  expect_equal(key_rows(c(State = "A", Region = "a1")), list(list(State = "A", Region = "a1")))
  expect_equal(key_rows(list(State = "A", Region = NA)), list(list(State = "A")))
  expect_equal(key_rows(list()), list(list()))
  expect_equal(key_rows(NULL), list())
  rows <- key_rows(data.frame(State = c("A", "B"), Region = c("a1", NA)))
  expect_equal(rows, list(list(State = "A", Region = "a1"), list(State = "B")))
  # Aggregated values, as in the aggregated data, are the keys left out
  agg <- fabletools::aggregate_key(small, State / Region, y = sum(y))
  keys <- unique(as.data.frame(agg)[c("State", "Region")])
  expect_true(any(lengths(key_rows(keys)) == 0))
  expect_error(key_rows(list("A")), "named")
})

test_that("commands go to the explorer's output, namespaced", {
  s <- mock_session()
  proxy <- graftsProxy("ts", session = s)
  expect_equal(proxy$id, "mod-ts")
  expect_identical(grafts_focus(proxy, list(State = "A")), proxy)
  grafts_pin(proxy, data.frame(State = c("A", "B")))
  grafts_unpin(proxy)
  grafts_view(proxy, "overlay", set = "pinned")
  grafts_theme(proxy, "dark")
  grafts_measure(proxy, "y")
  grafts_reset(proxy)
  sent <- s$sent()
  expect_equal(vapply(sent, function(m) m$message$cmd, ""), c("focus", "pin", "pin", "view", "theme", "measure", "reset"))
  expect_true(all(vapply(sent, function(m) m$type == "grafts" && m$message$id == "mod-ts", logical(1))))
  expect_equal(sent[[1]]$message$args$keys, list(State = "A"))
  expect_equal(sent[[2]]$message$args$pinned, TRUE)
  expect_equal(sent[[3]]$message$args, list(keys = list(), pinned = FALSE))
  expect_error(grafts_view(proxy, "pie"))
  expect_error(grafts_theme(proxy, "pink"))
  expect_error(grafts_focus(proxy, data.frame(State = c("A", "B"))), "one series")
  expect_error(graftsProxy("ts", session = NULL), "server")
  expect_error(grafts_focus(list(), list()), "graftsProxy")
})

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

