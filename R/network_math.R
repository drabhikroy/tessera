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

  # A directed copy is kept whenever the source says the ties have a
  # direction. Every measure and the grouping run on the undirected
  # graph, because that is what the prose in this app is about, and the
  # directed copy exists for the dyad and triad census alone, which is
  # the one place direction changes the answer rather than the wording.
  directed_source <- isTRUE(attr(edges, "directed"))

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

  # The directed copy rides along on the graph rather than being
  # returned beside it, so every existing caller keeps working and only
  # the census has to know it exists.
  if (directed_source) {
    attr(g, "digraph") <- igraph::simplify(
      igraph::graph_from_data_frame(as.data.frame(ed[, c("from", "to")]),
                                    directed = TRUE),
      remove.multiple = TRUE, remove.loops = TRUE)
  }
  g
}

# One pipeline adds every per person measure as node columns, then the
# whole network numbers are read off the finished graph. Returning one
# list keeps the server logic to a lookup rather than a recomputation.
compute_metrics <- function(g) {
  # Held before the pipeline below, since the verbs that follow rebuild
  # the graph object and drop anything hanging off it.
  digraph <- attr(g, "digraph")
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
    # Present only when the source declared a direction. The census
    # reads it; nothing else does.
    digraph      = digraph,
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
# The layout, in three passes rather than one.
#
# A plain force directed layout puts every node where the forces settle
# and stops, which produces the picture people recognize from a default
# graph plot: one dense knot in the middle, a few nodes flung wide, and
# clusters that overlap because nothing in the model knows they are
# clusters. Two corrections follow the force pass.
#
# The first pulls each community toward its own center of mass, so
# groups the analysis already found end up as groups the eye can see.
# This changes nothing about the numbers; the grouping is computed from
# the ties and the layout is only being asked to agree with it.
#
# The second separates nodes that landed on top of one another. A force
# layout has no notion of how large a node is going to be, so nodes that
# are far apart in the model can still overlap on screen once they are
# given a radius.
compute_layout <- function(g, seed = 42) {
  set.seed(seed)
  base <- ggraph::create_layout(g, layout = "fr", weights = weight) |>
    as_tibble()

  x <- base$x
  y <- base$y
  groups <- if ("group" %in% names(base)) as.integer(base$group) else NULL
  if (is.null(groups)) groups <- rep(1L, length(x))

  # Pass two: gather each group around its own center. A fifth of the
  # way is enough to read as a group without collapsing it into a blob
  # or hiding the ties that cross between groups.
  pull <- 0.20
  for (grp in unique(groups)) {
    idx <- which(groups == grp)
    if (length(idx) < 2) next
    cx <- mean(x[idx])
    cy <- mean(y[idx])
    x[idx] <- x[idx] + (cx - x[idx]) * pull
    y[idx] <- y[idx] + (cy - y[idx]) * pull
  }

  # Pass three: push apart anything closer than a node width. Ten
  # rounds is enough to clear the overlaps a force layout leaves and few
  # enough that the picture is still the one the forces produced.
  span <- max(max(x) - min(x), max(y) - min(y), 1e-9)
  floor_gap <- span * 0.035
  n <- length(x)
  if (n > 1) {
    for (round in seq_len(10)) {
      moved <- FALSE
      for (i in seq_len(n - 1)) {
        for (j in (i + 1):n) {
          dx <- x[j] - x[i]
          dy <- y[j] - y[i]
          d <- sqrt(dx * dx + dy * dy)
          if (d >= floor_gap) next
          # Two nodes in exactly the same place have no direction to
          # separate along, so one is nudged off the spot first.
          if (d < 1e-9) {
            dx <- stats::runif(1, -1, 1) * floor_gap
            dy <- stats::runif(1, -1, 1) * floor_gap
            d <- sqrt(dx * dx + dy * dy)
          }
          shift <- (floor_gap - d) / 2
          ux <- dx / d
          uy <- dy / d
          x[i] <- x[i] - ux * shift
          y[i] <- y[i] - uy * shift
          x[j] <- x[j] + ux * shift
          y[j] <- y[j] + uy * shift
          moved <- TRUE
        }
      }
      if (!moved) break
    }
  }

  tibble(x = x, y = y) |>
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
# The shortest route between two people, if there is one. Returns the
# people along it in order and the ties between them.
#
# This is the question people ask of a network diagram more than any
# other, and it is the one a picture answers worst: with fifty people on
# screen, tracing a path by eye is guesswork. The answer is exact and
# the map can show it.
shortest_route <- function(metrics, from_name, to_name) {
  gi <- as.igraph(metrics$graph)
  names_all <- metrics$names
  a <- match(from_name, names_all)
  b <- match(to_name, names_all)
  if (is.na(a) || is.na(b)) {
    return(list(ok = FALSE, message = "One of those names is not here."))
  }
  if (a == b) {
    return(list(ok = FALSE, message = "Those are the same person."))
  }
  path <- suppressWarnings(
    igraph::shortest_paths(gi, from = a, to = b, weights = NA,
                           output = "vpath")$vpath[[1]])
  ids <- as.integer(path)
  if (length(ids) < 2) {
    return(list(ok = FALSE, message = paste0(
      from_name, " and ", to_name,
      " are in separate pieces of this network, so no route connects",
      " them.")))
  }
  # The ties along the route, as from and to pairs in the order walked.
  steps <- lapply(seq_len(length(ids) - 1), function(i) {
    list(from = ids[i], to = ids[i + 1])
  })
  list(ok = TRUE, ids = ids, steps = steps,
       names = names_all[ids],
       length = length(ids) - 1)
}

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

  # Two properties of a tie that the map can show and the numbers
  # cannot. A bridge is a tie whose removal would break the network into
  # more pieces than before, so it is the only route between what sits
  # on either side of it. A crossing tie joins two different groups.
  #
  # These are the ties Granovetter's argument is about: the ones that
  # carry anything new into a cluster, and the ones a network loses
  # first and misses most. They are worth marking because a reader
  # cannot find them by looking, and no per person score points at them.
  gi <- as.igraph(metrics$graph)
  bridge_ids <- tryCatch(igraph::bridges(gi), error = function(e) integer(0))
  ed$bridge <- seq_len(nrow(ed)) %in% as.integer(bridge_ids)
  groups <- nd$group
  ed$crossing <- groups[ed$from] != groups[ed$to]

  list(nodes = as.data.frame(nd), edges = as.data.frame(ed),
       meta = list(n = metrics$n, m = metrics$m,
                   n_groups = n_distinct(nd$group),
                   n_bridges = sum(ed$bridge),
                   n_crossing = sum(ed$crossing)))
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
