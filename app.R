# app.R
# Tessera: a social network map with a plain language reading panel.
#
# Copyright Abhik Roy. Released under the PolyForm Noncommercial
# License 1.0.0. See LICENSE.md.
# The math is tidygraph pipelines (R/network_math.R), the prose is
# computed from those numbers (R/narrative.R), and a local language
# model can restate the prose when one is available. Nothing leaves the
# machine this app runs on.

# The file is ordered UI helpers first, then the two tab definitions,
# then the server. Content that a reader would read rather than operate,
# meaning the walkthrough, the model guide, and the Overview screen,
# lives in R/ so this file stays about wiring.

library(shiny)
suppressPackageStartupMessages({
  library(bslib)
  library(dplyr)
  library(readr)
})

source("R/info.R")
source("R/compat.R")
source("R/network_math.R")
source("R/sample_data.R")
source("R/narrative.R")
source("R/figure.R")
source("R/guide.R")
source("R/overview.R")
source("R/research_metrics.R")
source("R/runtime.R")
source("R/session_state.R")
source("R/help.R")
source("R/statistics.R")
source("R/tables.R")
source("R/appearance.R")

# Build a cache busting suffix from the version and the file's own
# modification time, so an edit during development is picked up without
# a manual reload and a release is picked up by everyone.
asset_url <- function(file) {
  path <- file.path("www", file)
  stamp <- if (file.exists(path)) {
    as.integer(file.info(path)$mtime)
  } else {
    0L
  }
  sprintf("%s?v=%s.%s", file, APP_VERSION, stamp)
}

# Fall back to a default when an input is missing or blank. Shiny inputs
# that live inside a dialog do not exist until the dialog opens, so this
# comes up throughout the server.
`%||%` <- function(a, b) if (is.null(a) || identical(a, "")) b else a

# The measure names on screen are plain phrases, not centrality jargon.
# The technical mapping: direct ties is degree, between groups is
# betweenness, quick reach is harmonic closeness, and well connected
# circle is eigenvector centrality.
size_choices <- c(
  "Direct ties"           = "degree",
  "Between groups"        = "between",
  "Quick reach"           = "close",
  "Well connected circle" = "eigen"
)

sort_choices <- c(size_choices, "Name" = "label")

# The title a downloaded figure carries. One function rather than a
# switch at each download, since two copies of the same list drift: the
# two directed samples were named in one of them and not the other, so
# the same network came out titled differently depending on which
# control produced the file.
dataset_title <- function(dataset) {
  if (is.null(dataset) || length(dataset) != 1) return("Your network")
  switch(dataset,
    org      = "Product studio",
    referral = "Customer referrals",
    advice   = "Advice seeking",
    message  = "Messaging",
    resumed  = "Your network",
    "Your network")
}

label_choices <- c(
  "Key people" = "key",
  "Everyone"   = "all",
  "No names"   = "none"
)

# Legend chips are tiny inline SVGs so the shapes in the key match the
# shapes on the map exactly, in every palette. Each chip is a button:
# choosing one lights only that group.
# The appearance toggle. The click handler is attached inline so the
# button works from the moment it exists, with no dependency on script
# load order, event delegation, or custom element registration. It flips
# the attribute the stylesheet reads, updates its own label, and tells
# the server so downloads follow the same mode.
theme_toggle_button <- function() {
  handler <- paste0(
    "var r = document.documentElement;",
    "var next = r.getAttribute('data-bs-theme') === 'dark' ? 'light' : 'dark';",
    "r.setAttribute('data-bs-theme', next);",
    "this.textContent = next === 'dark' ? 'Light mode' : 'Dark mode';",
    "this.setAttribute('aria-label', next === 'dark' ? ",
    "'Switch to light mode' : 'Switch to dark mode');",
    "try { window.localStorage.setItem('tessera-theme', next); } catch (e) {}",
    "if (window.Shiny) { Shiny.setInputValue('theme_mode', next); }")
  tags$button(type = "button", class = "btn theme-toggle",
              onclick = HTML(handler),
              `aria-label` = "Switch to light mode",
              "Light mode")
}

# The glyph for a group number. Twelve shapes cycle first, then three
# fill variants, which gives thirty six groups that stay apart from one
# another without hue being asked to carry any of it. Color repeats
# every twelve, so two groups sharing a color never share a shape.
glyph_for <- function(group) {
  i <- max(0, group - 1)
  list(shape = i %% 12, variant = (i %/% 12) %% 3, color = (i %% 12) + 1)
}

# The twelve legend shapes, laid out on a twenty unit square so they match
# the map glyphs. Index zero is a circle, which needs its own element.
legend_shape_svg <- function(shape) {
  poly <- function(sides, r, rot = 0) {
    ang <- (2 * pi * seq_len(sides) - 2 * pi) / sides - pi / 2 + rot
    pts <- paste(sprintf("%.1f,%.1f", 10 + cos(ang) * r, 10 + sin(ang) * r),
                 collapse = " ")
    sprintf('<polygon points="%s"></polygon>', pts)
  }
  star_svg <- function(r, inner) {
    ang <- (pi * (seq_len(10) - 1)) / 5 - pi / 2
    rr <- ifelse(seq_len(10) %% 2 == 1, r, r * inner)
    pts <- paste(sprintf("%.1f,%.1f", 10 + cos(ang) * rr,
                         10 + sin(ang) * rr), collapse = " ")
    sprintf('<polygon points="%s"></polygon>', pts)
  }
  cross_svg <- function(rot) {
    o <- 9; w <- 3.2
    raw <- matrix(c(-w, -o, w, -o, w, -w, o, -w, o, w, w, w,
                    w, o, -w, o, -w, w, -o, w, -o, -w, -w, -w),
                  ncol = 2, byrow = TRUE)
    rr <- cbind(raw[, 1] * cos(rot) - raw[, 2] * sin(rot),
                raw[, 1] * sin(rot) + raw[, 2] * cos(rot))
    pts <- paste(sprintf("%.1f,%.1f", 10 + rr[, 1], 10 + rr[, 2]),
                 collapse = " ")
    sprintf('<polygon points="%s"></polygon>', pts)
  }
  switch(as.character(shape),
    "0"  = '<circle cx="10" cy="10" r="8"></circle>',
    "1"  = poly(4, 8.2, pi / 4),
    "2"  = poly(4, 9, 0),
    "3"  = poly(3, 9, 0),
    "4"  = poly(3, 9, pi),
    "5"  = poly(6, 8.5, 0),
    "6"  = poly(5, 8.6, 0),
    "7"  = star_svg(9.5, 0.62),
    "8"  = cross_svg(0),
    "9"  = poly(8, 8.2, pi / 8),
    "10" = cross_svg(pi / 4),
    "11" = '<polygon points="1.5,3 18.5,17 18.5,3 1.5,17"></polygon>',
    '<circle cx="10" cy="10" r="8"></circle>'
  )
}

# Legend chips are tiny inline SVGs so the key matches the map exactly in
# every palette. Each chip is a button: choosing one lights that group.
legend_chip <- function(group, size) {
  gl <- glyph_for(group)
  shape <- legend_shape_svg(gl$shape)
  pip <- if (gl$variant == 2) {
    '<circle cx="10" cy="10" r="3" class="pip"></circle>'
  } else ""
  sprintf(paste0(
    '<button type="button" class="legend-item" ',
    'onclick="Shiny.setInputValue(\'legend_group\', %d, {priority: \'event\'})" ',
    'aria-label="Light only group %d, %d people">',
    '<svg width="20" height="20" class="node color-%d var-%d">%s%s</svg>',
    'Group %d <span class="legend-count">%d</span></button>'),
    group, group, size, gl$color, gl$variant,
    sub("<(polygon|circle)", '<\\1 class="mark"', shape), pip,
    group, size)
}

brand_title <- div(class = "brand",
  HTML(paste0('<svg class="brand-mark" viewBox="0 0 24 24" aria-hidden="true">',
    # Four tiles set together, a small mosaic: the app's namesake.
    '<rect x="3" y="3" width="8" height="8" rx="1.5"/>',
    '<rect x="13" y="3" width="8" height="8" rx="1.5" opacity="0.75"/>',
    '<rect x="3" y="13" width="8" height="8" rx="1.5" opacity="0.75"/>',
    '<rect x="13" y="13" width="8" height="8" rx="1.5" opacity="0.5"/></svg>')),
  tags$span(class = "app-name", APP_NAME))

# The General tab: the map, its reading panel, and the people table.
# This is the whole no-code experience the first persona needs.
general_tab <- nav_panel(
  title = "Explore",
  icon = NULL,
  div(class = "control-row",
    div(class = "control-group",
      tags$span(class = "group-label", "Network"),
      div(class = "control-items",
        div(class = "control",
          tags$label(`for` = "dataset", "Source"),
          selectInput("dataset", NULL, width = "230px", selectize = FALSE,
            choices = c("Your own data" = "upload",
                        "Product studio (sample)" = "org",
                        "Customer referrals (sample)" = "referral",
                        "Advice seeking, directed (sample)" = "advice",
                        "Messaging, directed (sample)" = "message"))
        ),
        conditionalPanel("input.dataset == 'upload'",
          div(class = "control",
            tags$label(`for` = "edges_file", "Tie list (CSV)"),
            uiOutput("file_input_ui")
          )
        ),
        div(class = "control",
          tags$label("Your work"),
          div(class = "btn-cluster",
            downloadButton("dl_session", "Save", class = "btn"),
            uiOutput("resume_input_ui")
          )
        )
      )
    ),
    uiOutput("view_controls"),
    # These three act on the whole view rather than on one part of it,
    # so they are grouped together and set apart from the controls that
    # change what the map shows. Full screen keeps its id here because
    # a keyboard reader meets this row before the map, and the copy on
    # the map is the one a mouse finds.
    div(class = "control-group actions",
      tags$span(class = "group-label", "Whole view"),
      div(class = "control-items",
        tags$button(id = "fs-toggle", type = "button", class = "btn",
                    `data-fs-toggle` = NA,
                    `aria-pressed` = "false", "Full screen"),
        actionButton("clear_pick", "Show everyone", class = "btn"),
        actionButton("reset_all", "Reset", class = "btn btn-quiet")
      )
    )
  ),
  htmlOutput("legend"),
  div(class = "main-grid",
    div(class = "map-panel",
      div(id = "map-host"),
      uiOutput("empty_state")
    ),
    div(class = "reading-panel", uiOutput("reading"))
  ),
  uiOutput("people_section")
)

# The Researcher tab: full diagnostics, the community algorithm menu,
# the dyad and triad census, and a one-click reproducible script. Every
# number here is classical graph statistics, computed on demand.
research_tab <- nav_panel(
  title = "Research",
  uiOutput("research_body")
)

# The Overview tab: what the app is, what it gives back, and what it
# asks for, all readable before anything is loaded. It sits leftmost
# because a person who has just arrived has none of that yet.
overview_tab <- nav_panel(
  title = "Overview",
  div(class = "overview", overview_body())
)

# The Statistics tab. The Research tab says what is in the network; this
# one asks whether it is more than the size and density would give on
# their own. Nothing here runs until it is asked to, because several
# hundred random networks take real seconds and a tab that starts
# computing the moment it is opened reads as one that has hung.
statistics_tab <- nav_panel(
  title = "Statistics",
  div(class = "stats-page",
    div(class = "stats-intro",
      tags$h2("Is this more than chance would give?"),
      tags$p(paste(
        "Every number in the Research tab describes what is in front of",
        "you. A network of this size at this density already has a",
        "clustering, a centralization, and a group separation before",
        "anyone has done anything social, so a number on its own cannot",
        "tell you whether the pattern means something.")),
      tags$p(paste(
        "The tests below compare what was measured against many random",
        "networks that hold one feature of yours fixed. This is the",
        "conditional uniform graph test, standard in network analysis",
        "since Anderson, Butts, and Carley showed in 1999 how strongly",
        "size and density alone drive these measures."))),
    div(class = "stats-controls",
      div(class = "control",
        tags$label(`for` = "stat_null", "Hold fixed"),
        selectInput("stat_null", NULL, selectize = FALSE, width = "260px",
          choices = c("Number of people and ties" = "edges",
                      "Each person's number of ties" = "degree"))),
      div(class = "control",
        tags$label(`for` = "stat_reps", "Random networks"),
        selectInput("stat_reps", NULL, selectize = FALSE, width = "180px",
          choices = STAT_REPS, selected = 500)),
      div(class = "control",
        tags$label("Run"),
        actionButton("run_stats", "Run the tests", class = "btn btn-primary"))
    ),
    tags$p(class = "helper-note stats-null-note", paste(
      "Holding the number of people and ties fixed asks whether the",
      "pattern exceeds what this much connection would give. Holding",
      "each person's number of ties fixed asks a harder question:",
      "whether it exceeds what these particular people, with exactly",
      "the ties they each have, would give. A result that survives the",
      "second is a claim about arrangement rather than about volume.")),
    uiOutput("stats_body"))
)

ui <- page_navbar(
  title = brand_title,
  id = "main_nav",
  theme = bs_theme(version = 5),
  window_title = APP_NAME,
  fillable = FALSE,
  header = tags$head(
    # Runs before the first paint so the page never flashes the wrong
    # mode and the toggle always agrees with what is on screen.
    tags$script(HTML(
      "document.documentElement.setAttribute('data-bs-theme', 'dark');")),
    tags$link(rel = "stylesheet", href = asset_url("styles.css")),
    tags$script(src = asset_url("layout.js")),
    tags$script(src = asset_url("graph.js")),
    tags$script(src = asset_url("tables.js")),
    tags$script(src = asset_url("theme.js")),
    tags$meta(name = "viewport",
              content = "width=device-width, initial-scale=1")
  ),
  overview_tab,
  general_tab,
  research_tab,
  statistics_tab,
  nav_spacer(),
  # Four links became two groups. The walkthrough is help, so it lives
  # inside Help rather than beside it, and the appearance toggle is a
  # setting, so it lives inside Settings. What is left is one thing the
  # app can set up for you and two places to look things up, with a gap
  # between them because they are different kinds of thing.
  nav_item(actionLink("open_models", "Local models")),
  nav_item(tags$span(class = "nav-gap", `aria-hidden` = "true")),
  nav_item(actionLink("open_help", "Help")),
  nav_item(actionLink("open_settings", "Settings"))
)

server <- function(input, output, session) {

  # Session state. Model output is held apart from the reading panel so
  # the computed prose is never overwritten or lost, and the file input
  # seed lets a reset rebuild that control from scratch.
  model_text <- reactiveVal(NULL)
  file_input_seed <- reactiveVal(0)

  # The walkthrough runs on a first visit only. The browser reports
  # whether it has been seen before, since Shiny itself keeps nothing
  # between sessions. The header link opens it again at any time.
  tour_step <- reactiveVal(1)
  observeEvent(input$tour_seen, {
    if (!isTRUE(input$tour_seen)) show_tour()
  }, once = TRUE)

  show_tour <- function() {
    slides <- tour_slides()
    i <- tour_step()
    s <- slides[[i]]
    dots <- paste(vapply(seq_along(slides), function(j) {
      sprintf('<span class="tour-dot%s"></span>',
              if (j == i) " on" else "")
    }, ""), collapse = "")
    showModal(modalDialog(
      class = "tour-modal",
      HTML(s$art),
      tags$h2(class = "tour-title", s$title),
      tags$p(class = "tour-text", s$text),
      HTML(paste0('<div class="tour-dots">', dots, "</div>")),
      footer = tagList(
        if (i > 1) actionButton("tour_back", "Back", class = "btn"),
        if (i < length(slides))
          actionButton("tour_next", "Next", class = "btn btn-primary")
        else
          actionButton("tour_done", "Start", class = "btn btn-primary"),
        modalButton("Skip")
      ),
      easyClose = TRUE, size = "m"
    ))
  }
  observeEvent(input$open_tour, { tour_step(1); show_tour() })

  # The Overview buttons are shortcuts into the two things a new reader
  # would otherwise have to find for themselves: a loaded network, and
  # the walkthrough. Both bottom and top copies of the sample button do
  # the same thing, so the reader does not have to scroll back up.
  open_sample <- function() {
    updateSelectInput(session, "dataset", selected = "org")
    nav_select("main_nav", "Explore", session = session)
  }
  observeEvent(input$ov_open_sample, open_sample())
  observeEvent(input$ov_open_tour, { tour_step(1); show_tour() })
  observeEvent(input$tour_back, { tour_step(tour_step() - 1); show_tour() })
  observeEvent(input$tour_next, { tour_step(tour_step() + 1); show_tour() })
  observeEvent(input$tour_done, {
    session$sendCustomMessage("tour-seen", TRUE)
    removeModal()
  })

  # Uploads fail politely. The reader learns what the file needs, not
  # what the parser choked on.
  # An upload is parsed here and nowhere else, so there is one place
  # where a bad file is turned into a sentence a person can act on.
  uploaded <- reactive({
    req(input$edges_file)
    out <- try(read_csv(input$edges_file$datapath, show_col_types = FALSE,
                        progress = FALSE), silent = TRUE)
    if (inherits(out, "try-error") || ncol(out) < 2) {
      showNotification(
        "That file could not be read. It needs at least two columns: who the tie is from and who it is to.",
        type = "error", duration = 8)
      return(NULL)
    }
    out
  })

  # The chosen network before any filtering. Kept separate from edges()
  # below so the strength filter can be adjusted without the sample data
  # being rebuilt on every move of the control.
  edges_raw <- reactive({
    # The select input has not reported yet on the first pass through
    # this, so the choice is NULL rather than a name. switch() needs one
    # value and raises on anything else, and the raise happens inside a
    # reactive four levels below an observer, so what reaches the log
    # names neither the control nor the screen. There is no network to
    # read before a choice arrives, so the answer is nothing.
    dataset <- input$dataset
    if (is.null(dataset) || length(dataset) != 1 || is.na(dataset)) {
      return(NULL)
    }
    switch(dataset,
      org      = sample_org_network(),
      referral = sample_referral_network(),
      advice   = sample_advice_network(),
      message  = sample_message_network(),
      upload   = { if (is.null(input$edges_file)) NULL else uploaded() },
      resumed  = resumed_edges()
    )
  })

  # The tie strength filter recomputes everything rather than hiding
  # lines, because a map whose numbers disagree with its picture would
  # be worse than no filter at all.
  edges <- reactive({
    ed <- edges_raw()
    if (is.null(ed)) return(NULL)
    t <- input$min_weight %||% 1
    if (ncol(ed) >= 3 && t > 1) {
      # Subsetting a data frame drops attributes that are not part of
      # the frame, and the direction flag is one of them, so it is put
      # back rather than quietly lost on the first move of the strength
      # control.
      was_directed <- isTRUE(attr(ed, "directed"))
      keep <- suppressWarnings(as.numeric(ed[[3]]))
      ed <- ed[!is.na(keep) & keep >= t, ]
      if (was_directed) attr(ed, "directed") <- TRUE
    }
    ed
  })

  # One reactive holds everything computed for the current network, so
  # the map, the prose, and the table always agree with each other.
  # bundle() answers NULL rather than canceling when no data exists, so
  # the empty state can ask the question and draw itself.
  bundle <- reactive({
    ed <- edges()
    if (is.null(ed) || nrow(ed) == 0) return(NULL)
    g <- try(build_graph(ed), silent = TRUE)
    if (inherits(g, "try-error")) {
      showNotification(attr(g, "condition")$message,
                       type = "error", duration = 8)
      return(NULL)
    }
    metrics <- compute_metrics(g)
    layout  <- compute_layout(metrics$graph)
    payload <- graph_payload(metrics, layout)
    list(metrics = metrics, payload = payload,
         groups = payload$nodes$group)
  })

  # The browser gets the whole graph once per dataset, converted to row
  # records at the door (see payload_wire). Cosmetic switches ride their
  # own messages so the map never recomputes for them.
  observe({
    b <- bundle()
    if (is.null(b)) {
      session$sendCustomMessage("clear-graph", list())
    } else {
      session$sendCustomMessage("graph-data", payload_wire(b$payload))
    }
  })
  # Each of these switches changes how the map looks and nothing about
  # what it means, so they travel as their own small messages. Sending
  # them through the graph payload instead would rebuild the layout and
  # move every node, which reads as the map having changed its mind.
  observeEvent(input$size_by, {
    session$sendCustomMessage("size-by", input$size_by)
  })
  observeEvent(input$label_mode, {
    session$sendCustomMessage("label-mode", input$label_mode)
  })
  observeEvent(input$reach_depth, {
    session$sendCustomMessage("reach-depth", input$reach_depth)
  })
  # The clear button exists for keyboard and screen reader users, who
  # have no open canvas to click.
  observeEvent(input$clear_pick, {
    session$sendCustomMessage("clear-selection", list())
    updateSelectInput(session, "person_pick", selected = "")
  })
  observeEvent(input$legend_group, {
    session$sendCustomMessage("focus-group", input$legend_group)
  })

  # Finding a person by name and clicking a person chip both route
  # through the same door as a map click, so the reading panel cannot
  # disagree about who is chosen.
  observeEvent(input$person_pick, {
    req(input$person_pick != "")
    b <- bundle()
    req(b)
    id <- b$payload$nodes |> filter(label == input$person_pick) |> pull(id)
    if (length(id) == 1) session$sendCustomMessage("select-node", id)
  })
  observeEvent(input$chip_person, {
    b <- bundle()
    req(b)
    id <- b$payload$nodes |> filter(label == input$chip_person) |> pull(id)
    if (length(id) == 1) session$sendCustomMessage("select-node", id)
  })

  # The file input is rendered rather than fixed so that a reset can
  # replace it, which is the only way to clear the file a browser
  # remembers having chosen.
  output$file_input_ui <- renderUI({
    file_input_seed()
    fileInput("edges_file", NULL, accept = ".csv", width = "260px",
              buttonLabel = "Browse", placeholder = "No file yet")
  })

  # Reset returns the app to the state it opens in. The dataset goes
  # back to the upload choice rather than to a sample, because a person
  # who presses Reset is usually clearing data that is not theirs off the
  # screen and a sample network appearing in its place reads as a
  # failure to clear.
  observeEvent(input$reset_all, {
    updateSelectInput(session, "dataset", selected = "upload")
    file_input_seed(file_input_seed() + 1)
    session$sendCustomMessage("clear-graph", list())
    model_text(NULL)
    showNotification("Cleared. Choose a network or upload your own.",
                     type = "message", duration = 4)
  })

  # The view controls only exist once a network does. Controls that sit
  # there disabled invite a reader to work out why, which is attention
  # spent on the interface rather than on the network.
  output$view_controls <- renderUI({
    b <- bundle()
    if (is.null(b)) return(NULL)
    nms <- sort(b$payload$nodes$label)
    div(class = "control-group",
      tags$span(class = "group-label", "Reading the map"),
      div(class = "control-items",
        div(class = "control",
          tags$label(`for` = "size_by", "Size by"),
          selectInput("size_by", NULL, choices = size_choices,
                      width = "190px", selectize = FALSE)),
        div(class = "control",
          tags$label(`for` = "label_mode", "Names"),
          selectInput("label_mode", NULL, choices = label_choices,
                      width = "140px", selectize = FALSE)),
        div(class = "control",
          tags$label(`for` = "person_pick", "Find a person"),
          selectInput("person_pick", NULL, selectize = FALSE,
                      width = "170px", choices = c("Choose" = "", nms))),
        div(class = "control",
          tags$label(`for` = "tie_marks", "Mark ties"),
          selectInput("tie_marks", NULL, selectize = FALSE, width = "180px",
                      choices = c("None" = "none",
                                  "Only routes (bridges)" = "bridges",
                                  "Ties between groups" = "crossing"))),
        uiOutput("weight_filter_ui")
      )
    )
  })

  output$weight_filter_ui <- renderUI({
    ed <- edges_raw()
    if (is.null(ed) || ncol(ed) < 3) return(NULL)
    w <- suppressWarnings(as.numeric(ed[[3]]))
    top <- max(w, na.rm = TRUE)
    if (!is.finite(top) || top <= 1) return(NULL)
    div(class = "control control-slider",
      tags$label(`for` = "min_weight", "Least tie strength"),
      sliderInput("min_weight", NULL, min = 1, max = ceiling(top),
                  value = 1, step = 1, ticks = FALSE, width = "160px")
    )
  })

  output$legend <- renderUI({
    b <- bundle()
    if (is.null(b)) return(NULL)
    counts <- table(b$groups)
    chips <- paste(vapply(as.integer(names(counts)), function(gp) {
      legend_chip(gp, as.integer(counts[as.character(gp)]))
    }, ""), collapse = "")
    extra <- paste0(
      '<span class="legend-item static"><svg width="20" height="20">',
      '<circle cx="10" cy="10" r="5" class="mark" fill="none" stroke="currentColor"></circle>',
      '<circle cx="10" cy="10" r="9" fill="none" stroke="currentColor" stroke-dasharray="4 3"></circle>',
      "</svg>Single point of failure</span>")
    HTML(paste0('<div class="legend">', chips, extra, "</div>"))
  })

  # The empty state is the first screen most people meet, since the app
  # opens on Your own data. It carries the whole path forward: what to
  # prepare, where to drop it, and two one click ways to look around.
  output$empty_state <- renderUI({
    if (!is.null(bundle())) return(NULL)
    div(class = "empty-state",
      HTML(stage(paste0(
        tie(105, 70, 160, 100), tie(160, 100, 220, 68),
        tie(160, 100, 160, 140),
        dot(105, 70, 11, "n1"), dot(220, 68, 11, "n2"),
        dot(160, 140, 9, "n3"), dot(160, 100, 14, "lit")
      ))),
      tags$h2("Map your own people"),
      tags$p(paste("Prepare a CSV with two or three columns: who the tie",
                   "is from, who it is to, and, if you have it, the tie",
                   "strength. Then choose Browse above, or start with a",
                   "sample:")),
      div(class = "empty-actions",
        actionButton("try_org", "Try the product studio", class = "btn"),
        actionButton("try_ref", "Try the referrals", class = "btn")
      ),
      tags$p(class = "caveat-line",
             "Your file stays on this machine. Nothing is sent anywhere.")
    )
  })
  # The two sample networks are offered from the empty state as well as
  # from the dataset menu, since a person looking at an empty map is
  # further from that menu than the screen makes it look.
  observeEvent(input$try_org, {
    updateSelectInput(session, "dataset", selected = "org")
  })
  observeEvent(input$try_ref, {
    updateSelectInput(session, "dataset", selected = "referral")
  })

  # The reading panel. Cards for the whole network, one card plus
  # controls for a chosen person. Person names inside cards are buttons
  # that select that person on the map.
  # The route finder. Tracing a path between two people by eye is
  # guesswork on any map with more than a dozen people on it, and it is
  # the question people ask of a network picture more than any other.
  # The answer is computed where the graph is and shown on the map.
  output$route_ui <- renderUI({
    b <- bundle()
    if (is.null(b)) return(NULL)
    nms <- sort(b$metrics$names)
    div(class = "route-box",
      tags$h3("Trace a route"),
      div(class = "route-picks",
        selectInput("route_from", "From", selectize = FALSE,
                    choices = c("Choose" = "", nms), width = "100%"),
        selectInput("route_to", "To", selectize = FALSE,
                    choices = c("Choose" = "", nms), width = "100%")),
      div(class = "btn-cluster",
        actionButton("route_go", "Show the route", class = "btn"),
        actionButton("route_clear", "Clear", class = "btn btn-quiet")),
      uiOutput("route_result"))
  })

  route_text <- reactiveVal(NULL)

  observeEvent(input$route_go, {
    b <- bundle(); req(b)
    a <- input$route_from
    z <- input$route_to
    if (is.null(a) || is.null(z) || !nzchar(a) || !nzchar(z)) {
      route_text(list(ok = FALSE, text = "Choose two people first."))
      return(NULL)
    }
    res <- shortest_route(b$metrics, a, z)
    if (!isTRUE(res$ok)) {
      route_text(list(ok = FALSE, text = res$message))
      session$sendCustomMessage("clear-route", TRUE)
      return(NULL)
    }
    route_text(list(ok = TRUE, names = res$names, length = res$length))
    session$sendCustomMessage("show-route",
      list(ids = res$ids, steps = res$steps))
  })

  observeEvent(input$route_clear, {
    route_text(NULL)
    updateSelectInput(session, "route_from", selected = "")
    updateSelectInput(session, "route_to", selected = "")
    session$sendCustomMessage("clear-route", TRUE)
  })

  output$route_result <- renderUI({
    res <- route_text()
    if (is.null(res)) return(NULL)
    if (!isTRUE(res$ok)) return(tags$p(class = "route-note", res$text))
    tagList(
      tags$p(class = "route-note", sprintf(
        "%d %s apart. The route runs:",
        res$length, if (res$length == 1) "step" else "steps")),
      div(class = "route-chain", lapply(seq_along(res$names), function(i) {
        tagList(
          tags$span(class = "route-stop", res$names[i]),
          if (i < length(res$names)) {
            tags$span(class = "route-arrow", HTML("&rarr;"))
          })
      })),
      tags$p(class = "route-caveat", paste(
        "One of possibly several shortest routes. It says these people",
        "are this far apart in recorded ties, not that anything travels",
        "this way.")))
  })

  observeEvent(input$tie_marks, {
    session$sendCustomMessage("tie-marks", input$tie_marks)
  })

  # One card. The numbers come first and the prose underneath, so a
  # reader who wants the figure does not have to read a paragraph to
  # find it, and a reader who wants the meaning has it in the same
  # place. Names inside a card are buttons rather than plain text
  # because every name in this panel is somewhere on the map.
  card_ui <- function(card) {
    stats <- if (length(card$stats) > 0) {
      div(class = "stat-row", lapply(card$stats, function(s) {
        div(class = "stat",
            tags$span(class = "stat-value", s$value),
            tags$span(class = "stat-label", s$label))
      }))
    }
    # The prose is split after its first sentence. The opening sentence
    # is the finding; the rest is the qualification, which matters but
    # does not have to be read before the next card can be reached. Four
    # cards of full paragraphs is a wall, and a reader facing a wall
    # skips all of it rather than some of it. Nothing is removed, and
    # the rest is one click away with no round trip to the server.
    split_prose <- function(text) {
      cut <- regexpr("(?<=[.?!]) ", text, perl = TRUE)
      if (cut < 1) return(list(lead = text, rest = ""))
      list(lead = substr(text, 1, cut - 1),
           rest = substr(text, cut + 1, nchar(text)))
    }
    parts <- split_prose(card$prose)
    prose <- if (nchar(parts$rest) == 0) {
      tags$p(class = "card-prose", parts$lead)
    } else {
      tagList(
        tags$p(class = "card-prose", parts$lead),
        tags$details(class = "card-more",
          tags$summary("More on this"),
          tags$p(class = "card-prose", parts$rest))
      )
    }
    # The name travels as an attribute and a listener in tables.js reads
    # it. Building a line of script around it instead would mean a name
    # from an uploaded file ending up inside the code that runs when the
    # control is pressed, and no amount of quoting that name is worth
    # trusting when the alternative is not to put it there at all.
    chips <- if (length(card$people) > 0) {
      div(class = "chip-row", lapply(card$people, function(nm) {
        tags$button(type = "button", class = "person-chip",
          `data-person` = nm,
          `aria-label` = paste("Focus the map on", nm), nm)
      }))
    }
    div(class = "card",
        tags$h3(card$title), stats, prose, chips)
  }

  output$reading <- renderUI({
    b <- bundle()
    if (is.null(b)) {
      return(div(class = "card muted-card",
        tags$h3("What this network says"),
        tags$p(paste("Once a network loads, this panel explains it in",
                     "plain English: its shape, its groups, who holds it",
                     "together, and where it is fragile."))))
    }
    sel <- input$selected_node
    if (is.null(sel) || length(sel) == 0 || is.na(sel)) {
      cards <- describe_cards(b$metrics, b$groups)
      tagList(
        lapply(cards, card_ui),
        uiOutput("route_ui"),
        div(class = "panel-foot",
          uiOutput("model_controls"),
          htmlOutput("model_out"),
          div(class = "caveat", caveat_line())
        )
      )
    } else {
      idx <- as.integer(sel)
      tagList(
        card_ui(person_card(b$metrics, idx, b$groups)),
        div(class = "card slim",
          tags$label(`for` = "reach_depth", "Reach shown on the map"),
          selectInput("reach_depth", NULL, selectize = FALSE,
                      width = "220px",
                      choices = c("Direct ties only" = 1,
                                  "Two steps out" = 2),
                      selected = isolate(input$reach_depth) %||% 1),
          actionButton("back_all", "Back to the whole network",
                       class = "btn")
        ),
        uiOutput("route_ui"),
        div(class = "panel-foot",
          uiOutput("model_controls"),
          htmlOutput("model_out"),
          div(class = "caveat", caveat_line())
        )
      )
    }
  })
  observeEvent(input$back_all, {
    session$sendCustomMessage("clear-selection", list())
    updateSelectInput(session, "person_pick", selected = "")
  })

  # The model is asked to restate prose that has already been computed
  # and displayed. It never sees the network, never produces a number,
  # and its answer appears beneath the computed text rather than in
  # place of it, so a reader can always compare the two.
  observeEvent(input$ask_model, {
    b <- bundle()
    req(b)
    # A reader who presses this without a model set up gets the setup
    # screen one press away, in the same place, rather than a sentence
    # saying something is wrong and nothing to do about it.
    status <- ollama_status(pref_url())
    if (!isTRUE(status$running)) {
      model_text(list(ok = FALSE, text = paste(
        "No local model is answering at this address. Setting one up",
        "takes a few minutes and happens entirely on this machine.")))
      return(NULL)
    }
    # A server can be answering while holding nothing, or holding a
    # different model than the one named in settings, and those are
    # three different problems with three different fixes.
    wanted <- input$restate_model %||% pref_model()
    present <- sub(":.*$", "", status$models)
    if (length(status$models) > 0 && !(sub(":.*$", "", wanted) %in% present)) {
      model_text(list(ok = FALSE, text = paste0(
        "The runtime is answering but does not hold ", wanted,
        ". It holds ", paste(status$models, collapse = ", "),
        ". Change the model name in Settings, or download this one.")))
      return(NULL)
    }
    sel <- input$selected_node
    # Findings only, not the panel prose. The panel explains the app as
    # well as the network, and a model handed a definition restates it
    # as though it were a discovery.
    paras <- if (is.null(sel) || length(sel) == 0 || is.na(sel)) {
      model_facts(b$metrics, b$groups)
    } else {
      model_facts_person(b$metrics, as.integer(sel), b$groups)
    }
    withProgress(message = "Asking the local model", value = 0.4, {
      res <- rewrite_with_local_model(
        paras,
        pref_url(),
        input$restate_model %||% pref_model())
    })
    if (res$ok) {
      model_text(list(ok = TRUE, text = res$text,
                      model = input$restate_model %||% pref_model()))
      # The answer lands below the fold on all but the tallest windows,
      # so the panel is scrolled to it. A result a reader has to go
      # looking for reads as a control that did nothing.
      session$sendCustomMessage("scroll-to", "model-answer-block")
    } else {
      model_text(list(ok = FALSE, text = res$message))
    }
  })
  # Model output is held in its own reactive value rather than in the
  # reading panel, so switching people or measures cannot silently throw
  # away an answer the reader asked for.
  # The restate control, plus a chooser when the machine holds more than
  # one model. A reader who downloaded two of them did so in order to
  # compare, and sending them to Settings to type a name is not a
  # comparison.
  output$model_controls <- renderUI({
    held <- tryCatch(ollama_status(pref_url())$models,
                     error = function(e) character(0))
    tagList(
      div(class = "btn-cluster",
        actionButton("ask_model", "Restate with the local model",
                     class = "btn"),
        if (length(held) > 1) {
          selectInput("restate_model", NULL, selectize = FALSE,
                      width = "170px", choices = held,
                      selected = isolate(pref_model()))
        }),
      if (length(held) > 1) {
        tags$p(class = "model-hint",
               "Run it again with another model to compare the wording.")
      })
  })

  # The answer arrives as one string with blank lines in it. Presenting
  # that string as a single paragraph is what produced the wall in the
  # panel: no breaks, no heading, and no way to tell where the model's
  # words start. It is split on blank lines and labeled with the model
  # that produced it, so the reader can see whose wording they are
  # reading and compare two runs.
  output$model_out <- renderUI({
    answer <- model_text()
    if (is.null(answer)) return(NULL)
    if (!isTRUE(answer$ok)) {
      return(div(class = "model-trouble",
        tags$p(class = "model-answer", answer$text),
        actionButton("open_setup", "Set up a local model",
                     class = "btn btn-primary")))
    }
    parts <- unlist(strsplit(answer$text, "\n[[:space:]]*\n"))
    parts <- trimws(parts)
    parts <- parts[nzchar(parts)]
    # Splitting on blank lines is only as good as the model's obedience,
    # and a model that returns three paragraphs of nine sentences each
    # is still handing back slabs. Every paragraph over roughly three
    # hundred characters is cut again at sentence boundaries into pieces
    # of two or three sentences, which is the length prose has to be
    # before a reader will take it in on a screen.
    reflow <- function(part) {
      if (nchar(part) <= 300) return(part)
      sentences <- unlist(strsplit(part, "(?<=[.?!]) ", perl = TRUE))
      if (length(sentences) < 3) return(part)
      groups <- split(sentences, ceiling(seq_along(sentences) / 2))
      vapply(groups, paste, "", collapse = " ")
    }
    parts <- unlist(lapply(parts, reflow), use.names = FALSE)
    # Bullet like lines the model produced on its own are kept as a list
    # rather than flattened into prose, since a model asked to restate
    # four findings sometimes numbers them and that structure is worth
    # keeping when it appears.
    is_item <- grepl("^([0-9]+[.)]|[-*\u2022])\\s", parts)
    div(id = "model-answer-block", class = "model-answer-block",
      div(class = "model-answer-head",
        tags$span(class = "model-badge", answer$model %||% "local model"),
        tags$span(class = "model-note", "A rewording. The numbers above are the computed ones.")),
      lapply(seq_along(parts), function(i) {
        if (is_item[i]) {
          tags$p(class = "model-answer model-item",
                 sub("^([0-9]+[.)]|[-*\u2022])\\s+", "", parts[i]))
        } else {
          tags$p(class = "model-answer", parts[i])
        }
      }))
  })

  # The local model guide. Everything a first time reader needs, in the
  # order they will ask: what is this, is it safe, how do I set it up,
  # which one should I pick.
  # The local model screen. It was one long column holding an
  # explanation, a numbered list, a live setup panel, and four model
  # cards, which is four documents in a dialog and a great deal of
  # scrolling. It is three steps now, each one a thing to decide, with
  # the state of the machine reported at the top so a reader can see
  # which step they are actually on.
  show_models_modal <- function() {
    showModal(modalDialog(
      class = "models-modal", size = "l",
      tags$h2("Set up a local language model"),
      tags$p(class = "modal-lede", paste0(
        "Optional. A model rewords the reading panel in its own voice ",
        "and never changes a number. Nothing in ", APP_NAME,
        " depends on one, and everything below happens on this machine.")),
      uiOutput("model_setup"),
      footer = modalButton("Close"), easyClose = TRUE
    ))
  }

  # ---- Local model setup --------------------------------------------
  # Three steps rather than one column, since an explanation, a
  # numbered list, a live panel, and four model cards stacked on each
  # other is four documents in a dialog.
  #
  # Which step a reader is on is a fact about the machine rather than
  # something to click through, so it is computed from what is actually
  # installed and running rather than remembered.
  setup_note <- reactiveVal(NULL)
  machine <- reactiveVal(NULL)
  setup_tick <- reactiveVal(0)

  runtime_now <- reactive({
    setup_tick()
    runtime_state(pref_url())
  })

  output$model_setup <- renderUI({
    st <- runtime_now()
    route <- input$setup_route %||% prefs$setup_route
    rep <- machine()
    opts <- model_options()

    state_of <- c(
      route = "done",
      runtime = if (st$running) "done" else if (st$installed) "part" else "now",
      model = if (length(st$models) > 0) "done"
              else if (st$installed) "now" else "wait"
    )

    step <- function(number, key, title, body) {
      state <- state_of[[key]]
      div(class = paste0("setup-step is-", state),
        div(class = "step-head",
          tags$span(class = "step-number", number),
          tags$h3(title),
          tags$span(class = "step-state", switch(state,
            done = "Done", part = "Almost", wait = "Waiting", "Now"))),
        div(class = "step-body", body))
    }

    status_line <- if (st$running) {
      div(class = "setup-status ready",
        tags$strong("A runtime is answering on this machine."),
        if (length(st$models) > 0) {
          tags$span(paste("Models present:", paste(st$models, collapse = ", ")))
        } else {
          tags$span("No model has been downloaded into it yet.")
        })
    } else if (st$installed) {
      div(class = "setup-status partial",
        tags$strong("The runtime is installed but not answering."),
        tags$span("Starting it takes a few seconds."))
    } else {
      div(class = "setup-status missing",
        tags$strong("No runtime found on this machine."),
        tags$span("Nothing is installed and nothing has been downloaded."))
    }

    route_body <- tagList(
      radioButtons("setup_route", NULL,
        choiceNames = list(
          "Guided. Tessera checks and tells you what to run.",
          "Managed. Tessera downloads and runs the runtime itself."),
        choiceValues = c("guided", "managed"),
        selected = route),
      if (identical(route, "managed")) {
        tags$p(class = "step-note", paste(
          "The download goes into a folder belonging to this app.",
          "Nothing is installed into the system, and deleting that",
          "folder undoes all of it."))
      } else {
        tags$p(class = "step-note", paste(
          "Tessera runs nothing on your behalf in this route. It only",
          "checks whether the runtime has appeared."))
      })

    runtime_body <- if (identical(route, "managed") && st$managed_available) {
      tagList(
        tags$p(if (is.na(st$managed_path)) {
          "Roughly a 500 MB download, once."
        } else {
          paste("Installed in this app's own folder at",
                st$managed_path, "and removable from here.")
        }),
        div(class = "btn-cluster",
          if (is.na(st$managed_path)) {
            actionButton("run_install", "Download and install",
                         class = "btn btn-primary")
          },
          actionButton("run_start", "Start it", class = "btn"),
          actionButton("run_recheck", "Check again", class = "btn"),
          if (!is.na(st$managed_path)) {
            actionButton("drop_runtime", "Remove the runtime",
                         class = "btn btn-quiet")
          }))
    } else if (identical(route, "managed")) {
      tagList(
        tags$p(paste(
          "A managed runtime is not offered on", st$platform$label,
          "because the vendor ships an installer there rather than an",
          "archive. The guided route works everywhere.")),
        div(class = "btn-cluster",
          actionButton("run_recheck", "Check again", class = "btn")))
    } else {
      tagList(
        tags$p("On this machine that is one line:"),
        tags$code(class = "pull-line", st$command),
        div(class = "btn-cluster",
          actionButton("run_recheck", "Check again", class = "btn")))
    }

    fits <- if (is.null(rep)) NULL else model_fit(rep)
    picked <- input$pull_choice %||%
      (if (is.null(rep)) "" else recommended_model(rep))
    model_body <- tagList(
      if (is.null(rep)) {
        div(class = "setup-scan",
          tags$p(paste(
            "Tessera can check this machine so the list says which models",
            "will run well here. It reads the operating system, the",
            "memory, the core count, and whether a graphics processor is",
            "present. Nothing else, and nothing leaves this machine.")),
          actionButton("scan_machine", "Check this machine", class = "btn"))
      } else {
        div(class = "setup-scan done",
          tags$p(sprintf("%s, %s of memory, %s cores%s.",
            rep$os,
            if (is.finite(rep$ram_gb)) paste0(rep$ram_gb, " GB") else "unknown",
            if (is.finite(rep$cores)) rep$cores else "an unknown number of",
            if (isTRUE(rep$accelerated)) ", with graphics acceleration" else "")),
          tags$p(class = "setup-pick",
                 paste("Suggested here:", recommended_model(rep))))
      },
      div(class = "model-grid", role = "radiogroup",
          `aria-label` = "Choose a model",
          lapply(seq_along(opts), function(i) {
        m <- opts[[i]]
        fit <- if (is.null(fits)) NULL else fits[i]
        chosen <- identical(picked, m$id)
        held <- any(sub(":.*$", "", st$models) == m$id)
        tags$button(type = "button",
          class = paste0("model-card",
            if (is.null(fit)) "" else paste0(" fit-", gsub(" ", "-", fit)),
            if (chosen) " selected" else "",
            if (held) " held" else ""),
          role = "radio",
          `aria-checked` = if (chosen) "true" else "false",
          # The identifier travels as an attribute and a listener reads
          # it, the same way the person chips work. These identifiers
          # come from a list in this repository rather than from a
          # reader, but a rule that holds only where it is convenient is
          # not a rule anyone can check.
          `data-model` = m$id,
          tags$h4(m$name),
          div(class = "card-flags",
            if (!is.null(fit)) tags$span(class = "fit", fit),
            if (held) tags$span(class = "held-flag", "Already downloaded")),
          tags$ul(tags$li(m$download), tags$li(m$memory), tags$li(m$speed)),
          tags$p(m$good),
          tags$p(class = "tradeoff", tags$strong("The catch: "), m$tradeoff))
      })),
      if (st$installed) {
        already <- nzchar(picked) &&
          any(sub(":.*$", "", st$models) == picked)
        div(class = "btn-cluster",
          if (already) {
            # Offering to download something that is already downloaded
            # is the app failing to read its own screen. The card says
            # it is present; the control should act on that.
            actionButton("use_model", paste("Use", picked),
                         class = "btn btn-primary")
          } else {
            actionButton("run_pull",
              if (nzchar(picked)) paste("Download", picked) else "Pick one above",
              class = if (nzchar(picked)) "btn btn-primary" else "btn",
              disabled = if (nzchar(picked)) NULL else NA)
          },
          if (already) {
            actionButton("run_pull", "Download it again", class = "btn")
          },
          if (already) {
            actionButton("drop_model", paste("Remove", picked),
                         class = "btn btn-quiet")
          })
      } else {
        tags$p(class = "step-note",
               "A model can be downloaded here once a runtime exists.")
      })

    tagList(
      status_line,
      div(class = "step-stack",
        step("1", "route", "Choose how to set it up", route_body),
        step("2", "runtime", "Get the runtime running", runtime_body),
        step("3", "model", "Pick and download a model", model_body)),
      if (!is.null(setup_note())) div(class = "setup-note", setup_note())
    )
  })

  observeEvent(input$setup_route, {
    write_prefs(list(setup_route = input$setup_route))
  }, ignoreInit = TRUE)

  observeEvent(input$scan_machine, machine(machine_report()))

  observeEvent(input$run_recheck, {
    setup_tick(setup_tick() + 1)
    setup_note(NULL)
  })

  # R answers one thing at a time, so a long install blocks every other
  # message from this session until it finishes. Presses that arrive
  # while it runs queue up and would otherwise start the work again the
  # moment it ended. The guard drops anything that arrives within a
  # minute of a run beginning, and the note says what is happening.
  run_started <- reactiveVal(0)

  too_soon <- function() {
    now <- as.numeric(Sys.time())
    if (now - run_started() < 60) return(TRUE)
    run_started(now)
    FALSE
  }

  observeEvent(input$run_install, {
    if (too_soon()) {
      setup_note(paste("That is already running. A first install takes",
                       "several minutes; the progress bar reports where",
                       "it has got to."))
      return(NULL)
    }
    withProgress(message = "Setting up the runtime", value = 0.1, {
      res <- managed_install(function(text) setProgress(detail = text))
      if (isTRUE(res$ok)) {
        setProgress(value = 0.8, detail = "Starting the server.")
        started <- managed_start(pref_url(),
                                 function(text) setProgress(detail = text))
        setup_note(paste(res$message, started$message))
      } else {
        setup_note(res$message)
      }
    })
    run_started(0)
    setup_tick(setup_tick() + 1)
  })

  observeEvent(input$run_start, {
    if (too_soon()) {
      setup_note("The server is already starting. Give it a moment.")
      return(NULL)
    }
    withProgress(message = "Starting the runtime", value = 0.5, {
      res <- managed_start(pref_url(),
                           function(text) setProgress(detail = text))
    })
    run_started(0)
    setup_note(res$message)
    setup_tick(setup_tick() + 1)
  })

  observeEvent(input$use_model, {
    name <- input$pull_choice
    req(name)
    pref_model(name)
    updateTextInput(session, "ollama_model", value = name)
    write_prefs(list(ollama_model = name))
    model_text(NULL)
    setup_note(paste(name, "is the model this app will use."))
  })

  # Removal asks first. A download can be repeated; a deletion of
  # several gigabytes that the reader did not mean to make cannot be
  # undone from here.
  observeEvent(input$drop_model, {
    name <- input$pull_choice
    req(name)
    showModal(modalDialog(
      title = paste("Remove", name),
      tags$p(paste("This deletes the model from the runtime's store on",
                   "this machine. It can be downloaded again from this",
                   "screen at any time.")),
      footer = tagList(
        modalButton("Keep it"),
        actionButton("drop_model_ok", paste("Remove", name),
                     class = "btn btn-primary"))
    ))
  })

  observeEvent(input$drop_model_ok, {
    name <- input$pull_choice
    removeModal()
    req(name)
    withProgress(message = paste("Removing", name), value = 0.5, {
      res <- remove_model(name)
    })
    setup_note(res$message)
    setup_tick(setup_tick() + 1)
    show_models_modal()
  })

  observeEvent(input$drop_runtime, {
    showModal(modalDialog(
      title = "Remove the runtime",
      tags$p(paste("This deletes the folder this app downloaded, along",
                   "with every model inside it. Nothing outside that",
                   "folder is touched, and it can be downloaded again",
                   "from this screen.")),
      footer = tagList(
        modalButton("Keep it"),
        actionButton("drop_runtime_ok", "Remove it", class = "btn btn-primary"))
    ))
  })

  observeEvent(input$drop_runtime_ok, {
    removeModal()
    withProgress(message = "Removing the runtime", value = 0.5, {
      res <- remove_runtime()
    })
    setup_note(res$message)
    setup_tick(setup_tick() + 1)
    show_models_modal()
  })

  observeEvent(input$run_pull, {
    name <- input$pull_choice
    req(name)
    withProgress(message = paste("Downloading", name), value = 0.3, {
      res <- pull_model(name, function(text) setProgress(detail = text))
    })
    setup_note(res$message)
    if (isTRUE(res$ok)) {
      pref_model(name)
      updateTextInput(session, "ollama_model", value = name)
      write_prefs(list(ollama_model = name))
      # The panel may be holding a complaint about a model that now
      # exists, and a stale complaint beside a working setup is worse
      # than no message at all.
      model_text(NULL)
    }
    setup_tick(setup_tick() + 1)
  })

  # Help opens as a dialog rather than as a tab. A tab would put it in
  # the same row as the two screens that do work, and help is not a
  # place to be; it is a thing to consult and leave.
  observeEvent(input$help_tour, {
    removeModal()
    tour_step(1)
    show_tour()
  })

  observeEvent(input$open_help, {
    showModal(modalDialog(
      class = "help-modal", size = "l",
      tags$h2("Help"),
      help_body(),
      footer = modalButton("Close"), easyClose = TRUE
    ))
  })

  observeEvent(input$open_models, show_models_modal())
  observeEvent(input$open_setup, {
    removeModal()
    show_models_modal()
  })

  # Settings live in a dialog so the main screen stays quiet. Theme and
  # palette apply as body classes; theme.js does the class work.
  observeEvent(input$open_settings, {
    showModal(modalDialog(
      title = "Settings",
      div(class = "settings-group",
        tags$span(class = "group-label", "Appearance"),
        div(class = "control-items",
          theme_toggle_button())),
      div(class = "palette-choices",
      radioButtons("palette", "Color settings",
        choiceNames = list(
          swatch_label("Standard", "standard",
                       "Twelve colors on twelve shapes."),
          swatch_label("Deuteranopia", "deutan",
                       "For readers who lose the red to green axis."),
          swatch_label("Protanopia", "protan",
                       "The same axis, with the red end darkened too."),
          swatch_label("Tritanopia", "tritan",
                       "For readers who lose the blue to yellow axis."),
          swatch_label("High contrast grays", "mono",
                       "No color at all. The shapes carry the groups.")),
        choiceValues = PALETTE_NAMES,
        selected = isolate(input$palette) %||% prefs$palette)),
      tags$p(class = "caveat", paste(
        "Deuteranopia and protanopia both lose the red to green axis,",
        "and they are separate settings here because the two lose it",
        "differently: under protanopia the red end also darkens, so a",
        "pair of colors that stays apart for one can collapse for the",
        "other.")),
      tags$hr(),
      tags$p(tags$strong("Local language model (optional)")),
      tags$p(class = "caveat",
        paste("When an Ollama server runs on this machine, the Restate",
              "button asks it to reword the reading panel. The Local",
              "models button in the header explains everything.")),
      textInput("ollama_url", "Address",
                value = isolate(pref_url())),
      textInput("ollama_model", "Model name",
                value = isolate(pref_model())),
      tags$hr(),
      tags$p(class = "colophon",
        HTML(paste0(
          APP_NAME, " ", APP_VERSION, ". Built with ",
          '<a href="https://www.r-project.org" target="_blank" ',
          'rel="noopener">R</a> and ',
          '<a href="https://shiny.posit.co" target="_blank" ',
          'rel="noopener">Shiny</a>, using igraph, tidygraph, ggraph, ',
          'and bslib. Copyright Abhik Roy, released under the ',
          '<a href="https://polyformproject.org/licenses/noncommercial/1.0.0" ',
          'target="_blank" rel="noopener">PolyForm Noncommercial ',
          "License 1.0.0</a>."))),
      footer = modalButton("Close"),
      easyClose = TRUE
    ))
  })
  # The header toggle drives the body class directly through theme.js;
  # the server only needs the value so downloads and the figure follow.
  # The palette radio in Settings still pushes its class from here.
  observeEvent(input$palette, {
    session$sendCustomMessage("set-palette", input$palette)
  })

  # ---- Downloads ----------------------------------------------------
  census_now <- reactive({
    b <- bundle()
    req(b)
    dyad_triad_census(b$metrics$digraph %||% b$metrics$graph)
  })

  # The census is recomputed here rather than reached for from the
  # research tab, so a download works whether or not that tab has been
  # opened in this session.
  # An undirected network has no census, so these controls are not on
  # the card for one. The handlers still write something a reader can
  # read rather than an empty file, since a download can be reached
  # from a saved link long after the card that offered it has gone.
  census_csv <- function(file, part) {
    census <- census_now()
    if (!isTRUE(census$directed) || NROW(census[[part]]) == 0) {
      writeLines(paste("This network is undirected, so it has no dyad or",
                       "triad census. Both describe direction."), file)
      return(invisible(NULL))
    }
    write.csv(census[[part]], file, row.names = FALSE)
  }

  output$dl_dyads <- downloadHandler(
    filename = function() "tessera-dyad-census.csv",
    content = function(file) census_csv(file, "dyads"))

  output$dl_triads <- downloadHandler(
    filename = function() "tessera-triad-census.csv",
    content = function(file) census_csv(file, "triads"))

  # Everything at once. A reader who has finished with a network wants
  # the whole of it in one place, and assembling nine downloads by hand
  # is how a file goes missing from a report.
  #
  # The archive is built in a temporary directory and holds only what
  # this session actually has: the statistics go in when they have been
  # run, and the figure only when ggplot2 can draw it.
  output$dl_everything <- downloadHandler(
    filename = function() {
      paste0("tessera-outputs-", format(Sys.Date(), "%Y-%m-%d"), ".zip")
    },
    content = function(file) {
      b <- bundle()
      req(b)
      dir <- file.path(tempdir(), paste0("tessera-", as.integer(Sys.time())))
      dir.create(dir, recursive = TRUE, showWarnings = FALSE)
      on.exit(unlink(dir, recursive = TRUE), add = TRUE)

      written <- character(0)
      put <- function(name, writer) {
        path <- file.path(dir, name)
        ok <- tryCatch({ writer(path); TRUE }, error = function(e) FALSE)
        if (ok && file.exists(path)) written <<- c(written, name)
      }

      put("people.csv", function(p) {
        b$payload$nodes |>
          transmute(
            name = label, direct_ties = degree,
            between_groups = between, quick_reach = close,
            well_connected_circle = eigen, group,
            single_point_of_failure = is_cut) |>
          write_csv(p)
      })
      put("summary.txt", function(p) {
        cards <- describe_cards(b$metrics, b$groups)
        lines <- unlist(lapply(cards, function(cd) c(cd$title, cd$prose, "")))
        writeLines(c(lines, caveat_line()), p)
      })
      put("diagnostics.csv", function(p) {
        write.csv(global_diagnostics(b$metrics$graph, b$metrics$membership),
                  p, row.names = FALSE)
      })
      put("centralities.csv", function(p) {
        write.csv(extended_centralities(b$metrics$graph), p,
                  row.names = FALSE)
      })
      put("dyad-census.csv", function(p) {
        write.csv(census_now()$dyads, p, row.names = FALSE)
      })
      put("triad-census.csv", function(p) {
        write.csv(census_now()$triads, p, row.names = FALSE)
      })
      put("ties.csv", function(p) write.csv(edges(), p, row.names = FALSE))
      put("analysis-igraph.R", function(p) {
        writeLines(export_script(input$community_method %||% "louvain",
                                 input$size_by %||% "degree", "igraph"), p)
      })
      put("analysis-tidy.R", function(p) {
        writeLines(export_script(input$community_method %||% "louvain",
                                 input$size_by %||% "degree", "tidy"), p)
      })
      put("map.png", function(p) {
        title <- dataset_title(input$dataset)
        ggplot2::ggsave(p,
          plot = network_figure(b$payload, input$palette %||% "standard",
                                title),
          width = 9, height = 7.5, dpi = 200, bg = "white")
      })
      stats <- stats_result()
      if (!is.null(stats) && is.null(stats$error)) {
        put("statistics.csv", function(p) {
          write.csv(stats$table, p, row.names = FALSE)
        })
      }
      put("README.txt", function(p) {
        writeLines(c(
          paste(APP_NAME, APP_VERSION, "outputs"),
          format(Sys.time(), "%Y-%m-%d %H:%M"),
          "",
          "This archive holds everything this session produced.",
          "",
          paste("Files:", paste(written, collapse = ", ")),
          "",
          caveat_line()), p)
      })

      old_wd <- setwd(dir)
      on.exit(setwd(old_wd), add = TRUE)
      utils::zip(file, files = list.files(dir), flags = "-r9Xq")
    })

  # ---- The statistics tab -------------------------------------------
  # Held in a reactive value rather than computed on demand, so the
  # results stay on screen while a reader reads them and do not vanish
  # the moment an unrelated control moves.
  stats_result <- reactiveVal(NULL)

  # Running is a deliberate act. Several hundred random networks take
  # real seconds, and R answers one thing at a time, so a tab that
  # started computing on arrival would look like one that had hung.
  observeEvent(input$run_stats, {
    b <- bundle()
    if (is.null(b)) {
      showNotification("Load a network first.", type = "message")
      return(NULL)
    }
    reps <- as.integer(input$stat_reps %||% 500)
    # The progress bar follows the run rather than sitting at a fifth of
    # the way across for the whole of it. A bar that does not move is a
    # bar that says the app has hung.
    withProgress(message = "Building random networks", value = 0.02, {
      res <- tryCatch(
        network_statistics(b$metrics, reps = reps,
                           conditioning = input$stat_null %||% "edges",
                           on_step = function(done) {
                             setProgress(value = min(0.95, done))
                           }),
        error = function(e) list(error = conditionMessage(e)))
    })
    stats_result(res)
    session$sendCustomMessage("scroll-to", "stats-results")
  })

  # A run describes the network it was run on, so it is thrown away
  # when the network changes rather than left to be read as though it
  # still applied.
  observeEvent(bundle(), stats_result(NULL), ignoreInit = TRUE)

  # The results screen. Each test carries its numbers and its sentence
  # together, since a table of proportions with the readings elsewhere
  # is how a reader ends up quoting a number whose meaning they never
  # saw.
  output$stats_body <- renderUI({
    res <- stats_result()
    if (is.null(res)) {
      return(div(class = "stats-empty",
        tags$p(paste(
          "Nothing has been run yet. The tests build several hundred",
          "random networks and take a few seconds."))))
    }
    if (!is.null(res$error)) {
      return(div(class = "stats-empty",
        tags$p(paste("These tests could not run on this network:",
                     res$error))))
    }
    tab <- res$table
    if (nrow(tab) == 0) {
      return(div(class = "stats-empty",
        tags$p(paste(
          "None of these tests could run on this network. That usually",
          "means it is too small or too sparse for a random network of",
          "the same size to differ from it in any measurable way."))))
    }
    # Every number the cards below read comes through this, so a value
    # that arrives missing shows as "n/a" rather than reaching an if()
    # and taking the screen down with a message that names neither the
    # measure nor the card it was on.
    shown <- function(value, digits = 2, missing = "n/a") {
      value <- one_number(value)
      if (!is.finite(value)) return(missing)
      formatC(value, format = "f", digits = digits)
    }
    div(id = "stats-results",
      div(class = "stats-head",
        tags$h3("Results"),
        tags$span(class = "stats-meta", sprintf(
          "%d people, %d ties, %d random networks, holding %s fixed.",
          res$n, res$m, res$reps,
          if (identical(res$conditioning, "degree")) {
            "each person's number of ties"
          } else {
            "the number of people and ties"
          }))),
      div(class = "stat-cards", lapply(seq_len(nrow(tab)), function(i) {
        row <- tab[i, ]
        p <- suppressWarnings(min(row$p_higher, row$p_lower, na.rm = TRUE))
        # The verdict is computed in R/statistics.R, which weighs the
        # proportion against three other things: whether the observation
        # falls outside what chance actually produced, whether the
        # sampling error on the proportion straddles the threshold, and
        # whether removing the best connected person moves the result
        # back inside the range. A proportion on its own decides nothing
        # here.
        band <- row$band %||% "none"
        div(class = paste0("stat-card band-", band),
          div(class = "stat-card-head",
            tags$h4(row$measure),
            tags$span(class = "stat-verdict", row$verdict)),
          tags$p(class = "stat-note", row$note),
          div(class = "stat-numbers",
            div(class = "stat-num",
              tags$span(class = "stat-value", shown(row$observed, 3)),
              tags$span(class = "stat-label", "Here")),
            # The range chance produced, rather than only its average.
            # An average alone gives a reader nothing to judge the gap
            # against, which is how a difference in the third decimal
            # place comes to look like a result.
            div(class = "stat-num wide",
              tags$span(class = "stat-value", paste(
                shown(row$chance_low, 3), "to", shown(row$chance_high, 3))),
              tags$span(class = "stat-label", "Chance produced")),
            div(class = "stat-num",
              tags$span(class = "stat-value", shown(row$z, 1)),
              tags$span(class = "stat-label", "Spreads out")),
            div(class = "stat-num",
              tags$span(class = "stat-value", paste0(
                shown(p, 3),
                if (has_number(row$p_error)) {
                  paste0(" \u00b1 ", shown(row$p_error, 3))
                } else {
                  ""
                })),
              tags$span(class = "stat-label", "p, with its own error")),
            if (has_number(row$without_top)) {
              div(class = "stat-num",
                tags$span(class = "stat-value", shown(row$without_top, 3)),
                tags$span(class = "stat-label",
                          paste("Without", row$top_person)))
            }),
          tags$p(class = "stat-reading", row$reading))
      })),

      # The same results as one table, for a reader who wants to compare
      # across measures rather than read them one at a time.
      div(class = "stat-table-block",
        table_block("Every test in one table",
          div(class = "table-hidden", `aria-hidden` = "true",
            html_table(
              c("Measure", "Verdict", "Here", "Chance low", "Chance high",
                "Chance average", "Spreads out", "p", "p error",
                "Without the busiest person"),
              list(tab$measure, tab$verdict,
                   vapply(tab$observed, shown, "", digits = 4),
                   vapply(tab$chance_low, shown, "", digits = 4),
                   vapply(tab$chance_high, shown, "", digits = 4),
                   vapply(tab$chance_mean, shown, "", digits = 4),
                   vapply(tab$z, shown, "", digits = 2),
                   vapply(pmin(tab$p_higher, tab$p_lower, na.rm = TRUE),
                          shown, "", digits = 4),
                   vapply(tab$p_error, shown, "", digits = 4),
                   vapply(tab$without_top, shown, "", digits = 4)),
              justify = c("left", "left", rep("num", 8)),
              class = "people-table", name = "full")),
          open_label = "Open the results table", name = "full")),

      if (length(res$skipped) == 0) NULL else div(class = "stat-skipped",
        tags$h4("Left out of this run"),
        tags$ul(lapply(res$skipped, function(item) {
          tags$li(tags$strong(item$measure), ": ", item$why)
        }))),

      div(class = "stat-extra",
        tags$h3("Two further readings"),
        div(class = "stat-cards",
          div(class = "stat-card",
            tags$h4("Clustered but short"),
            tags$p(class = "stat-note", paste(
              "Watts and Strogatz asked whether a network closes its",
              "triangles like a lattice while keeping paths short like a",
              "random graph. The two halves are reported separately,",
              "because a single small world number hides which half is",
              "doing the work.")),
            tags$p(class = "stat-reading",
              if (!has_number(res$small_world$ratio_c) ||
                  !has_number(res$small_world$ratio_l)) {
                paste("This comparison could not be made for this",
                      "network, which happens when it has no closed",
                      "triangles at all or comes apart into pieces too",
                      "small to measure a distance across.")
              } else {
                clustered <- res$small_world$ratio_c
                short <- res$small_world$ratio_l
                verdict <- if (clustered > 1.5 && short < 1.5) {
                  paste("Both halves hold, so this network is small",
                        "world in the sense Watts and Strogatz meant:",
                        "people cluster into groups, and anything moving",
                        "through it still has short paths available.")
                } else if (clustered > 1.5) {
                  paste("The first half holds and the second does not.",
                        "People here cluster, but getting from one side",
                        "to the other takes longer than it would in a",
                        "random network, so this is a clustered network",
                        "rather than a small world.")
                } else if (short < 1.1) {
                  paste("Paths here are as short as a random network",
                        "gives, but the clustering that would make this",
                        "a small world is not present, so it behaves",
                        "like a random network in both respects.")
                } else {
                  paste("Neither half holds, so nothing about this",
                        "network fits the small world description.")
                }
                paste0(
                  sprintf(paste("People here close their triangles %s times",
                                "as often as a random network of the same",
                                "size does, and the average distance",
                                "between two of them is %s times the",
                                "random figure. "),
                          shown(clustered), shown(short)),
                  verdict)
              })),
          div(class = "stat-card",
            tags$h4("How connection counts are spread"),
            tags$p(class = "stat-note", paste(
              "Whether a few people hold most of the ties or everyone",
              "holds a similar number. The tail is fitted by the",
              "Clauset, Shalizi, and Newman method.")),
            tags$p(class = "stat-reading", paste0(
              sprintf(paste("People here hold %s ties on average, with",
                            "the busiest holding %s. "),
                      shown(res$degree$mean, 1), shown(res$degree$max, 0)),
              # A spread larger than the average is the plain reading of
              # a lopsided network, and it needs no distribution fitted
              # to it, which is why it comes first.
              if (has_number(res$degree$ratio) && res$degree$ratio > 1) {
                paste("The spread is wider than the average itself,",
                      "which means the busiest people are doing a lot",
                      "more than the quietest and no single number",
                      "describes a typical person here. ")
              } else if (has_number(res$degree$ratio) &&
                         res$degree$ratio < 0.5) {
                paste("The spread is narrow, so people here hold",
                      "similar numbers of ties and no one is carrying",
                      "the network by volume. ")
              } else {
                paste("The spread is moderate, so there is a busier end",
                      "and a quieter end without either dominating. ")
              },
              if (!has_number(res$degree$ks_p)) {
                paste("Whether the counts follow a heavy tailed shape",
                      "was not tested. That test resamples the fitted",
                      "distribution, and the igraph on this machine does",
                      "it only when asked, or this network is too small",
                      "for the answer to mean anything.")
              } else if (res$degree$ks_p < 0.05) {
                paste("A heavy tailed shape does not describe these",
                      "counts, so whatever unevenness is here is not the",
                      "kind where a handful of people hold most of the",
                      "network.")
              } else {
                sprintf(paste("Above %s ties the counts are consistent",
                              "with a heavy tailed shape, the pattern in",
                              "which a few people hold much of the",
                              "connection. With %s people that is worth",
                              "treating as a hint rather than a result,",
                              "since the fit has little to work with."),
                        shown(res$degree$xmin, 0), shown(res$n, 0))
              })))
        )),

      # The file first, on its own line. The model control below it,
      # behind a rule. They were side by side and reading as one
      # control, which they are not: one saves what is on the screen and
      # the other asks a program to write about it.
      div(class = "stat-actions",
        downloadButton("dl_stats", "Download these results (CSV)",
                       class = "btn")),
      uiOutput("stats_model_ui"),
      uiOutput("stats_model_out"),

      div(class = "stats-caveat",
        tags$h4("How to read these"),
        tags$p(class = "caveat", paste(
          "No verdict above rests on the proportion alone. The American",
          "Statistical Association said in 2016 that a proportion below",
          "a threshold is not by itself evidence of anything, and the",
          "reason is arithmetic: it answers how often chance would beat",
          "this observation, which is a different question from whether",
          "the difference is large, whether it would survive a second",
          "sample, or whether it rests on one person.")),
        tags$p(class = "caveat", paste(
          "So each result is weighed four ways. The proportion is one.",
          "The second is whether this network falls outside the range",
          "the random ones actually produced, which is the column beside",
          "it. The third is the sampling error on the proportion, since",
          "one computed from a few hundred random networks is an",
          "estimate; when that error straddles the threshold the verdict",
          "reads as near the edge and the cure is more random networks.",
          "The fourth is what happens with the best connected person",
          "removed: a result that moves back inside the range when one",
          "person leaves is a fact about that person.")),
        tags$p(class = "caveat", paste(
          "What none of this can do is say what caused anything. These",
          "are one snapshot of recorded ties, so nothing here supports a",
          "claim about change over time, and a result beyond chance",
          "still needs a reason before it means something.")))
    )
  })

  output$dl_stats <- downloadHandler(
    filename = function() {
      paste0("tessera-statistics-", format(Sys.Date(), "%Y-%m-%d"), ".csv")
    },
    content = function(file) {
      res <- stats_result()
      req(res, is.null(res$error))
      write.csv(res$table, file, row.names = FALSE)
    })

  # The model can restate these too, and the same rule applies: it is
  # given the findings, never the explanations.
  # What a reader can ask the model to do with a page of proportions.
  # Three things rather than one, because which one they want depends on
  # why they came: the results in plain words, the paragraph they would
  # write in a paper, or the objection a reviewer will raise. All three
  # are rewordings of the same findings and none of them computes
  # anything.
  output$stats_model_ui <- renderUI({
    res <- stats_result()
    if (is.null(res) || !is.null(res$error)) return(NULL)
    modes <- model_modes()
    div(class = "control stats-model-control",
      tags$hr(class = "stat-rule"),
      tags$label(`for` = "stats_model_mode", "Ask the local model for"),
      div(class = "btn-cluster",
        selectInput("stats_model_mode", NULL, width = "240px",
                    selectize = FALSE,
                    choices = stats::setNames(
                      names(modes),
                      vapply(modes, function(m) m$label, ""))),
        actionButton("ask_model_stats", "Ask", class = "btn")))
  })

  stats_model_text <- reactiveVal(NULL)

  observeEvent(input$ask_model_stats, {
    res <- stats_result()
    req(res, is.null(res$error))
    status <- ollama_status(pref_url())
    if (!isTRUE(status$running)) {
      stats_model_text(list(ok = FALSE, text = paste(
        "No local model is answering at this address. Local models in",
        "the header sets one up.")))
      return(NULL)
    }
    facts <- stats_facts(res, dataset_title(input$dataset))
    mode <- input$stats_model_mode %||% "plain"
    withProgress(message = "Asking the local model", value = 0.4, {
      out <- rewrite_with_local_model(
        facts, pref_url(), input$restate_model %||% pref_model(),
        mode = mode)
    })
    stats_model_text(if (out$ok) {
      list(ok = TRUE, text = out$text,
           model = input$restate_model %||% pref_model(),
           mode = model_modes()[[mode]]$label)
    } else {
      list(ok = FALSE, text = out$message)
    })
    session$sendCustomMessage("scroll-to", "stats-model-block")
  })

  output$stats_model_out <- renderUI({
    answer <- stats_model_text()
    if (is.null(answer)) return(NULL)
    if (!isTRUE(answer$ok)) {
      return(tags$p(class = "model-answer", answer$text))
    }
    parts <- trimws(unlist(strsplit(answer$text, "\n[[:space:]]*\n")))
    parts <- parts[nzchar(parts)]
    div(id = "stats-model-block", class = "model-answer-block",
      div(class = "model-answer-head",
        tags$span(class = "model-badge", answer$model %||% "local model"),
        if (!is.null(answer$mode)) {
          tags$span(class = "model-badge model-mode", answer$mode)
        },
        tags$span(class = "model-note",
                  "A rewording. The numbers above are the computed ones.")),
      lapply(parts, function(part) tags$p(class = "model-answer", part)))
  })

  # ---- Saving and resuming ------------------------------------------
  # A saved session carries the ties themselves along with how they were
  # being looked at, so resuming does not depend on the original file
  # still being where it was. Preferences are a separate thing and never
  # travel in a session file: they belong to the machine rather than to
  # the work.
  resumed_edges <- reactiveVal(NULL)
  resume_seed <- reactiveVal(0)

  output$resume_input_ui <- renderUI({
    resume_seed()
    fileInput("resume_file", NULL, accept = ".json", width = "150px",
              buttonLabel = "Resume", placeholder = "")
  })

  output$dl_session <- downloadHandler(
    filename = function() {
      paste0("tessera-session-", format(Sys.Date(), "%Y-%m-%d"), ".json")
    },
    content = function(file) {
      ed <- edges()
      req(ed)
      view <- list(
        directed = isTRUE(attr(ed, "directed")),
        size_by = input$size_by %||% "degree",
        label_mode = input$label_mode %||% "key",
        sort_by = input$sort_by %||% "degree",
        min_weight = as.character(input$min_weight %||% 1),
        palette = input$palette %||% "standard",
        community_method = input$community_method %||% "louvain",
        selected = as.character(input$selected_node %||% "")
      )
      save_session(file, session_snapshot(ed, view))
    })

  observeEvent(input$resume_file, {
    res <- read_session(input$resume_file$datapath)
    if (!isTRUE(res$ok)) {
      showNotification(res$message, type = "error", duration = 8)
      resume_seed(resume_seed() + 1)
      return(NULL)
    }
    restored <- res$edges
    if (isTRUE(res$view$directed)) attr(restored, "directed") <- TRUE
    resumed_edges(restored)
    updateSelectInput(session, "dataset", selected = "resumed")
    # The view is restored where the control exists. Controls that are
    # rendered on demand are set after the network loads rather than
    # here, since setting an input that is not on screen does nothing.
    v <- res$view
    # A session file is a file, and a file can say anything. The palette
    # is checked against the settings this app actually has before it is
    # sent to the browser, since the browser turns it into a class name
    # and a value that is not one of these would either name a class
    # that does not exist or fail to be a class name at all.
    v$palette <- if (isTRUE(v$palette %in% PALETTE_NAMES)) v$palette else NULL
    if (!is.null(v$palette)) {
      updateRadioButtons(session, "palette", selected = v$palette)
      session$sendCustomMessage("set-palette", v$palette)
    }
    pending_view(v)
    showNotification(paste("Session restored from", res$saved %||% "file"),
                     type = "message", duration = 5)
  })

  # The view controls do not exist until a network is on screen, so a
  # restored view waits here until they do.
  pending_view <- reactiveVal(NULL)
  observeEvent(bundle(), {
    v <- pending_view()
    if (is.null(v) || is.null(bundle())) return(NULL)
    if (!is.null(v$size_by)) {
      updateSelectInput(session, "size_by", selected = v$size_by)
    }
    if (!is.null(v$label_mode)) {
      updateSelectInput(session, "label_mode", selected = v$label_mode)
    }
    if (!is.null(v$sort_by)) {
      updateSelectInput(session, "sort_by", selected = v$sort_by)
    }
    pending_view(NULL)
  })

  # ---- Preferences --------------------------------------------------
  # Read once at the start of the session and written whenever one of
  # the three settings they cover changes, so a reader sets an address
  # or a model name once rather than every time.
  prefs <- read_prefs()

  # The address and the model name are held as reactive values rather
  # than read once into a list. The settings dialog does not exist until
  # it is opened, so updateTextInput on a model chosen during setup has
  # nothing to write to, and a later check reading the list would still
  # see the startup value long after a model was installed.
  pref_url <- reactiveVal(prefs$ollama_url)
  pref_model <- reactiveVal(prefs$ollama_model)

  observe({
    session$sendCustomMessage("set-palette", prefs$palette)
    updateRadioButtons(session, "palette", selected = prefs$palette)
  })
  observeEvent(input$palette, {
    write_prefs(list(palette = input$palette))
  }, ignoreInit = TRUE)
  observeEvent(input$ollama_url, {
    pref_url(input$ollama_url)
    write_prefs(list(ollama_url = input$ollama_url))
  }, ignoreInit = TRUE)
  observeEvent(input$ollama_model, {
    pref_model(input$ollama_model)
    write_prefs(list(ollama_model = input$ollama_model))
  }, ignoreInit = TRUE)

  # The people section only exists once a network does; a headline table
  # over an empty map would read as a broken page.
  output$people_section <- renderUI({
    if (is.null(bundle())) return(NULL)
    tagList(
      tags$h2(class = "section-title", "People"),
      p(class = "helper-note",
        paste("Every number below describes position in the map above.",
              "Click a person on the map, or press Tab and Enter, to",
              "read about them on the right.")),
      div(class = "control-row tight",
        div(class = "control",
          tags$label(`for` = "sort_by", "Sort people by"),
          selectInput("sort_by", NULL, choices = sort_choices,
                      width = "220px", selectize = FALSE)
        ),
        div(class = "control",
          tags$label("Downloads"),
          div(class = "btn-cluster",
            downloadButton("dl_people", "People (CSV)", class = "btn"),
            downloadButton("dl_summary", "Summary (text)", class = "btn"),
            downloadButton("dl_figure", "Map figure (PNG)", class = "btn"),
          downloadButton("dl_everything", "Everything (ZIP)",
                         class = "btn btn-primary")
          )
        )
      ),
      # Two ways to see the rest of it, because they answer different
      # questions. The in place expansion keeps the table where it is
      # for a reader scrolling the page; the open control gives the same
      # table a search box, sortable headings, and paging for a reader
      # looking for one person among fifty eight.
      table_block("People",
        div(class = "people-wrap short", id = "people-wrap",
            htmlOutput("people_table")),
        open_label = "Open with search and sorting",
        actions = tags$button(type = "button", class = "btn show-all",
          onclick = paste0(
            "var w = document.getElementById('people-wrap');",
            "var short = w.classList.toggle('short');",
            "this.textContent = short ? 'Show every person' : ",
            "'Show the first twelve';",
            "this.setAttribute('aria-expanded', short ? 'false' : 'true');"),
          `aria-controls` = "people-wrap",
          `aria-expanded` = "false",
          "Show every person"))
    )
  })

  # The table is rendered by hand rather than through a table widget so
  # every theme and palette state stays under the control of this
  # stylesheet.
  # Sorting is done in R rather than in the browser so the order in the
  # table always matches the order in a downloaded file.
  output$people_table <- renderUI({
    b <- bundle()
    req(b)
    key <- input$sort_by %||% "degree"
    nd <- b$payload$nodes |>
      arrange(if (key == "label") label else desc(.data[[key]]))
    # A bar behind the column the table is sorted by. Fifty eight rows of
    # bare decimals give a reader nothing to catch hold of, and the
    # number that was chosen as the sort key is the one being scanned.
    # The number stays exactly where it was; the bar sits behind it, so
    # nothing is lost and the shape of the distribution becomes visible
    # without a second chart.
    bar_col <- if (key == "label") "degree" else key
    vals <- nd[[bar_col]]
    top <- suppressWarnings(max(vals, na.rm = TRUE))
    share <- if (is.finite(top) && top > 0) vals / top else rep(0, length(vals))
    # The bar is a short track under the number rather than a wash
    # across the cell. A background that fills the whole column reads as
    # a selected row, and its length depends on how wide the column
    # happens to be, which is not a property of the data. A fixed track
    # is the same length for every row, so the fills can be compared
    # against each other and against nothing else.
    cell <- function(column, i, text) {
      if (column != bar_col) {
        return(sprintf('<td class="num">%s</td>', text))
      }
      sprintf(paste0(
        '<td class="num barred"><span class="cell-value">%s</span>',
        '<span class="bar-track"><span class="bar-fill" ',
        'style="width: %.1f%%"></span></span></td>'),
        text, 100 * share[i])
    }
    rows <- paste(vapply(seq_len(nrow(nd)), function(i) {
      paste0(
        "<tr><td>", htmltools::htmlEscape(nd$label[i]), "</td>",
        cell("degree", i, sprintf("%d", nd$degree[i])),
        cell("between", i, sprintf("%.3f", nd$between[i])),
        cell("close", i, sprintf("%.3f", nd$close[i])),
        cell("eigen", i, sprintf("%.3f", nd$eigen[i])),
        '<td class="num">', nd$group[i], "</td>",
        "<td>", if (nd$is_cut[i]) "Single point of failure" else "",
        "</td></tr>")
    }, ""), collapse = "")
    HTML(paste0(
      '<table class="people-table"><thead><tr>',
      '<th>Name</th><th class="num-head">Direct ties</th>',
      '<th class="num-head">Between groups</th>',
      '<th class="num-head">Quick reach</th>',
      '<th class="num-head">Well connected circle</th>',
      '<th class="num-head">Group</th>',
      "<th>Note</th></tr></thead><tbody>", rows, "</tbody></table>"))
  })

  # Exports carry the same plain column names as the screen, and the
  # summary text ships with its caveat attached.
  output$dl_people <- downloadHandler(
    filename = function() "network_people.csv",
    content = function(file) {
      b <- bundle()
      req(b)
      b$payload$nodes |>
        transmute(
          name = label, direct_ties = degree,
          between_groups = between, quick_reach = close,
          well_connected_circle = eigen, group,
          single_point_of_failure = is_cut) |>
        write_csv(file)
    })

  # The figure is exported on a white ground whatever mode the app is
  # in, because it is going into a document or a slide rather than back
  # onto this screen. It follows the color setting, though, since a
  # reader who chose a palette for a reason needs that reason to survive
  # the export.
  output$dl_figure <- downloadHandler(
    filename = function() "network_map.png",
    content = function(file) {
      b <- bundle()
      req(b)
      pal <- input$palette %||% "standard"
      title <- dataset_title(input$dataset)
      fig <- network_figure(b$payload, pal, title)
      ggplot2::ggsave(file, fig, width = 9, height = 7.5, dpi = 300,
                      bg = "white")
    })

  # The text summary is the reading panel as a file, caveat included.
  output$dl_summary <- downloadHandler(
    filename = function() "network_summary.txt",
    content = function(file) {
      b <- bundle()
      req(b)
      cards <- describe_cards(b$metrics, b$groups)
      lines <- unlist(lapply(cards, function(cd) c(cd$title, cd$prose, "")))
      writeLines(c(lines, caveat_line()), file)
    })

  # The researcher tab. It reuses the same loaded network as the general
  # tab, so a person can move between the plain-language view and the
  # full statistics without reloading anything.
  output$research_body <- renderUI({
    b <- bundle()
    if (is.null(b)) {
      return(div(class = "research-empty",
        tags$h2("Load a network first"),
        tags$p(paste("Choose a network on the Explore tab, or upload your",
                     "own. The full diagnostics, community algorithms, and",
                     "reproducible code appear here once a network is",
                     "loaded."))))
    }
    tagList(
      # Three cards of one height, each holding as much as fits and the
      # rest behind the control in its heading. Letting them size
      # themselves gives three very different heights, and letting the
      # grid even them out gives two cards of empty space beside one
      # that is still cut off at the foot.
      div(class = "research-grid",
        card(class = "research-card",
          clipped_card("Global structure", tableOutput("global_table"))),
        card(class = "research-card",
          clipped_card("Community detection",
            # The control and its answer are wrapped rather than left as
            # bare siblings. Spacing between two unmarked children is
            # spacing nobody can point at, and the space that matters
            # here is between a menu and the numbers it produced, which
            # read as part of the control when they sit against it.
            div(class = "card-control",
              selectInput("community_method", "Algorithm",
                          choices = community_methods(), width = "100%",
                          selectize = FALSE)),
            div(class = "card-answer", uiOutput("community_result")))),
        card(class = "research-card",
          clipped_card("Dyad and triad census", uiOutput("census_body")))
      ),
      card(class = "research-card full",
        card_header("Extended centralities"),
        p(class = "helper-note",
          paste("Every measure below is standard graph statistics.",
                "Sorted by PageRank. Constraint and effective size are",
                "Burt's structural hole measures: a low constraint means",
                "a person's contacts are largely strangers to one",
                "another, which is the brokerage position. Coreness is",
                "the deepest k core a person sits in, which separates a",
                "dense center from a fringe in a way degree alone",
                "cannot.")),
        table_block("Extended centralities",
          uiOutput("extended_preview"),
          open_label = "Open the full table", name = "full",
          actions = downloadButton("dl_extended", "Centralities (CSV)",
                                   class = "btn"))),
      card(class = "research-card full",
        card_header("Reproducible script"),
        p(class = "helper-note",
          paste("A runnable script that recreates this analysis outside",
                "the app. The community algorithm follows your choice",
                "above. Two dialects are offered because the choice is",
                "not about which is better: take igraph to drop into an",
                "existing analysis, or tidy to stay in the tidyverse and",
                "get a figure worth putting in a document.")),
        # A menu rather than a pair of inline radio controls. Every
        # other choice in this app is made from a menu, and the inline
        # radio markup Bootstrap 5 emits puts its control outside the
        # box its label draws, which inside a flex row leaves a target
        # that is hard to hit and, next to a wide code block, sometimes
        # impossible.
        div(class = "control script-dialect",
          tags$label(`for` = "script_dialect", "Dialect"),
          selectInput("script_dialect", NULL, width = "240px",
                      selectize = FALSE,
                      choices = c(`igraph` = "igraph",
                                  `tidygraph and ggraph` = "tidy"),
                      selected = "igraph")),
        tags$pre(class = "code-export", textOutput("export_code")),
        div(class = "btn-cluster",
          downloadButton("dl_script", "Download script (R)",
                         class = "btn")))
    )
  })

  output$global_table <- renderTable({
    b <- bundle(); req(b)
    # The grouping is passed in so the E-I index can be computed over
    # the same communities the map shows rather than over nothing.
    global_diagnostics(b$metrics$graph, b$metrics$membership)
  }, colnames = FALSE, width = "100%")

  research_community <- reactive({
    b <- bundle(); req(b)
    method <- input$community_method %||% "louvain"
    # Girvan Newman is quadratic; guard it so a large upload cannot lock
    # the session. The guard is honest about why it declined.
    if (method == "edge_betweenness" && b$metrics$m > 800) {
      return(list(too_big = TRUE))
    }
    community_partition(b$metrics$graph, method)
  })

  output$community_result <- renderUI({
    cp <- research_community()
    if (isTRUE(cp$too_big)) {
      return(tags$p(class = "guard-note",
        paste("Girvan Newman is slow on networks this size. Choose",
              "another algorithm, or filter to fewer ties first.")))
    }
    tagList(
      div(class = "stat-row",
        div(class = "stat",
          tags$span(class = "stat-value", cp$n_groups),
          tags$span(class = "stat-label", "Groups")),
        div(class = "stat",
          tags$span(class = "stat-value", sprintf("%.3f", cp$modularity)),
          tags$span(class = "stat-label", "Modularity"))),
      tags$p(class = "helper-note",
        paste("Modularity near zero means the grouping is barely better",
              "than chance; above 0.3 means clear structure; above 0.5",
              "means strongly separated groups.")))
  })

  output$census_body <- renderUI({
    b <- bundle(); req(b)
    ct <- dyad_triad_census(b$metrics$digraph %||% b$metrics$graph)
    if (!isTRUE(ct$directed)) {
      return(tags$p(class = "helper-note",
        paste("The dyad and triad census describe direction, so they",
              "need a directed network. This network is undirected.",
              "Upload ties with a consistent direction to see the",
              "census.")))
    }
    share <- function(count) {
      total <- sum(count)
      if (total == 0) rep("0%", length(count))
      else sprintf("%.1f%%", 100 * count / total)
    }
    counted <- function(count) format(count, big.mark = ",")

    triads <- ct$triads
    present <- triads[triads$count > 0, , drop = FALSE]
    top <- head(present[order(-present$count), , drop = FALSE], 4)
    triad_headers <- c("Code", "What it counts", "Triples", "Share")
    triad_justify <- c("left", "left", "num", "num")
    all_share <- share(triads$count)
    top_share <- all_share[match(top$type, triads$type)]

    tagList(
      tags$h4(class = "census-head", "Dyads"),
      tags$p(class = "helper-note",
        paste("Every pair of people is one of three things: both",
              "directions present, one direction only, or nothing at",
              "all. The share of connected pairs that are returned is",
              "the plainest reading of whether this network is a",
              "conversation or a broadcast.")),
      html_table(c("Pair type", "Pairs", "Share"),
                 list(ct$dyads$type, counted(ct$dyads$count),
                      share(ct$dyads$count)),
                 justify = c("left", "num", "num"),
                 class = "people-table census-table"),
      tags$h4(class = "census-head", "Triads"),
      tags$p(class = "helper-note",
        paste("The sixteen ways three people can be arranged, in the",
              "Holland and Leinhardt order. Most networks are mostly",
              "empty triads, so the arrangements this network has are",
              "here, largest first.")),
      # Two versions of the same table. The short one is what the card
      # shows; the full one is what the open control finds. The short
      # one is dropped from the copy the panel makes and the full one is
      # shown, so neither appears twice.
      div(`data-panel-drop` = NA,
        html_table(triad_headers,
                   list(top$type, top$meaning, counted(top$count),
                        top_share),
                   justify = triad_justify,
                   class = "people-table census-table")),
      div(class = "table-hidden", `aria-hidden` = "true",
        html_table(triad_headers,
                   list(triads$type, triads$meaning,
                        counted(triads$count), all_share),
                   justify = triad_justify,
                   class = "people-table census-table",
                   name = "full")),
      div(class = "btn-cluster census-actions",
        downloadButton("dl_dyads", "Dyads (CSV)", class = "btn btn-quiet"),
        downloadButton("dl_triads", "Triads (CSV)", class = "btn btn-quiet")))
  })

  output$extended_preview <- renderUI({
    b <- bundle(); req(b)
    ec <- extended_centralities(b$metrics$graph)
    shown <- min(10L, nrow(ec))
    headers <- c("Name", "Degree", "Strength", "Between", "Reach",
                 "Eigenvector", "PageRank", "Hub", "Authority",
                 "Constraint", "Effective size", "Coreness")
    as_text <- function(column, digits) {
      if (is.null(digits)) return(as.character(column))
      ifelse(is.finite(column), sprintf(paste0("%.", digits, "f"), column),
             "n/a")
    }
    cells <- list(
      ec$name, as.character(ec$degree), as_text(ec$strength, 2),
      as_text(ec$between, 4), as_text(ec$close, 4), as_text(ec$eigen, 4),
      as_text(ec$pagerank, 4), as_text(ec$hub, 4),
      as_text(ec$authority, 4), as_text(ec$constraint, 4),
      as_text(ec$effective, 3), as.character(ec$coreness))
    justify <- c("left", rep("num", length(headers) - 1))
    tagList(
      div(class = "table-scroll table-preview",
        html_table(headers, lapply(cells, function(x) x[seq_len(shown)]),
                   justify = justify, class = "people-table",
                   name = "preview")),
      preview_note(shown, nrow(ec), "people"),
      # The full table is in the markup but not on the card. The open
      # control reads it from here, so nothing has to be fetched or
      # recomputed when the modal opens.
      div(class = "table-hidden", `aria-hidden` = "true",
        html_table(headers, cells, justify = justify,
                   class = "people-table", name = "full")))
  })

  output$export_code <- renderText({
    method <- input$community_method %||% "louvain"
    size <- input$size_by %||% "degree"
    export_script(method, size, input$script_dialect %||% "igraph")
  })

  output$dl_extended <- downloadHandler(
    filename = function() "extended_centralities.csv",
    content = function(file) {
      b <- bundle(); req(b)
      write_csv(extended_centralities(b$metrics$graph), file)
    })

  output$dl_script <- downloadHandler(
    filename = function() {
      if (identical(input$script_dialect, "tidy")) {
        "tessera_analysis_tidy.R"
      } else {
        "tessera_analysis_igraph.R"
      }
    },
    content = function(file) {
      method <- input$community_method %||% "louvain"
      size <- input$size_by %||% "degree"
      writeLines(export_script(method, size,
                               input$script_dialect %||% "igraph"), file)
    })
}

shinyApp(ui, server)
