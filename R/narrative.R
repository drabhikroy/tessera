# narrative.R
# The interpretation layer. Every sentence here is computed from the numbers
# in network_math.R, so the prose can never say more than the data supports.
# The hedging is deliberate: a network snapshot suggests, it does not prove.
#
# Copyright Abhik Roy. Released under the PolyForm Noncommercial
# License 1.0.0. See LICENSE.md.

suppressPackageStartupMessages({
  library(dplyr)
  library(tibble)
})

# Small helpers keep the sentence templates readable further down.

# Percentages are written as words rather than with a symbol, because
# the prose reads them aloud in sentences and a symbol interrupts that.
pct <- function(x) paste0(round(100 * x), " percent")

# Joins names the way a sentence would, with the serial comma. Three or
# more names is the common case in a network of any size, so the list
# form matters more here than it looks like it should.
name_list <- function(x) {
  if (length(x) == 0) return("")
  if (length(x) == 1) return(x)
  if (length(x) == 2) return(paste(x[1], "and", x[2]))
  paste0(paste(x[-length(x)], collapse = ", "), ", and ", x[length(x)])
}

# The k highest scoring names for a measure, used wherever the prose
# says who stands out. Ties are broken arbitrarily rather than reported,
# since a sentence naming six people for third place helps nobody.
top_names <- function(values, names, k = 3) {
  tibble(name = names, value = values) |>
    # Ties at zero say nothing worth naming, so they are dropped.
    filter(value > 0) |>
    slice_max(value, n = k, with_ties = FALSE) |>
    pull(name)
}

# Density reads differently at different network sizes, so the wording bands
# are wide and the number is always given alongside the word.
density_phrase <- function(d) {
  if (d >= 0.30) "tightly knit"
  else if (d >= 0.10) "moderately connected"
  else "loosely connected"
}

# The usual reading of modularity: below 0.3 the group boundaries are
# weak enough that a different algorithm would likely draw them
# elsewhere, and the wording says so rather than announcing groups.
modularity_phrase <- function(q) {
  if (q >= 0.5) "clearly separated"
  else if (q >= 0.3) "visibly distinct"
  else "loosely defined"
}

# The full network summary. Returns a character vector of paragraphs so the
# interface can place them with breathing room instead of one wall of text.
describe_network <- function(metrics) {
  p <- character(0)

  # Paragraph 1: shape and connectedness.
  shape <- sprintf(
    "This snapshot covers %d people joined by %d ties. The network is %s: about %s of all possible ties are present.",
    metrics$n, metrics$m, density_phrase(metrics$density), pct(metrics$density)
  )
  if (metrics$n_components == 1) {
    shape <- paste(shape,
      sprintf("Everyone can reach everyone else, and a typical message would pass through about %s people on the way.",
              round(metrics$mean_dist, 1)))
  } else {
    shape <- paste(shape,
      sprintf("The network is in %d separate pieces. The largest piece holds %s of the people, and the rest cannot reach it at all in this data.",
              metrics$n_components, pct(metrics$giant_share)))
  }
  p <- c(p, shape)

  # Paragraph 2: groups.
  p <- c(p, sprintf(
    "The people fall into %d groups based on who talks with whom. The boundaries between groups look %s in this data (modularity %.2f). Group patterns like these usually reflect teams, locations, or shared work, though the data alone cannot say which.",
    metrics$n_groups, modularity_phrase(metrics$modularity), metrics$modularity
  ))

  # Paragraph 3: the people who hold it together. Betweenness and degree
  # are reported together on purpose. They disagree often, and a reader
  # who sees only one of them draws a confident wrong conclusion about
  # who matters in the network.
  bridges <- top_names(metrics$betweenness, metrics$names, 3)
  hubs    <- top_names(metrics$degree, metrics$names, 3)
  if (length(bridges) > 0) {
    p <- c(p, sprintf(
      "%s sit on more of the shortest paths between other people than anyone else, which suggests they carry much of the traffic between groups. %s have the most direct ties, which makes them the busiest points of contact day to day. These readings describe position in this snapshot, not performance.",
      name_list(bridges), name_list(hubs)
    ))
  }

  # Paragraph 4: fragility, only when the data shows any.
  if (length(metrics$cut_ids) > 0) {
    shown <- head(sort(metrics$cut_ids), 4)
    more  <- length(metrics$cut_ids) - length(shown)
    tail_note <- if (more > 0) sprintf(" and %d more", more) else ""
    p <- c(p, sprintf(
      "If %s%s stepped away, parts of this network would lose their only connection to the rest. Positions like these are worth a closer look: they can signal either a person quietly holding things together or a process that depends too much on one desk.",
      name_list(shown), tail_note
    ))
  } else {
    p <- c(p, "No single person is the only link between parts of this network. If any one person stepped away, everyone else could still reach each other another way.")
  }

  p
}

# The spotlight text for one selected person. Written to be read next to the
# dimmed map, so it names what the reader is looking at.
#
# Every sentence about a person is comparative rather than absolute: a
# rank among the people present, not a score. A raw betweenness figure
# means nothing to a reader who has never seen another one.
describe_person <- function(metrics, node_index, groups) {
  nm  <- metrics$names[node_index]
  deg <- metrics$degree[node_index]
  grp <- groups[node_index]

  rank_of <- function(values) {
    # Rank 1 is the highest value. Ties share the better rank, which is the
    # generous reading and the honest one for a snapshot.
    as.integer(min_rank(desc(values))[node_index])
  }
  r_btw <- rank_of(metrics$betweenness)
  r_deg <- rank_of(metrics$degree)

  p <- character(0)
  p <- c(p, sprintf(
    "%s has %d direct ties and belongs to group %d. Among the %d people here, that is the number %d spot for direct connections.",
    nm, deg, grp, metrics$n, r_deg
  ))

  if (metrics$betweenness[node_index] > 0) {
    p <- c(p, sprintf(
      "%s ranks number %d for sitting between other people on their shortest paths. Positions like this often act as a go between: news, requests, and favors tend to pass through them.",
      nm, r_btw
    ))
  } else {
    p <- c(p, sprintf(
      "%s does not sit between other people on any shortest path in this snapshot, which usually means their ties stay inside one circle.",
      nm
    ))
  }

  if (nm %in% metrics$cut_ids) {
    p <- c(p, sprintf(
      "%s is also a single point of failure: without them, at least one part of this network would lose its only route to the rest.",
      nm
    ))
  }

  p <- c(p, "The dimmed map shows the people this person can reach directly. Everything else is one or more steps further out.")
  p
}

# A one line caveat that travels with every export so the numbers are never
# read as more than they are.
# What the model is given. Not the panel prose.
#
# The cards explain the app as well as the network: what a group is, how
# groups are found, what the reading does and does not claim. Those
# sentences are right on screen beside the map and useless coming back
# from a model, which restates a definition as though it were a finding
# and spends a paragraph doing it. Sending the whole panel is what
# produced answers explaining that groups come from patterns of
# connection.
#
# So the model gets findings only, as short statements of fact with the
# numbers and the names in them, and is asked to write from those. The
# definitions stay where they belong, above the answer, in prose nobody
# had to generate.
model_facts <- function(metrics, groups) {
  m <- metrics
  top <- top_names(m$betweenness, m$names, 3)
  busiest <- top_names(m$degree, m$names, 3)
  facts <- c(
    sprintf("People: %d. Ties: %d.", m$n, m$m),
    sprintf("Density: %s of all possible ties are present.",
            pct(m$density)),
    if (m$n_components == 1) {
      sprintf("The network is in one piece. A typical path runs through %.1f people.",
              m$mean_dist)
    } else {
      sprintf("The network is in %d separate pieces. The largest holds %s of everyone.",
              m$n_components, pct(m$giant_share))
    },
    sprintf("Groups found: %d. The largest holds %d people.",
            m$n_groups, max(table(m$membership))),
    sprintf("Group separation (modularity): %.2f.", m$modularity),
    sprintf("Sitting on the most paths between other people: %s.",
            name_list(top)),
    sprintf("Most direct connections: %s.", name_list(busiest)),
    if (length(m$cut_ids) > 0) {
      sprintf("Removing any one of these would split the network: %s.",
              name_list(head(m$cut_ids, 5)))
    } else {
      "No single person holds the network together on their own."
    }
  )
  facts[!vapply(facts, is.null, logical(1))]
}

# The same, for one person. Comparative rather than absolute, since a
# raw score means nothing to a reader who has seen no other.
model_facts_person <- function(metrics, idx, groups) {
  m <- metrics
  rank_of <- function(values) {
    sum(values > values[idx]) + 1
  }
  who <- m$names[idx]
  c(
    sprintf("This is about %s.", who),
    sprintf("%s has %d direct connections, which ranks %d of %d people.",
            who, m$degree[idx], rank_of(m$degree), m$n),
    sprintf("On sitting between others, %s ranks %d of %d.",
            who, rank_of(m$betweenness), m$n),
    sprintf("On reaching the rest of the network quickly, %s ranks %d of %d.",
            who, rank_of(m$closeness), m$n),
    sprintf("%s is in group %s, which holds %d people.",
            who, as.character(m$membership[idx]),
            sum(m$membership == m$membership[idx])),
    if (who %in% m$cut_ids) {
      sprintf("Removing %s would split the network into pieces.", who)
    } else {
      sprintf("Removing %s would not split the network.", who)
    }
  )
}

# This line is attached to every export rather than shown once in the
# interface, because the file outlives the screen it came from and will
# be read by people who never saw the app.
caveat_line <- function() {
  paste("These readings come from one snapshot of recorded ties.",
        "They describe position in the network, not skill, effort, or worth.")
}

# Card structure for the reading panel. Each card is one idea with a
# short title, a row of headline numbers, prose beneath, and the people
# it names as clickable chips. The panel reads top to bottom in the
# order a person would ask the questions.
describe_cards <- function(metrics, groups) {
  cards <- list()

  connected_line <- if (metrics$n_components == 1) {
    sprintf("Everyone can reach everyone else. A typical message passes through about %s people on the way.",
            round(metrics$mean_dist, 1))
  } else {
    sprintf("The network is in %d separate pieces. The largest holds %s of the people; the rest cannot reach it at all in this data.",
            metrics$n_components, pct(metrics$giant_share))
  }
  cards$shape <- list(
    id    = "shape",
    title = "The shape",
    stats = list(
      list(label = "People", value = as.character(metrics$n)),
      list(label = "Ties", value = as.character(metrics$m)),
      list(label = "Of possible ties", value = pct(metrics$density)),
      list(label = "Pieces", value = as.character(metrics$n_components))
    ),
    prose = paste(
      sprintf("This snapshot is %s.", density_phrase(metrics$density)),
      connected_line),
    people = character(0)
  )

  group_tbl <- tibble(group = groups) |> count(group)
  cards$groups <- list(
    id    = "groups",
    title = "The groups",
    stats = list(
      list(label = "Groups found", value = as.character(metrics$n_groups)),
      list(label = "Largest", value = as.character(max(group_tbl$n))),
      list(label = "Separation",
           value = modularity_phrase(metrics$modularity))
    ),
    prose = paste(
      "Groups come from the tie pattern alone: people who talk with each",
      "other more than with everyone else. Patterns like these usually",
      "reflect teams, locations, or shared work, though the data cannot",
      "say which. Choose a group in the key above the map to light only",
      "that group."),
    people = character(0)
  )

  bridges <- top_names(metrics$betweenness, metrics$names, 3)
  hubs    <- setdiff(top_names(metrics$degree, metrics$names, 3), bridges)
  holders_prose <- if (length(bridges) > 0) {
    paste(
      sprintf("%s sit on more of the shortest paths between other people than anyone else, which suggests they carry much of the traffic between groups.",
              name_list(bridges)),
      if (length(hubs) > 0) {
        sprintf("%s have the most direct ties and make the busiest day to day contacts.",
                name_list(hubs))
      } else "",
      "These readings describe position in this snapshot, not performance.")
  } else {
    "No one stands between others often enough to name. Ties spread evenly here."
  }
  cards$holders <- list(
    id     = "holders",
    title  = "Who holds it together",
    stats  = list(),
    prose  = holders_prose,
    people = unique(c(bridges, hubs))
  )

  fragile_people <- head(sort(metrics$cut_ids), 4)
  more <- length(metrics$cut_ids) - length(fragile_people)
  fragile_prose <- if (length(metrics$cut_ids) > 0) {
    paste0(
      sprintf("If %s%s stepped away, parts of this network would lose their only connection to the rest.",
              name_list(fragile_people),
              if (more > 0) sprintf(" and %d more", more) else ""),
      " Positions like these can signal a person quietly holding things",
      " together, or a process that depends too much on one desk.")
  } else {
    paste("No single person is the only link between parts of this",
          "network. If any one person stepped away, everyone else could",
          "still reach each other another way.")
  }
  cards$fragile <- list(
    id     = "fragile",
    title  = "If someone stepped away",
    stats  = list(
      list(label = "Single points of failure",
           value = as.character(length(metrics$cut_ids)))
    ),
    prose  = fragile_prose,
    people = fragile_people
  )

  cards
}

# The person card, shown when the map has a selection. Same structure as
# the network cards so the panel swaps cleanly.
person_card <- function(metrics, node_index, groups) {
  nm  <- metrics$names[node_index]
  r_deg <- as.integer(min_rank(desc(metrics$degree))[node_index])
  r_btw <- as.integer(min_rank(desc(metrics$betweenness))[node_index])

  between_line <- if (metrics$betweenness[node_index] > 0) {
    sprintf("%s ranks number %d for sitting between other people on their shortest paths. Positions like this often act as a go between: news, requests, and favors pass through them.",
            nm, r_btw)
  } else {
    sprintf("%s does not sit between other people on any shortest path here, which usually means their ties stay inside one circle.",
            nm)
  }
  cut_line <- if (nm %in% metrics$cut_ids) {
    sprintf(" %s is also a single point of failure: without them, at least one part of this network would lose its only route to the rest.",
            nm)
  } else ""

  list(
    id    = "person",
    title = paste("About", nm),
    stats = list(
      list(label = "Direct ties",
           value = as.character(metrics$degree[node_index])),
      list(label = "Rank for direct ties",
           value = paste0("#", r_deg, " of ", metrics$n)),
      list(label = "Group",
           value = as.character(groups[node_index]))
    ),
    prose = paste0(between_line, cut_line,
      " The lit part of the map is who this person reaches at the chosen",
      " number of steps."),
    people = character(0)
  )
}
