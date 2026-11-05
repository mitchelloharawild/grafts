# Package index

## Exploration

Interactive exploration of aggregated time series and their forecasts

- [`grafts()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts.md)
  : Explore an aggregated tsibble through its series and dimension
  graphs
- [`grafts_options()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts_options.md)
  : Options for the explorer

## Serving

The explorer on a server, sending each series when it is drawn

- [`grafts_api()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts_api.md)
  [`grafts_serve()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts_api.md)
  : Serve the explorer with plumber2

## Embedding

The explorer on static web pages, with no R process behind it

- [`grafts_save()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts_save.md)
  : Save the explorer as a static web page

## Shiny

The explorer in a Shiny app, reporting what it shows and steered by the
server

- [`graftsOutput()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts-shiny.md)
  [`renderGrafts()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts-shiny.md)
  : Shiny bindings for grafts()
- [`graftsProxy()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts-proxy.md)
  [`grafts_focus()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts-proxy.md)
  [`grafts_pin()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts-proxy.md)
  [`grafts_unpin()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts-proxy.md)
  [`grafts_view()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts-proxy.md)
  [`grafts_theme()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts-proxy.md)
  [`grafts_measure()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts-proxy.md)
  [`grafts_reset()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts-proxy.md)
  [`grafts_update()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts-proxy.md)
  : Steer an explorer in Shiny
