# render_controls.R
# Writes the rendered control row to a file so the full screen suite can
# drive the same markup the app produces rather than a copy of it typed
# out inside the test.
#
# The control row is built by the server on demand, which a plain page
# fetch cannot reach, so it is produced here through testServer with the
# inputs the app would have once a network is loaded. CONTRIBUTING.md
# documents the same call for running the suite by hand.
#
# Usage: Rscript tests/render_controls.R <output.html>

suppressPackageStartupMessages(library(shiny))

out <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(out)) stop("Give an output path")

testServer(shinyAppFile("app.R"), {
  # These are the inputs present once a sample network is chosen. The
  # control row renders nothing at all before that, which is the point
  # of the empty state and would leave the suite with no button.
  session$setInputs(dataset = "org", size_by = "degree",
                    sort_by = "degree", label_mode = "key")
  # Only the rendered view controls are written. The full screen button
  # sits in the fixed part of the tab, so it is already in the page the
  # suite fetches from the server, and writing a second copy here would
  # be a copy that drifts.
  writeLines(as.character(output$view_controls$html), out)
})

cat("wrote", out, "\n")
