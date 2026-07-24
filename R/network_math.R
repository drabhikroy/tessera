# network_math.R
# Everything quantitative lives here, written as tidygraph pipelines. The
# graph travels as a tbl_graph whose node table carries every measure the
# app reports, so downstream code reads columns instead of calling igraph.
# All measures are classical and auditable. No language model is involved
# anywhere in this file.
#
# Copyright Abhik Roy. Released under the PolyForm Noncommercial
# License 1.0.0. See LICENSE.md.

suppressPackageStartupMessages({
  library(tidygraph)
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(tibble)
})

# Build an undirected weighted tbl_graph from an edge table and an
# optional node table. Ties are undirected because the interpretation
# layer speaks about working relationships, and a directed reading would
# need different prose.
build_graph <- function(edges, nodes = NULL) {
  stopifnot(is.data.frame(edges), ncol(edges) >= 2)
  ed <- tibble(
    from = trimws(as.character(edges[[1]])),
    to   = trimws(as.character(edges[[2]]))
  )
  # A third column, when present, is read as tie weight. Anything that
  # fails numeric conversion falls back to 1 so a stray text cell cannot
  # sink the whole upload.
  ed <- ed |>
    mutate(
      weight = if (ncol(edges) >= 3) {
        suppressWarnings(as.numeric(edges[[3]]))
      } else {
        1
      },
      weight = if_else(is.na(weight) | weight <= 0, 1, weight)
    ) |>
    filter(from != "", to != "", from != to)
  if (nrow(ed) == 0) stop("No usable ties were found in the file.")

  g <- as_tbl_graph(ed, directed = FALSE) |>
    # Parallel ties collapse into one tie whose weight is the sum.
    # Repeated contact reads naturally as a stronger relationship.
    convert(to_simple) |>
    activate(edges) |>
    mutate(weight = map_dbl(.orig_data, ~ sum(.x$weight))) |>
    select(from, to, weight) |>
    activate(nodes)

  if (!is.null(nodes) && is.data.frame(nodes) && ncol(nodes) >= 2) {
    given <- tibble(
      name        = trimws(as.character(nodes[[1]])),
      given_group = trimws(as.character(nodes[[2]]))
    )
    g <- g |> left_join(given, by = "name")
  }
  g
}

# One pipeline adds every per person measure as node columns, then the
# whole network numbers are read off the finished graph. Returning one
# list keeps the server logic to a lookup rather than a recomputation.
compute_metrics <- function(g) {
  n <- igraph::gorder(g)
  if (n < 2) stop("The network needs at least two people.")

  scored <- g |>
    activate(nodes) |>
    mutate(
      degree  = centrality_degree(),
      tie_sum = centrality_degree(weights = weight),
      between = centrality_betweenness(weights = NULL, normalized = TRUE),
      # Harmonic closeness is defined even when the network is in pieces,
      # which uploaded real data often is. Plain closeness returns NaN
      # there. The igraph call runs inside the pipeline through .G() so
      # no extra package is needed.
      close   = igraph::harmonic_centrality(.G(), weights = NA,
                                            normalized = TRUE),
      eigen   = centrality_eigen(weights = weight),
      group   = group_louvain(weights = weight),
      piece   = group_components(),
      # Cut nodes are the single points of failure: remove one and the
      # network falls apart. This is the fragility story in one column.
      is_cut  = node_is_cut()
    )

  nd <- scored |> as_tibble()
  piece_sizes <- nd |> count(piece, sort = TRUE)
  giant <- scored |>
    filter(piece == piece_sizes$piece[1])

  list(
    graph        = scored,
    node_table   = nd,
    n            = n,
    m            = igraph::gsize(g),
    density      = igraph::edge_density(g),
    n_components = nrow(piece_sizes),
    giant_share  = piece_sizes$n[1] / n,
    diameter     = with_graph(giant, graph_diameter(weights = NULL)),
    mean_dist    = with_graph(giant, graph_mean_dist(weights = NULL)),
    modularity   = with_graph(scored, graph_modularity(group = group, weights = weight)),
    n_groups     = n_distinct(nd$group),
    cut_ids      = nd |> filter(is_cut) |> pull(name),
    names        = nd$name,
    degree       = nd$degree,
    betweenness  = nd$between,
    closeness    = nd$close,
    eigenvector  = nd$eigen,
    membership   = nd$group
  )
}

# Deterministic layout through ggraph. The seed matters: the same data
# should land in the same picture every time, or people lose their sense
# of place in the map. Coordinates come back scaled to the unit square.
compute_layout <- function(g, seed = 42) {
  set.seed(seed)
  ggraph::create_layout(g, layout = "fr", weights = weight) |>
    as_tibble() |>
    select(x, y) |>
    mutate(
      x = (x - min(x)) / max(max(x) - min(x), 1e-9),
      y = (y - min(y)) / max(max(y) - min(y), 1e-9)
    )
}

# Groups are renumbered by size so group 1 is always the largest. The
# glyph system pairs twelve shapes with three fill variants across
# twelve colors, so thirty six groups stay visually distinct before any
# repetition. Anything past that shares the final bucket, which is rare
# enough in real data to be an honest simplification.
relabel_groups <- function(membership, cap = 36) {
  # Order groups by size, largest first, breaking ties by the original
  # group number. Ranking on size alone gave equally sized communities
  # the same label, which quietly merged distinct groups on the map and
  # in the key, so the tie break is what keeps them separate.
  sizes <- tibble(old = membership) |>
    count(old, name = "members") |>
    arrange(desc(members), old) |>
    mutate(new = pmin(row_number(), cap + 1L))

  tibble(old = membership) |>
    left_join(sizes, by = "old") |>
    pull(new) |>
    as.integer()
}

# The complete package the browser needs to draw and describe the map.
graph_payload <- function(metrics, layout) {
  nd <- metrics$node_table |>
    bind_cols(layout) |>
    mutate(
      id      = row_number(),
      label   = name,
      between = round(between, 4),
      close   = round(close, 4),
      eigen   = round(eigen, 4),
      group   = relabel_groups(group)
    ) |>
    select(id, label, x, y, degree, between, close, eigen, group, is_cut)

  ed <- metrics$graph |>
    activate(edges) |>
    as_tibble() |>
    select(from, to, weight)

  list(nodes = as.data.frame(nd), edges = as.data.frame(ed),
       meta = list(n = metrics$n, m = metrics$m,
                   n_groups = n_distinct(nd$group)))
}

# Shiny serializes data frames column wise on the websocket, which is not
# what the renderer reads. payload_wire() converts each table to a list of
# row records right before sending, so the browser receives an array of
# objects. R side consumers keep working with the data frames above.
payload_wire <- function(payload) {
  df_rows <- function(df) {
    lapply(seq_len(nrow(df)), function(i) as.list(df[i, , drop = FALSE]))
  }
  list(nodes = df_rows(payload$nodes), edges = df_rows(payload$edges),
       meta = payload$meta)
}
