# research_metrics.R
# The researcher tier. Everything here is classical graph statistics from
# igraph, computed on demand so the general tier stays light. Each
# function returns plain data frames or named lists the interface can
# render without further math. No language model touches any of this.
#
# Copyright Abhik Roy. Released under the PolyForm Noncommercial
# License 1.0.0. See LICENSE.md.

suppressPackageStartupMessages({
  library(igraph)
  library(tidygraph)
  library(dplyr)
  library(tibble)
})

# Extended per person centralities beyond the four the general tier
# shows. PageRank and the HITS pair (hub and authority) round out the
# standard toolkit a network researcher expects.
extended_centralities <- function(g) {
  gi <- as.igraph(g)
  tibble(
    name      = V(gi)$name,
    degree    = degree(gi),
    strength  = strength(gi, weights = E(gi)$weight),
    between   = round(betweenness(gi, weights = NA, normalized = TRUE), 4),
    close     = round(harmonic_centrality(gi, weights = NA,
                                          normalized = TRUE), 4),
    eigen     = round(eigen_centrality(gi, weights = E(gi)$weight)$vector, 4),
    pagerank  = round(page_rank(gi, weights = E(gi)$weight)$vector, 4),
    hub       = round(hub_score(gi, weights = E(gi)$weight)$vector, 4),
    authority = round(authority_score(gi,
                                     weights = E(gi)$weight)$vector, 4)
  ) |>
    arrange(desc(pagerank))
}

# The community algorithm menu. Each returns membership plus the
# modularity it achieved, so the interface can compare partitions on the
# same footing. Girvan Newman is edge betweenness; it is slow on large
# graphs, which the caller guards.
community_partition <- function(g, method = "louvain") {
  gi <- as.igraph(g)
  w  <- E(gi)$weight
  comm <- switch(method,
    louvain    = cluster_louvain(gi, weights = w),
    walktrap   = cluster_walktrap(gi, weights = w),
    leiden     = cluster_leiden(gi, weights = w,
                                objective_function = "modularity"),
    fast_greedy = cluster_fast_greedy(gi, weights = w),
    edge_betweenness = cluster_edge_betweenness(gi, weights = w),
    cluster_louvain(gi, weights = w)
  )
  list(
    membership = as.integer(membership(comm)),
    modularity = modularity(gi, membership(comm), weights = w),
    n_groups   = length(unique(membership(comm))),
    method     = method
  )
}

# The plain names for the algorithm menu, kept here so the interface
# and any export share one source.
community_methods <- function() {
  c("Louvain (fast, general purpose)" = "louvain",
    "Leiden (refined Louvain)"         = "leiden",
    "Walktrap (random walk based)"     = "walktrap",
    "Fast greedy (agglomerative)"      = "fast_greedy",
    "Girvan Newman (edge betweenness)" = "edge_betweenness")
}

# Global structure in one table. These are the numbers a methods section
# reports: size, density, how much of the triangle closes, how often ties
# are returned, and how far apart the farthest pair sits.
global_diagnostics <- function(g) {
  gi <- as.igraph(g)
  comp <- components(gi)
  giant <- induced_subgraph(gi, which(comp$membership == which.max(comp$csize)))
  directed <- is_directed(gi)
  tibble(
    measure = c("People", "Ties", "Density", "Transitivity",
                "Reciprocity", "Components", "Diameter",
                "Mean distance", "Mean degree"),
    value = c(
      as.character(vcount(gi)),
      as.character(ecount(gi)),
      sprintf("%.3f", edge_density(gi)),
      sprintf("%.3f", transitivity(gi, type = "global")),
      if (directed) sprintf("%.3f", reciprocity(gi)) else "n/a (undirected)",
      as.character(comp$no),
      as.character(diameter(giant, weights = NA)),
      sprintf("%.2f", mean_distance(giant)),
      sprintf("%.2f", mean(degree(gi)))
    )
  )
}

# The dyad and triad census. The dyad census needs a directed graph; on
# undirected input the interface says so rather than showing an empty
# table. The triad census returns the classic sixteen isomorphism
# classes with their standard labels.
dyad_triad_census <- function(g) {
  gi <- as.igraph(g)
  if (!is_directed(gi)) {
    return(list(directed = FALSE))
  }
  dc <- dyad_census(gi)
  tc <- triad_census(gi)
  # igraph returns the sixteen classes in the conventional order, so the
  # Holland and Leinhardt labels line up position by position.
  triad_labels <- c("003", "012", "102", "021D", "021U", "021C",
                    "111D", "111U", "030T", "030C", "120D", "120U",
                    "120C", "210", "300", "201")
  list(
    directed = TRUE,
    dyads = tibble(
      type = c("Mutual", "Asymmetric", "Null"),
      count = c(dc$mut, dc$asym, dc$null)
    ),
    triads = tibble(type = triad_labels, count = as.integer(tc))
  )
}

# Bipartite projection. When an edge list joins two kinds of node, the
# interface can fold it into a one mode network among either kind. This
# is the matrix multiplication the blueprint asks for, done through
# igraph's bipartite projection so it stays exact.
project_bipartite <- function(edges, which_mode = 1) {
  ed <- data.frame(
    a = trimws(as.character(edges[[1]])),
    b = trimws(as.character(edges[[2]])),
    stringsAsFactors = FALSE
  )
  types <- data.frame(
    name = c(unique(ed$a), unique(ed$b)),
    type = c(rep(FALSE, length(unique(ed$a))),
             rep(TRUE, length(unique(ed$b))))
  )
  g <- graph_from_data_frame(ed, directed = FALSE,
                             vertices = types)
  V(g)$type <- types$type[match(V(g)$name, types$name)]
  proj <- bipartite_projection(g)
  side <- if (which_mode == 1) proj$proj1 else proj$proj2
  as_data_frame(side, what = "edges")[, c("from", "to")]
}

# A pristine, runnable script that reproduces the current analysis
# outside the app. Researchers asked to leave with their method intact,
# so the export is real igraph code, not a description of it.
export_script <- function(method = "louvain", size_by = "degree") {
  paste(
    "# Reproduce this analysis outside the app.",
    "# Requires: igraph. Point the read.csv at your own edge list.",
    "",
    "library(igraph)",
    "",
    'edges <- read.csv("your_edges.csv", stringsAsFactors = FALSE)',
    "g <- simplify(graph_from_data_frame(edges, directed = FALSE))",
    "",
    "# Per person centralities",
    "V(g)$degree      <- degree(g)",
    "V(g)$betweenness <- betweenness(g, normalized = TRUE)",
    "V(g)$closeness   <- harmonic_centrality(g, normalized = TRUE)",
    "V(g)$eigenvector <- eigen_centrality(g)$vector",
    "V(g)$pagerank    <- page_rank(g)$vector",
    "",
    "# Community detection",
    sprintf("communities <- cluster_%s(g)",
            if (method == "edge_betweenness") "edge_betweenness" else method),
    "V(g)$group <- membership(communities)",
    "cat(\"Modularity:\", modularity(communities), \"\\n\")",
    "",
    "# A basic plot, sized by the measure chosen in the app",
    sprintf("plot(g, vertex.size = 4 + 2 * V(g)$%s,",
            if (size_by == "between") "betweenness" else "degree"),
    "     vertex.color = V(g)$group, vertex.label.cex = 0.7)",
    sep = "\n")
}
