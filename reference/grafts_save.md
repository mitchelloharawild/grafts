# Save the explorer as a static web page

Writes an explorer from
[`grafts()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts.md)
to an HTML file that needs no R session, for sharing or publishing on a
static site (such as GitHub Pages or a pkgdown site). Every series, and
its forecasts, is written into the page, so it suits small data: for
large data use
[`grafts_api()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts_api.md),
which serves each series only when it is drawn.

## Usage

``` r
grafts_save(explorer, file, self_contained = TRUE)
```

## Arguments

- explorer:

  An explorer from
  [`grafts()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts.md),
  which takes the data, forecasts and options.

- file:

  The HTML file to write.

- self_contained:

  Write a single file holding the explorer's script, styles and data.
  When `FALSE`, `file` loads `grafts.js` and `grafts.css` written beside
  it, and its data from a `.json` file named after `file` (`page.html`
  loads `page-data.json`), so pages in one directory share the script
  and styles but not their data. Browsers only load the data when the
  page is served over http(s), not opened from disk.

## Value

`file`, invisibly.

## Examples

``` r
tourism_agg <- fabletools::aggregate_key(
  tsibble::tourism, Purpose * (State / Region), Trips = sum(Trips)
)
file <- grafts_save(grafts(tourism_agg), tempfile(fileext = ".html"))
if (interactive()) utils::browseURL(file)

# The page's height, rather than the window's
grafts(tourism_agg, options = grafts_options(height = 500)) |>
  grafts_save(tempfile(fileext = ".html"))
```
