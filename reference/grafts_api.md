# Serve the explorer with plumber2

`grafts_api()` adds an explorer to a plumber2 api, for deploying it
(with Docker or Posit Connect, say) or mounting it beside other routes.
It adds the routes `{path}api/spec`, `{path}api/series` and
`{path}api/health` (for load balancers and containers), and the app's
page at `{path}`, which `{path}` without its trailing slash redirects
to. Responses are cached privately and revalidated with an `ETag`, so a
redeployed dataset is seen at once. `grafts_serve()` runs an explorer on
its own server, for scripts and containers. Printing an explorer from
[`grafts()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts.md)
in the console runs `grafts_serve()`, blocking the console like a Shiny
app until it is stopped.

## Usage

``` r
grafts_api(api, explorer, path = "/", max_ids = 1000)

grafts_serve(
  explorer,
  port = serve_port(),
  host = serve_host(),
  launch = FALSE,
  block = TRUE
)
```

## Arguments

- api:

  A plumber2 api, such as from
  [`plumber2::api()`](https://plumber2.posit.co/reference/api.html).

- explorer:

  An explorer from
  [`grafts()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts.md),
  which takes the data, forecasts and options.

- path:

  Where the explorer is mounted on `api`. Mount several explorers at
  different paths, such as `"/tourism/"` and `"/retail/"`.

- max_ids:

  The most series that one request to `api/series` may ask for. The app
  asks for up to 200 at a time.

- port, host:

  Where the app is served, by default port 8000 on this machine only.
  Set `GRAFTS_PORT` (or `PORT`) and `GRAFTS_HOST`, or the options
  `grafts.port` and `grafts.host`, to change the defaults without
  editing code. Use `host = "0.0.0.0"` to accept connections from other
  machines, such as from a container. The app has no sign-in, so put
  anything private behind an authenticating proxy.

- launch:

  Open the app, in the IDE's viewer where there is one, else in a
  browser.

- block:

  Block the R session while serving, like a Shiny app. When `FALSE`,
  stop the app with
  [`plumber2::api_stop()`](https://plumber2.posit.co/reference/api_run.html)
  on the returned api.

## Value

`grafts_api()` returns `api` with the explorer added. `grafts_serve()`
returns its plumber2 api, invisibly.

## Details

The data stays in R, and the app is sent each series when it is drawn,
so data of any size can be explored.

## Examples

``` r
if (FALSE) {
# A plumber2 file (plumber.R), for Posit Connect or plumber2::api("plumber.R")
#* @plumber
function(api) {
  data <- readRDS("tourism_agg.rds")
  grafts_api(api, grafts(data))
}

# Several datasets on one api, at /tourism/ and /retail/
plumber2::api() |>
  grafts_api(grafts(tourism_agg), path = "/tourism/") |>
  grafts_api(grafts(retail_agg, forecasts = retail_fc), path = "/retail/") |>
  plumber2::api_run()

# In Docker, from the command line
# Rscript -e 'readRDS("tourism_agg.rds") |> grafts::grafts() |>
#   grafts::grafts_serve(host = "0.0.0.0")'
}
```
