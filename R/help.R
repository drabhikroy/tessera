# help.R
# The Help screen: everything a reader might need to look up, in short
# sections they can open one at a time.
#
# Copyright Abhik Roy. Released under the PolyForm Noncommercial
# License 1.0.0. See LICENSE.md.
#
# The shape is deliberate. Help that arrives as one long page is help
# nobody reads, because finding the paragraph that matters costs more
# than guessing. Each section here is a disclosure that starts closed,
# so the whole of it fits on one screen as a list of questions, and only
# the answer a reader asked for opens.
#
# The order follows the order a person meets the app rather than the
# order the code is arranged in: getting something on screen, reading
# it, going deeper, keeping the work, the optional model, then the two
# things people come to help for after something has gone wrong.
#
# Nothing here explains an idea that the reading panel already explains
# in place. Help that repeats the interface goes stale the moment the
# interface changes, and a reader who finds two different answers
# believes neither.

# One section. The heading is a question a person would actually ask,
# not the name of a feature, because a reader scanning this list is
# looking for their problem rather than for our vocabulary.
help_section <- function(question, ..., open = FALSE) {
  tags$details(class = "help-section", open = if (open) NA else NULL,
    tags$summary(question),
    div(class = "help-body", ...))
}

# A short labeled definition, used where a term in the app needs one
# sentence rather than a paragraph.
help_term <- function(term, meaning) {
  div(class = "help-term",
    tags$span(class = "term-name", term),
    tags$span(class = "term-meaning", meaning))
}

# The groups become tabs down the left rather than headings stacked in
# one column. Six groups of questions in a single scroll means a reader
# looking for the last one passes every answer in the first five. With
# the groups as a list, the screen only ever holds the questions from
# one of them, and the list itself says what else is here.
help_group <- function(title, ...) {
  bslib::nav_panel(title, div(class = "help-panel", ...))
}

help_body <- function() {
  tagList(
    div(class = "help-top",
      tags$p(class = "help-lede", paste(
        "Pick a group on the left, then the question that matches what",
        "you are trying to do. Nothing here is needed to use the app; the",
        "reading panel explains the map as you go.")),
      actionButton("help_tour", "Take the walkthrough instead",
                   class = "btn")),

    # The four groups below are the four situations a reader is in when
    # they open help: before they have loaded anything, while looking at
    # a map, while digging into the statistics, and after something has
    # gone wrong. Anything that does not belong to one of those is
    # probably not help.
    bslib::navset_pill_list(
      widths = c(3, 9),
      well = FALSE,
      help_group("Getting started",
    help_section("What do I need before I can use this", open = TRUE,
      tags$p(paste(
        "A list of connections, one per row. Two columns is enough: who",
        "the connection is from and who it is to. A third column can",
        "give each connection a strength, and without it every",
        "connection counts the same.")),
      tags$p(paste(
        "Save it as a CSV. Nothing else needs preparing: no identifier",
        "scheme, no dates, no ordering. The names can be people, teams,",
        "organizations, or anything else that connects to something.")),
      tags$p(class = "help-aside", paste(
        "If you would rather see what the app does before preparing",
        "anything, two sample networks are in the Source menu."))),

    help_section("Where does my data go",
      tags$p(paste(
        "Nowhere. The file is read into memory by the copy of R running",
        "on this machine and is never uploaded. There is no account, no",
        "server, and nothing that reports back.")),
      tags$p(paste(
        "The one exception is a setting you would have to change",
        "yourself. If you point the local model address at a machine",
        "other than this one, the computed sentences from the reading",
        "panel are sent there when you press Restate. The network data",
        "itself is never sent, even then."))),

    help_section("What is the fastest way to see whether this is useful",
      tags$p(paste(
        "Open a sample network, read the four cards beside the map, and",
        "click one person. That is the whole app in about a minute. The",
        "Overview tab has a worked example if you would rather read",
        "first.")))
      ),
      help_group("Reading the map",
    # This section and the next two are the questions the reading panel
    # answers in passing but that a reader often wants stated plainly
    # somewhere they can go back to.
    help_section("What do the shapes and colors mean",
      tags$p(paste(
        "Both mark the group a person belongs to. The shape comes first",
        "and the color supports it, which is why the map still works in",
        "the monochrome setting and for every kind of color vision.")),
      tags$p(paste(
        "Groups are found from the connection pattern alone: people who",
        "connect to each other more than they connect to everyone else.",
        "The app does not know what a group means. A group is often a",
        "team, a location, or a shared piece of work, and the data",
        "cannot say which."))),

    help_section("Why is one person bigger than another",
      tags$p(paste(
        "Size follows whichever measure is chosen under Size by. It is",
        "the same number the people table reports in that column, so the",
        "map and the table always agree.")),
      tags$p(paste(
        "Size is a position in this snapshot of connections. It is not",
        "importance, effort, or worth, and a person can be central in a",
        "network for reasons that have nothing to do with how well they",
        "do their job."))),

    # The five definitions use the words the interface uses rather than
    # the words the literature uses. Betweenness centrality is the
    # correct term and is no help at all to someone who has just seen a
    # column headed Between groups.
    help_section("What does each measure actually mean",
      help_term("Direct ties", paste(
        "How many people this person is connected to. The plainest",
        "measure and usually the first one worth looking at.")),
      help_term("Between groups", paste(
        "How often this person sits on the shortest path between two",
        "other people. A high score suggests traffic passes through",
        "them, which is a different thing from being well connected.")),
      help_term("Quick reach", paste(
        "How short this person's paths are to everyone else. Someone can",
        "have few connections and still reach the whole network fast.")),
      help_term("Well connected circle", paste(
        "Whether this person's connections are themselves well",
        "connected. It rewards being close to the center rather than",
        "being busy.")),
      help_term("Single point of failure", paste(
        "Removing this person would split the network into pieces. It is",
        "worth knowing about whatever their other scores say."))),

    # Worth its own section because it is the question that separates
    # reading a network from reporting one, and because a reader who
    # does not ask it tends to pick whichever measure agrees with what
    # they already believed.
    help_section("Why do the measures disagree about who matters",
      tags$p(paste(
        "Because they measure different things, and that disagreement is",
        "usually the interesting part. Someone with many connections and",
        "a low between groups score is busy inside their own group.",
        "Someone with few connections and a high between groups score is",
        "the only route between two parts of the network.")),
      tags$p(paste(
        "If one person leads on every measure, that is worth noticing",
        "too. It usually means the network is small or has one obvious",
        "center."))),

    # Two capabilities that a reader will not find by poking at the map,
    # because neither is a property of a person and neither has a
    # control that looks like what it does.
    help_section("How do I find the route between two people",
      tags$p(paste(
        "Under the reading panel, choose two names and press Show the",
        "route. The shortest chain of connections between them lights up",
        "on the map and the names along it are listed in order.")),
      tags$p(paste(
        "There is often more than one shortest route and the app shows",
        "one of them. A route says these two people are this far apart",
        "in the ties you recorded. It does not say anything travels that",
        "way.")),
      tags$p(class = "help-aside", paste(
        "If the two are in separate pieces of the network, the app says",
        "so rather than showing nothing."))),

    help_section("Which ties matter most",
      tags$p(paste(
        "Mark ties, above the map, has two settings besides off.")),
      help_term("Only routes", paste(
        "Marks the ties whose removal would break the network into more",
        "pieces than before. Each one is the sole route between what",
        "sits on either side of it, so these are the ties a network",
        "misses first when someone leaves.")),
      help_term("Ties between groups", paste(
        "Marks every tie that joins two different groups. These are the",
        "connections that carry anything new into a cluster; the rest",
        "circulate what the cluster already has.")),
      tags$p(class = "help-aside", paste(
        "Both are marked with a dashed heavier line as well as a color,",
        "so they survive the monochrome setting."))),

    help_section("How do I look at one person on their own",
      tags$p(paste(
        "Click them on the map, or press Tab until they have focus and",
        "then Enter. Everything past their reach dims and the panel",
        "rewrites itself for them. Click empty space, or use Back to the",
        "whole network, to step out.")))
      ),
      help_group("Going further",
    help_section("What is in the Research tab",
      tags$p(paste(
        "The same network, with the statistics rather than the",
        "sentences: extended centralities, a choice of community",
        "detection algorithms, global diagnostics, and the dyad and",
        "triad census.")),
      tags$p(paste(
        "It also writes a runnable script that reproduces the analysis",
        "outside the app, in either igraph or tidygraph and ggraph. Take",
        "the first to drop into an existing analysis, the second to stay",
        "in the tidyverse and get a publishable figure."))),

    help_section("Which community algorithm should I use",
      tags$p(paste(
        "Louvain is a reasonable default and is what the Explore tab",
        "uses. The others are offered because no algorithm is correct",
        "for every network, and running two is a cheap way to find out",
        "how stable the grouping is.")),
      tags$p(paste(
        "If two algorithms draw the same boundaries, the grouping is",
        "telling you something about the network. If they disagree",
        "sharply, the boundaries are weak and any story built on them",
        "should say so."))),

    # The Research tab grew four measures that a reader will not have
    # met in the Explore tab, and a column headed constraint with no
    # explanation anywhere is worse than no column.
    help_section("What are the measures in the Research tab",
      help_term("Constraint", paste(
        "Burt's measure of how far a person's contacts are already",
        "connected to each other. A low score means their contacts are",
        "largely strangers, which is the brokerage position: they are",
        "the route between parts that would otherwise not meet.")),
      help_term("Effective size", paste(
        "The same idea from the other side. Contacts minus the",
        "redundancy among them, so ten contacts who all know each other",
        "count for far less than ten who do not.")),
      help_term("Coreness", paste(
        "The deepest nested core a person belongs to. It separates a",
        "dense center from a fringe in a way the count of ties cannot,",
        "since a person can have many ties and all of them to the",
        "edge.")),
      help_term("Degree centralization", paste(
        "How far the network is from one where a single person holds",
        "every tie. Two networks with the same density can be a hub and",
        "spoke or an even mesh, and this is what tells them apart.")),
      help_term("Degree assortativity", paste(
        "Whether well connected people connect to other well connected",
        "people. Positive is the usual pattern in social networks. A",
        "clearly negative value points to a hub and spoke arrangement",
        "and is worth stopping on.")),
      help_term("E-I index", paste(
        "Krackhardt and Stern's measure of group crossing, from minus",
        "one when every tie stays inside a group to plus one when every",
        "tie crosses between groups. It is the plainest answer to",
        "whether the groups are talking to each other.")),
      help_term("Dyad and triad census", paste(
        "Counts of how pairs and triples are arranged. It needs",
        "direction, so it works on the two directed samples and on any",
        "directed data you bring. Compare the advice sample against the",
        "messaging one: advice runs one way and comes back mostly",
        "asymmetric, messages are answered and come back mostly",
        "mutual."))),

    # The Statistics tab is the one place in the app that produces a
    # number a reader might put in a report, so the section explaining
    # it leads with what the number cannot support.
    help_section("What is the Statistics tab for",
      tags$p(paste(
        "Every number in the Research tab describes what is in front of",
        "you. A network of a given size and density already has a",
        "clustering, a centralization, and a group separation before",
        "anyone has done anything social, so a number on its own cannot",
        "say whether a pattern means anything.")),
      tags$p(paste(
        "The tests compare what was measured against several hundred",
        "random networks that hold one feature of yours fixed. This is",
        "the conditional uniform graph test, standard in network",
        "analysis since Anderson, Butts, and Carley showed in 1999 how",
        "strongly size and density alone drive these measures.")),
      help_term("Holding people and ties fixed", paste(
        "Asks whether the pattern exceeds what this much connection",
        "among this many people would give on its own.")),
      help_term("Holding each person's ties fixed", paste(
        "A harder question: whether the pattern exceeds what these",
        "particular people, with exactly the ties they each have, would",
        "give. A result that survives this is a claim about arrangement",
        "rather than about volume.")),
      help_term("The p value", paste(
        "The share of random networks that reached the observed value",
        "or beyond. Small means chance rarely produces what you have.",
        "It does not mean the pattern is large, useful, or caused by",
        "anything in particular.")),
      tags$p(class = "help-aside", paste(
        "One exception to read the other way round: in the connection",
        "count section, a small value means the fitted heavy tailed",
        "shape does not describe your data."))),

    help_section("What these tests cannot tell you",
      tags$p(paste(
        "They cannot say what caused a pattern. They cannot say a",
        "pattern matters, since that depends on what you are deciding",
        "and no test knows that.")),
      tags$p(paste(
        "They also cannot speak about change, because this is one",
        "snapshot of recorded ties. Comparing two networks, or the same",
        "network at two times, needs methods this app does not carry.",
        "The reproducible script in the Research tab is the exit into",
        "that work."))),

    help_section("What does modularity tell me",
      tags$p(paste(
        "How cleanly the network divides. Below about 0.3 the boundaries",
        "are weak enough that a different algorithm would likely draw",
        "them elsewhere, and the app says so rather than announcing",
        "groups. Above it, the division is doing real work.")))
      ),

    # Saving is where a reader turns after losing something, so this
    # group says plainly which things persist on their own and which do
    # not, rather than only how to press Save.
      help_group("Keeping your work",
    help_section("How do I save what I am looking at",
      tags$p(paste(
        "Save, beside the network menu, writes a session file. It holds",
        "the connections themselves along with how you were looking at",
        "them: the sizing measure, the labels, the sort order, the",
        "strength filter, the color setting, and any selected person.")),
      tags$p(paste(
        "Resume reads one back. Because the file carries its own copy of",
        "the connections, it works even if the original spreadsheet has",
        "moved or changed. It is plain JSON, so you can open it in any",
        "editor to see exactly what it holds."))),

    help_section("What is saved automatically and what is not",
      tags$p(paste(
        "Settings that belong to the machine rather than to the work are",
        "remembered on their own: the color setting, the model address,",
        "the model name, and the setup route. Those follow you into the",
        "next session without a file.")),
      tags$p(paste(
        "Nothing about the network is remembered automatically. If you",
        "want the work back, save it."))),

    help_section("How do I get a figure or a table out",
      tags$p(paste(
        "Three downloads sit above the people table. People writes the",
        "full table as CSV, Summary writes the reading panel as text",
        "with its caveat attached, and Map figure writes the map as a",
        "PNG on a white background.")),
      tags$p(paste(
        "The figure follows your color setting, since a setting chosen",
        "for a reason should survive the export.")))
      ),
      help_group("The optional model",
    # The model sections lead with what it does not do. Readers arrive
    # at this feature either expecting an assistant or suspecting their
    # data is being sent somewhere, and both are answered before the
    # instructions start.
    help_section("What does the local model do, and do I need one",
      tags$p(paste(
        "It rewords the reading panel in its own voice. That is all. It",
        "never produces a number, never sees the network, and its answer",
        "appears beneath the computed text rather than in place of it,",
        "so the two can always be compared.")),
      tags$p(paste(
        "You do not need one. Every measure and every sentence is",
        "computed by the app without any model involved."))),

    help_section("How do I set one up",
      tags$p(paste(
        "Local models in the header opens a screen with three steps.",
        "Step one is a choice between two routes.")),
      tags$p(paste(
        "Guided checks what is on the machine, says what is missing, and",
        "hands you the one command that installs it. The app runs",
        "nothing on your behalf in this route.")),
      tags$p(paste(
        "Managed downloads the runtime into a folder belonging to this",
        "app and runs it from there. Nothing is installed into the",
        "system, and deleting that folder undoes all of it. Windows is",
        "offered the guided route only, because the vendor ships an",
        "installer there rather than an archive.")),
      tags$p(class = "help-aside", paste(
        "The first install is a download of roughly 500 MB and the first",
        "start can take up to half a minute. Both report progress, and",
        "pressing the control again while it works does nothing."))),

    help_section("Which model should I choose",
      tags$p(paste(
        "Any of the four in the list does this job. Bigger models write",
        "better summaries and ask for more memory and more patience.")),
      tags$p(paste(
        "Check this machine, in step three, reads your memory and core",
        "count and marks each model as comfortable, workable, or too",
        "large, then suggests one. It says what it reads before it reads",
        "it, and nothing leaves the machine.")))
      ),

    # The last group is written for someone who is already annoyed:
    # every section starts with the symptom in their words rather than
    # with the name of the part that failed.
      help_group("When something is wrong",
    help_section("My file will not load",
      tags$p(paste(
        "The app names what the file needs rather than what the parser",
        "objected to, so start with the message it gave you. The usual",
        "causes are a file that is not comma separated, a first row that",
        "is data rather than column names, or only one column.")),
      tags$p(paste(
        "A quick test: open a sample network. If that works, the app is",
        "fine and the file is the thing to look at."))),

    help_section("The panel says no local model answered",
      tags$p(paste(
        "Three different things produce that message, and the message",
        "says which. Either nothing is answering at the address, or",
        "something is answering but holds no model, or it holds a",
        "different model than the name in Settings.")),
      tags$p(paste(
        "The Set up a local model control beside the message opens the",
        "screen that fixes all three."))),

    # The three answers here are in order of how much they change: hide
    # connections, then narrow to one group, then give the map more
    # room. A reader who starts with full screen still has the tangle.
    help_section("The map looks tangled or too crowded",
      tags$p(paste(
        "Raise Least tie strength to hide the weakest connections, which",
        "usually reveals the structure underneath. Choosing a group in",
        "the key lights only that group. Names on the map can be set to",
        "key people only, or turned off.")),
      tags$p(paste(
        "Full screen gives the map the whole window, and the reading",
        "panel can be resized by its left edge or folded away."))),

    # This one names the audit on purpose. A reader who cannot separate
    # two groups should know the difference between a limit of the
    # design and a fault we would want reported.
    help_section("I cannot tell two groups apart",
      tags$p(paste(
        "Settings holds five color settings: standard, three tuned for",
        "different kinds of color vision, and one that removes color",
        "altogether and lets shape carry the groups on its own.")),
      tags$p(paste(
        "Every color in every one of those settings is measured against",
        "the WCAG 2.2 AA thresholds by a test that fails the build, so",
        "if two groups are hard to tell apart in any of them, that is a",
        "fault worth reporting rather than something to work around."))),

    # Kept in this group rather than in its own, because a person
    # looking for it is usually looking for it after something did not
    # respond the way they expected.
    help_section("Keyboard and screen reader use",
      tags$p(paste(
        "Every person on the map takes focus with Tab and opens with",
        "Enter or Space. Every control clears the 44 pixel target size.",
        "The reading panel is text, so it reads in order.")),
      tags$p(paste(
        "The app respects a reduced motion preference: the walkthrough",
        "animations and the panel transitions stop.")))
      )
    ),

    tags$p(class = "help-foot", paste0(
      "Still stuck, or found something wrong? The repository holds an",
      " issue tracker. ", APP_NAME, " ", APP_VERSION, "."))
  )
}
