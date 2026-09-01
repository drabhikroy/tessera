# session_state.R
# Saving work and picking it up again, and the small set of preferences
# that outlive a session.
#
# Copyright Abhik Roy. Released under the PolyForm Noncommercial
# License 1.0.0. See LICENSE.md.
#
# Two different things live here and they are kept apart on purpose.
#
# A session file is the reader's work: the ties they loaded and how they
# were looking at them. It is a file they hold, in a place they chose,
# which they can put beside the report they are writing or send to a
# colleague. It travels.
#
# Preferences are the settings the app should stop asking about: the
# address of a local model, which model, the color setting. Those belong
# to the machine rather than to the work, so they go in the config
# directory R provides and are never part of a session file.
#
# Both are plain JSON. A format a person can open and read is worth more
# here than a compact one, since the whole point of the app is that
# nothing about it is opaque.

suppressPackageStartupMessages({
  library(jsonlite)
})

SESSION_FORMAT <- 1L

# Everything needed to put the reader back where they were. The edge
# list travels with it, so a resumed session does not depend on the
# original file still being where it was, or on the sample data being
# the same version.
session_snapshot <- function(edges, view) {
  list(
    format = SESSION_FORMAT,
    app = APP_NAME,
    version = APP_VERSION,
    saved = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
    view = view,
    edges = edges
  )
}

save_session <- function(path, snapshot) {
  jsonlite::write_json(snapshot, path, auto_unbox = TRUE, dataframe = "rows",
                       pretty = TRUE, digits = 8)
  invisible(path)
}

# Reads a session file and says plainly what is wrong with it rather
# than failing somewhere later. A file from a newer version is read
# rather than refused: the fields this version does not know about are
# ignored, which is friendlier than a version wall and costs nothing
# while the format stays additive.
read_session <- function(path) {
  parsed <- tryCatch(jsonlite::read_json(path, simplifyVector = TRUE),
                     error = function(e) NULL)
  if (is.null(parsed)) {
    return(list(ok = FALSE, message = paste(
      "That file could not be read as a saved session. A session file is",
      "the one this app writes with the Save button.")))
  }
  if (is.null(parsed$edges) || NROW(parsed$edges) == 0) {
    return(list(ok = FALSE, message = paste(
      "That session file holds no ties, so there is nothing to put back",
      "on the map.")))
  }
  edges <- as.data.frame(parsed$edges, stringsAsFactors = FALSE)
  if (ncol(edges) < 2) {
    return(list(ok = FALSE, message = paste(
      "That session file holds ties with only one end, which cannot be",
      "put on a map.")))
  }
  list(ok = TRUE, edges = edges,
       view = if (is.null(parsed$view)) list() else parsed$view,
       saved = parsed$saved,
       message = "Session restored.")
}

# Preferences. Reading tolerates a missing or damaged file by returning
# the defaults, because a preference file is never important enough to
# stop the app starting.
prefs_path <- function() file.path(tessera_dir("config"), "preferences.json")

default_prefs <- function() {
  list(
    ollama_url = "http://localhost:11434",
    ollama_model = "llama3.2",
    palette = "standard",
    setup_route = "guided"
  )
}

read_prefs <- function() {
  path <- prefs_path()
  if (!file.exists(path)) return(default_prefs())
  parsed <- tryCatch(jsonlite::read_json(path, simplifyVector = TRUE),
                     error = function(e) NULL)
  if (!is.list(parsed)) return(default_prefs())
  defaults <- default_prefs()
  # Unknown keys are dropped and missing ones take the default, so a
  # file written by a different version can never introduce a setting
  # this version does not understand.
  for (key in names(defaults)) {
    value <- parsed[[key]]
    if (!is.null(value) && length(value) == 1 && !is.na(value)) {
      defaults[[key]] <- as.character(value)
    }
  }
  defaults
}

write_prefs <- function(values) {
  current <- read_prefs()
  for (key in names(values)) {
    if (key %in% names(current) && !is.null(values[[key]])) {
      current[[key]] <- as.character(values[[key]])
    }
  }
  tryCatch({
    jsonlite::write_json(current, prefs_path(), auto_unbox = TRUE,
                         pretty = TRUE)
    invisible(TRUE)
  }, error = function(e) invisible(FALSE))
}
