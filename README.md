# Tessera

Every person a tile; together they show the pattern.

![The Explore tab showing a customer referral network of forty people,
with the reading panel describing its shape, its groups, the people who
hold it together, and where it is
fragile.](docs/screenshot-operator.png)

Tessera is a social network analysis dashboard written in R and Shiny. It
takes a list of ties between people, computes classical network measures,
and explains what they mean in plain English. Everything runs on the
machine that opens it. No account, no server, no data leaving the room.

## Two ways in

Tessera opens on the Explore tab, the no-code view: an interactive map, a
plain language reading panel, and a people table. The Research tab holds
the full statistics for anyone who wants them:

- Extended centralities: degree, strength, betweenness, harmonic
  closeness, eigenvector, PageRank, and the HITS hub and authority scores
- Community detection with a choice of algorithm: Louvain, Leiden,
  Walktrap, fast greedy, and Girvan Newman, each reporting its modularity
- Global diagnostics: density, transitivity, reciprocity, components,
  diameter, mean distance, and mean degree
- Dyad and triad census with the Holland and Leinhardt labels, for
  directed networks
- A runnable igraph script that reproduces the analysis outside the app

Both tabs read the same loaded network, so moving between them reloads
nothing.

## The map

Nodes can be dragged and their ties follow. The view fits the network
when it loads, and a full screen button gives the map the whole window
with the reading panel floating over the top right corner, optionally
see through so the network stays legible underneath. Escape leaves full
screen.

Group identity uses twelve base shapes crossed with three fill variants
(solid, hollow, and solid with a centered pip) across twelve colors. That
gives thirty six combinations distinguishable by shape alone, before
color is considered, so large numbers of communities stay readable in
every palette including the monochrome one.

## Where the language model fits

All detection math is classical graph analysis through tidygraph and
igraph. The plain English reading works with no model at all. When a
local Ollama server is running, the Restate button asks it to reword the
computed summary, with every number passed in so the model restates
rather than invents. The division of labor is deliberate: auditable
methods produce the numbers, and a language model is used only for the
last step of phrasing.

The Local models button in the app opens a guide written for someone who
has never heard of a local language model: what it is, the setup steps
through Ollama, and a comparison of four models with their download
sizes, memory needs, and tradeoffs.

## Installing

Tessera needs R 4.1 or newer, for the native pipe.

```r
install.packages(c(
  "shiny", "bslib", "igraph", "tidygraph", "ggraph", "ggplot2",
  "dplyr", "tidyr", "purrr", "tibble", "readr", "jsonlite"
))

# Optional, only for the local language model connection
install.packages("curl")
```

## Running

```r
shiny::runApp("path/to/tessera")
```

The app opens ready for your own data, with a walkthrough on first launch
and two built in samples one click away.

## Your data

Provide a CSV with two or three columns: who the tie is from, who it is
to, and an optional tie strength.

```csv
from,to,weight
Maya,Tom,3
Tom,Ines,1
Ines,Maya,2
```

A sample file sits in `data/sample_ties.csv`.

## Accessibility

Dark and light modes combine with four color settings: standard, one
tuned for red green color vision, one tuned for blue yellow color vision,
and a high contrast mode with no color at all. Group identity is carried
by shape as well as color in every mode. All text meets a WCAG contrast
of 4.5 to 1 or better in all combinations, and the test suite verifies
this on every run. Every person on the map is a keyboard stop with a
spoken description. Motion respects the reduced motion system setting.

## Tests

```r
Rscript tests/run_tests.R
```

```sh
npm install jsdom
node tests/dom_test.mjs
```

Two further suites run against the page the server actually sends, which
is where several bugs hid from tests that built their own markup:

```sh
# with the app running on port 7823
curl -s http://127.0.0.1:7823/ -o /tmp/page.html
curl -s http://127.0.0.1:7823/styles.css -o /tmp/styles.css
node tests/theme_test.mjs /tmp/page.html /tmp/styles.css
```

The R suite covers the graph math against known answers, the behavior of
the generated prose, the research tier statistics, the full contrast
matrix, and a headless run of the live server. The Node suite drives the
real map renderer in a simulated DOM and checks the glyph system,
dragging, the spotlight, and full screen behavior.

## Built with

Tessera is written in [R](https://www.r-project.org) and
[Shiny](https://shiny.posit.co). The graph work uses
[igraph](https://r.igraph.org) and
[tidygraph](https://tidygraph.data-imaginist.com), the exported figure
uses [ggraph](https://ggraph.data-imaginist.com) and
[ggplot2](https://ggplot2.tidyverse.org), and the interface layout uses
[bslib](https://rstudio.github.io/bslib). The interactive map is
hand-written SVG rather than a charting library, which is what allows the
keyboard navigation and the palette work.

## Releases

Version history is in `NEWS.md`. Pushing a version tag publishes a
release automatically: the notes come from the matching section of
`NEWS.md` and a source archive is attached, so a specific version can be
cited or returned to.

```sh
git tag -a v0.11.0 -m "Tessera 0.11.0"
git push origin v0.11.0
```

Every push and pull request runs the three test suites through GitHub
Actions. The workflows are in `.github/workflows/`.

## Contributing

See `CONTRIBUTING.md`. It covers the test suites, the conventions the
sweeps enforce, how to add a graph measure or a community algorithm, and
the accessibility requirements any interface change must preserve.

If you are citing this work, `CITATION.cff` gives GitHub what it needs to
render a "Cite this repository" button.

## License

Copyright Abhik Roy. Released under the
[PolyForm Noncommercial License 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0).
See `LICENSE.md`.

Noncommercial use is permitted, which includes personal projects,
academic research, and work by charitable, educational, public research,
public health, and government organizations. Commercial use requires a
separate license.
