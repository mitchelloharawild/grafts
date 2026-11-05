# Shiny bindings for grafts()

Shows an explorer from
[`grafts()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts.md)
in Shiny. The explorer tells the app what it shows, through inputs named
after its output, and
[`graftsProxy()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts-proxy.md)
lets the app steer it and replace its data.

## Usage

``` r
graftsOutput(outputId, width = "100%", height = "600px")

renderGrafts(expr, env = parent.frame(), quoted = FALSE, lazy = NULL)
```

## Arguments

- outputId:

  Output variable to read from.

- width, height:

  A CSS length for the explorer.

- expr:

  An expression that returns an explorer from
  [`grafts()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts.md).

- env:

  The environment in which to evaluate `expr`.

- quoted:

  Is `expr` a quoted expression (with
  [`quote()`](https://rdrr.io/r/base/substitute.html))?

- lazy:

  Serve each series through the session when it is drawn, rather than
  writing them all into the page. `NULL` (the default) serves data with
  more than 250,000 values.

## Details

Small data are written into the page. Large data stay in R, which serves
each series through the Shiny session when it is drawn, as the console
and
[`grafts_api()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts_api.md)
do. By default data with more than 250,000 values are served; set `lazy`
to choose.

For an output `"ts"`, the app can read these inputs:

- `input$ts_focus`, the focused series, as a one-row data frame with a
  column for each key of the data, and `NA` for the keys it is
  aggregated over.

- `input$ts_children`, the series of the focus's last split, one row
  each.

- `input$ts_pinned`, the pinned series, one row each.

- `input$ts_split`, the keys the children were split by, as a character
  vector.

- `input$ts_view`, the view shown (`"grid"`, `"overlay"`, `"stacked"` or
  `"season"`) and `input$ts_set`, the set it draws (`"children"` or
  `"pinned"`).

- `input$ts_theme` (`"system"`, `"light"` or `"dark"`) and
  `input$ts_measure`.

They are `NULL` until the explorer is drawn, and change as the visitor
explores. Modules namespace them as for any output.

## See also

[`graftsProxy()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts-proxy.md)
to steer the explorer and update its data.

## Examples

``` r
if (FALSE) { # interactive()
library(shiny)
tourism_agg <- fabletools::aggregate_key(
  tsibble::tourism, Purpose * (State / Region), Trips = sum(Trips)
)
ui <- fluidPage(graftsOutput("ts"), verbatimTextOutput("focus"))
server <- function(input, output, session) {
  output$ts <- renderGrafts(grafts(tourism_agg))
  output$focus <- renderPrint(input$ts_focus)
}
shinyApp(ui, server)
}
```
