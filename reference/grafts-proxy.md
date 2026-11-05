# Steer an explorer in Shiny

`graftsProxy()` points at an explorer drawn by
[`renderGrafts()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts-shiny.md),
to change what it shows or its data from the server, without drawing it
again. The explorer reports what it shows back through inputs (see
[`graftsOutput()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts-shiny.md)).

## Usage

``` r
graftsProxy(outputId, session = shiny::getDefaultReactiveDomain())

grafts_focus(proxy, keys)

grafts_pin(proxy, keys, pinned = TRUE)

grafts_unpin(proxy, keys = NULL)

grafts_view(proxy, view = NULL, set = NULL)

grafts_theme(proxy, theme = c("system", "light", "dark"))

grafts_measure(proxy, measure)

grafts_reset(proxy)

grafts_update(proxy, explorer, lazy = NULL)
```

## Arguments

- outputId:

  The id of the output, as given to
  [`graftsOutput()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts-shiny.md)
  in the same module or app.

- session:

  The Shiny session, by default the one running the server.

- proxy:

  A proxy from `graftsProxy()`.

- keys:

  The series, as a data frame with a column for each key and a row for
  each series (such as the rows of the explorer's data, or of the
  `input$<id>_focus` it reports), or a named list or vector for one
  series. Keys left out, or `NA`, are aggregated over:
  `list(State = "NSW")` is the total of New South Wales, and
  [`list()`](https://rdrr.io/r/base/list.html) the total of everything.

- pinned:

  `TRUE` to pin, `FALSE` to unpin.

- view:

  The view to show: `"grid"`, `"overlay"`, `"stacked"` or `"season"`,
  among those the explorer offers.

- set:

  The series the view draws: the focus's `"children"` or the `"pinned"`
  series.

- theme:

  `"system"`, `"light"` or `"dark"`.

- measure:

  One of the data's numeric measured variables.

- explorer:

  An explorer from
  [`grafts()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts.md)
  with the new data.

- lazy:

  Serve each series through the session when it is drawn, rather than
  writing them all into the page. `NULL` (the default) serves data with
  more than 250,000 values.

## Details

- `grafts_focus()` focuses a series, drawing the splits that reach it.

- `grafts_pin()` and `grafts_unpin()` pin and unpin series. Unpinning
  with no `keys` clears every pin.

- `grafts_view()` chooses the view and the set of series it draws.

- `grafts_theme()` and `grafts_measure()` choose the theme and measure.

- `grafts_reset()` returns the graph to the total.

- `grafts_update()` replaces the explorer's data. When the new data have
  the same series, the graph, focus, pins, views and layout stay as they
  were, so the visitor sees the numbers change. Otherwise the explorer
  starts again.

Each returns the proxy, invisibly, so that calls can be piped.

## See also

[`renderGrafts()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts-shiny.md)

## Examples

``` r
if (FALSE) { # interactive()
library(shiny)
tourism_agg <- fabletools::aggregate_key(
  tsibble::tourism, Purpose * (State / Region), Trips = sum(Trips)
)
ui <- fluidPage(
  actionButton("nsw", "New South Wales"),
  actionButton("recent", "Last 10 years"),
  graftsOutput("ts")
)
server <- function(input, output, session) {
  output$ts <- renderGrafts(grafts(tourism_agg))
  observeEvent(input$nsw, {
    graftsProxy("ts") |> grafts_focus(list(State = "New South Wales"))
  })
  observeEvent(input$recent, {
    recent <- tsibble::filter_index(tourism_agg, "2007 Q1" ~ .)
    graftsProxy("ts") |> grafts_update(grafts(recent))
  })
}
shinyApp(ui, server)
}
```
