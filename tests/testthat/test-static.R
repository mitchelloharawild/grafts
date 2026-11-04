small_agg <- function() fabletools::aggregate_key(small, Purpose * (State / Region), y = sum(y), z = mean(y))

test_that("the payload has every series of every measure, at full length", {
  m <- explore_model(small_agg(), rlang::quo(NULL), NULL, c(80, 95), 2)
  p <- jsonlite::fromJSON(explore_payload(m), simplifyVector = FALSE)
  expect_named(p, c("spec", "series"))
  expect_named(p$series, c("y", "z"))
  for (s in p$series) {
    expect_setequal(names(s), as.character(seq_len(m$n) - 1))
    expect_length(s[["0"]]$y, 8)
    expect_null(s[["0"]]$step)
  }
  expect_length(p$spec$series, m$n)
})

test_that("the payload carries forecasts", {
  skip_if_not_installed("fable")
  agg <- small_agg()
  fc <- fabletools::forecast(fabletools::model(agg, naive = fable::NAIVE(y)), h = 4)
  m <- explore_model(agg, rlang::quo(NULL), fc, c(80, 95), Inf)
  p <- jsonlite::fromJSON(explore_payload(m), simplifyVector = FALSE)
  expect_equal(p$spec$forecast$models, list("naive"))
  expect_true(all(vapply(p$series$y, function(s) !is.null(s$fc$naive), logical(1))))
  expect_null(p$series$z[["0"]]$fc)
})

test_that("JSON can't close the script holding it", {
  expect_equal(escape_json('{"a":"</script>"}'), '{"a":"\\u003c/script>"}')
  expect_equal(jsonlite::fromJSON(escape_json('{"a":"</script>"}'))$a, "</script>")
})

test_that("grafts_save() writes a page holding the payload", {
  # A key that would close the page's <script> if written as it is
  odd <- as.data.frame(small)
  odd$Purpose <- paste0("</script>", odd$Purpose)
  odd <- tsibble::as_tsibble(odd, index = Quarter, key = c(State, Region, Purpose))
  agg <- fabletools::aggregate_key(odd, Purpose * (State / Region), y = sum(y), z = mean(y))
  file <- tempfile(fileext = ".html")
  expect_identical(grafts_save(agg, file, height = 500), file)
  html <- paste(readLines(file), collapse = "\n")
  json <- sub('.*<script type="application/json" id="gx-data">(.*?)</script>.*', "\\1", html)
  expect_false(grepl("</script", json, fixed = TRUE))
  expect_match(json, "\\u003c\\/script>Work", fixed = TRUE)
  p <- jsonlite::fromJSON(json, simplifyVector = FALSE)
  expect_named(p$series, c("y", "z"))
  expect_match(html, "GraphExplore.mount", fixed = TRUE)
  expect_match(html, "body > .gx { height: 500px; }", fixed = TRUE)
  expect_false(grepl("fonts.googleapis", html, fixed = TRUE))
})

test_that("grafts_save() can write its script, styles and data beside the page", {
  dir <- tempfile()
  dir.create(dir)
  grafts_save(small_agg(), file.path(dir, "index.html"), selfcontained = FALSE)
  expect_setequal(list.files(dir), c("index.html", "graph-explore.js", "graph-explore.css", "data.json"))
  p <- jsonlite::fromJSON(file.path(dir, "data.json"), simplifyVector = FALSE)
  expect_named(p, c("spec", "series"))
  html <- paste(readLines(file.path(dir, "index.html")), collapse = "\n")
  expect_match(html, "fetch('data.json')", fixed = TRUE)
})

test_that("grafts() embeds the payload as JSON", {
  w <- grafts(small_agg(), value = z)
  expect_s3_class(w, "grafts")
  p <- jsonlite::fromJSON(unclass(w$x$payload), simplifyVector = FALSE)
  expect_equal(p$spec$measure, "z")
  file <- tempfile(fileext = ".html")
  htmlwidgets::saveWidget(w, file, selfcontained = FALSE)
  html <- paste(readLines(file), collapse = "\n")
  expect_match(html, '"payload":{"spec":', fixed = TRUE)
})

test_that("large payloads warn", {
  expect_warning(check_payload_size(strrep("x", 11), max = 10), "grafts_explore")
  expect_no_warning(check_payload_size(strrep("x", 10), max = 10))
})
