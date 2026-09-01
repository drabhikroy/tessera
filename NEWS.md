# Tessera 0.25.0

A correctness round. The Statistics tab was
reported as failing with "argument is of length zero" on the messaging
sample, and following that message led to two further problems that had
been quietly wrong for longer.

## Fixed

- The Statistics tab no longer fails with a message that names nothing.
  The cause was igraph. From version 2.0 the power law fit computes its
  goodness of fit proportion only when asked for, so the value came back
  as NULL, assigning NULL into a list dropped the element entirely, and
  the screen read the missing element inside an if(). Nothing in the
  code was wrong on the machine it was written on, which is why R/compat.R
  now asks the installed igraph what it offers rather than assuming, and
  why every number the statistics screen reads is checked for its length
  before it is used.
- Distances are counted in steps rather than in tie weight. igraph reads
  a weight column as a cost, so a pair joined by a strong tie was coming
  out further apart than a pair joined by a weak one, which is backwards
  for a column that means how much two people work together. On the
  Research tab this had put the mean distance above the diameter printed
  directly under it, which is arithmetically impossible and is how it
  was caught. In the statistics battery it was worse: the observation
  was measured in weighted cost and compared against random networks
  measured in steps, so the mean distance test was reading many times
  further out than it should have been.
- Degree centralization is left out of the battery when each person's
  number of ties is the thing being held fixed. The measure is computed
  from the degree sequence and nothing else, so every random network
  returned the observed value exactly and the test reported a proportion
  of one under the heading "Within chance". That is not a weak result,
  it is not a result, and it is now named among the measures the run
  declined to make with the reason attached.
- The grouping travels into the statistics by name rather than by
  position. It happened to line up, because both graphs list people in
  the order the ties first mention them, but it would stop lining up the
  first time a node table arrived carrying people with no ties.
- Three checks in the suite were red before this round began and were
  not being seen, because shiny was attached partway down the file while
  the first screen it builds is constructed near the top, so the run
  aborted before it reached most of itself. The measure count in the
  global diagnostics check had not been moved when measures were added
  in 0.22.0 and 0.24.0, and the walkthrough slide count had not been
  moved when a slide was added in 0.20.0.

## Fixed, second pass

- The walkthrough no longer stops on the seventh slide. Seven of the
  eight slides build their picture as markup and one built it as a tag
  list, which the walkthrough hands to a function that takes text, so
  pressing Next onto that slide raised a message about a character
  vector and named neither the slide nor the picture. The same slide
  would have shown a blank space had it rendered, since the shapes had
  no frame around them. The walkthrough is now driven forward and back
  through every slide by the test suite, and each picture is checked for
  being a whole drawing rather than the parts of one.
- The app no longer raises on startup. The network chooser has not
  reported when the first pass through the reactive graph happens, so
  the choice arrives as nothing rather than as a name, and handing that
  to switch() raised four levels below an observer. What reached the log
  named neither the control nor the screen.
- A person's name can no longer become something the browser runs. Names
  come from an uploaded file, and the reading panel was building a line
  of script around each one with a single quote escaped. A name ending
  in a backslash escapes the escape, so a name of the right shape in a tie list
  reached the page as code. The name is now carried on the control as
  data and read back by one listener, which removes the class of problem
  rather than the instance. The model cards on the setup screen were
  changed the same way, and the suite now refuses any source file that
  writes a value into a line of script.
- A model name is checked before it is handed to the runtime. There is
  no shell involved, so there was nothing to inject into, but a name
  beginning with a dash would have arrived as an option rather than as a
  name.
- A restored session cannot name a color setting this app does not have.
  The value becomes a class on the page, and a session file is a file,
  so it is checked against the five real settings first.
- The downloaded figure carries the same title whichever control
  produced it. Two copies of the same list had drifted, and the one
  behind the single figure download had never learned the names of the
  two directed samples.
- The dyad and triad downloads write an explanation rather than an empty
  file when the network is undirected and has no census.

## Changed, second pass

- The three cards on the Research tab are held to one height, with the
  whole of each behind the control in its heading. Sizing them to their
  own content leaves three very different heights side by side, and
  letting the grid even them out leaves two cards of empty space beside
  one that is still cut off at the foot.
- The control in a card heading opens the whole card rather than one
  table in it, so a card holding a dyad table and a triad table opens
  with both, each with its own search box, sortable headings, paging,
  and file. The shortened table on the card is dropped from the copy and
  the full one is shown, so neither appears twice.
- Comments through the source no longer refer to past versions or to
  what a piece of code used to do. What each one says now is what the
  code does and why.

## Fixed, third pass

- The dialect control on the Research tab can be worked. Both dialects
  always computed correctly, but the pair of inline radio controls could
  not reliably be pressed: the markup Bootstrap 5 emits for an inline
  radio puts the control outside the box its label draws, and inside a
  flex row beside a wide code block that leaves a target that is hard to
  hit. It is a menu now, like every other choice in this app.
- A card only says it is cut off when it is. Community detection holds a
  menu, two numbers, and a sentence, and never fills the height the row
  is held to, so it was carrying a fade over empty space and a control
  offering to open something that was already all there. Both are driven
  by measuring the card rather than by markup, so a card earns its
  control by having more in it than fits.
- The menu inside a card has air above and below it. It was sitting
  against its own label, with the numbers under it reading as part of
  the control rather than as its answer.

## Changed, third pass

- The color settings are a list rather than a paragraph. Each option
  gives its name, a line saying who it is for, and its own swatches,
  each starting at the same left edge. Running the swatches on after
  labels of different lengths put five rows of shapes at five different
  distances from the margin, which is what made the list read as
  clutter: there was nothing for the eye to compare down.
- The color settings and the swatches that preview them moved into
  R/appearance.R. Three places have to agree about what counts as a
  color setting, and a list that three places read is one worth being
  able to point at, and one the test suite can reach.

## Changed, fifth pass

This pass is about what the Statistics tab actually says. Everything on
it computed correctly and none of it told a reader anything about their
own network.

- Every reading is now written about the network in front of the reader.
  A finding says how many of what this network has, what the random
  networks actually produced as a range, and what the gap amounts to in
  the same units: not "clustering was 0.216 against a chance average of
  0.164" but "41 of this network's 188 connected triples close, and
  across 500 shuffled versions that came out between 0.036 and 0.294".
  A reading that names a proportion and a threshold is a reading of the
  method rather than of the data.
- No verdict rests on the proportion alone. The American Statistical
  Association said in 2016 that a proportion below a threshold is not by
  itself evidence of anything, and the reason is arithmetic: it answers
  how often chance would beat this observation, which is a different
  question from whether the difference is large, whether it would
  survive a second sample, or whether it rests on one person. Three
  further checks now weigh alongside it, and each can change a verdict
  on its own.
- The range the random networks produced is reported beside every
  result, as the middle 95 percent of what they gave. An average alone
  leaves a reader nothing to judge a gap against, which is how a
  difference in the third decimal place comes to look like a result.
- The proportion is reported with its own sampling error. One computed
  from five hundred random networks is an estimate, and quoting three
  decimal places of it without saying so claims a precision the method
  does not have. When that error straddles the threshold the verdict
  reads as near the edge, and the cure is more random networks rather
  than a firmer sentence.
- Every measure is recomputed with the best connected person removed. A
  network level number computed from nineteen people can rest almost
  entirely on one of them, and a proportion cannot tell you that. A
  result that moves back inside the range when one person leaves now
  reads as resting on that person, and says whose.
- Each reading names which null model produced its range, since holding
  the number of ties fixed and holding each person's own number of ties
  fixed answer different questions and the answer means different things
  under each.
- The two further readings say what they found rather than what the
  measures are. The small world reading names which half held and which
  did not; the connection counts reading leads with the plain fact of
  whether the spread is wider than the average, which needs no
  distribution fitted to it, and says outright when a network is too
  small for the fitted tail to mean much.
- The local model is given the network rather than three numbers per
  measure. It previously received a list of observed values, chance
  averages, and proportions, and a list of numbers is the only honest
  thing to write from a list of numbers. It now gets the size, density,
  direction, and grouping of the network and the whole reading of each
  finding, and is asked to group the findings that point the same way,
  use at most four numbers, and say plainly which results were beyond
  chance and which were not. It still computes nothing and still never
  sees the network.
- The file control and the model control are no longer side by side. One
  saves what is on the screen and the other asks a program to write
  about it, and next to each other they read as one control. The
  download control is also set out as a flex box: Shiny renders it as a
  link with button styling, and a link puts its label on the text
  baseline, which is what made it tall and left its label off center.

## Fixed, fourth pass

- The live layout settles instead of jittering. Friction alone never
  stops a network: every arrangement has forces still pulling on it at
  rest, since a spring wanting to be a certain length and a repulsion
  wanting to be further apart never both get their way, so the leftover
  pull shuffles nodes back and forth by a pixel forever. The forces are
  now scaled by a temperature that falls each frame, so the map arranges
  itself freely at first, comes to a stop, and stays stopped. Taking
  hold of a node warms it back up, because a drag is a new question.
- The menu inside a card has real space around it. The gap has to be
  larger than it looks like it needs to be: a row of numbers set at
  nineteen points carries most of a line of leading above the digits, so
  a box margin reads as roughly half itself and a gap that measures
  right still has the numbers sitting against the control that made
  them.

## Added, fourth pass

- People can be pinned in place. Dragging someone out of a knot only
  helps while the forces are running; pinning is how a reader says where
  someone belongs and has it stay there. Double press a person to pin
  them, double press again to release, or press P with the person
  focused. Pinned people are marked on the map, since a pin that cannot
  be seen leaves an arrangement with parts that will not move for
  reasons nobody remembers.
- A spacing control on the map, cycling through three settings and
  naming the one it is on. Three steps rather than a slider: a slider in
  a row of square controls is a different kind of thing in a place with
  no room for it, and three steps cover the reason anyone reaches for
  this, which is a map that came out too dense to read or too sparse to
  see.
- The local model can be asked for three different readings of one set
  of statistical results: the findings in plain words, the paragraph a
  researcher would put in a methods and results section, or the
  cautions a careful reviewer would raise. Which one a reader wants
  depends on why they came. All three are rewordings of the same
  findings; the model still computes nothing and still never sees the
  network.

## Added

- Five more tests in the battery: path concentration, which asks whether
  the routes through a network funnel through a few people rather than
  whether the ties do, and the two come apart in exactly the case worth
  knowing about, which is a person of modest degree sitting between two
  halves; whether well connected people connect to each other or to
  poorly connected ones; how much of the network hangs together in one
  piece; and, for directed networks, the closed and the cyclic triad
  classes, which are the directed reading of closure and the arrangement
  a ranking cannot produce.
- A standardized score beside each proportion. A proportion cannot go
  below one over the number of random networks, so two results that both
  read 0.002 can sit two standard deviations out or twenty.
- Every table in the app can be opened at full size, with a search box,
  sortable headings, paging, a copy control, and a file. The file
  carries what is on screen, so a table filtered to one group downloads
  as that group. This is written here rather than taken from a table
  library: two of the tables are markup this app writes by hand with a
  magnitude bar inside a cell, which a library that owns its rendering
  would drop, and the palettes are carried by the stylesheet, which a
  library would need overriding in all ten appearance states.
- A live layout on the map, and a control that puts it back. A node
  being held is pinned in the forces rather than merely moved, so the
  people attached to it follow the hand instead of being pulled back
  toward where they were. The physics is Barnes and Hut, so the
  expensive term costs people times the log of people rather than one
  calculation per pair.
- A benchmark that measures the cost of a frame on the machine the app
  is running on, and a live layout control that turns itself off with a
  stated reason above the size where a redraw stops fitting in a frame.
  On the machine this round was built on the forces cost 13.5 ms per
  frame at five thousand people, which is inside a frame; what does not
  keep up at that size is writing the positions back into the document,
  which is why the limit is set by measuring a redraw.
- Measures a run declined to make are listed with the reason. A test
  that disappears without a word is read as a test that passed.

## Changed

- The Research tab cards size to what is in them. Grid stretches its
  items to a common height by default, so a card holding a short table
  and a card holding a menu both became as tall as the sixteen row
  census beside them and each carried half a screen of nothing
  underneath.
- The triad card shows the arrangements the network actually has,
  largest first, which is usually four or five rows rather than sixteen.
  The empty arrangements are one control away rather than behind a
  scrollbar on the card.
- The extended centralities card shows ten people rather than all of
  them, with the rest in the opened table.
- The statistics run reports progress as it goes. The bar previously sat
  a fifth of the way across for the whole run, which reads as an app
  that has hung.
- The null model is measured in one pass rather than once per measure.
  Several hundred random graphs were being held in a list and walked
  again for every statistic, so each new measure cost another full walk;
  now each random graph is made, measured, and thrown away. Eleven
  measures cost less than the five did.

# Tessera 0.24.0

## Added

- A Statistics tab. Everything else in the app describes what is in
  front of you; this asks whether it is more than the size and density
  would give on their own. A network of fifty people at nine percent
  density already has a clustering, a centralization, and a group
  separation before anyone has done anything social, so a number on its
  own cannot say whether a pattern means anything.
- Conditional uniform graph tests for clustering, degree centralization,
  group separation, mean distance, and reciprocity where the data is
  directed. This has been the standard approach since Anderson, Butts,
  and Carley showed in 1999 how strongly size and density alone drive
  graph level indices. Two null models are offered because they answer
  different questions: holding the number of people and ties fixed asks
  whether the pattern exceeds what this much connection would give,
  while holding each person's number of ties fixed asks whether it
  exceeds what these particular people, with exactly the ties they have,
  would give. Surviving the second is a claim about arrangement rather
  than about volume.
- A permutation test for the E-I index. The measure is about the
  grouping, so the null holds the network fixed and shuffles who is in
  which group rather than randomizing ties.
- Two further readings: whether the network is clustered like a lattice
  while staying short like a random graph, reported as two ratios rather
  than one small world number because the single number hides which half
  is doing the work; and whether connection counts are heavy tailed,
  fitted by the Clauset, Shalizi, and Newman method.
- Every result carries its numbers and its sentence on the same card. A
  table of proportions with the readings somewhere else is how a reader
  ends up quoting a number whose meaning they never saw. The results
  download as CSV and can be restated by the local model.
- The triad table opens at eight rows with a control for all sixteen,
  and both census tables download as CSV.
- One control that takes everything at once: people, summary,
  diagnostics, centralities, both censuses, the ties, both script
  dialects, the map, the statistics if they have been run, and a README
  listing what is inside.

## Changed

- The authorship line closes the license sentence on the Overview screen
  rather than standing on its own above it.
- A rule separates the restate control from the computed reading above
  it, since one acts on the other.

# Tessera 0.23.0

## Added

- A route finder. Choose two people under the reading panel and the
  shortest chain of connections between them lights up on the map, with
  the names along it listed in order. Tracing a path by eye is guesswork
  on any map with more than a dozen people on it, and it is the question
  people ask of a network picture more than any other. The answer is
  computed where the graph is, and the panel says plainly that it is one
  of possibly several shortest routes and that nothing is claimed to
  travel that way.
- Tie marking, above the map. Only routes marks the ties whose removal
  would break the network into more pieces than before, each one the
  sole connection between what sits on either side of it. Ties between
  groups marks every tie joining two different groups. Neither is a
  property of a person, so no centrality column points at them, and
  neither can be found by looking. Both are marked by weight and dash as
  well as color, so they survive the monochrome setting.
- The triad census carries a sentence for each of the sixteen codes
  saying what arrangement it counts, and both census tables carry the
  share alongside the count. The Holland and Leinhardt codes are exact
  and mean nothing to a reader who has not memorized them.
- The Overview screen names its author.

## Fixed

- The dyad and triad census printed its own markup as text. The tables
  were built by calling renderTable and dropping the result into a
  tagList, which escapes it. They are written directly now.
- Counts in the census appeared as decimals.
- The local model was being handed the reading panel, which explains the
  app as well as the network, so it spent paragraphs restating what a
  group is and how groups are found. It receives findings now: short
  statements of fact carrying the numbers and the names, with an
  instruction not to explain any measure or define any term. The
  definitions stay on screen where they were already written, above the
  answer, in prose nobody had to generate.

# Tessera 0.22.0

## Fixed

- The dyad and triad census failed with a message about no applicable
  method for as.igraph. tidygraph supplies that method for its own class
  and igraph supplies none for its, and the census started being handed
  a plain igraph in 0.21.0 when the directed copy arrived. Every
  research function accepts either form now, and the test suite checks
  both.
- The panel did not scroll to the model's answer. The message and the
  rendered answer arrive in the same flush, so looking once on the next
  animation frame found nothing and gave up. It now looks for up to two
  seconds, and scrolls the panel itself rather than asking the browser
  to scroll whatever it decides is nearest, which could move the page
  behind the panel instead.
- Folding the reading panel in full screen hid its contents and left the
  box exactly as tall as before, which is a fold that folds nothing. The
  fixed height the panel carries in the split view was winning. In full
  screen it takes its height from its contents.

## Changed

- The model's answer is broken up further. Splitting on blank lines is
  only as good as the model's obedience, and three paragraphs of nine
  sentences each is still slabs, so any paragraph over roughly three
  hundred characters is cut again at sentence boundaries. A line the
  model numbered or bulleted itself keeps that shape rather than being
  flattened into prose.
- The picture beside the description is a network rather than a pattern.
  The tiles vary in size the way sized nodes do, the joins run between
  them rather than across the field, the quiet tiles fade outward, and
  the larger marks carry the four square motif of the app mark inside
  them.
- The second Open a sample network at the foot of the Overview screen is
  gone. The same control sits at the top, and repeating it at the bottom
  of a page a reader has already decided about adds nothing.

## Added

- Structural hole measures in the extended table. Constraint is Burt's
  measure of how far a person's contacts are already connected to each
  other, so a low score is the brokerage position. Effective size is the
  same idea counted from the other side. Neither is derivable from the
  centralities already present, which is the test of whether a measure
  earns a column.
- Coreness, the deepest nested core a person belongs to. It separates a
  dense center from a fringe in a way the count of ties cannot, since a
  person can have many ties and all of them to the edge.
- Three network level measures in the diagnostics. Freeman degree
  centralization says how far the network is from one where a single
  person holds every tie, which density cannot: two networks with the
  same density can be a hub and spoke or an even mesh. Degree
  assortativity says whether well connected people connect to each
  other. The Krackhardt and Stern E-I index says how much of the tie
  volume crosses between groups rather than staying inside them, which
  is the measure most often wanted in applied work and least often
  present in a general tool.
- A Help section defining all of them, since a column headed constraint
  with no explanation anywhere is worse than no column.

# Tessera 0.21.0

## Added

- Two directed sample networks, an advice seeking one and a messaging
  one, so the dyad and triad census has something to work on. They are
  the same size and differ in exactly what the census measures: advice
  runs one way and is mostly asymmetric, messages come back and are
  mostly mutual. Reading the two side by side is the fastest way to see
  what the census is telling you. A test checks that the two really do
  differ, since a sample that failed to would teach the wrong lesson.
- Models and the managed runtime can be removed from inside the app.
  Both ask first, because a download can be repeated and a deletion of
  several gigabytes cannot be undone from here. Only the managed runtime
  can be removed this way, and the screen says so: a runtime installed
  through a package manager belongs to the system and should leave the
  way it arrived.
- A model chooser beside the restate control when more than one model is
  present. Someone who downloaded two did so in order to compare them,
  and sending them to Settings to type a name is not a comparison.
- The panel scrolls to the model's answer when it arrives. A result a
  reader has to go looking for reads as a control that did nothing.

## Fixed

- The download control offered to download a model that was already
  downloaded, on a card that said it was already downloaded. It now
  offers to use it, with downloading again and removing it as the two
  secondary choices.
- The model answer arrived as one unbroken block. The request now asks
  for short paragraphs and for the restatement to begin without
  announcing itself, an opening line that announces one anyway is
  stripped, and the answer is presented as paragraphs under the name of
  the model that wrote it, set apart from the computed text so the two
  are never mistaken for each other.
- The picture beside the description on the Overview screen was the same
  drawing as the worked example further down, so the page showed one
  small network twice. The hero is now a field of tiles with connections
  closing across it, which is the idea rather than an instance of it,
  and nothing in it invites interpretation.

## Changed

- Four header links became two groups. The walkthrough is help, so it
  opens from inside Help, and the appearance toggle is a setting, so it
  lives in Settings above the color settings. What is left is one thing
  the app can set up for you and two places to look things up, with a
  gap between them.
- Help is a list of groups down the left with one group of questions on
  the right. Six groups stacked in a single scroll meant a reader
  looking for the last one passed every answer in the first five.

# Tessera 0.20.0

## Added

- A Help screen, opened from the header. It is a list of questions with
  every answer closed, grouped by the situation a reader is in rather
  than by the part of the app involved: getting started, reading the
  map, going further, keeping your work, the optional model, and when
  something is wrong. Help that arrives as one long page is help nobody
  reads, because finding the paragraph that matters costs more than
  guessing.
- The reproducible script comes in two dialects. The igraph version is
  the shortest path from an edge list to the same numbers, with one
  dependency. The tidy version does the same work through tidygraph and
  ggraph, which is what this app itself uses, and produces a figure
  worth putting in a document rather than a diagnostic plot.
- A walkthrough slide about the optional model, with its own picture.
  Readers otherwise met the feature for the first time as a control that
  failed.
- The palette audit checks two conditions the protanopia palette exists
  to satisfy: that no color loses more than about a third of its light
  under the simulation, and that every color sits a measured distance
  from the one holding the same slot in the deuteranopia palette.

## Fixed

- The zoom and full screen controls floated on top of every dialog. They
  carried a stacking value above the Bootstrap dialog layer, which they
  did not need, because in full screen they sit inside the overlay and
  rise with it.
- The deuteranopia and protanopia palettes looked almost identical. Both
  lose the red to green axis, so the same constraints produced nearly
  the same answer twice. What actually differs is that protanopia also
  darkens the long wavelength end, so a deep red keeps its hue distance
  and loses its light, arriving muddy rather than merely shifted. The
  protanopia palette is rebuilt with that as an explicit condition and
  is now visibly its own palette.
- The reading panel went on reporting that no model answered after one
  had been installed. Preferences were read once into a list at startup,
  and the settings dialog does not exist until it is opened, so a model
  chosen during setup never reached the check. The address and the model
  name are reactive values now, a successful download points the app at
  what it downloaded, and a stale complaint is cleared.
- The restate control could not tell three different problems apart. A
  server that is not answering, a server holding no model, and a server
  holding a different model than the one named in Settings now each get
  their own message.
- Installing the runtime went quiet for several minutes. The download is
  streamed in chunks and reports megabytes as they arrive, the first
  start waits up to thirty seconds rather than six and says what it is
  waiting for, and a second press while either is running is refused
  with an explanation rather than starting the work again.

## Changed

- The model cards are the selection control. Choosing from a menu beside
  a grid of cards asked a reader to match a name to a card and then look
  away from both. The cards are buttons now, the chosen one is marked by
  border, fill, and state, and a model already downloaded says so on its
  own card.

# Tessera 0.19.0

## Changed

- The map layout runs in three passes rather than one. A force directed
  layout on its own produces the picture people recognize from a default
  graph plot: a knot in the middle, a few nodes flung wide, and clusters
  that overlap because nothing in the model knows they are clusters. The
  forces still decide the shape, and then each community is gathered a
  fifth of the way toward its own center, and anything sitting closer
  than a node width is pushed apart. Neither pass touches a number; the
  grouping is computed from the ties either way, and the layout is only
  being asked to agree with it.
- The magnitude bar in the people table is a short track under its
  number rather than a wash across the cell. The wash read as a selected
  row, and its length depended on how wide the column happened to be,
  which is not a property of the data. The numeric columns now take the
  width of their contents instead of an equal share of the table, so
  Direct ties no longer holds three hundred pixels for two digits.
- The local model screen is three steps: choose a route, get the runtime
  running, pick a model. Which step you are on is computed from what is
  actually installed rather than from a click count, and a step that is
  done says so and stays readable. The dialog is wider, so the four
  model cards sit side by side instead of stacking, and the explanation
  that used to open it is one line.
- Exit full screen is the same four corners as the control that enters
  it, turned inward, rather than a phrase beside an icon.
- The walkthrough no longer slides down from above the window on every
  slide. Dialogs fade, and hold still for anyone who asked for less
  motion. The text is updated for the Overview tab, the five color
  settings, saving and resuming, and the setup screen.

## Added

- The reading panel in full screen can be resized and folded away. A
  grip on its left edge sets the width by pointer or by arrow key, and a
  control in its own bar folds it to a single strip so the whole network
  is visible without losing the way back. It also starts wider, since
  the old fixed width was narrower than the text it holds.

# Tessera 0.18.0

## Added

- A local model setup screen with two routes, chosen by the reader
  rather than assumed. Guided detects what is on the machine, says what
  is missing, hands over the one command that fixes it, and executes
  nothing. Managed downloads the Ollama release into a folder belonging
  to this app, runs it from there, and installs nothing into the system,
  so removing that folder removes all of it. Windows is offered the
  guided route only, because the vendor ships an installer there rather
  than an archive and offering the other route would be a promise the
  app cannot keep.
- A hardware report behind its own control. It says what it will read
  before it reads it, and it reads four things: the operating system,
  the amount of memory, the number of cores, and whether a graphics
  processor is present. Nothing else, and nothing leaves the machine.
  Once it has run, each model in the catalogue is marked comfortable,
  workable, or too large for this machine, and one is suggested.
- Models can be downloaded from inside the app once a runtime exists,
  on either route, since a model pull is a fetch into the runtime's own
  store rather than a system install.
- Saving and resuming. A session file carries the ties themselves along
  with the sizing measure, label mode, sort order, tie strength filter,
  color setting, community algorithm, and any selection, so resuming
  does not depend on the original file still being where it was. It is
  plain JSON, readable in any editor.
- Preferences that outlive a session: the model address, the model name,
  the color setting, and the chosen setup route, kept in the config
  directory R provides. They are deliberately not part of a session
  file, since they belong to the machine rather than to the work.
- Restate with the local model now leads somewhere when nothing answers
  it. The message arrives with a control that opens the setup screen,
  in the place the reader was already looking.

## Fixed

- Switching the reading panel between solid and see through refitted the
  map, throwing away the reader's zoom and pan. The refit is now guarded
  on the measured size of the drawing area, so the map moves when the
  space it has changes and at no other time. The reset control still
  refits on request.
- See through mode was not very see through. Two translucent layers were
  stacked, the panel and the cards inside it, which read as one opaque
  one. The cards lose their own fill entirely, the panel drops to
  roughly a quarter opacity, and the blur behind it does more work.
- The icons in the map controls sat off center. A plus, a minus sign,
  and a circled dot are three glyphs from three parts of a font with
  three different optical centers, which no amount of box centering
  fixes. All four controls are now geometry on one twenty unit grid.
- The brand and the tab links still sat on different center lines. The
  first attempt missed the collapse wrapper the nav sits inside, and
  left the underline on the active tab adding height to that link alone.
  Every level between the bar and the text is centered now, and every
  link carries the same border with only the active one colored.

## Changed

- Solid panel and See through panel are one icon control rather than two
  words that swap. A control whose label changes has to be read twice
  before a reader knows which state they are in; the pressed state is
  carried by color and by aria-pressed instead.

# Tessera 0.17.0

## Fixed

- The app failed to start with "object APP_TAG not found". Shiny sources
  `app.R` into an environment of its own, while `source()` called from
  inside `app.R` loads into the global environment, so a function
  defined in `R/` cannot see a value assigned at the top of `app.R`. The
  Overview screen was the first file in `R/` ever to reference one. The
  constants now live in `R/info.R`, sourced alongside everything else,
  and `tests/run_tests.R` builds every screen from the sourced files
  alone so the same mistake fails a test rather than a launch.
- The map was fitted to a square view inside a panel that is not square,
  so the browser letterboxed it. The network sat in a strip down the
  middle with dead space on either side, and a wider window made the
  dead space larger. The view is now fitted to the shape of the panel,
  and the zoom controls keep that shape rather than forcing a square
  back on the first press.
- The map only refitted on a window resize, which missed every other way
  the panel changes shape. A ResizeObserver on the panel itself now
  catches a reading panel that grows, a full screen switch, and a phone
  being turned.
- The map panel took its height from whatever the reading panel beside
  it needed, so a long card stack stretched it and a taller window
  stretched it again without adding anything to see. Both panels now
  take a height tied to the viewport, and the reading panel scrolls
  inside it.
- The brand and the tab links sat on different center lines in the
  navigation bar. The two are separate children with separate padding,
  one from bslib and one from Bootstrap, so they are now stretched to
  full height and centered rather than matched by adjusting padding.

## Changed

- The control row was eight equal controls under eight uppercase
  labels. It is now three groups with a quiet heading each: what network
  is loaded, how the map is read, and the actions that apply to the
  whole view. Labels lost their uppercase and their letter spacing,
  since a control row is scanned rather than read.
- Full screen has a second control on the map itself, beside zoom and
  reset, where a person looks for a view control. The word version stays
  in the control row, because a keyboard reader meets the row first.
  Both drive the same toggle.
- Each reading card now leads with its finding and puts the
  qualification behind a disclosure. Nothing is removed and no round
  trip is needed to open one. Four cards of full paragraphs is a wall,
  and a reader facing a wall skips all of it rather than some of it.
- The people table opens at twelve rows with a control to show every
  person, and the column it is sorted by carries a magnitude bar behind
  its digits. The numbers are unchanged and the whole table is present
  in the markup, so finding and copying still see all of it.

# Tessera 0.16.0

## Added

- An Overview screen, now the leftmost tab. It says what the app does,
  shows a small network beside the sentences the reading panel would
  write about it, gives the shape of the input file as a table, and
  states where data goes, all before anything is loaded. A person
  deciding whether to upload their own data had no way to find any of
  that out first.
- A separate protanopia color setting. Deuteranopia and protanopia both
  lose the red to green axis and used to share one palette here, but
  they lose it differently: under protanopia the red end also darkens,
  so a pair of colors that stays apart for one reader can collapse for
  the other. There are now five color settings rather than four.
- A palette audit, `tests/palette_test.mjs`, which reads the stylesheet,
  resolves all ten theme and palette states the way a browser would, and
  measures every token against WCAG 2.2 AA, every pair of group colors
  against a separation floor under the color vision simulation that
  palette is built for, and the exported figure's own copy of the
  palettes against the stylesheet it is supposed to mirror. It runs in
  CI ahead of everything else.
- A house writing standard gate, `tests/standards_test.mjs`, covering em
  and en dashes, contractions, a banned lexicon, and a comment floor of
  fifteen percent in every source file.
- Repository scaffolding matching the other projects: a security policy,
  a code of conduct, a pull request template, issue templates, a
  dependabot configuration for the workflow actions, and a
  `.gitattributes` that normalizes line endings.

## Fixed

- Ninety three color measurements were below their threshold. The
  stylesheet carried a comment saying its colors had been checked at 4.5
  to 1; the first run of the new audit found otherwise. Every group
  color has been rebuilt to clear the interface threshold against the
  panel it sits on, in both modes.
- Light mode redefined only a handful of the twelve group colors and
  inherited the rest from dark mode. Yellow sat at 1.32 to 1 against a
  white panel. All twelve are now defined for each mode.
- Ties were painted with an opacity layer over the edge color, so the
  color a reader saw was the blend rather than the token, and the token
  was the thing being checked. The opacity is gone and the token now
  holds the value that reaches the screen.
- The exported figure kept its own copy of the palettes, which had
  drifted from the stylesheet. It now mirrors the light mode blocks,
  since the figure sits on a white ground, and the audit compares the
  two on every run.
- One hairline token was doing two jobs. Panel borders, button borders,
  and table row rules all read the same value, which cannot be both
  quiet enough for a row rule and strong enough for a control boundary.
  Controls and containers now clear 3 to 1; dividers use a separate
  token held to a presence floor.
- `tests/fullscreen_test.mjs` had never run. It was added three versions
  ago, after full screen broke three times, and was never wired into the
  workflow. It now runs in CI against the page the server sends, with
  the control row rendered from the same function the app uses rather
  than from a copy written out in the test.

## Changed

- The test workflow runs the two cheap gates first, so a banned word or
  a color below threshold is reported in seconds rather than after an R
  toolchain has been installed. Both workflows now declare the
  permissions they need.
- Comments in every source file meet the fifteen percent floor. The
  additions explain decisions rather than restating code.

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
