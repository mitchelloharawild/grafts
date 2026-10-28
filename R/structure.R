# Logical rows of fixed keys as strings, for matching
pattern <- function(m) apply(m, 1, function(r) paste(as.integer(r), collapse = ""))

# The chains of nested keys that the combinations cross, e.g.
# Purpose * (State / Region) -> list("Purpose", c("State", "Region")), or NULL
# when they aren't a product of chains, as for (State / Region) + Purpose or
# State:Purpose. b is nested in a when every combination fixing b fixes a.
combo_chains <- function(combos, keys) {
  req <- map(set_names(keys), function(k) keys[apply(combos[combos[, k], , drop = FALSE], 2, all)])
  chains <- list()
  for (k in keys[order(lengths(req))]) {
    up <- setdiff(req[[k]], k)
    i <- detect_index(chains, function(v) setequal(v, up))
    if (!length(up)) chains <- c(chains, list(k))
    else if (i) chains[[i]] <- c(chains[[i]], k)
    else return(NULL)
  }
  lv <- expand.grid(map(chains, function(v) 0:length(v)))
  crossed <- map_chr(seq_len(nrow(lv)), function(i) {
    paste(as.integer(keys %in% unlist(map2(chains, unlist(lv[i, ]), head))), collapse = "")
  })
  if (setequal(crossed, pattern(combos))) chains
}

chains_text <- function(chains) {
  parts <- map_chr(chains, function(v) if (length(v) > 1) paste(v, collapse = " / ") else v)
  if (length(parts) > 1) parts <- ifelse(lengths(chains) > 1, paste0("(", parts, ")"), parts)
  paste(parts, collapse = " * ")
}
# Combinations that aren't chains, as aggregate_key() terms, e.g. State + State:Region + Purpose
combos_text <- function(combos, keys) {
  terms <- map_chr(seq_len(nrow(combos)), function(i) paste(keys[combos[i, ]], collapse = ":"))
  paste(terms[nzchar(terms)], collapse = " + ")
}

# One node per key combination, with Hasse edges to the combinations that fix
# the fewest more keys. Crossed chains are laid out as a lattice: the first
# steps down-left and the last down-right. Other structures are laid out by
# rows of depth.
dimension_graph <- function(combos, fixed, keys, chains) {
  m <- nrow(combos)
  n <- tabulate(match(pattern(fixed), pattern(combos)), m)
  # sub[i, j]: combination i fixes a subset of combination j's keys
  sub <- tcrossprod(combos, !combos) == 0
  diag(sub) <- FALSE
  cover <- which(sub & !(sub %*% sub > 0), arr.ind = TRUE)
  cover <- cover[order(cover[, 1], cover[, 2]), , drop = FALSE]
  # Combinations come in order of size, so each one's parents come first
  y <- integer(m)
  for (j in seq_len(m)) y[j] <- max(c(0L, y[cover[cover[, 2] == j, 1]] + 1L))
  if (!is.null(chains)) {
    lv <- do.call(cbind, map(chains, function(v) rowSums(combos[, v, drop = FALSE])))
    x <- if (length(chains) == 1) rep(0, m) else drop(lv %*% seq(-1, 1, length.out = length(chains)))
    name <- map_chr(seq_len(m), function(i) {
      parts <- compact(map2(chains, lv[i, ], function(v, l) if (l) paste(v[seq_len(l)], collapse = " / ")))
      if (length(parts)) paste(parts, collapse = " \u00d7 ") else "Total"
    })
  } else {
    x <- ave(seq_len(m), y, FUN = function(i) seq_along(i) - (length(i) + 1) / 2)
    name <- map_chr(seq_len(m), function(i) if (any(combos[i, ])) paste(keys[combos[i, ]], collapse = " \u00d7 ") else "Total")
  }
  nodes <- map(seq_len(m), function(i) list(keys = I(keys[combos[i, ]]), name = name[[i]], n = n[[i]], x = x[[i]], y = y[[i]]))
  edges <- map(seq_len(nrow(cover)), function(r) {
    i <- cover[r, 1]; j <- cover[r, 2]
    list(from = i - 1L, to = j - 1L, vars = I(keys[combos[j, ] & !combos[i, ]]))
  })
  list(nodes = nodes, edges = edges)
}
