# Tessera

[![License](https://img.shields.io/badge/license-PolyForm%20Noncommercial%201.0.0-blue)](LICENSE)
[![Shiny](https://img.shields.io/badge/Shiny-R-276DC3?logo=r&logoColor=white)](#requirements)
[![Release](https://img.shields.io/badge/release-v0.15.0-blue)](https://github.com/drabhikroy/rank-and-folder/releases/tag/v0.15.0)

Tessera is a social network analysis dashboard written in R and Shiny.
It helps researchers and analysts explore patterns of relationships,
such as who connects to whom, which groups form, and which people occupy
important positions in a network.

The app takes a list of connections between people, calculates common
network measures, and explains what those measures mean in plain
English. Everything runs on your computer. No account is required, no
server is used, and no data leave your machine.

![The Explore tab showing a customer referral network of forty people,
with the reading panel describing its shape, its groups, the people who
hold it together, and where it is
fragile.](docs/screenshot-operator.png)

## How Tessera works

A typical workflow:

1.  Upload a network file containing connections between people.
2.  Explore the network map and identify groups or important
    connections.
3.  Review the plain-language reading panel.
4.  Open the Research tab for detailed network statistics.
5.  Export an R script that reproduces the analysis.

Tessera supports two audiences from one screen:

-   The Explore tab provides an interactive map, readable explanations,
    and a people table.
-   The Research tab provides detailed statistics for users who want to
    inspect the analysis.

Both tabs use the same loaded network, so moving between them does not
require reloading data.

## Explore and research

The Explore tab provides a no-code view of the network:

-   Interactive network map
-   Plain-language reading panel
-   People table
-   Group and relationship exploration

The Research tab provides:

-   Extended centralities: degree, strength, betweenness, harmonic
    closeness, eigenvector, PageRank, and HITS hub and authority scores
-   Community detection with Louvain, Leiden, Walktrap, fast greedy, and
    Girvan-Newman algorithms
-   Global diagnostics including density, transitivity, reciprocity,
    components, diameter, mean distance, and mean degree
-   Dyad and triad census with Holland and Leinhardt labels for directed
    networks
-   A runnable igraph script that reproduces the analysis outside the
    app

## The network map

The interactive map lets you explore relationships directly.

Nodes can be dragged, and connections follow. The view adjusts when the
network loads, and full-screen mode provides more space for exploration.

Groups remain readable across different visual settings. Tessera uses
combinations of shape and color so community identity does not depend on
color alone.

## Optional local model support

All network calculations are performed using classical graph analysis
methods through tidygraph and igraph. The plain-language reading works
without a model.

When a local Ollama server is running, the Restate button can rewrite
the computed summary. The model receives the calculated information and
helps improve wording rather than generating new findings.

The division of work is intentional:

-   Network methods produce the statistics.
-   The local model is used only to improve phrasing.

The Local models guide inside the app explains setup, model choices,
download sizes, memory requirements, and tradeoffs.

## Installing

Tessera requires R 4.1 or newer.

Install the required packages:

``` r
install.packages(c(
  "shiny", "bslib", "igraph", "tidygraph", "ggraph", "ggplot2",
  "dplyr", "tidyr", "purrr", "tibble", "readr", "jsonlite"
))

# Optional, only for the local model connection
install.packages("curl")
```

## Running

From the project folder:

``` r
shiny::runApp("path/to/tessera")
```

The app opens ready for your own data, with a walkthrough on first
launch and two built-in samples available.

## Your data

Provide a CSV with two or three columns:

-   `from`: the person or entity where a connection starts
-   `to`: the person or entity where a connection ends
-   `weight`: an optional value representing tie strength

Example:

``` csv
from,to,weight
Maya,Tom,3
Tom,Ines,1
Ines,Maya,2
```

A sample file is available at:

``` text
data/sample_ties.csv
```

## Accessibility

Tessera is designed so network patterns remain readable across different
visual settings.

Features include:

-   Dark and light modes
-   Color settings for different vision differences, including
    monochrome
-   WCAG contrast checks across themes and palettes
-   Shape-based encoding alongside color
-   Keyboard navigation for network elements
-   Spoken descriptions for people on the map
-   Reduced motion support

## Tests

Run the R test suite:

``` r
Rscript tests/run_tests.R
```

Run the browser checks:

``` sh
npm install jsdom
node tests/dom_test.mjs
```

Additional checks run against the live application page, including theme
behavior and styling.

The test suites cover:

-   Network calculations against known answers
-   Generated explanations
-   Research statistics
-   Contrast checks
-   Live server behavior
-   Map rendering
-   Keyboard interaction
-   Full-screen behavior

## Built with

Tessera is written in [R](https://www.r-project.org) and
[Shiny](https://shiny.posit.co).

The graph analysis uses:

-   [igraph](https://r.igraph.org)
-   [tidygraph](https://tidygraph.data-imaginist.com)

Figures use:

-   [ggraph](https://ggraph.data-imaginist.com)
-   [ggplot2](https://ggplot2.tidyverse.org)

The interface uses:

-   [bslib](https://rstudio.github.io/bslib)

The interactive map is hand-written SVG rather than a charting library,
allowing direct control over keyboard navigation and accessibility
features.

## Releases

Version history is available in `NEWS.md`.

Pushing a version tag publishes a release automatically. Release
information combines the stable overview, installation instructions,
highlights, and license information with the matching version entry.

Example:

``` sh
git tag -a v0.11.0 -m "Tessera 0.11.0"
git push origin v0.11.0
```

Every push and pull request runs the test suites through GitHub Actions.

## Contributing

See `CONTRIBUTING.md` for:

-   Test requirements
-   Writing conventions
-   Adding graph measures or community algorithms
-   Accessibility requirements

If you are citing this work, `CITATION.cff` provides the information
GitHub needs to generate a citation.

## License

Copyright Abhik Roy.

Released under the [PolyForm Noncommercial License
1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0).

See `LICENSE.md`.

Noncommercial use is permitted, including personal projects, academic
research, and work by charitable, educational, public research, public
health, and government organizations. Commercial use requires a separate
license.
