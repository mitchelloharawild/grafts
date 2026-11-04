# grafts (development version)

* `api_graph_explore()` adds the explorer to a plumber2 api, optionally under a `path`, so it can be deployed (Docker, Posit Connect) or mounted next to other routes. `/api/series` rejects requests for more than `max_ids` series and responses are cacheable.
* `graph_explore()` now announces its url before blocking, and shows a loopback url when `host` is `"0.0.0.0"`.
* `graph_explore()` explores an aggregated tsibble, and optionally its forecasts, through its series and dimension graphs in a browser app.
* `graph_save()` writes the explorer to a static web page, and `graph_widget()` embeds it in R Markdown, Quarto and Shiny, with every series in the page and no R process behind it. A page can hold several explorers, each saving its own layout and theme.
