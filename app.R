# app.R
# Tessera: a social network map with a plain language reading panel.
#
# Copyright Abhik Roy. Released under the PolyForm Noncommercial
# License 1.0.0. See LICENSE.md.
# The math is tidygraph pipelines (R/network_math.R), the prose is
# computed from those numbers (R/narrative.R), and a local language
# model can restate the prose when one is available. Nothing leaves the
# machine this app runs on.

library(shiny)
suppressPackageStartupMessages({
  library(bslib)
  library(dplyr)
  library(readr)
})

source("R/network_math.R")
source("R/sample_data.R")
source("R/narrative.R")
source("R/figure.R")
source("R/guide.R")
source("R/research_metrics.R")

APP_NAME    <- "Tessera"
APP_TAG     <- "Every person a tile; together they show the pattern."
APP_VERSION <- "0.15.0"

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

# Swatch rows preview each color setting inside Settings, so choosing a
# palette is a look, not a guess. Five of the twelve colors are shown,
# each on a different shape, which is enough to judge a palette without
# turning the dialog into a chart.
palette_swatch <- function(hexes) {
  shapes <- list(
    function(fill) sprintf('<circle cx="9" cy="9" r="7" fill="%s"/>', fill),
    function(fill) sprintf('<rect x="3" y="3" width="12" height="12" fill="%s"/>', fill),
    function(fill) sprintf('<polygon points="9,1 17,9 9,17 1,9" fill="%s"/>', fill),
    function(fill) sprintf('<polygon points="9,2 17,16 1,16" fill="%s"/>', fill),
    function(fill) sprintf('<polygon points="9,1 16,5 16,13 9,17 2,13 2,5" fill="%s"/>', fill)
  )
  chips <- vapply(seq_along(shapes), function(i) {
    sprintf('<svg width="18" height="18" class="swatch">%s</svg>',
            shapes[[i]](hexes[i]))
  }, "")
  HTML(paste0('<span class="swatch-row">', paste(chips, collapse = ""),
              "</span>"))
}

swatch_label <- function(text, palette_name) {
  # The swatch hexes reuse the figure palettes, which mirror the CSS, so
  # the preview can never drift from the map.
  tagList(tags$span(class = "swatch-name", text),
          palette_swatch(figure_palettes[[palette_name]]))
}

# The shared brand mark, reused in the navbar title.
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
    div(class = "control",
      tags$label(`for` = "dataset", "Network"),
      selectInput("dataset", NULL, width = "230px", selectize = FALSE,
        choices = c("Your own data" = "upload",
                    "Product studio (sample)" = "org",
                    "Customer referrals (sample)" = "referral"))
    ),
    conditionalPanel("input.dataset == 'upload'",
      div(class = "control",
        tags$label(`for` = "edges_file", "Tie list (CSV: from, to, strength)"),
        uiOutput("file_input_ui")
      )
    ),
    div(class = "control",
      tags$label("Start over"),
      actionButton("reset_all", "Reset", class = "btn")
    ),
    uiOutput("view_controls")
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
    tags$script(src = asset_url("graph.js")),
    tags$script(src = asset_url("theme.js")),
    tags$meta(name = "viewport",
              content = "width=device-width, initial-scale=1")
  ),
  general_tab,
  research_tab,
  nav_spacer(),
  nav_item(theme_toggle_button()),
  nav_item(actionLink("open_tour", "Walkthrough")),
  nav_item(actionLink("open_models", "Local models")),
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
  observeEvent(input$tour_back, { tour_step(tour_step() - 1); show_tour() })
  observeEvent(input$tour_next, { tour_step(tour_step() + 1); show_tour() })
  observeEvent(input$tour_done, {
    session$sendCustomMessage("tour-seen", TRUE)
    removeModal()
  })

  # Uploads fail politely. The reader learns what the file needs, not
  # what the parser choked on.
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

  edges_raw <- reactive({
    switch(input$dataset,
      org      = sample_org_network(),
      referral = sample_referral_network(),
      upload   = { if (is.null(input$edges_file)) NULL else uploaded() }
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
      keep <- suppressWarnings(as.numeric(ed[[3]]))
      ed <- ed[!is.na(keep) & keep >= t, ]
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

  observeEvent(input$reset_all, {
    updateSelectInput(session, "dataset", selected = "upload")
    file_input_seed(file_input_seed() + 1)
    session$sendCustomMessage("clear-graph", list())
    model_text(NULL)
    showNotification("Cleared. Choose a network or upload your own.",
                     type = "message", duration = 4)
  })

  output$view_controls <- renderUI({
    b <- bundle()
    if (is.null(b)) return(NULL)
    nms <- sort(b$payload$nodes$label)
    tagList(
      div(class = "control",
        tags$label(`for` = "size_by", "Size people by"),
        selectInput("size_by", NULL, choices = size_choices,
                    width = "200px", selectize = FALSE)),
      div(class = "control",
        tags$label(`for` = "label_mode", "Names on the map"),
        selectInput("label_mode", NULL, choices = label_choices,
                    width = "150px", selectize = FALSE)),
      div(class = "control",
        tags$label(`for` = "person_pick", "Find a person"),
        selectInput("person_pick", NULL, selectize = FALSE,
                    width = "170px", choices = c("Choose" = "", nms))),
      uiOutput("weight_filter_ui"),
      div(class = "control",
        tags$label("Focus"),
        actionButton("clear_pick", "Show everyone", class = "btn")),
      div(class = "control",
        tags$label("Map size"),
        tags$button(id = "fs-toggle", type = "button", class = "btn",
                    `aria-pressed` = "false", "Full screen"))
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
  observeEvent(input$try_org, {
    updateSelectInput(session, "dataset", selected = "org")
  })
  observeEvent(input$try_ref, {
    updateSelectInput(session, "dataset", selected = "referral")
  })

  # The reading panel. Cards for the whole network, one card plus
  # controls for a chosen person. Person names inside cards are buttons
  # that select that person on the map.
  card_ui <- function(card) {
    stats <- if (length(card$stats) > 0) {
      div(class = "stat-row", lapply(card$stats, function(s) {
        div(class = "stat",
            tags$span(class = "stat-value", s$value),
            tags$span(class = "stat-label", s$label))
      }))
    }
    chips <- if (length(card$people) > 0) {
      div(class = "chip-row", lapply(card$people, function(nm) {
        tags$button(type = "button", class = "person-chip",
          onclick = sprintf(
            "Shiny.setInputValue('chip_person', '%s', {priority: 'event'})",
            gsub("'", "\\\\'", nm)),
          `aria-label` = paste("Focus the map on", nm), nm)
      }))
    }
    div(class = "card",
        tags$h3(card$title), stats, tags$p(card$prose), chips)
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
        div(class = "panel-foot",
          actionButton("ask_model", "Restate with the local model",
                       class = "btn"),
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
        div(class = "panel-foot",
          actionButton("ask_model", "Restate with the local model",
                       class = "btn"),
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

  observeEvent(input$ask_model, {
    b <- bundle()
    req(b)
    sel <- input$selected_node
    paras <- if (is.null(sel) || length(sel) == 0 || is.na(sel)) {
      vapply(describe_cards(b$metrics, b$groups),
             function(cd) cd$prose, "")
    } else {
      person_card(b$metrics, as.integer(sel), b$groups)$prose
    }
    withProgress(message = "Asking the local model", value = 0.4, {
      res <- rewrite_with_local_model(
        paras,
        input$ollama_url %||% "http://localhost:11434",
        input$ollama_model %||% "llama3.2")
    })
    if (res$ok) model_text(res$text) else model_text(res$message)
  })
  output$model_out <- renderUI({
    txt <- model_text()
    if (is.null(txt)) return(NULL)
    tags$p(class = "model-answer", txt)
  })

  # The local model guide. Everything a first time reader needs, in the
  # order they will ask: what is this, is it safe, how do I set it up,
  # which one should I pick.
  observeEvent(input$open_models, {
    opts <- model_options()
    showModal(modalDialog(
      class = "models-modal", size = "l",
      tags$h2("Local language models"),
      tags$p(paste0(
        "A language model is a program that writes text. In ", APP_NAME,
        " its only job is optional: rewording the reading panel in its ",
        "own voice while keeping every number exactly as computed. ",
        "Nothing else in the app depends on one.")),
      div(class = "assure",
        tags$h3("Your data never leaves this machine"),
        tags$p(paste("Every measure on the map and every sentence in the",
                     "reading panel is computed by this app, on this",
                     "machine, with no model involved. A model you add",
                     "runs here too, through a free program named",
                     "Ollama. Nothing is sent to any company or",
                     "service."))
      ),
      tags$h3("Set up, once"),
      tags$ol(class = "setup-steps",
        tags$li(HTML(paste0("Install Ollama from ",
          '<a href="https://ollama.com" target="_blank" rel="noopener">ollama.com</a>',
          ". It is free and takes about a minute."))),
        tags$li(HTML(paste0("Open the Terminal app and paste one line ",
          "from the table below, for example ",
          "<code>ollama pull llama3.2</code>. ",
          "The model downloads once and stays."))),
        tags$li(paste("Keep Ollama running, come back here, and press",
                      "Restate with the local model under the reading",
                      "panel."))
      ),
      tags$h3("Which model to pick"),
      tags$p(paste("Any of these four does the job. Bigger models write",
                   "better prose and ask for more memory and patience.",
                   "If unsure, start with the first.")),
      div(class = "model-cards", lapply(opts, function(m) {
        div(class = "model-card",
          tags$h4(m$name),
          tags$code(class = "pull-line", m$pull),
          tags$ul(
            tags$li(m$download),
            tags$li(m$memory),
            tags$li(m$speed)
          ),
          tags$p(tags$strong("Why pick it: "), m$good),
          tags$p(class = "tradeoff", tags$strong("The catch: "),
                 m$tradeoff)
        )
      })),
      tags$p(class = "caveat", paste(
        "Model settings live under Settings in the header. The model",
        "name there must match the one you downloaded.")),
      footer = modalButton("Close"), easyClose = TRUE
    ))
  })

  # Settings live in a dialog so the main screen stays quiet. Theme and
  # palette apply as body classes; theme.js does the class work.
  observeEvent(input$open_settings, {
    showModal(modalDialog(
      title = "Settings",
      radioButtons("palette", "Color settings",
        choiceNames = list(
          swatch_label("Standard", "standard"),
          swatch_label("Tuned for red green color vision", "deutan"),
          swatch_label("Tuned for blue yellow color vision", "tritan"),
          swatch_label("High contrast grays, shapes carry the groups",
                       "mono")),
        choiceValues = c("standard", "deutan", "tritan", "mono"),
        selected = isolate(input$palette) %||% "standard"),
      tags$hr(),
      tags$p(tags$strong("Local language model (optional)")),
      tags$p(class = "caveat",
        paste("When an Ollama server runs on this machine, the Restate",
              "button asks it to reword the reading panel. The Local",
              "models button in the header explains everything.")),
      textInput("ollama_url", "Address",
                value = isolate(input$ollama_url) %||% "http://localhost:11434"),
      textInput("ollama_model", "Model name",
                value = isolate(input$ollama_model) %||% "llama3.2"),
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
            downloadButton("dl_figure", "Map figure (PNG)", class = "btn")
          )
        )
      ),
      div(class = "people-wrap", htmlOutput("people_table"))
    )
  })

  # The table is rendered by hand rather than through a table widget so
  # every theme and palette state stays under the control of this
  # stylesheet.
  output$people_table <- renderUI({
    b <- bundle()
    req(b)
    key <- input$sort_by %||% "degree"
    nd <- b$payload$nodes |>
      arrange(if (key == "label") label else desc(.data[[key]]))
    rows <- paste(sprintf(
      '<tr><td>%s</td><td class="num">%d</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%.3f</td><td class="num">%d</td><td>%s</td></tr>',
      htmltools::htmlEscape(nd$label), nd$degree, nd$between, nd$close,
      nd$eigen, nd$group,
      ifelse(nd$is_cut, "Single point of failure", "")),
      collapse = "")
    HTML(paste0(
      '<table class="people-table"><thead><tr>',
      "<th>Name</th><th>Direct ties</th><th>Between groups</th>",
      "<th>Quick reach</th><th>Well connected circle</th><th>Group</th>",
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

  output$dl_figure <- downloadHandler(
    filename = function() "network_map.png",
    content = function(file) {
      b <- bundle()
      req(b)
      pal <- input$palette %||% "standard"
      title <- switch(input$dataset,
        org = "Product studio", referral = "Customer referrals",
        "Your network")
      fig <- network_figure(b$payload, pal, title)
      ggplot2::ggsave(file, fig, width = 9, height = 7.5, dpi = 300,
                      bg = "white")
    })

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
      div(class = "research-grid",
        card(class = "research-card",
          card_header("Global structure"),
          tableOutput("global_table")),
        card(class = "research-card",
          card_header("Community detection"),
          selectInput("community_method", "Algorithm",
                      choices = community_methods(), width = "100%",
                      selectize = FALSE),
          uiOutput("community_result")),
        card(class = "research-card",
          card_header("Dyad and triad census"),
          uiOutput("census_body"))
      ),
      card(class = "research-card full",
        card_header("Extended centralities"),
        p(class = "helper-note",
          paste("Every measure below is standard graph statistics.",
                "Sorted by PageRank. The full table downloads as CSV.")),
        div(class = "btn-cluster", style = "margin-bottom: 12px;",
          downloadButton("dl_extended", "Centralities (CSV)",
                         class = "btn")),
        div(class = "table-scroll", tableOutput("extended_table"))),
      card(class = "research-card full",
        card_header("Reproducible script"),
        p(class = "helper-note",
          paste("A runnable igraph script that recreates this analysis",
                "outside the app. The community algorithm follows your",
                "choice above.")),
        tags$pre(class = "code-export", textOutput("export_code")),
        div(class = "btn-cluster",
          downloadButton("dl_script", "Download script (R)",
                         class = "btn")))
    )
  })

  output$global_table <- renderTable({
    b <- bundle(); req(b)
    global_diagnostics(b$metrics$graph)
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
      tags$p(class = "helper-note", style = "margin-top: 10px;",
        paste("Modularity near zero means the grouping is barely better",
              "than chance; above 0.3 means clear structure; above 0.5",
              "means strongly separated groups.")))
  })

  output$census_body <- renderUI({
    b <- bundle(); req(b)
    ct <- dyad_triad_census(b$metrics$graph)
    if (!isTRUE(ct$directed)) {
      return(tags$p(class = "helper-note",
        paste("The dyad and triad census describe direction, so they",
              "need a directed network. This network is undirected.",
              "Upload ties with a consistent direction to see the",
              "census.")))
    }
    tagList(
      tags$h4("Dyads", class = "census-head"),
      renderTable(ct$dyads, colnames = TRUE)(),
      tags$h4("Triads", class = "census-head"),
      div(class = "table-scroll",
          renderTable(ct$triads, colnames = TRUE)()))
  })

  output$extended_table <- renderTable({
    b <- bundle(); req(b)
    extended_centralities(b$metrics$graph)
  }, width = "100%", digits = 4)

  output$export_code <- renderText({
    method <- input$community_method %||% "louvain"
    size <- input$size_by %||% "degree"
    export_script(method, size)
  })

  output$dl_extended <- downloadHandler(
    filename = function() "extended_centralities.csv",
    content = function(file) {
      b <- bundle(); req(b)
      write_csv(extended_centralities(b$metrics$graph), file)
    })

  output$dl_script <- downloadHandler(
    filename = function() "tessera_analysis.R",
    content = function(file) {
      method <- input$community_method %||% "louvain"
      size <- input$size_by %||% "degree"
      writeLines(export_script(method, size), file)
    })
}

shinyApp(ui, server)
