# Tessera 0.15.0

## Fixed

- Full screen had no visible way out. A native full screen element is
  the only thing the browser paints, and both controls sat outside it,
  the exit toggle in the control row and the see through button on the
  document body, so both disappeared at the moment they were needed and
  the Escape key was the only remaining route. Full screen now carries
  its own control bar inside the overlay, with an emphasized Exit full
  screen button beside the see through toggle. Escape still works and
  the button says so.

# Tessera 0.14.0

## Added

- The first release page now has the same shape used across these
  projects: an overview, highlights, installation instructions, and the
  license, kept in `.github/RELEASE_TEMPLATE.md` so every future release
  reads consistently rather than being reconstructed from a changelog. A
  version's specific changes from `NEWS.md` still appear underneath, so
  a returning user can see both what the app is and what moved.
- A check, `tests/release_notes_test.sh`, that confirms the template has
  no unfilled placeholder, names the current version, keeps its required
  sections, and that `NEWS.md` has a matching heading. It runs in CI on
  every push, so a broken template is caught long before a tag.

# Tessera 0.13.0

## Fixed

- Full screen, the Show everyone button, clearing the map when the data
  source changes, palette switching, and the record of having seen the
  walkthrough were all dead. Shiny requires a custom message handler to
  declare exactly one argument and throws when it does not, and a throw
  during a script's top level execution aborts the rest of that file.
  Three handlers took no arguments, so everything defined below the
  first of them never ran, including the entire full screen module. The
  browser console reported it as "handler must be a function that takes
  one argument". Every handler now takes its argument.
- The browser test stub accepted any function as a handler while Shiny
  refuses one with the wrong signature, which is why a fatal load error
  passed every suite. The stub now enforces the same contract, the test
  suite checks that the client script loads without throwing, and a
  reintroduced fault fails the run with a named cause.

# Tessera 0.12.0

## Changed

- Full screen now checks its own work. After a switch it measures
  whether the overlay covers the window, and if it does not, it says so
  on screen together with the reason: a page running inside a frame,
  such as an editor viewer pane, where browsers block full screen; a
  browser that offers no full screen mode; or a request that was
  declined. Three rounds of this control failing silently made the cause
  impossible to find from the outside.

# Tessera 0.11.0

## Fixed

- Full screen still had no effect. Two rounds of positioning an overlay
  through the stylesheet failed because a fixed element can always be
  trapped by an ancestor that creates a containing block. The control
  now calls the browser's own full screen primitive, which answers to
  nothing in the page layout, and the overlay is kept only to arrange
  the panels inside it and as a fallback where a browser refuses the
  request. Leaving full screen through the browser, by its own control
  or by Escape, restores the panels as well.
- The overlay carries its own positioning inline, so a stylesheet that
  fails to load cannot break the control.

## Added

- Continuous integration that runs all three test suites on every push
  and pull request.
- A release workflow that publishes a tagged version, taking its notes
  from the matching section of this file and attaching a source archive.
- A test suite for full screen that runs against the page and script the
  server actually sends, rather than markup written by the test.

# Tessera 0.10.0

## Fixed

- The full screen control had no effect. A fixed position element is
  only positioned against the viewport when no ancestor creates a
  containing block, and the map sits several framework containers deep,
  so the overlay was being trapped inside the page layout. Entering full
  screen now moves the map and the reading panel into an overlay
  attached to the body, and leaving puts them back in their original
  place and order.

## Changed

- The screenshot moved to `docs/screenshot-operator.png`, matching the
  layout used across these projects.

# Tessera 0.9.0

## Fixed

- Switching the network source back to Your own data left the previous
  sample network on screen. The map now clears when there is nothing to
  show.
- Communities of identical size were given the same label, which merged
  distinct groups on the map and in the key. A network could report
  eight groups in its summary while the key listed five. Groups are now
  ordered by size with the original group number breaking ties.
- The full screen control was created as a floating element that never
  became visible. It is now part of the control row, where it is
  reachable by keyboard like every other control.
- The brand sat hard against the first navigation tab, and labels and
  fields in the control row did not share a baseline because Shiny wraps
  different widgets in containers with different margins.

## Added

- A reset button that returns the app to its opening state, including
  clearing the chosen file.
- A screenshot in the documentation.

# Tessera 0.8.0

## Fixed

- The appearance toggle appeared to do nothing. Shiny serves files from
  `www/` with a Last-Modified header but no Cache-Control and no ETag,
  so browsers applied heuristic caching and could hold an old stylesheet
  against new markup. Asset URLs now carry a version and file time
  stamp. The app also detects a stale stylesheet at startup and says so
  on screen, rather than presenting a control that silently fails.

## Added

- `CITATION.cff`, `CONTRIBUTING.md`, `DESCRIPTION`, `LICENSE.md`, and
  `NOTICE`. Released under the PolyForm Noncommercial License 1.0.0.
- An end to end test suite for the appearance toggle that runs against
  the page the server actually sends.
- The walkthrough now runs on a first visit only and stays available
  from the navigation bar.

## Changed

- Attribution for R, Shiny, igraph, tidygraph, ggraph, and bslib appears
  in the documentation and in a colophon at the foot of Settings.

# Tessera 0.7.0

## Fixed

- Dragging a node moved the node but not its ties, because a helper
  removed during an earlier rewrite was still being called and threw on
  every pointer move.
- Node sizing rescanned every person on each call, which made building a
  map quadratic and re-scanned the whole network on every pointer move
  during a drag.

## Added

- A glyph system of twelve base shapes crossed with three fill variants
  across twelve colors, giving thirty six combinations that are
  distinguishable by shape alone before color is considered. Group
  identity no longer collapses into a shared bucket past the eighth
  group.
- Full screen map with the reading panel floating over it, optionally
  see through.
- Page level scrolling, which a fixed viewport height had prevented.

# Tessera 0.6.0

## Added

- A Research tab with extended centralities including PageRank and the
  HITS hub and authority scores, a choice of community detection
  algorithm, global diagnostics, the dyad and triad census, and an
  export of runnable igraph code.
- The interface moved to bslib with two persona tabs.

# Tessera 0.5.0

## Changed

- The analysis layer was rewritten as tidygraph and dplyr pipelines, and
  the exported figure now uses ggraph.

# Tessera 0.4.0

## Fixed

- The map did not render at all. Shiny serializes data frames column
  wise, and the renderer expected rows.

## Added

- A first run walkthrough, a reading panel of cards, a clickable key,
  person search, a tie strength filter, and a guide to local language
  models.
