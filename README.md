# Tessera

[![License](https://img.shields.io/badge/license-PolyForm%20Noncommercial%201.0.0-blue)](LICENSE)
[![Shiny](https://img.shields.io/badge/Shiny-R-276DC3?logo=r&logoColor=white)](#requirements)
[![Release](https://img.shields.io/badge/release-v0.25.0-blue)](https://github.com/drabhikroy/tessera/releases/tag/v0.25.0)

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

-   The Overview tab explains what the app does, shows a worked example,
    and gives the shape of the file it expects. It reads the same before
    any data is loaded as after.
-   The Explore tab provides an interactive map, readable explanations,
    a route finder between any two people, and a people table.
-   The Research tab provides detailed statistics for users who want to
    inspect the analysis.
-   The Statistics tab asks whether what the other tabs describe is more
    than the size and density of the network would produce on their own,
    using conditional uniform graph tests and a permutation test for
    group crossing.

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

The three cards at the top of the Research tab are held to one height,
with the whole of each one behind the control in its heading. Opening a
card gives every table in it a search box, sortable headings, paging,
and a file that carries what is on screen rather than what was on screen
before the search. The people table and the statistics results open the
same way.

The Statistics tab asks a different question from the Research tab.
Everything on the Research tab describes what is in front of you; the
Statistics tab asks whether it is more than the size and density of the
network would produce on their own, which is the conditional uniform
graph test. Clustering, degree centralization, path concentration, group
separation, mean distance, degree assortativity, how much of the network
hangs together, and, for directed networks, reciprocity and the closed
and cyclic triad classes are each compared against several hundred
random networks under one of two null models. The E-I index is tested by
permuting the grouping rather than the ties, since the question is about
the grouping. No verdict rests on the proportion alone. Each result is
weighed four ways: the proportion, whether the network falls outside the
range the random ones actually produced, the sampling error on the
proportion itself, and what happens to the result when the best
connected person is removed. Each of those can change a verdict on its
own, and a result that moves back inside the range when one person
leaves is reported as a fact about that person. Every reading is written
about the network in front of you, in counts of what it has rather than
in shares, and any measure the run declined to make is listed with the
reason. If a local model is set up, the
results can be asked for in plain words, as the paragraph a researcher
would put in a methods and results section, or as the cautions a careful
reviewer would raise.

## The network map

The interactive map lets you explore relationships directly.

Nodes can be dragged, and connections follow. The view adjusts when the
network loads, and full-screen mode provides more space for exploration.

A live layout can be switched on from the map controls. It hands the
arrangement to a force simulation, so a node pulled out of a knot takes
what it is attached to with it; a node being held is pinned rather than
merely moved, so the people around it follow the hand rather than
pulling back. Double press a person, or press P with them focused, to
pin them in place for good, and press again to release. A spacing
control cycles through three distances for a map that came out too
dense to read or too sparse to see. One control returns the map to the
layout the server computed, which knows about the communities and
separates overlapping people in a way a few hundred frames of physics
will not find.

The forces are scaled by a temperature that falls each frame, so the
map arranges itself and then stops. Friction alone does not settle a
network: the leftover pull between a spring and a repulsion that never
both get their way keeps nodes shuffling by a pixel indefinitely, which
is what reads as jitter.

The simulation uses the Barnes and Hut approximation, so the repulsion
term costs people times the log of people rather than one calculation
per pair. The physics is not what limits this: at five thousand people
a frame of forces costs about fourteen milliseconds, which fits inside a
frame. What does not keep up at that size is writing several thousand
positions back into the document, so the control measures the machine it
is running on and switches itself off above the size where a redraw
stops fitting, with the reason stated on the control rather than left
for the reader to work out.

Groups remain readable across different visual settings. Tessera uses
combinations of shape and color so community identity does not depend on
color alone.

## Help

A Help screen opens from the header. It is a list of questions with
every answer closed, grouped by the situation rather than by the part of
the app: getting started, reading the map, going further, keeping your
work, the optional model, and when something is wrong.

## Saving your work

The Save control beside the network menu writes a session file holding
the ties themselves along with how you were looking at them: the sizing
measure, the labels, the sort order, the tie strength filter, the color
setting, the community algorithm, and any selected person. Resume reads
one back. The file is plain JSON, so it can be opened in any editor, and
it carries its own copy of the ties, which means resuming does not
depend on the original spreadsheet still being where it was.

Settings that belong to the machine rather than to the work, meaning the
model address, the model name, the color setting, and the setup route,
are kept separately in the configuration directory R provides. They are
not part of a session file and follow you across sessions without one.

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

### Setting up a model

The Local models screen offers two routes and does not choose for you.

Guided detects what is on the machine, says what is missing, and hands
over the one command that installs it. Tessera runs nothing on your
behalf in this route.

Managed downloads the Ollama release into a folder belonging to this app
and runs it from there. Nothing is installed into the system, and
deleting that folder undoes all of it. Windows is offered the guided
route only, because the vendor ships an installer there rather than an
archive.

Either way, once a runtime exists, models can be downloaded from inside
the app. A separate control checks the machine, after saying what it
will read, and marks each model in the catalogue as comfortable,
workable, or too large for the memory it found.

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

Tessera is built so network patterns stay readable across different
visual settings, and the claims below are measured rather than asserted.

-   Dark and light modes
-   Five color settings: standard, deuteranopia, protanopia, tritanopia,
    and monochrome
-   Shape and fill variant carry group identity before color does, which
    is why the monochrome setting works at all
-   Keyboard navigation for every person on the map
-   Spoken descriptions for people on the map
-   Reduced motion support

Two theme modes crossed with five color settings make ten states.
`tests/palette_test.mjs` resolves each one from the stylesheet the way a
browser would and measures every token in it: text at 4.5 to 1 against
the surface behind it, interface parts and graphical objects at 3 to 1,
and every pair of group colors against a separation floor after the
color vision simulation that palette is built for. The suite fails the
build rather than warning, and it also compares the exported figure's
copy of the palettes against the stylesheet, so the two cannot drift.

The first run of that suite found ninety three measurements below
threshold in colors a comment claimed had been checked. That is the
reason the check is a test rather than a comment.

## Tests

Two checks need nothing installed and run in under a second each, so
they come first here and first in CI:

``` sh
node tests/standards_test.mjs
node tests/palette_test.mjs
node tests/layout_test.mjs
```

The first is the house writing standard: no em or en dashes, no
contractions, no word from the banned lexicon in comments, strings, or
documentation, and a comment floor of fifteen percent in every source
file. The second is the color audit described under Accessibility. The
third checks the force layout behind the live map and then measures what
a frame costs on the machine it is run on, which is the number that
decides the size at which live layout is offered.

Run the R test suite:

``` r
Rscript tests/run_tests.R
```

Run the browser checks:

``` sh
npm install jsdom
node tests/dom_test.mjs
```

Two further suites drive the page the server actually sends rather than
markup written inside a test, so they need the app running. CI starts
it, saves the page, the client script, and the rendered control row,
then runs the appearance and full screen suites against those files.

The test suites cover:

-   Network calculations against known answers
-   Both dialects of the reproducible script
-   Generated explanations
-   Research statistics, including structural holes and group crossing
-   Every color token in all ten theme and palette states
-   The house writing standard across every file
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
