# Changelog

## grafts (development version)

- [`grafts()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts.md)
  makes an explorer of an aggregated tsibble, and optionally its
  forecasts, drawn in the browser through its series and dimension
  graphs. Where it goes decides how the series reach the browser:
  printed in the console, it is served from the R session a series at a
  time, blocking like a Shiny app until stopped; knitted, in Shiny
  ([`renderGrafts()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts-shiny.md))
  or saved with
  [`grafts_save()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts_save.md),
  every series is written into the page, which needs no R process.
  [`grafts_save()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts_save.md),
  [`grafts_api()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts_api.md)
  and
  [`grafts_serve()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts_api.md)
  take an explorer from
  [`grafts()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts.md).
- [`grafts_options()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts_options.md)
  (the `options` argument of
  [`grafts()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts.md))
  chooses the views offered (the first being shown at the start), the
  theme, the seasonal period (or none), whether visitors’ choices
  persist, how long series are sent to the app (`max_points`) the size
  of an embedded explorer (`width`, `height`, `element_id`) and the page
  `title`. Whether series add up to their parents is detected, so the
  Stacked view and share scales are dropped for means and the like.
- [`grafts_api()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts_api.md)
  adds the explorer to a plumber2 api, optionally under a `path`, so it
  can be deployed (Docker, Posit Connect) or mounted next to other
  routes. The path without its trailing slash redirects to it.
  `/api/series` rejects requests for more than `max_ids` series and
  responses are privately cached and revalidated with an `ETag`.
  `/api/health` reports that it is up.
- [`grafts_serve()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts_api.md)
  runs an explorer on its own server, for scripts and containers, or in
  the background with `block = FALSE`. It announces its url and how to
  stop it, and shows a loopback url when `host` is `"0.0.0.0"`.
- A page can hold several explorers, each saving its own layout and
  theme.
- In Shiny, the explorer reports what it shows through the inputs
  `<id>_focus`, `_children`, `_pinned`, `_split`, `_view`, `_set`,
  `_theme` and `_measure`.
  [`graftsProxy()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts-proxy.md)
  steers it from the server
  ([`grafts_focus()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts-proxy.md),
  [`grafts_pin()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts-proxy.md),
  [`grafts_unpin()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts-proxy.md),
  [`grafts_view()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts-proxy.md),
  [`grafts_theme()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts-proxy.md),
  [`grafts_measure()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts-proxy.md),
  [`grafts_reset()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts-proxy.md)),
  and
  [`grafts_update()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts-proxy.md)
  replaces its data, keeping the graph, focus, pins and views when the
  series are the same.
- [`renderGrafts()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts-shiny.md)
  serves large data (over 250,000 values, or `lazy = TRUE`) a series at
  a time through the Shiny session, rather than writing every series
  into the page.
