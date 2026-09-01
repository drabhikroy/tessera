# Contributing to Tessera

Thank you for considering a contribution. This is a noncommercial open source
project under the PolyForm Noncommercial License 1.0.0, and contributions are
accepted under those same terms.

## Before you start

Open an issue describing the change before writing code. A new graph measure,
a change to the map, and a bug fix each want a different conversation, and an
issue saves you from building something that does not fit the design.

## Running the app

```r
shiny::runApp("tessera")
```

Requires R 4.1 or later, for the native pipe, with shiny, bslib, igraph,
tidygraph, ggraph, ggplot2, dplyr, tidyr, purrr, tibble, readr, and jsonlite.
The curl package is needed only for the optional local model connection.

## Running the tests

Two gates need nothing installed and finish in about a second. Run them
first, because they fail on the things easiest to introduce by accident and
hardest to catch by eye:

```sh
node tests/standards_test.mjs
node tests/palette_test.mjs
node tests/layout_test.mjs
```

The first is the house writing standard: no em or en dashes anywhere, no
contractions, no word from the banned lexicon in comments, strings, or
documentation, and comments making up at least fifteen percent of the lines
that hold something in every source file. The lexicon and its exemptions for
names the languages define, such as `text-align`, live in `standards/`.

The second measures color. It reads `www/styles.css`, resolves all ten theme
and palette states the way a browser would, and checks every token against
WCAG 2.2 AA, every pair of group colors against a separation floor after the
color vision simulation that palette is built for, and the exported figure's
copy of the palettes against the stylesheet it mirrors. If you change a color,
this is the check that says whether you may.

```r
Rscript tests/run_tests.R
```

```sh
npm install jsdom
node tests/dom_test.mjs
```

All suites must pass before a pull request is reviewed, and GitHub Actions
runs them on every push. Together they cover:

- **Graph math.** Measures are checked against small graphs with known
  answers, where betweenness, cut points, and degree can be verified by hand
  rather than by trusting the library.
- **Research tier.** Every registered community algorithm returns a partition
  and a finite modularity, the global diagnostics report their nine measures,
  and the exported script is runnable igraph code.
- **Prose.** The generated reading is checked for structure and for numbers
  that match the metrics behind them, so a sentence can never claim more than
  the data supports.
- **Contrast.** Every color pair that carries meaning is checked against WCAG
  2.2 at 4.5 to 1, in all theme and palette combinations.
- **Writing sweeps.** Banned lexemes, em and en dashes, contractions, and
  comment density.
- **DOM.** The real map renderer under jsdom, including the glyph system,
  node dragging with its ties, the spotlight, and full screen behavior.
- **Live boot.** The app starts and serves its page.

Before tagging a release, check that the release notes are ready:

```sh
sh tests/release_notes_test.sh
```

It confirms `.github/RELEASE_TEMPLATE.md` has no unfilled placeholder, names
the version in `DESCRIPTION`, still has its overview, highlights,
installation, and license sections, and that `NEWS.md` has a heading for that
version. The release workflow builds the actual release page from these two
files, and CI runs this check on every push so a broken template is caught
long before a tag is pushed.

Two further suites run against the page the server actually sends rather than
a reconstruction of it. The appearance toggle:

```sh
# with the app running on port 7823
curl -s http://127.0.0.1:7823/ -o /tmp/page.html
curl -s http://127.0.0.1:7823/styles.css -o /tmp/styles.css
node tests/theme_test.mjs /tmp/page.html /tmp/styles.css
```

And full screen, which needs the rendered control row alongside the page:

```sh
Rscript tests/render_controls.R /tmp/controls.html
curl -s http://127.0.0.1:7823/ -o /tmp/page.html
curl -s "http://127.0.0.1:7823/graph.js" -o /tmp/graph.js
node tests/fullscreen_test.mjs /tmp/page.html /tmp/graph.js /tmp/controls.html
```

Both suites exist for a reason worth knowing before you touch the interface.
Shiny serves files from `www/` with a Last-Modified header but no Cache-Control
and no ETag, so a browser can hold an old stylesheet against new markup. The
result looks exactly like a dead control, and it will not reproduce in any test
that fetches fresh. Asset URLs therefore carry a version stamp, the app warns
on screen when it detects a stale stylesheet, and these suites check both.

The same lesson applies to layout. Full screen was reimplemented twice through
the stylesheet before the cause was understood: a fixed position element is
only positioned against the viewport when no ancestor creates a containing
block, and the map sits several framework containers deep. Anything that must
escape the page layout should call the browser primitive rather than trusting
the cascade, and should carry its own inline positioning as a fallback.

## Adding a graph measure

Per person measures live in `extended_centralities()` in
`R/research_metrics.R`, which returns one tidy row per person. Add a column
there and it appears in the research table and its CSV export without further
wiring.

Community detection algorithms are registered in two places that must agree:
`community_partition()` for the computation and `community_methods()` for the
menu label. Anything slower than roughly quadratic needs a size guard, as
Girvan Newman has, so that a large upload cannot lock the session.

Measures shown on the Explore tab need a plain name as well as a technical
one. The mapping lives in `size_choices` in `app.R`: direct ties is degree,
between groups is betweenness, quick reach is harmonic closeness, and well
connected circle is eigenvector centrality. A general reader should never meet
the word centrality.

## Adding to the map

The map is hand written SVG in `www/graph.js` rather than a charting library,
which is what allows the keyboard navigation, the palettes, and the drag
behavior. Two rules keep it honest:

- Layout coordinates are computed once and held. Changing node size or color
  must not recompute positions, or the map will jump under the reader.
- Anything that carries meaning needs a channel besides color. Group identity
  uses twelve shapes crossed with three fill variants, tie strength uses
  thickness, and fragility uses a dashed ring.

If you add an interaction, add a DOM test that asserts the state actually
changed. An assertion that a value merely exists will pass while the feature
is broken, which is how a drag that never moved its ties survived a release.

## Style

The codebase follows a few conventions that the sweeps enforce:

- No em dashes or en dashes anywhere, including comments.
- No contractions in code, comments, or interface text.
- Comments explain why a choice was made, not what the next line does.
- Comment density between ten and twenty five percent.
- Plain declarative prose in anything a reader will see.

## Accessibility

Accessibility is not a later pass. Any contribution that touches the interface
should preserve the following, all of which are checked or reviewed:

- Contrast at 4.5 to 1 across all themes and palettes.
- Meaning carried by shape as well as color.
- Keyboard reachability, with visible focus. Every person on the map is a
  keyboard stop with a spoken description, not only a row in the table.
- Touch targets of at least 44 pixels.
- Motion that honors the reduced motion preference.

## Interpretation and the local model

Every sentence in the reading panel is computed from the numbers in
`R/narrative.R`, so the prose cannot say more than the data supports. Keep it
that way. The optional local model receives the already computed paragraphs
and is asked to reword them, with the numbers passed in so it restates rather
than invents. A contribution that lets a model produce a figure, a ranking, or
a claim of its own will not be merged.
