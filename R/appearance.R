# appearance.R
# The color settings and the swatches that preview them.
#
# Copyright Abhik Roy. Released under the PolyForm Noncommercial
# License 1.0.0. See LICENSE.md.
#
# These sit in their own file rather than at the top of app.R because
# three separate places have to agree about what counts as a color
# setting: the dialog that offers them, the figure export that draws
# with them, and the check that a restored session has not named one
# this app does not have. A list that three places read is a list worth
# being able to point at, and a list in app.R is one the test suite
# cannot reach.

# The color settings this app offers. Named here because the settings
# dialog, the figure export, and the check on a restored session all
# have to agree about what counts as one.
PALETTE_NAMES <- c("standard", "deutan", "protan", "tritan", "mono")

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

# One row of the color settings list: the name of the setting and a
# preview of what it does.
swatch_label <- function(text, palette_name, note = NULL) {
  # Name, then what the name is for, then the colors themselves, each on
  # its own line and every line starting at the same left edge. Running
  # the swatches on after the text put five rows of shapes at five
  # different distances from the margin, which is the whole of why that
  # list read as clutter: the eye had nothing to compare down.
  #
  # The swatch hexes reuse the figure palettes, which mirror the CSS, so
  # the preview can never drift from the map.
  tagList(
    tags$span(class = "swatch-name", text),
    if (is.null(note)) NULL else tags$span(class = "swatch-note", note),
    palette_swatch(figure_palettes[[palette_name]]))
}

# The shared brand mark, reused in the navbar title.
