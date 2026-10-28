# grafts hex: a bonsai whose branches are time series grafted onto the trunk,
# each ending in a fan chart of its forecast. Run from the package root.
out_file <- "hex/grafts.svg"

# ---- Canvas and palette ------------------------------------------------------

W <- 520; H <- 600
CX <- 260; CY <- 300; R <- 292

pal <- list(
  bg = "#2b2547", sky = "#5b4266", ink = "#f2e6d0", star = "#f1dfc0",
  ranges = c("#6d5677", "#584463", "#423350", "#30263e"),
  stock = "#6b4630", knot = "#86593b", scion = "#a97c55",
  glaze = "#a5583f", glaze2 = "#86452f", word = "#f6e9d4"
)
# Foliage: c(95% band, 80% band)
variety <- list(
  stock   = c("#86b25e", "#5b8c43"),
  maple   = c("#e8836a", "#c4513f"),
  ginkgo  = c("#efc75c", "#cd9a2e"),
  blossom = c("#f2a7b9", "#d47490")
)

# ---- SVG helpers -------------------------------------------------------------

fmt <- function(v) {
  s <- sprintf("%.1f", v)
  sub("\\.0$", "", s)
}
pts <- function(x, y) paste0(fmt(x), ",", fmt(y), collapse = " ")
svg_path <- function(x, y, close = FALSE) {
  paste0("M", paste0(fmt(x), ",", fmt(y), collapse = " L"), if (close) " Z" else "")
}
hexagon <- function(r = R) {
  a <- seq(0, 300, by = 60) * pi / 180
  list(x = CX + r * sin(a), y = CY - r * cos(a))
}
offset <- function(x, y, d) {
  n <- length(x); d <- rep_len(d, n)
  i0 <- pmax(seq_len(n) - 1, 1); i1 <- pmin(seq_len(n) + 1, n)
  dx <- x[i1] - x[i0]; dy <- y[i1] - y[i0]
  len <- sqrt(dx^2 + dy^2); len[len == 0] <- 1
  list(x = x - dy / len * d, y = y + dx / len * d)
}
el <- function(tag, ...) {
  a <- list(...)
  attrs <- paste0(gsub("_", "-", names(a)), '="', vapply(a, function(v) if (is.numeric(v)) fmt(v) else v, ""), '"', collapse = " ")
  sprintf("<%s %s/>", tag, attrs)
}
line <- function(x, y, col, w, ...) el("path", d = svg_path(x, y), fill = "none", stroke = col, stroke_width = w,
                                       stroke_linecap = "round", stroke_linejoin = "round", ...)
mix <- function(a, b, t) {
  ra <- grDevices::col2rgb(a)[, 1]; rb <- grDevices::col2rgb(b)[, 1]
  v <- round(ra + (rb - ra) * t)
  sprintf("#%02x%02x%02x", v[1], v[2], v[3])
}
smooth <- function(y, k = 5) {
  f <- stats::filter(c(rep(y[1], k), y, rep(y[length(y)], k)), rep(1 / (2 * k + 1), 2 * k + 1))
  as.numeric(f[(k + 1):(k + length(y))])
}
# A tapered stroke following a polyline
taper <- function(x, y, w0, w1, fill) {
  n <- length(x); w <- w0 + (w1 - w0) * (0:(n - 1)) / (n - 1)
  a <- offset(x, y, w / 2); b <- offset(x, y, -w / 2)
  el("path", d = svg_path(c(a$x, rev(b$x)), c(a$y, rev(b$y)), TRUE), fill = fill,
     stroke = fill, stroke_width = 1, stroke_linejoin = "round")
}
move <- function(content, dx = 0, dy = 0) {
  sprintf('<g transform="translate(%s %s) scale(1)">%s</g>', fmt(dx), fmt(dy), paste(content, collapse = ""))
}

# ---- Sky: ridgelines, moon and the hierarchy as a constellation ---------------

MOON <- c(446, 128, 46)   # tucked under the upper-right border

# A seasonal series with trend and AR(1) noise, scaled to [-1, 1]: the ridgelines
series <- function(n, seed, period = 12, trend = .4, season = .7, noise = .3) {
  set.seed(seed)
  e <- stats::filter(rnorm(n), .5, method = "recursive")
  y <- trend * seq(-1, 1, length.out = n) + season * sin(2 * pi * (1:n) / period + runif(1, 0, 2 * pi)) + noise * e / sd(e)
  as.numeric(2 * (y - min(y)) / (max(y) - min(y)) - 1)
}

# Total, two groups and four bottom-level series, scattered like real stars
stars <- list(nodes = list(c(344, 84), c(324, 116), c(382, 168), c(304, 180), c(330, 180), c(350, 226), c(414, 230)),
              edges = list(c(1, 2), c(1, 3), c(2, 4), c(2, 5), c(3, 6), c(3, 7)))

sky <- function(uid) {
  set.seed(42)
  sx <- runif(60, 0, W); sy <- runif(60, 20, 300)
  nx <- vapply(stars$nodes, `[`, 0, 1); ny <- vapply(stars$nodes, `[`, 0, 2)
  out <- c(sprintf('<defs><linearGradient id="sky-%s" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient></defs>',
                   uid, pal$bg, pal$sky),
           el("rect", x = 0, y = 0, width = W, height = H, fill = sprintf("url(#sky-%s)", uid)),
           sprintf('<circle cx="%s" cy="%s" r="%s" fill="%s" opacity="%s"/>', fmt(sx), fmt(sy), fmt(runif(60, .6, 1.5)), pal$star, fmt(runif(60, .2, .55))),
           unlist(lapply(stars$edges, function(e) line(nx[e], ny[e], pal$star, 1.3, opacity = ".32"))),
           el("circle", cx = MOON[1], cy = MOON[2], r = MOON[3], fill = pal$star, opacity = ".94"),
           el("circle", cx = MOON[1] - 14, cy = MOON[2] + 12, r = 8, fill = "#e2cca7", opacity = ".6"),
           el("circle", cx = MOON[1] + 10, cy = MOON[2] - 16, r = 5, fill = "#e2cca7", opacity = ".5"),
           # Opaque, so the lines don't show through: the colour of the star at 85% over the sky behind it
           unlist(lapply(seq_along(nx), function(k)
             el("circle", cx = nx[k], cy = ny[k], r = if (k == 1) 3.8 else 2.7, fill = mix(mix(pal$bg, pal$sky, ny[k] / H), pal$star, .85)))))
  x <- seq(0, W, length.out = 60)
  for (k in seq_along(pal$ranges)) {
    y <- 262 + 50 * k - (30 - 4 * k) * series(60, 100 + k, period = 22 - 3 * k, noise = .3)
    out <- c(out, el("path", d = paste0(svg_path(c(0, x, W), c(H, y, H)), " Z"), fill = pal$ranges[k]))
  }
  out
}

# ---- Grafted branches ----------------------------------------------------------

# Where each scion is grafted: inside the trunk silhouette (hex/trunk.svg), with the
# trunk's edge at that height, and the history length out from the edge
grafts <- list(list(x = 315, y = 404, side = 1, L = 112, edge = 343), list(x = 309, y = 362, side = -1, L = 176, edge = 265),
               list(x = 184, y = 306, side = 1, L = 140, edge = 219), list(x = 188, y = 272, side = -1, L = 132, edge = 169),
               list(x = 224, y = 230, side = 1, L = 94, edge = 239),  list(x = 193, y = 196, side = -1, L = 106, edge = 181))

# Each series has its own season and its own forecast uncertainty: a scale, a horizon and
# a growth shape (rw: random walk, trend: drift, ar: stationary, levelling off into a club)
FAN <- 88; HALF <- 28; AMP <- 5; STUB <- 10
grow <- list(rw = function(h) sqrt(h), trend = function(h) h, ar = function(h) (1 - exp(-5 * h)) / (1 - exp(-5)))
seasons <- list(double = c(0, 1, -.2, .4, -1), saw = c(-1, -.5, 0, .5, 1), spike = c(-.4, -.3, 1, -.6, -.4), lop = c(-.8, .2, .9, .4, -.3))
spread <- list(list(s = 1.12, F = 84, shape = "ar",    season = "double", P = 38, amp = .75),
               list(s = 1.15, F = 96, shape = "trend", season = "saw",    P = 46, amp = .7),
               list(s = 1.02, F = 78, shape = "rw",    season = "spike",  P = 32, amp = .8),
               list(s = .92,  F = 80, shape = "ar",    season = "lop",    P = 42, amp = .65),
               list(s = .82,  F = 62, shape = "trend", season = "double", P = 30, amp = .55),
               list(s = .74,  F = 64, shape = "rw",    season = "saw",    P = 36, amp = .6))

# The series behind a branch: a zigzag season plus AR(1) noise, then a forecast mean
# carrying the season on, with the interval half-width w growing over the horizon.
# It stays flat until it is past the union, so the stub always sits inside the trunk.
branch_geom <- function(p0, side, L, seed, sp, s0, lift = 6) {
  n <- 60; s <- seq(0, L, length.out = n); F <- min(sp$F, .75 * L); h <- pmax(0, (s - (L - F)) / F)
  set.seed(seed)
  ph <- runif(1, 0, 2 * pi); e <- smooth(as.numeric(stats::filter(rnorm(n, 0, .7), .75, method = "recursive")), 2)
  fc <- h > 0; o <- max(which(!fc))
  e[fc] <- e[o] * .82^(seq_len(sum(fc)))                          # the noise decays into the forecast
  pat <- seasons[[sp$season]]; P <- sp$P
  seas <- approx(seq(0, P, length.out = length(pat) + 1), c(pat, pat[1]), (s + ph * 6) %% P)$y
  y <- sp$amp * seas + .6 * e
  list(x = p0[1] + side * s, y = p0[2] + AMP * y * pmin(1, pmax(0, s - s0) / 18) - lift * (s / L)^2,
       w = sp$s * HALF * sqrt(F / FAN) * grow[[sp$shape]](h) + 1.5 * fc, o = o, n = n, side = side, fc = fc)
}

# The forecast as a fan chart: nested 99/95/80/50% bands, lightening outwards
fan <- function(g, cols) {
  k <- which(g$fc | seq_len(g$n) == g$o); n <- g$n
  band <- function(f, fill) {
    w <- f * g$w; xe <- g$x[n] + g$side * w[n] * .7                 # round the leading edge
    el("path", d = paste0(svg_path(c(g$x[k], rev(g$x[k])), c(g$y[k] - w[k], rev(g$y[k] + w[k]))),
                          sprintf(" M%s,%s Q%s,%s %s,%s Z", fmt(g$x[n]), fmt(g$y[n] - w[n]), fmt(xe), fmt(g$y[n]), fmt(g$x[n]), fmt(g$y[n] + w[n]))),
       fill = fill)
  }
  c(band(1.2, mix(cols[1], "#ffffff", .3)), band(1, cols[1]), band(.65, mix(cols[1], cols[2], .55)), band(.34, cols[2]))
}

# Scion wood: the history tapers out to the forecast origin, the mean thins on through the leaves
scion <- function(g, lw) {
  o <- g$o; n <- g$n
  c(taper(g$x[1:o], g$y[1:o], lw * 1.9, lw * 1.05, pal$scion), taper(g$x[o:n], g$y[o:n], lw * 1.05, lw * .45, pal$scion))
}

# The union: a short stub of the trunk's wood swelling into a knuckle, the scion growing on from it
union <- function(g, x0, lw) {
  y0 <- approx(g$x, g$y, x0)$y; k <- which(g$side * (g$x - x0) <= 0)
  c(taper(g$x[k], g$y[k], lw * 2.4, lw * 1.9, pal$stock),
    el("ellipse", cx = x0, cy = y0, rx = lw * 1.05, ry = lw * 1.35, fill = pal$stock),
    el("ellipse", cx = x0 - g$side * lw * .25, cy = y0 - lw * .35, rx = lw * .4, ry = lw * .6, fill = pal$knot))
}

# ---- Crown, pot and soil -------------------------------------------------------------

# The rootstock's own foliage at the apex: scalloped domes, layered like the fans
crown <- function(cx, cy, s, cols) {
  t <- seq(0, pi, length.out = 60)
  dome <- function(x0, y0, w, h, fill) {
    r <- 1 + .08 * abs(sin(t * 5))
    xx <- x0 + cos(t) * w * r; yy <- y0 - sin(t) * h * r
    el("path", d = paste0(svg_path(xx, yy), sprintf(" Q%s,%s %s,%s Z", fmt(x0), fmt(y0 + h * .35), fmt(xx[1]), fmt(yy[1]))), fill = fill)
  }
  domes <- function(f, fill) c(dome(cx - 30 * s, cy + 6 * s, 36 * s * f, 25 * s * f, fill), dome(cx + 30 * s, cy + 4 * s, 34 * s * f, 23 * s * f, fill),
                               dome(cx, cy - 8 * s, 46 * s * f, 36 * s * f, fill))
  c(domes(1.12, mix(cols[1], "#ffffff", .3)), domes(1, cols[1]), domes(.66, mix(cols[1], cols[2], .55)), domes(.36, cols[2]))
}

pot <- function(top = 452, wt = 262, wb = 232, h = 56) {
  cx <- 250
  c(
    # Feet
    el("rect", x = cx - wb / 2 + 10, y = top + h - 4, width = 26, height = 14, rx = 3, fill = pal$glaze2),
    el("rect", x = cx + wb / 2 - 36, y = top + h - 4, width = 26, height = 14, rx = 3, fill = pal$glaze2),
    # Body, with a shaded right flank
    el("path", d = svg_path(c(cx - wt / 2, cx + wt / 2, cx + wb / 2, cx - wb / 2), c(top + 8, top + 8, top + h, top + h), TRUE), fill = pal$glaze),
    el("path", d = svg_path(c(cx + wt / 2 - 26, cx + wt / 2, cx + wb / 2, cx + wb / 2 - 24), c(top + 8, top + 8, top + h, top + h), TRUE), fill = pal$glaze2),
    # Rim
    el("rect", x = cx - wt / 2 - 8, y = top - 4, width = wt + 16, height = 13, rx = 4, fill = pal$glaze),
    line(c(cx - wt / 2 - 2, cx + wt / 2 + 2), c(top - 1, top - 1), mix(pal$glaze, "#ffffff", .25), 2),
    # Wordmark, centred on the pot; 3.02 em: advance width of "grafts" in Lexend SemiBold
    sprintf(paste0('<text x="%s" y="%s" text-anchor="middle" font-family="Lexend, \'Helvetica Neue\', Arial, sans-serif" ',
                   'font-weight="600" font-size="%s" textLength="%s" lengthAdjust="spacingAndGlyphs" fill="%s">grafts</text>'),
            fmt(cx - 8), fmt(top + h - 17), 40, fmt(3.02 * 40), pal$word)
  )
}

soil <- function(top = 452) {
  c(el("path", d = sprintf("M%s,%s Q250,%s %s,%s Z", 128, top, top - 16, 372, top), fill = "#4a3526"),
    el("path", d = sprintf("M%s,%s Q%s,%s %s,%s Z", 150, top - 1, 186, top - 14, 222, top - 4), fill = "#6f9a4c"),
    el("path", d = sprintf("M%s,%s Q%s,%s %s,%s Z", 286, top - 4, 318, top - 13, 352, top - 1), fill = "#6f9a4c"))
}

# ---- The tree -------------------------------------------------------------------------

# The trunk is drawn by hand
trunk <- paste(readLines("hex/trunk.svg"), collapse = "\n")

bonsai <- function(varieties = c("maple", "ginkgo", "blossom"), lw = 3.68) {
  pads <- wood <- unions <- c()
  for (i in seq_along(grafts)) {
    b <- grafts[[i]]; sp <- spread[[i]]
    L <- b$L + abs(b$edge - b$x) + (sp$F - FAN) * .4
    g <- branch_geom(c(b$x, b$y), b$side, L, c(3, 8, 13, 21, 34, 5)[i], sp, s0 = abs(b$edge - b$x) + STUB + 2)
    pads <- c(pads, fan(g, variety[[varieties[(i - 1) %% 3 + 1]]]))
    wood <- c(wood, scion(g, lw))
    unions <- c(unions, union(g, b$edge + b$side * STUB, lw))
  }
  c(pads, wood, unions, pot(), soil(), trunk, crown(204, 146, 1.45, variety$stock))
}

# ---- Sticker ---------------------------------------------------------------------------

hx <- hexagon()
svg <- paste0(
  sprintf('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %s %s" role="img" aria-label="grafts hex sticker">', W, H),
  sprintf('<defs><clipPath id="clip-grafts"><polygon points="%s"/></clipPath></defs>', pts(hx$x, hx$y)),
  sprintf('<polygon points="%s" fill="%s"/>', pts(hx$x, hx$y), pal$bg),
  sprintf('<g clip-path="url(#clip-grafts)">%s</g>', paste(c(sky("grafts"), move(bonsai(), 10, 0)), collapse = "")),
  sprintf('<polygon points="%s" fill="none" stroke="%s" stroke-width="12" stroke-linejoin="round"/></svg>', pts(hx$x, hx$y), pal$ink)
)
writeLines(svg, out_file)
