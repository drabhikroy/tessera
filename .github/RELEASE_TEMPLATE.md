## Tessera {{VERSION}}

An open source R Shiny app for social network analysis. Classical,
transparent methods turn a list of ties between people into an
interactive map, with plain language readings for general users and full
statistics for researchers.

### Highlights

- Two tabs behind one loaded network: Explore, a no-code map, plain
  language reading panel, and people table; Research, extended
  centralities including PageRank and the HITS hub and authority scores,
  a choice of five community detection algorithms, global diagnostics,
  the dyad and triad census, and a runnable igraph script export.
- A glyph system of twelve shapes crossed with three fill variants
  across twelve colors, thirty six combinations distinguishable by shape
  alone before color, across five color settings including separate
  deuteranopia and protanopia palettes and a monochrome, no color mode.
  Every color in all ten theme and palette states is measured against
  WCAG 2.2 AA by a test that fails the build rather than by a claim in a
  comment.
- A hand built SVG map: draggable people whose ties follow, keyboard
  reachable with spoken descriptions, and a full screen view using the
  browser's own full screen mode with the reading panel floating over
  the top corner.
- An optional local model layer, running fully on your own machine
  through Ollama, that rewords the computed reading panel in its own
  voice. It never invents a number, and nothing else in the app depends
  on one.
- An Overview screen that says what the app does, shows a worked example
  with the sentences it would write about it, and gives the shape of the
  input file, all before anything is loaded.
- A seven slide walkthrough on first launch, always available again from
  the navigation bar.

### Installation

Download the source below, or clone the repository, then run:

```
shiny::runApp("tessera")
```

Requires R 4.1 or later with shiny, bslib, igraph, tidygraph, ggraph,
ggplot2, dplyr, tidyr, purrr, tibble, readr, and jsonlite. curl is needed
only for the optional local model connection.

### License

PolyForm Noncommercial License 1.0.0.
