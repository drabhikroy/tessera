# overview.R
# The Overview screen: the first thing a new reader meets, and the
# leftmost tab. It answers three questions before the person has loaded
# anything, in the order they tend to be asked. What is this. What will
# it tell me. What do I have to give it.
#
# Copyright Abhik Roy. Released under the PolyForm Noncommercial
# License 1.0.0. See LICENSE.md.

# The screen is content rather than wiring, so it lives here beside the
# walkthrough rather than in app.R. Nothing on it depends on a loaded
# network, which is the point: a person who has not decided whether to
# upload anything can still find out what would happen if they did.

# A small network, laid out by hand, used as the hero picture and again
# in the worked example below. The coordinates are fixed rather than
# computed so the picture is the same on every visit and can be talked
# about in the prose beside it.
overview_layout <- list(
  list(id = "Ana",   x = 78,  y = 52,  group = 1, size = 11),
  list(id = "Ben",   x = 30,  y = 96,  group = 1, size = 8),
  list(id = "Cass",  x = 92,  y = 118, group = 1, size = 9),
  list(id = "Dev",   x = 168, y = 88,  group = 2, size = 12),
  list(id = "Elin",  x = 240, y = 50,  group = 2, size = 9),
  list(id = "Faris", x = 262, y = 122, group = 2, size = 8),
  list(id = "Gita",  x = 196, y = 160, group = 3, size = 8)
)

overview_ties <- list(
  c("Ana", "Ben"), c("Ana", "Cass"), c("Ben", "Cass"),
  c("Ana", "Dev"), c("Dev", "Elin"), c("Dev", "Faris"),
  c("Elin", "Faris"), c("Dev", "Gita")
)

# Looks a node up by name. The layout is a short list and this runs a
# handful of times, so a linear scan is the clearest thing that works.
overview_node <- function(id) {
  for (node in overview_layout) {
    if (node$id == id) return(node)
  }
  NULL
}

# The hero picture. Every color comes from a theme token rather than a
# literal, so the picture follows the mode and the color setting the
# same way the map does.
overview_art <- function(with_labels = TRUE) {
  ties <- vapply(overview_ties, function(pair) {
    a <- overview_node(pair[1])
    b <- overview_node(pair[2])
    sprintf('<line x1="%d" y1="%d" x2="%d" y2="%d" class="ov-tie"/>',
            a$x, a$y, b$x, b$y)
  }, "")
  # Dev is the one node in the picture that touches all three groups, so
  # the prose beside it has something true to point at.
  nodes <- vapply(overview_layout, function(node) {
    label <- if (with_labels) {
      sprintf('<text x="%d" y="%d" class="ov-name">%s</text>',
              node$x, node$y - node$size - 7, node$id)
    } else {
      ""
    }
    sprintf(paste0('<circle cx="%d" cy="%d" r="%d" class="ov-node ov-g%d"/>',
                   "%s"),
            node$x, node$y, node$size, node$group, label)
  }, "")
  HTML(sprintf(paste0(
    '<svg class="ov-art" viewBox="0 0 300 200" role="img" ',
    'aria-label="A small network of seven people in three groups, with ',
    'one person joining all three.">%s%s</svg>'),
    paste(ties, collapse = ""), paste(nodes, collapse = "")))
}

# The hero picture. It is the idea rather than an instance of it, which
# is what keeps it distinct from the worked example further down the
# page: a field of tiles,
# which is what a tessera is, with connections closing across them until
# the tiling reads as a network. Nothing here corresponds to a person or
# a measure, so there is nothing for a reader to try to interpret, which
# is the right relationship between a hero picture and the sentence
# beside it.
overview_emblem <- function() {
  step <- 42
  # Positions are given as grid cells so the network keeps the square
  # rhythm of the icon, and sizes vary because a network built from
  # ten identical marks reads as a pattern instead.
  live <- list(
    list(r = 1, c = 3, size = 17), list(r = 1, c = 6, size = 11),
    list(r = 2, c = 1, size = 13), list(r = 2, c = 4, size = 21),
    list(r = 3, c = 6, size = 15), list(r = 3, c = 2, size = 12),
    list(r = 4, c = 4, size = 13), list(r = 4, c = 7, size = 10),
    list(r = 5, c = 2, size = 16), list(r = 5, c = 5, size = 11)
  )
  joins <- list(
    c(1, 4), c(1, 2), c(2, 5), c(3, 4), c(3, 6), c(4, 5),
    c(4, 6), c(4, 7), c(5, 8), c(6, 9), c(7, 9), c(7, 10),
    c(9, 10), c(4, 9)
  )
  centre <- function(cell) {
    c((cell$c - 1) * step + 30, (cell$r - 1) * step + 26)
  }

  # The quiet tiles sit behind everything and fade toward the edges, so
  # the field reads as a surface the network is set into rather than as
  # a grid competing with it.
  ground <- character(0)
  for (r in 1:5) {
    for (c in 1:7) {
      p <- centre(list(r = r, c = c))
      distance <- abs(c - 4) / 3.5 + abs(r - 3) / 2.5
      ground <- c(ground, sprintf(
        paste0('<rect x="%d" y="%d" width="16" height="16" rx="3" ',
               'class="em-tile" opacity="%.2f"/>'),
        p[1] - 8, p[2] - 8, max(0.10, 0.42 - distance * 0.13)))
    }
  }

  lines <- vapply(joins, function(pair) {
    a <- centre(live[[pair[1]]])
    b <- centre(live[[pair[2]]])
    sprintf('<line x1="%d" y1="%d" x2="%d" y2="%d" class="em-join"/>',
            a[1], a[2], b[1], b[2])
  }, "")

  # The live tiles are rounded squares rather than circles, which is
  # what keeps the icon in the picture while the joins make it a
  # network. The largest three carry a second square inside them, the
  # four square motif of the mark itself.
  marks <- vapply(seq_along(live), function(i) {
    cell <- live[[i]]
    p <- centre(cell)
    half <- cell$size / 2
    inner <- if (cell$size >= 15) {
      sprintf(paste0('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" ',
                     'rx="2" class="em-inner"/>'),
              p[1] - half / 2.6, p[2] - half / 2.6,
              half / 1.3, half / 1.3)
    } else {
      ""
    }
    sprintf(paste0('<rect x="%.1f" y="%.1f" width="%d" height="%d" ',
                   'rx="%.1f" class="em-live"/>%s'),
            p[1] - half, p[2] - half, cell$size, cell$size,
            cell$size / 3.4, inner)
  }, "")

  HTML(sprintf(paste0(
    '<svg class="ov-art ov-emblem" viewBox="0 0 320 220" ',
    'xmlns="http://www.w3.org/2000/svg" role="img" ',
    'aria-label="A network of square tiles joined across a quiet grid.">',
    "%s%s%s</svg>"),
    paste(ground, collapse = ""), paste(lines, collapse = ""),
    paste(marks, collapse = "")))
}

# One card of the three that say what the app does. Kept as a function
# so the three read as three of the same thing rather than three blocks
# of markup that happen to look alike.
overview_card <- function(title, body) {
  div(class = "ov-card",
    tags$h3(title),
    tags$p(body))
}

# The example CSV. Three columns, six rows, small enough to read at a
# glance and shaped exactly like the file the app expects, so a person
# can compare it against their own spreadsheet without opening the help.
overview_csv <- function() {
  rows <- list(
    c("from", "to", "strength"),
    c("Ana", "Ben", "3"),
    c("Ana", "Cass", "2"),
    c("Ben", "Cass", "1"),
    c("Ana", "Dev", "4"),
    c("Dev", "Elin", "2")
  )
  body <- vapply(seq_along(rows), function(i) {
    cells <- paste(vapply(rows[[i]], function(cell) {
      sprintf("<%s>%s</%s>", if (i == 1) "th" else "td", cell,
              if (i == 1) "th" else "td")
    }, ""), collapse = "")
    paste0("<tr>", cells, "</tr>")
  }, "")
  HTML(paste0('<table class="ov-csv">', paste(body, collapse = ""),
              "</table>"))
}

# The whole screen. The order is deliberate: the picture and the claim
# first, then what the two tabs give back, then the worked example, then
# what the app asks for, then the ground rules about where data goes.
overview_body <- function() {
  tagList(
    div(class = "ov-hero",
      div(class = "ov-hero-text",
        tags$h1(class = "ov-title", "Tessera"),
        tags$p(class = "ov-tagline", APP_TAG),
        tags$p(class = "ov-lede", paste(
          "Tessera takes a list of who is connected to whom and turns it",
          "into a map you can read. It names the people who hold the",
          "network together, the groups it falls into, and the places",
          "where it would break if one person left. Every number comes",
          "with a sentence saying what it means.")),
        div(class = "ov-actions",
          actionButton("ov_open_sample", "Open a sample network",
                       class = "btn btn-primary"),
          actionButton("ov_open_tour", "Take the walkthrough",
                       class = "btn"))
      ),
      div(class = "ov-hero-art", overview_emblem())
    ),

    tags$h2(class = "ov-section", "What you get"),
    div(class = "ov-cards",
      overview_card("A map and a reading of it", paste(
        "The Explore tab holds the network map, a panel that describes",
        "what the map shows in plain sentences, and a table of every",
        "person with their position in the network. Choosing a person",
        "lights their part of the map and writes about them.")),
      overview_card("The full statistics underneath", paste(
        "The Research tab holds extended centralities, a choice of",
        "community detection algorithms, global diagnostics, the dyad",
        "and triad census, and an R script that reproduces the whole",
        "analysis outside this app.")),
      overview_card("Nothing leaves the machine", paste(
        "The file you load is read in memory and never sent anywhere.",
        "There is no account, no server, and no telemetry. The optional",
        "language model connection speaks to a local Ollama server on",
        "this same machine or to nothing at all."))
    ),

    tags$h2(class = "ov-section", "A worked example"),
    div(class = "ov-worked",
      div(class = "ov-worked-art", overview_art(with_labels = TRUE)),
      div(class = "ov-worked-text",
        tags$p(paste(
          "Seven people, eight ties, three groups. The map above is what",
          "Tessera makes of it. The panel beside the map would read",
          "something close to this:")),
        tags$blockquote(class = "ov-quote", paste(
          "This snapshot covers 7 people joined by 8 ties. The network",
          "is moderately connected: about 38 percent of all possible",
          "ties are present. Everyone can reach everyone else. Dev sits",
          "on more of the shortest paths between other people than",
          "anyone else, which suggests they carry much of the traffic",
          "between groups. Removing Dev would split the network into",
          "three pieces.")),
        tags$p(class = "ov-note", paste(
          "The sentences are computed from the same numbers the Research",
          "tab reports. They hedge on purpose. A snapshot of ties",
          "suggests where attention sits; it does not explain why."))
      )
    ),

    tags$h2(class = "ov-section", "What Tessera asks for"),
    div(class = "ov-asks",
      div(class = "ov-ask",
        tags$h3("A list of ties"),
        tags$p(paste(
          "One row per connection. The first two columns name the two",
          "ends of the tie. A third column is optional and gives the",
          "tie a strength; without it every tie counts the same.")),
        overview_csv()
      ),
      div(class = "ov-ask",
        tags$h3("Nothing else"),
        tags$p(paste(
          "No headers beyond those, no identifier scheme, no date",
          "format, no preparation step. Names can be people, teams,",
          "organizations, or anything else that has connections. If a",
          "file does not read, the app says what the file needs rather",
          "than what the parser objected to.")),
        tags$p(class = "ov-note", paste(
          "Two sample networks ship with the app, so the fastest way to",
          "see what it does is to open one and read the panel."))
      )
    ),

    div(class = "ov-close",
      tags$p(paste(
        "Tessera is free and open source under the PolyForm",
        "Noncommercial License. The computation is classical graph",
        "statistics from igraph and tidygraph, and the explanations are",
        "written from those numbers by rules that can be read in the",
        "source. Built by Abhik Roy."))
    )
  )
}
