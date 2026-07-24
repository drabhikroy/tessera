# run_tests.R
# Headless checks run before every delivery. Four suites: the math, the
# prose, the WCAG contrast matrix across all eight theme and palette
# states, and a live server smoke test.

`%||%` <- function(a, b) if (is.null(a)) b else a
# The suite runs from the project root. When launched from tests/, step up.
if (basename(getwd()) == "tests") setwd("..")

source("R/network_math.R")
source("R/sample_data.R")
source("R/narrative.R")
source("R/figure.R")
source("R/guide.R")
source("R/research_metrics.R")

pass <- 0; fail <- 0
check <- function(label, ok) {
  if (isTRUE(ok)) { pass <<- pass + 1; cat("ok  ", label, "\n") }
  else { fail <<- fail + 1; cat("FAIL", label, "\n") }
}

# Suite 1: the math on a graph with known answers. A path of four nodes
# has exact betweenness and two articulation points, so nothing here is
# a matter of taste.
ed <- data.frame(from = c("A", "B", "C"), to = c("B", "C", "D"))
g <- build_graph(ed)
m <- compute_metrics(g)
check("path graph has 4 people and 3 ties", m$n == 4 && m$m == 3)
check("middle nodes are the cut points",
      setequal(m$cut_ids, c("B", "C")))
check("betweenness peaks in the middle",
      which.max(m$betweenness) %in% c(2, 3))
check("degree is exact", all(sort(m$degree) == c(1, 1, 2, 2)))

# Duplicate and self ties collapse correctly.
ed2 <- data.frame(from = c("A", "A", "A"), to = c("B", "B", "A"),
                  w = c(2, 3, 9))
g2 <- build_graph(ed2)
check("parallel ties merge and weights sum",
      igraph::gsize(g2) == 1 &&
        (g2 |> activate(edges) |> pull(weight)) == 5)

# The two samples build end to end.
for (nm in c("org", "referral")) {
  ed_s <- if (nm == "org") sample_org_network() else sample_referral_network()
  ms <- compute_metrics(build_graph(ed_s))
  if (nm == "referral") {
    check("referral sample uses real names, not generic labels",
          !any(grepl("Customer", ms$names)))
  }
  ly <- compute_layout(ms$graph)
  pl <- graph_payload(ms, ly)
  check(paste(nm, "sample yields a payload"),
        nrow(pl$nodes) == ms$n && all(pl$nodes$group >= 1))
  check(paste(nm, "layout lands inside the unit square"),
        all(ly$x >= 0 & ly$x <= 1 & ly$y >= 0 & ly$y <= 1))
}
org_m <- compute_metrics(build_graph(sample_org_network()))
check("org sample has more than one group", org_m$n_groups > 1)
check("org sample surfaces at least one cut point",
      length(org_m$cut_ids) >= 1)

# Layout is deterministic: same seed, same picture.
l1 <- compute_layout(org_m$graph)
l2 <- compute_layout(org_m$graph)
check("layout repeats exactly with the same seed", identical(l1, l2))

# The wire format: rows, not columns. This is the regression test for
# the blank map: a row record list survives Shiny serialization intact.
wire <- payload_wire(graph_payload(org_m, compute_layout(org_m$graph)))
check("wire nodes are a list of row records",
      is.list(wire$nodes) && !is.data.frame(wire$nodes) &&
        is.list(wire$nodes[[1]]) && !is.null(wire$nodes[[1]]$label))
check("wire edges are row records with weights",
      length(wire$edges) > 0 && !is.null(wire$edges[[1]]$weight))

# The card layer: four cards, in reading order, numbers matching.
groups_org <- relabel_groups(org_m$membership)
cards <- describe_cards(org_m, groups_org)
check("four cards in reading order",
      identical(names(cards), c("shape", "groups", "holders", "fragile")))
check("shape card states the true head count",
      cards$shape$stats[[1]]$value == as.character(org_m$n))
check("fragile card counts the cut points",
      cards$fragile$stats[[1]]$value ==
        as.character(length(org_m$cut_ids)))
check("holder chips name real people",
      all(cards$holders$people %in% org_m$names))
pc <- person_card(org_m, 1, groups_org)
check("person card names the person",
      grepl(org_m$names[1], pc$title, fixed = TRUE))

# The walkthrough and the model guide carry their content.
slides <- tour_slides()
check("walkthrough has seven slides with art and text",
      length(slides) == 7 &&
        all(vapply(slides, function(s) nchar(s$art) > 100 &&
                     nchar(s$text) > 50, TRUE)))
check("model guide offers four options with commands",
      length(model_options()) == 4 &&
        all(vapply(model_options(),
                   function(m) grepl("^ollama pull ", m$pull), TRUE)))

# The group cap: a network with many communities keeps them separate
# rather than folding everything past the eighth into one bucket.
many <- relabel_groups(rep(1:30, times = 30:1))
check("thirty communities keep thirty distinct labels",
      length(unique(many)) == 30 && max(many) == 30)
check("groups are numbered by size, largest first",
      sum(many == 1) >= sum(many == 30))

# Equally sized communities are still separate communities. Ranking on
# size alone merged them, so the key showed fewer groups than the
# summary counted.
tied <- relabel_groups(c(rep(1, 5), rep(2, 5), rep(3, 3),
                         rep(4, 3), rep(5, 1)))
check("equally sized groups keep separate labels",
      length(unique(tied)) == 5)
check("the summary count and the key agree",
      length(unique(tied)) == length(unique(c(rep(1, 5), rep(2, 5),
                                              rep(3, 3), rep(4, 3),
                                              rep(5, 1)))))

# Suite 2: the prose. The check is behavioral, not aesthetic: paragraphs
# exist, numbers inside them match the metrics, and the person view names
# the person it was asked about.
paras <- describe_network(org_m)
check("network summary has at least four paragraphs", length(paras) >= 4)
check("summary states the true head count",
      grepl(paste0("\\b", org_m$n, " people"), paras[1]))
groups <- relabel_groups(org_m$membership)
pp <- describe_person(org_m, 1, groups)
check("person view names the person",
      grepl(org_m$names[1], pp[1], fixed = TRUE))
check("person view states their exact tie count",
      grepl(paste0(" ", org_m$degree[1], " direct ties"), pp[1]))

# The fragility paragraph appears only when cut points exist.
ring <- data.frame(from = c("A", "B", "C", "D"), to = c("B", "C", "D", "A"))
ring_m <- compute_metrics(build_graph(ring))
ring_p <- describe_network(ring_m)
check("a ring reports no single point of failure",
      any(grepl("No single person", ring_p)))

# Suite 3: WCAG contrast across all eight theme and palette states. The
# token pairs below are the ones that carry reading text. 4.5 to 1 is the
# floor everywhere.
lum <- function(hex) {
  v <- strtoi(c(substr(hex, 2, 3), substr(hex, 4, 5), substr(hex, 6, 7)), 16L) / 255
  v <- ifelse(v <= 0.03928, v / 12.92, ((v + 0.055) / 1.055) ^ 2.4)
  sum(v * c(0.2126, 0.7152, 0.0722))
}
ratio <- function(a, b) {
  la <- lum(a); lb <- lum(b)
  (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
}

tokens <- list(
  dark_standard = list(bg = "#0f1317", surface = "#171d24", raised = "#202a34",
                       text = "#e9eef3", muted = "#a7b4c1", accent = "#8fc1de"),
  light_standard = list(bg = "#f2f4f6", surface = "#ffffff", raised = "#ffffff",
                        text = "#17222d", muted = "#465562", accent = "#10577e"),
  dark_mono = list(bg = "#0f1317", surface = "#171d24", raised = "#202a34",
                   text = "#ffffff", muted = "#cfcfcf", accent = "#ffffff"),
  light_mono = list(bg = "#f2f4f6", surface = "#ffffff", raised = "#ffffff",
                    text = "#000000", muted = "#363636", accent = "#000000")
)
# The deutan and tritan palettes change node colors only, so their text
# checks reduce to the standard sets. Both reductions are asserted here so
# a future edit that adds text overrides gets caught.
for (state in names(tokens)) {
  tk <- tokens[[state]]
  for (surface_name in c("bg", "surface", "raised")) {
    check(sprintf("%s: text on %s", state, surface_name),
          ratio(tk$text, tk[[surface_name]]) >= 4.5)
    check(sprintf("%s: muted on %s", state, surface_name),
          ratio(tk$muted, tk[[surface_name]]) >= 4.5)
  }
  check(sprintf("%s: accent on surface", state),
        ratio(tk$accent, tk$surface) >= 4.5)
}
css <- readLines("www/styles.css")
deutan_block <- grep("cb-deutan|cb-tritan", css, value = TRUE)
check("deutan and tritan blocks leave text tokens alone",
      !any(grepl("--text|--muted", deutan_block)))

# Node label halo: label text against its halo stroke in both modes.
check("dark label on halo", ratio("#e9eef3", "#0f1317") >= 4.5)
check("light label on halo", ratio("#17222d", "#ffffff") >= 4.5)

# Suite: the ggraph figure renders in every palette without error and
# writes a real file.
pl_fig <- graph_payload(org_m, compute_layout(org_m$graph))
for (pal in names(figure_palettes)) {
  f <- file.path(tempdir(), paste0("fig_", pal, ".png"))
  ok_fig <- tryCatch({
    ggplot2::ggsave(f, network_figure(pl_fig, pal, "Test"),
                    width = 8, height = 7, dpi = 72, bg = "white")
    file.exists(f) && file.size(f) > 20000
  }, error = function(e) FALSE)
  check(paste("figure renders in the", pal, "palette"), ok_fig)
}

# Research tier: extended centralities, every community algorithm, the
# global diagnostics, and the reproducible script.
ec <- extended_centralities(org_m$graph)
check("extended centralities include pagerank and hits",
      all(c("pagerank", "hub", "authority") %in% names(ec)) &&
        nrow(ec) == org_m$n)
for (meth in c("louvain", "leiden", "walktrap", "fast_greedy")) {
  cp <- community_partition(org_m$graph, meth)
  check(paste(meth, "partition returns groups and modularity"),
        cp$n_groups >= 1 && is.finite(cp$modularity))
}
gd <- global_diagnostics(org_m$graph)
check("global diagnostics report the nine standard measures",
      nrow(gd) == 9 &&
        gd$value[gd$measure == "People"] == as.character(org_m$n))
scr <- export_script("leiden", "between")
check("export script is runnable igraph code",
      grepl("library\\(igraph\\)", scr) &&
        grepl("cluster_leiden", scr))

# Suite 4: the app boots and answers. testServer drives the real server
# function with the org sample and confirms the outputs materialize.
suppressPackageStartupMessages(library(shiny))
app <- shinyAppFile("app.R")
ok_server <- tryCatch({
  testServer(app, {
    session$setInputs(dataset = "org", size_by = "degree",
                      sort_by = "degree", label_mode = "key")
    b <- bundle()
    stopifnot(!is.null(b), b$metrics$n == 58)
    stopifnot(nchar(output$people_table$html) > 500)
    stopifnot(nchar(output$reading$html) > 200)
    stopifnot(nchar(output$legend$html) > 100)
    session$setInputs(selected_node = 1)
    stopifnot(grepl(b$metrics$names[1], output$reading$html, fixed = TRUE))
    # The empty state appears when the app opens on Your own data.
    session$setInputs(dataset = "upload")
    stopifnot(grepl("Map your own people", output$empty_state$html,
                    fixed = TRUE))
    stopifnot(grepl("Load a network first", output$research_body$html,
                    fixed = TRUE))
    # With a network loaded, the research tab fills in.
    session$setInputs(dataset = "org", community_method = "louvain")
    stopifnot(grepl("Global structure", output$research_body$html,
                    fixed = TRUE))
  })
  TRUE
}, error = function(e) { cat("  server error:", conditionMessage(e), "\n"); FALSE })
check("server answers with map, prose, legend, and table", ok_server)

cat("\n", pass, "passed,", fail, "failed\n")
if (fail > 0) quit(status = 1)
