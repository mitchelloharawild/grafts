# Explore an aggregated tsibble through its series and dimension graphs

Makes an explorer of an aggregated tsibble, drawn in the browser. The
left column holds the series graph, drawn on demand, above the dimension
graph of the key combinations given to
[`fabletools::aggregate_key()`](https://fabletools.tidyverts.org/reference/aggregate_key.html).
The right column plots the focused series, with forecasts when a fable
is given, above a view of its children or of the pinned series.

## Usage

``` r
grafts(
  data,
  measure = NULL,
  forecasts = NULL,
  level = c(80, 95),
  options = grafts_options()
)
```

## Arguments

- data:

  An aggregated tsibble, as produced by
  [`fabletools::aggregate_key()`](https://fabletools.tidyverts.org/reference/aggregate_key.html).

- measure:

  The measured variable shown first. Every numeric measured variable can
  be chosen in the app. Defaults to the first.

- forecasts:

  A fable of forecasts for `data`, with the same keys (and optionally
  `.model`). Its response variable must be a measured variable of
  `data`. Each model's mean and intervals are drawn after the data.

- level:

  Interval levels drawn for `forecasts`.

- options:

  Which views the explorer offers, how it starts and is sized, and how
  its data are sent, from
  [`grafts_options()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts_options.md).

## Value

An explorer, of class `grafts`.

## Details

Where the explorer goes decides how its series reach the browser:

- Printed in the console, it opens in the viewer or a browser, served by
  a local server that sends each series when it is drawn, so data of any
  size can be explored. Like a Shiny app, the console waits while it is
  served: press Ctrl+C (or Esc in RStudio and Positron) to stop it. Use
  [`grafts_serve()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts_api.md)
  to serve it in the background instead.

- In R Markdown, Quarto, pkgdown or Shiny
  ([`renderGrafts()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts-shiny.md)),
  and in a page written by
  [`grafts_save()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts_save.md),
  every series is written into the page, which needs no R session. This
  suits small data.

- On a server,
  [`grafts_api()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts_api.md)
  adds it to a plumber2 api and
  [`grafts_serve()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts_api.md)
  runs it, sending each series when it is drawn.

Embedded explorers use the system's UI font. The served app brings its
own copy of Source Sans 3, which a page can load too, for the same look.

## Examples

``` r
tourism_agg <- fabletools::aggregate_key(
  tsibble::tourism, Purpose * (State / Region), Trips = sum(Trips)
)
tourism <- grafts(tourism_agg)

# Printing opens it, served from this R session
if (interactive()) tourism

# With forecasts, drawn after the data with their intervals
if (requireNamespace("fable", quietly = TRUE)) {
  library(fable)
  tourism_fc <- tourism_agg |>
    model(snaive = SNAIVE(Trips)) |>
    forecast(h = "2 years")
  grafts(tourism_agg, forecasts = tourism_fc)
}
#> Loading required package: fabletools
#> <grafts explorer> 425 series of Purpose * (State / Region)
#> Measures: Trips (showing Trips)
#> Forecasts: snaive
```
