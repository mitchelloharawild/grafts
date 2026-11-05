
test_that("the payload has every series of every measure, at full length", {
  m <- explore_model(small_agg(), rlang::quo(NULL), NULL, c(80, 95), grafts_options(max_points = 2))
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
  m <- explore_model(agg, rlang::quo(NULL), fc, c(80, 95), grafts_options(max_points = Inf))
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
  expect_identical(grafts_save(grafts(agg, options = grafts_options(height = 500)), file), file)
  html <- paste(readLines(file), collapse = "\n")
  json <- sub('.*<script type="application/json" id="grafts-data">(.*?)</script>.*', "\\1", html)
  expect_false(grepl("</script", json, fixed = TRUE))
  expect_match(json, "\\u003c\\/script>Work", fixed = TRUE)
  p <- jsonlite::fromJSON(json, simplifyVector = FALSE)
  expect_named(p$series, c("y", "z"))
  expect_match(html, "Grafts.mount", fixed = TRUE)
  expect_match(html, "body > .grafts-root { height: 500px; }", fixed = TRUE)
  expect_false(grepl("fonts.googleapis", html, fixed = TRUE))
})

test_that("grafts_save() can write its script, styles and data beside the page", {
  dir <- tempfile()
  dir.create(dir)
  grafts_save(grafts(small_agg()), file.path(dir, "index.html"), self_contained = FALSE)
  expect_setequal(list.files(dir), c("index.html", "grafts.js", "grafts.css", "index-data.json"))
  p <- jsonlite::fromJSON(file.path(dir, "index-data.json"), simplifyVector = FALSE)
  expect_named(p, c("spec", "series"))
  html <- paste(readLines(file.path(dir, "index.html")), collapse = "\n")
  expect_match(html, "fetch(\"index-data.json\")", fixed = TRUE)
})

test_that("pages saved beside each other keep their own data, and a title", {
  dir <- tempfile()
  dir.create(dir)
  a <- grafts(small_agg(), options = grafts_options(title = "A <b>"))
  b <- grafts(small_agg(), measure = z)
  grafts_save(a, file.path(dir, "a.html"), self_contained = FALSE)
  grafts_save(b, file.path(dir, "b.html"), self_contained = FALSE)
  expect_setequal(list.files(dir), c("a.html", "b.html", "a-data.json", "b-data.json", "grafts.js", "grafts.css"))
  expect_match(paste(readLines(file.path(dir, "a.html")), collapse = "\n"), "<title>A &lt;b&gt;</title>", fixed = TRUE)
  m <- function(f) jsonlite::fromJSON(file.path(dir, f), simplifyVector = FALSE)$spec$measure
  expect_equal(c(m("a-data.json"), m("b-data.json")), c("y", "z"))
})

test_that("an explorer becomes a widget holding the payload as JSON", {
  w <- as_widget(grafts(small_agg(), measure = z, options = grafts_options(height = 400, element_id = "gx1")))
  expect_s3_class(w, "htmlwidget")
  expect_equal(w$height, 400)
  p <- jsonlite::fromJSON(unclass(w$x$payload), simplifyVector = FALSE)
  expect_equal(p$spec$measure, "z")
  file <- tempfile(fileext = ".html")
  htmlwidgets::saveWidget(w, file, selfcontained = FALSE)
  html <- paste(readLines(file), collapse = "\n")
  expect_match(html, '"payload":{"spec":', fixed = TRUE)
})

test_that("the explorer and its widget share a class, but not methods", {
  x <- grafts(small_agg())
  w <- as_widget(x)
  expect_s3_class(x, "grafts")
  expect_s3_class(w, c("grafts", "htmlwidget"), exact = TRUE)
  expect_identical(as_widget(w), w)
  expect_match(as.character(htmltools::as.tags(w)), "htmlwidget", fixed = TRUE)
  expect_error(grafts_api(plumber2::api(doc_type = NULL), w), "widget")
})

test_that("an explorer is knitted and tagged as its widget", {
  x <- grafts(small_agg())
  tags <- htmltools::as.tags(x)
  expect_match(as.character(tags), "htmlwidget", fixed = TRUE)
  skip_if_not_installed("knitr")
  withr::local_options(knitr.in.progress = TRUE)
  old <- knitr::opts_knit$get("rmarkdown.pandoc.to")
  knitr::opts_knit$set(rmarkdown.pandoc.to = "html")
  withr::defer(knitr::opts_knit$set(rmarkdown.pandoc.to = old))
  out <- knitr::knit_print(x)
  expect_s3_class(out, "knit_asis")
  expect_true(length(attr(out, "knit_meta")) > 0)
})

test_that("renderGrafts() takes an explorer", {
  skip_if_not_installed("shiny")
  x <- grafts(small_agg())
  f <- renderGrafts(x)
  expect_true(is.function(f))
})

test_that("the delivery functions take an explorer, not data", {
  file <- tempfile(fileext = ".html")
  grafts_save(grafts(small_agg(), measure = z), file)
  expect_match(paste(readLines(file), collapse = "\n"), '"measure":"z"', fixed = TRUE)
  expect_error(grafts_save(small_agg(), file), "grafts\\(data\\)")
  expect_error(grafts_serve(small_agg()), "explorer made by")
  expect_error(grafts_api(plumber2::api(doc_type = NULL), small_agg()), "explorer made by")
})

test_that("large payloads warn", {
  expect_warning(check_payload_size(strrep("x", 11), max = 10), "grafts_api")
  expect_no_warning(check_payload_size(strrep("x", 10), max = 10))
})
