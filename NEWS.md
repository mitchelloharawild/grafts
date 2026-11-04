# grafts (development version)

* `grafts_options()` (the `options` argument of `grafts_explore()`, `api_grafts()`, `grafts_save()` and `grafts()`) chooses the views offered (the first being shown at the start), the theme, the seasonal period (or none), and whether visitors' choices persist. Whether series add up to their parents is detected, so the Stacked view and share scales are dropped for means and the like.
* `api_grafts()` adds the explorer to a plumber2 api, optionally under a `path`, so it can be deployed (Docker, Posit Connect) or mounted next to other routes. `/api/series` rejects requests for more than `max_ids` series and responses are cacheable.
* `grafts_explore()` now announces its url before blocking, and shows a loopback url when `host` is `"0.0.0.0"`.
* `grafts_explore()` explores an aggregated tsibble, and optionally its forecasts, through its series and dimension graphs in a browser app.
* `grafts_save()` writes the explorer to a static web page, and `grafts()` embeds it in R Markdown, Quarto and Shiny, with every series in the page and no R process behind it. A page can hold several explorers, each saving its own layout and theme.
