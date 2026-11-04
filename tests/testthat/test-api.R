agg <- fabletools::aggregate_key(small, State / Region, y = sum(y))

# Simulate a request without starting a server
hit <- function(api, url) {
  req <- fiery::fake_request(paste0("http://127.0.0.1:8000", url))
  api$test_request(req)
}

test_that("spec and series are served with cache headers", {
  api <- api_graph_explore(plumber2::api(doc_type = NULL), agg)
  res <- hit(api, "/api/spec")
  expect_equal(res$status, 200L)
  expect_match(res$headers[["cache-control"]], "max-age")
  expect_true("measures" %in% names(jsonlite::fromJSON(res$body)))

  res <- hit(api, "/api/series?ids=0,1")
  expect_equal(res$status, 200L)
  expect_setequal(names(jsonlite::fromJSON(res$body)), c("0", "1"))
})

test_that("invalid requests are 400", {
  api <- api_graph_explore(plumber2::api(doc_type = NULL), agg, max_ids = 2)
  expect_equal(hit(api, "/api/series?ids=0,1,2")$status, 400L)
  expect_equal(hit(api, "/api/series?ids=0,1")$status, 200L)
  expect_equal(hit(api, "/api/series?measure=nope&ids=0")$status, 400L)
  expect_equal(hit(api, "/api/series?ids=9999")$status, 400L)
  expect_equal(hit(api, "/api/series?ids=a")$status, 400L)
})

test_that("explorers mount at sub-paths", {
  api <- plumber2::api(doc_type = NULL) |>
    api_graph_explore(agg, path = "tourism") |>
    api_graph_explore(agg, path = "/retail/")
  expect_equal(hit(api, "/tourism/api/spec")$status, 200L)
  expect_equal(hit(api, "/retail/api/series?ids=0")$status, 200L)
  expect_equal(hit(api, "/api/spec")$status, 404L)
})

test_that("static files are served under a sub-path", {
  skip_on_cran()
  skip_if_not_installed("callr")
  skip_if_not_installed("pkgload")
  port <- httpuv::randomPort()
  bg <- callr::r_bg(function(pkg, port) {
    if (file.exists(file.path(pkg, "DESCRIPTION"))) {
      pkgload::load_all(pkg, quiet = TRUE)
    } else {
      library(grafts)
    }
    small <- tsibble::tsibble(t = 1:4, k = "a", y = 1:4, index = t, key = k)
    agg <- fabletools::aggregate_key(small, k, y = sum(y))
    plumber2::api(port = port, doc_type = NULL) |>
      api_graph_explore(agg, path = "/tourism/") |>
      plumber2::api_run(block = TRUE, showcase = FALSE, silent = TRUE)
  }, list(pkg = testthat::test_path("../.."), port = port))
  withr::defer(bg$kill())
  base <- paste0("http://127.0.0.1:", port, "/tourism/")
  for (i in 1:50) {
    ok <- tryCatch(suppressWarnings(length(readLines(paste0(base, "api/spec"), warn = FALSE)) > 0), error = function(e) FALSE)
    if (ok) break
    Sys.sleep(0.2)
  }
  expect_true(ok)
  expect_match(paste(readLines(base, warn = FALSE), collapse = "\n"), "<html", ignore.case = TRUE)
  expect_true(length(readLines(paste0(base, "graph-explore.js"), warn = FALSE)) > 10)
})
