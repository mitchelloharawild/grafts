
<!-- README.md is generated from README.Rmd. Please edit that file -->

# grafts <a href="https://pkg.mitchelloharawild.com/grafts/"><img src="man/figures/logo.svg" align="right" height="139" alt="grafts website" /></a>

<!-- badges: start -->

[![Lifecycle:
experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![R-CMD-check](https://github.com/mitchelloharawild/grafts/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/mitchelloharawild/grafts/actions/workflows/R-CMD-check.yaml)
<!-- badges: end -->

grafts (**gra**ph **f**orecasts for **t**ime **s**eries) is an
interactive browser app for exploring aggregated time series, such as
hierarchical, grouped and nested series, and their forecasts.

<figure>
<img src="man/figures/app.png" alt="The grafts explorer app" />
<figcaption aria-hidden="true">The grafts explorer app</figcaption>
</figure>

## Installation

You can install the development version of grafts from
[GitHub](https://github.com/mitchelloharawild/grafts) with:

``` r
# install.packages("pak")
pak::pak("mitchelloharawild/grafts")
```

## Usage

grafts explores time series stored in a
[tsibble](https://tsibble.tidyverts.org/) whose keys have been
aggregated with `aggregate_key()`. Any structure of keys works, whether
hierarchical (`State / Region`), grouped (`Purpose * State`) or a mix of
both.

``` r
library(grafts)
library(fable)

tourism_agg <- aggregate_key(
  tsibble::tourism, Purpose * (State / Region), Trips = sum(Trips)
)
app <- graph_explore(tourism_agg)
```

`graph_explore()` opens the explorer in a browser. The data stays in R,
which serves each series only when it is drawn, so large collections of
series open quickly. The app runs in the background until it is stopped
with:

``` r
plumber2::api_stop(app)
```

To also explore forecasts, pass a [fable](https://fable.tidyverts.org/)
of forecasts for those series to `forecasts`. Each model’s forecasts and
intervals are drawn after the data.

``` r
tourism_fc <- tourism_agg |>
  model(ets = ETS(Trips), snaive = SNAIVE(Trips)) |>
  forecast(h = "2 years")
app <- graph_explore(tourism_agg, forecasts = tourism_fc)
```

## Exploring

The explorer starts from the total of all series. Its left side shows
the **series graph**, where each node is a series and its children sum
to it. Clicking a node lists the ways it can be split, such as by
`Purpose` or `State`, and choosing one adds those disaggregates to the
graph. Below it, the **dimension graph** shows the structure of keys and
highlights where the explorer is.

The right side plots the series being explored above its disaggregates,
which can be shown as small multiples, overlaid, stacked (to see what
each contributes to the total) or as seasonal plots. Clicking a time
plot focuses that series, and hovering a node highlights its series
wherever it is plotted. Right-clicking a node collapses its children,
and shift-clicking pins it so series from different parts of the graph
can be compared side by side.

## Deploying

`graph_explore()` is for the console. To serve the explorer from a
server, add it to a plumber2 api with `api_graph_explore()`. In a
plumber2 file, such as for Posit Connect:

``` r
#* @plumber
function(api) {
  api_graph_explore(api, readRDS("tourism_agg.rds"))
}
```

In Docker, listen on all interfaces:

``` r
readRDS("tourism_agg.rds") |>
  graph_explore(host = "0.0.0.0", port = 8000, launch = FALSE)
```

Several explorers can share one api by giving each a `path`, such as
`api_graph_explore(api, tourism_agg, path = "/tourism/")`. Open the app
at the trailing slash (`/tourism/`), as it fetches its data with
relative urls.

## Embedding

Small collections of series can be explored without R, on a static web
page such as a pkgdown site, a blog or GitHub Pages. `graph_save()`
writes the explorer and every series into a single HTML file, and
`graph_widget()` embeds it in R Markdown, Quarto or Shiny, where a page
can hold several explorers.

``` r
graph_save(tourism_agg, "tourism.html", forecasts = tourism_fc)
graph_widget(tourism_agg, height = 600)
```

`graph_options()` chooses the views offered, the starting view and
theme, and whether visitors’ choices are remembered, for every way of
serving the explorer. Whether series add up to their parents is
detected, hiding the Stacked view and share scales for means.

``` r
graph_widget(tourism_agg, options = graph_options(
  views = c("grid", "season"), theme = "dark", remember = FALSE
))
```

Every series is written into the page, so large collections are better
served by `graph_explore()`. Embedded explorers use the system’s UI
font, unless the page loads [Source Sans
3](https://fonts.google.com/specimen/Source+Sans+3) as the app does.
