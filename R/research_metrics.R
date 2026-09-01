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
# tidygraph supplies an as.igraph method for tbl_graph and igraph itself
# supplies none for its own class, so calling it on a plain igraph fails
# with a message about no applicable method. Every function here takes
# either, since the directed copy travels as a plain igraph while
# everything else travels as a tbl_graph.
as_plain_igraph <- function(g) {
  if (inherits(g, "tbl_graph")) return(as.igraph(g))
  if (inherits(g, "igraph")) return(g)
  stop("That object is not a graph.")
}

extended_centralities <- function(g) {
  gi <- as_plain_igraph(g)
  # hub_score() and authority_score() were folded into one hits_scores()
  # call in igraph 2.0.3 and both older names now warn. R/compat.R calls
  # whichever the installed igraph has.
  hits <- net_hits(gi, weights = E(gi)$weight)
  tibble(
    name      = V(gi)$name,
    degree    = degree(gi),
    strength  = strength(gi, weights = E(gi)$weight),
    between   = round(betweenness(gi, weights = NA, normalized = TRUE), 4),
    close     = round(harmonic_centrality(gi, weights = NA,
                                          normalized = TRUE), 4),
    eigen     = round(eigen_centrality(gi, weights = E(gi)$weight)$vector, 4),
    pagerank  = round(page_rank(gi, weights = E(gi)$weight)$vector, 4),
    hub       = round(hits$hub, 4),
    authority = round(hits$authority, 4),
    # Burt's constraint: how far a person's contacts are already
    # connected to each other. A low score means their contacts are
    # strangers to one another, which is the structural hole position.
    # It answers a question none of the centralities do, which is why it
    # is worth its own column rather than being inferred from degree.
    constraint = round(suppressWarnings(
      constraint(gi, weights = E(gi)$weight)), 4),
    # Effective size, the other half of the same idea: contacts minus
    # the redundancy among them.
    effective  = round(vapply(seq_len(vcount(gi)), function(i) {
      nb <- neighbors(gi, i)
      k <- length(nb)
      if (k == 0) return(0)
      sub <- induced_subgraph(gi, nb)
      k - (2 * ecount(sub) / k)
    }, numeric(1)), 3),
    # Coreness: the deepest k core a person belongs to. It separates a
    # dense center from a fringe in a way degree alone does not, since
    # a person can have many ties and all of them to the fringe.
    coreness   = coreness(gi)
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
global_diagnostics <- function(g, membership = NULL) {
  gi <- as_plain_igraph(g)
  comp <- components(gi)
  giant <- induced_subgraph(gi, which(comp$membership == which.max(comp$csize)))
  directed <- is_directed(gi)
  # Freeman degree centralization: how far this network is from one in
  # which a single person holds every tie. It is the network level
  # counterpart of a centrality score and says something density cannot,
  # because two networks with the same density can be a hub and spoke or
  # an even mesh.
  centralization <- suppressWarnings(
    centr_degree(gi, normalized = TRUE)$centralization)

  # Degree assortativity: whether well connected people connect to other
  # well connected people. Positive is the pattern usually seen in
  # social networks; a clearly negative value points to a hub and spoke
  # arrangement and is worth stopping on.
  assortativity <- suppressWarnings(assortativity_degree(gi))

  # The Krackhardt and Stern E-I index, computed over whatever grouping
  # was passed in. It runs from minus one, every tie inside a group, to
  # plus one, every tie between groups. It is the standard way to ask
  # whether groups are talking to each other, and it is the measure most
  # often wanted and least often present in a general tool.
  ei <- if (!is.null(membership) && length(membership) == vcount(gi)) {
    ends_of <- ends(gi, E(gi), names = FALSE)
    internal <- sum(membership[ends_of[, 1]] == membership[ends_of[, 2]])
    external <- ecount(gi) - internal
    if (ecount(gi) > 0) (external - internal) / ecount(gi) else NA_real_
  } else {
    NA_real_
  }

  tibble(
    measure = c("People", "Ties", "Density", "Transitivity",
                "Degree centralization", "Degree assortativity",
                "E-I index (group crossing)",
                "Reciprocity", "Components", "Diameter",
                "Mean distance", "Mean degree"),
    value = c(
      as.character(vcount(gi)),
      as.character(ecount(gi)),
      sprintf("%.3f", edge_density(gi)),
      sprintf("%.3f", transitivity(gi, type = "global")),
      sprintf("%.3f", centralization),
      if (is.finite(assortativity)) sprintf("%.3f", assortativity) else "n/a",
      if (is.finite(ei)) sprintf("%.3f", ei) else "n/a (no grouping)",
      if (directed) sprintf("%.3f", reciprocity(gi)) else "n/a (undirected)",
      as.character(comp$no),
      as.character(diameter(giant, weights = NA)),
      # weights = NA counts steps. Without it igraph reads the tie
      # weight column as a cost, so a pair joined by a strong tie comes
      # out further apart than a pair joined by a weak one, which is
      # backwards for a column that means how much two people work
      # together. It also put this number above the diameter directly
      # beneath it, which is arithmetically impossible and was the sign
      # something was wrong.
      sprintf("%.2f", mean_distance(giant, weights = NA)),
      sprintf("%.2f", mean(degree(gi)))
    )
  )
}

# The dyad and triad census. The dyad census needs a directed graph; on
# undirected input the interface says so rather than showing an empty
# table. The triad census returns the classic sixteen isomorphism
# classes with their standard labels.
dyad_triad_census <- function(g) {
  gi <- as_plain_igraph(g)
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
  # The Holland and Leinhardt codes are exact and mean nothing to a
  # reader who has not memorized them, so each one carries a sentence
  # saying what arrangement it counts. The wording describes three
  # people rather than a graph, since that is what a triad is.
  triad_meaning <- c(
    "003"  = "Three people, no ties at all",
    "012"  = "One tie, running one way",
    "102"  = "One tie, returned",
    "021D" = "One person reaches out to two others",
    "021U" = "Two people both reach the same third",
    "021C" = "A chain: the first reaches the second reaches the third",
    "111D" = "A returned tie, plus one person reaching into it",
    "111U" = "A returned tie, plus one person reached from it",
    "030T" = "A chain that also closes the shortcut",
    "030C" = "A loop of three, each reaching the next",
    "120D" = "One person reaches two who already answer each other",
    "120U" = "Two who answer each other both reach a third",
    "120C" = "A returned tie with a chain around it",
    "210"  = "Two ties returned, one still one way",
    "300"  = "Everyone answers everyone",
    "201"  = "Two returned ties, the third pair unconnected"
  )
  list(
    directed = TRUE,
    dyads = tibble(
      type = c("Mutual", "Asymmetric", "Null"),
      count = c(dc$mut, dc$asym, dc$null)
    ),
    triads = tibble(type = triad_labels,
                    meaning = unname(triad_meaning[triad_labels]),
                    count = as.integer(tc))
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
# The reproducible script, in two dialects.
#
# The igraph version is the shortest path from an edge list to the same
# numbers this app reports, and it depends on one package. The tidy
# version does the same work through tidygraph and ggraph, which is what
# this app itself uses, and produces a figure worth putting in a
# document rather than a diagnostic plot.
#
# Both are offered because the choice is not about which is better. A
# reader dropping the script into an existing igraph analysis wants the
# first; a reader who works in the tidyverse and would otherwise spend
# an hour rewriting it wants the second.
export_script <- function(method = "louvain", size_by = "degree",
                          dialect = c("igraph", "tidy")) {
  dialect <- match.arg(dialect)
  measure <- if (size_by == "between") "betweenness" else "degree"
  cluster_fn <- if (method == "edge_betweenness") {
    "edge_betweenness"
  } else {
    method
  }

  if (dialect == "igraph") {
    return(paste(
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
      sprintf("communities <- cluster_%s(g)", cluster_fn),
      "V(g)$group <- membership(communities)",
      "cat(\"Modularity:\", modularity(communities), \"\\n\")",
      "",
      "# A basic plot, sized by the measure chosen in the app",
      sprintf("plot(g, vertex.size = 4 + 2 * V(g)$%s,", measure),
      "     vertex.color = V(g)$group, vertex.label.cex = 0.7)",
      sep = "\n"))
  }

  paste(
    "# Reproduce this analysis outside the app, the tidy way.",
    "# Requires: tidygraph, ggraph, dplyr, ggplot2. These are the same",
    "# packages the app itself uses, so the numbers below are the ones",
    "# it reports rather than a close approximation of them.",
    "",
    "library(tidygraph)",
    "library(ggraph)",
    "library(dplyr)",
    "library(ggplot2)",
    "",
    'edges <- read.csv("your_edges.csv", stringsAsFactors = FALSE)',
    "",
    "# A tbl_graph holds the nodes and the edges as two tables you can",
    "# work on with the usual verbs. activate() says which one a verb",
    "# applies to.",
    "g <- as_tbl_graph(edges, directed = FALSE) |>",
    "  convert(to_simple, .clean = TRUE)",
    "",
    "# Per person centralities. Every one of these is a column, so the",
    "# result can be filtered, arranged, and joined like any other table.",
    "g <- g |>",
    "  activate(nodes) |>",
    "  mutate(",
    "    degree      = centrality_degree(),",
    "    betweenness = centrality_betweenness(normalized = TRUE),",
    "    closeness   = centrality_closeness(normalized = TRUE),",
    "    eigenvector = centrality_eigen(),",
    "    pagerank    = centrality_pagerank(),",
    sprintf("    group       = as.factor(group_%s())", cluster_fn),
    "  )",
    "",
    "# The people table, in the order the app sorts it",
    "people <- g |>",
    "  activate(nodes) |>",
    "  as_tibble() |>",
    sprintf("  arrange(desc(%s))", measure),
    "print(people, n = 20)",
    "",
    "# How separated the groups are. Above 0.3 is usually read as a",
    "# real division rather than an artifact of the algorithm.",
    "g |>",
    "  activate(nodes) |>",
    "  mutate(modularity = graph_modularity(group = group)) |>",
    "  as_tibble() |>",
    "  slice(1) |>",
    "  pull(modularity)",
    "",
    "# The figure. Same layout family the app uses.",
    "ggraph(g, layout = \"fr\") +",
    "  geom_edge_link(alpha = 0.35, width = 0.4) +",
    sprintf("  geom_node_point(aes(size = %s, colour = group,", measure),
    "                      shape = group)) +",
    "  geom_node_text(aes(label = name), repel = TRUE, size = 3) +",
    "  scale_size_continuous(range = c(2, 9)) +",
    "  theme_graph(base_family = \"sans\")",
    sep = "\n")
}
