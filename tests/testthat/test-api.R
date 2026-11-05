agg <- fabletools::aggregate_key(small, State / Region, y = sum(y))

# Simulate a request without starting a server
hit <- function(api, url) {
  req <- fiery::fake_request(paste0("http://127.0.0.1:8000", url))
  api$test_request(req)
}

test_that("spec and series are served, privately cached and revalidated", {
  api <- api_grafts(plumber2::api(doc_type = NULL), agg)
  res <- hit(api, "/api/spec")
  expect_equal(res$status, 200L)
  expect_match(res$headers[["cache-control"]], "private")
  expect_false(is.null(res$headers[["etag"]]))
  expect_true("measures" %in% names(jsonlite::fromJSON(res$body)))

  res <- hit(api, "/api/series?ids=0,1")
  expect_equal(res$status, 200L)
  expect_setequal(names(jsonlite::fromJSON(res$body)), c("0", "1"))
})

test_that("an unchanged response is a 304, and a changed one is not", {
  api <- api_grafts(plumber2::api(doc_type = NULL), agg)
  etag <- hit(api, "/api/series?ids=0")$headers[["etag"]]
  again <- function(url, tag) {
    api$test_request(fiery::fake_request(
      paste0("http://127.0.0.1:8000", url), headers = list(`If-None-Match` = tag)
    ))
  }
  expect_equal(again("/api/series?ids=0", etag)$status, 304L)
  expect_equal(again("/api/series?ids=1", etag)$status, 200L)
})

test_that("the font is served with the app, and no third party is called", {
  api <- api_grafts(plumber2::api(doc_type = NULL), agg)
  res <- hit(api, "/fonts/source-sans-3-400.woff2")
  expect_equal(res$status, 200L)
  expect_match(res$headers[["content-type"]], "font/woff2")
  expect_equal(
    as.integer(res$headers[["content-length"]] %||% length(res$body)),
    file.size(system.file("www/fonts/source-sans-3-400.woff2", package = "grafts"))
  )
  expect_false(grepl("googleapis", hit(api, "/")$body, fixed = TRUE))
})

test_that("a health route reports the series", {
  api <- api_grafts(plumber2::api(doc_type = NULL), agg)
  res <- hit(api, "/api/health")
  expect_equal(res$status, 200L)
  expect_equal(jsonlite::fromJSON(res$body)$status, "ok")
})

test_that("the serving port and host come from options and the environment", {
  withr::local_options(grafts.port = NULL, grafts.host = NULL)
  withr::local_envvar(GRAFTS_PORT = NA, PORT = NA, GRAFTS_HOST = NA)
  expect_equal(serve_port(), 8000L)
  expect_equal(serve_host(), "127.0.0.1")
  withr::local_envvar(PORT = "9000")
  expect_equal(serve_port(), 9000L)
  withr::local_envvar(GRAFTS_PORT = "9100", GRAFTS_HOST = "0.0.0.0")
  expect_equal(serve_port(), 9100L)
  expect_equal(serve_host(), "0.0.0.0")
  withr::local_options(grafts.port = 9200L)
  expect_equal(serve_port(), 9200L)
})

test_that("invalid requests are 400", {
  api <- api_grafts(plumber2::api(doc_type = NULL), agg, max_ids = 2)
  expect_equal(hit(api, "/api/series?ids=0,1,2")$status, 400L)
  expect_equal(hit(api, "/api/series?ids=0,1")$status, 200L)
  expect_equal(hit(api, "/api/series?measure=nope&ids=0")$status, 400L)
  expect_equal(hit(api, "/api/series?ids=9999")$status, 400L)
  expect_equal(hit(api, "/api/series?ids=a")$status, 400L)
})

test_that("explorers mount at sub-paths", {
  api <- plumber2::api(doc_type = NULL) |>
    api_grafts(agg, path = "tourism") |>
    api_grafts(agg, path = "/retail/")
  expect_equal(hit(api, "/tourism/api/spec")$status, 200L)
  expect_equal(hit(api, "/retail/api/series?ids=0")$status, 200L)
  expect_equal(hit(api, "/api/spec")$status, 404L)
})

test_that("the app's files are served, and the bare path redirects", {
  api <- plumber2::api(doc_type = NULL) |> api_grafts(agg, path = "/tourism/")
  res <- hit(api, "/tourism/")
  expect_equal(res$status, 200L)
  expect_match(res$headers[["content-type"]], "text/html")
  expect_match(res$body, "<html", fixed = TRUE)
  expect_equal(hit(api, "/tourism/grafts.js")$status, 200L)
  expect_match(hit(api, "/tourism/grafts.css")$headers[["content-type"]], "text/css")
  res <- hit(api, "/tourism")
  expect_true(res$status %in% c(301L, 302L, 307L, 308L))
  expect_equal(res$headers[["location"]], "/tourism/")
})

test_that("api_grafts() takes an explorer, and reduces long series", {
  x <- grafts(agg)
  api <- api_grafts(plumber2::api(doc_type = NULL), x, max_points = 2)
  s <- jsonlite::fromJSON(hit(api, "/api/series?ids=0")$body, simplifyVector = FALSE)
  expect_false(is.null(s[["0"]]$step))
  # The explorer itself keeps the default
  expect_equal(x$model$max_points, 1000)
})

test_that("explorers print a summary outside the console", {
  out <- capture.output(print(grafts(agg)))
  expect_match(out[[1]], "<grafts explorer>", fixed = TRUE)
  expect_match(out[[1]], "series of State / Region", fixed = TRUE)
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
      api_grafts(agg, path = "/tourism/") |>
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
  expect_true(length(readLines(paste0(base, "grafts.js"), warn = FALSE)) > 10)
})

test_that("grafts_serve() serves until interrupted, then stops", {
  skip_on_cran()
  skip_on_os("windows")
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
    grafts_serve(agg, port = port, launch = FALSE, block = TRUE)
    "returned"
  }, list(pkg = testthat::test_path("../.."), port = port), stderr = "2>&1")
  withr::defer(bg$kill())
  url <- paste0("http://127.0.0.1:", port, "/api/spec")
  up <- function() tryCatch(suppressWarnings(length(readLines(url, warn = FALSE)) > 0), error = function(e) FALSE)
  for (i in 1:50) if (up()) break else Sys.sleep(0.2)
  expect_true(up())
  bg$interrupt()
  bg$wait(10000)
  expect_false(bg$is_alive())
  expect_equal(bg$get_result(), "returned")
  expect_false(up())
})
