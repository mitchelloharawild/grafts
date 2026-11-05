# Options for the explorer

Chooses which views the explorer offers, how it starts, how its data are
sent and how big it is when embedded, for the `options` argument of
[`grafts()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts.md).

## Usage

``` r
grafts_options(
  views = c("grid", "overlay", "stacked", "season"),
  additive = NULL,
  season = NULL,
  theme = c("system", "light", "dark"),
  persist = TRUE,
  max_points = 1000,
  width = NULL,
  height = NULL,
  element_id = NULL,
  title = "Graph explorer"
)
```

## Arguments

- views:

  The view tabs offered, in order: any of `"grid"`, `"overlay"`,
  `"stacked"` and `"season"`. The first is shown at the start.

- additive:

  Whether each series is the sum of its children. `NULL` detects it.
  When not additive, the Stacked view and the share scales are removed.

- season:

  The seasonal period of the Season view: `NULL` for the automatic one
  (the year, where the data has one), `FALSE` for no Season view, or the
  name of one of `fabletools::common_periods(data)`, such as `"week"`
  for daily data.

- theme:

  The theme at first, for visitors who haven't chosen one: `"system"`
  follows their device.

- persist:

  Whether the explorer saves the visitor's choices (tab, scales, layout
  and theme) in their browser. Use `FALSE` for a fixed starting view,
  such as in documentation. When `TRUE`, saved choices that the options
  don't allow fall back to the first of `views` and each tab's default
  scale.

- max_points:

  Series more than twice this long are sent to the app as the minimum
  and maximum of blocks of time, about `max_points` values, so spikes
  stay visible. The season and stacked plots always get the full series,
  and an explorer written into a page
  ([`grafts_save()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts_save.md),
  documents and Shiny) always has the full series.

- width, height:

  Size of the explorer when written into a page, in pixels or as a CSS
  length. In documents and Shiny the height defaults to 600px, and a
  page from
  [`grafts_save()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts_save.md)
  fills the window.

- element_id:

  An id for the explorer's element in a document.

- title:

  The title of the page, for the browser's tab: served by
  [`grafts_serve()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts_api.md)
  and
  [`grafts_api()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts_api.md),
  and written by
  [`grafts_save()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts_save.md).

## Value

A `grafts_options` list, for the `options` argument of
[`grafts()`](https://pkg.mitchelloharawild.com/grafts/reference/grafts.md).

## Details

The Stacked view and the grid's share-of-parent scale only make sense
when each series is the sum of the series it splits into. With
`additive = NULL` this is checked on `data` (for every split of every
series, at the times where all the parts are observed), so means or
other non-additive aggregates lose those options automatically.

## Examples

``` r
# A grid and season plots only, always starting dark and fresh
grafts_options(views = c("grid", "season"), theme = "dark", persist = FALSE)
#> <grafts_options> views: grid, season (starting at grid)

# Weekly seasons for daily data, instead of yearly ones
grafts_options(views = c("season", "grid", "overlay"), season = "week")
#> <grafts_options> views: season, grid, overlay (starting at season)

# No Season view, and a mean-aggregated tsibble known to be non-additive
grafts_options(season = FALSE, additive = FALSE)
#> <grafts_options> views: grid, overlay, stacked, season (starting at grid)
```
