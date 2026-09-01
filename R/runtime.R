# runtime.R
# The local model runtime. Everything here is about getting a language
# model onto the reader's own machine and keeping it there between
# sessions. None of it is required to use the app.
#
# Copyright Abhik Roy. Released under the PolyForm Noncommercial
# License 1.0.0. See LICENSE.md.
#
# Two routes are offered, and the choice is the reader's rather than
# ours. Guided setup detects what is present, says what is missing, and
# gives the exact command to fix it, executing nothing. Managed setup
# downloads the Ollama release into a directory belonging to this app
# and runs it from there, which installs nothing into the system and can
# be removed by deleting one folder.
#
# The managed route asks before it downloads and says how large the
# download is. The hardware report asks before it reads anything and
# says exactly what it will read. Neither runs on its own.

suppressPackageStartupMessages({
  library(jsonlite)
})

# Where this app keeps things between sessions. R gives every package a
# place for each of these, so nothing is written beside the source or
# into a home directory at random.
tessera_dir <- function(which = c("data", "config")) {
  which <- match.arg(which)
  path <- tools::R_user_dir("tessera", which)
  if (!dir.exists(path)) dir.create(path, recursive = TRUE, showWarnings = FALSE)
  path
}

# The platform, named the way the Ollama release assets are named. An
# unknown platform is not a failure: it means the managed route is not
# offered and the guided route is.
host_platform <- function() {
  info <- Sys.info()
  arch <- R.version$arch
  if (identical(as.character(info["sysname"]), "Darwin")) {
    return(list(id = "darwin", label = "macOS",
                asset = "ollama-darwin.tgz"))
  }
  if (identical(as.character(info["sysname"]), "Linux")) {
    asset <- if (grepl("aarch64|arm", arch)) {
      "ollama-linux-arm64.tgz"
    } else {
      "ollama-linux-amd64.tgz"
    }
    return(list(id = "linux", label = "Linux", asset = asset))
  }
  if (identical(as.character(info["sysname"]), "Windows")) {
    # Windows ships an installer rather than an archive, so the managed
    # route cannot be offered honestly there.
    return(list(id = "windows", label = "Windows", asset = NA_character_))
  }
  list(id = "unknown", label = "this system", asset = NA_character_)
}

# The one command a reader needs for the guided route, per platform.
install_command <- function(platform = host_platform()) {
  switch(platform$id,
    darwin = "brew install ollama",
    linux  = "curl -fsSL https://ollama.com/install.sh | sh",
    windows = "winget install Ollama.Ollama",
    "See https://ollama.com/download")
}

# The hardware report. This function reads nothing until it is called,
# and it is only called from a control the reader presses after being
# told what it reads. It reports four things: the operating system, the
# amount of memory, the number of cores, and whether a discrete graphics
# processor is present. Nothing is sent anywhere; the values are used to
# say which models will fit.
machine_report <- function() {
  info <- Sys.info()
  platform <- host_platform()
  cores <- tryCatch(parallel::detectCores(logical = TRUE),
                    error = function(e) NA_integer_)

  bytes <- tryCatch({
    if (platform$id == "darwin") {
      as.numeric(system2("sysctl", c("-n", "hw.memsize"), stdout = TRUE))
    } else if (platform$id == "linux") {
      line <- grep("^MemTotal", readLines("/proc/meminfo", warn = FALSE),
                   value = TRUE)[1]
      as.numeric(gsub("[^0-9]", "", line)) * 1024
    } else if (platform$id == "windows") {
      out <- system2("wmic",
                     c("computersystem", "get", "TotalPhysicalMemory"),
                     stdout = TRUE)
      as.numeric(gsub("[^0-9]", "", paste(out, collapse = " ")))
    } else {
      NA_real_
    }
  }, error = function(e) NA_real_, warning = function(e) NA_real_)

  gpu <- tryCatch({
    if (platform$id == "darwin") {
      # Apple silicon shares memory between the processor and the
      # graphics unit, which is why it runs models well at modest
      # memory sizes, so it is worth naming.
      grepl("Apple", paste(system2("sysctl", c("-n", "machdep.cpu.brand_string"),
                                   stdout = TRUE), collapse = " "))
    } else if (platform$id == "linux") {
      nzchar(Sys.which("nvidia-smi"))
    } else {
      FALSE
    }
  }, error = function(e) FALSE, warning = function(e) FALSE)

  list(
    os = platform$label,
    ram_gb = if (is.finite(bytes)) round(bytes / 1024^3, 1) else NA_real_,
    cores = cores,
    accelerated = isTRUE(gpu)
  )
}

# Is a server answering at this address, and what does it hold. The
# check is a plain request for the model list, which is the cheapest
# thing an Ollama server will answer.
ollama_status <- function(base_url = "http://localhost:11434") {
  if (!requireNamespace("curl", quietly = TRUE)) {
    return(list(running = FALSE, models = character(0),
                message = paste("The curl package is not installed, so the",
                                "app cannot reach a local server.")))
  }
  out <- tryCatch({
    handle <- curl::new_handle(timeout = 3L)
    resp <- curl::curl_fetch_memory(paste0(sub("/$", "", base_url),
                                           "/api/tags"), handle)
    if (resp$status_code != 200) stop("status ", resp$status_code)
    parsed <- jsonlite::fromJSON(rawToChar(resp$content))
    names <- if (is.null(parsed$models)) character(0) else parsed$models$name
    list(running = TRUE, models = as.character(names),
         message = "A local server is answering.")
  }, error = function(e) {
    list(running = FALSE, models = character(0),
         message = "No local server is answering at this address.")
  })
  out
}

# Where the managed copy lives, and whether it is there. A binary the
# app downloaded is preferred over one on the path only when the reader
# chose the managed route, so both are reported and the caller decides.
managed_root <- function() file.path(tessera_dir("data"), "ollama")

managed_binary <- function() {
  candidates <- c(
    file.path(managed_root(), "bin", "ollama"),
    file.path(managed_root(), "ollama")
  )
  found <- candidates[file.exists(candidates)]
  if (length(found) > 0) found[1] else NA_character_
}

system_binary <- function() {
  path <- Sys.which("ollama")
  if (nzchar(path)) unname(path) else NA_character_
}

# Everything the setup screen needs in one call, so the screen never has
# to work out what is true from three separate places.
runtime_state <- function(base_url = "http://localhost:11434") {
  platform <- host_platform()
  managed <- managed_binary()
  system <- system_binary()
  status <- ollama_status(base_url)
  list(
    platform = platform,
    managed_available = !is.na(platform$asset),
    managed_path = managed,
    system_path = system,
    installed = !is.na(managed) || !is.na(system),
    running = status$running,
    models = status$models,
    message = status$message,
    command = install_command(platform)
  )
}

# The managed download. The archive goes into this app's own data
# directory and is extracted there. Nothing is written outside it, and
# removing that one directory removes everything this function did.
#
# The caller supplies a reporter so progress can be shown on screen.
# Returns a list with ok and message, never a condition, because the
# calling screen has to say something either way.
managed_install <- function(report = function(text) invisible(NULL)) {
  platform <- host_platform()
  if (is.na(platform$asset)) {
    return(list(ok = FALSE, message = paste(
      "A managed runtime is not offered on", platform$label,
      "because the vendor ships an installer there rather than an",
      "archive. Use the guided route instead.")))
  }
  url <- paste0("https://github.com/ollama/ollama/releases/latest/download/",
                platform$asset)
  root <- managed_root()
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  archive <- file.path(root, platform$asset)

  result <- tryCatch({
    # The download is streamed in chunks rather than fetched in one
    # blocking call, so the reader is told how far along it is. The
    # first version reported once at the start and then went silent for
    # several minutes, which reads as a failure rather than as work.
    if (requireNamespace("curl", quietly = TRUE)) {
      connection <- file(archive, open = "wb")
      on.exit(try(close(connection), silent = TRUE), add = TRUE)
      seen <- 0
      last_said <- 0
      curl::curl_fetch_stream(url, function(chunk) {
        writeBin(chunk, connection)
        seen <<- seen + length(chunk)
        megabytes <- seen / 1024^2
        # Reporting every chunk would spend more time on messages than
        # on the download, so it speaks every five megabytes.
        if (megabytes - last_said >= 5) {
          last_said <<- megabytes
          report(sprintf("Downloaded %.0f MB of roughly 500 MB.",
                         megabytes))
        }
      })
      close(connection)
    } else {
      report(paste("Downloading the runtime, roughly 500 MB. This takes",
                   "a few minutes and cannot report progress without the",
                   "curl package installed."))
      utils::download.file(url, archive, mode = "wb", quiet = TRUE)
    }
    report("Unpacking the download.")
    utils::untar(archive, exdir = root)
    unlink(archive)
    binary <- managed_binary()
    if (is.na(binary)) stop("the archive held no ollama binary")
    Sys.chmod(binary, "0755")
    list(ok = TRUE, message = paste("The runtime is installed at", root))
  }, error = function(e) {
    list(ok = FALSE, message = paste(
      "The download did not finish:", conditionMessage(e),
      "The guided route is always available as a fallback."))
  })
  result
}

# Starts a server from whichever binary is present, in the background,
# so the app stays responsive. A server that is already answering is
# left alone rather than started twice.
managed_start <- function(base_url = "http://localhost:11434",
                          report = function(text) invisible(NULL)) {
  if (ollama_status(base_url)$running) {
    return(list(ok = TRUE, message = "A server was already running."))
  }
  binary <- managed_binary()
  if (is.na(binary)) binary <- system_binary()
  if (is.na(binary)) {
    return(list(ok = FALSE, message = paste(
      "No runtime is installed yet, so there is nothing to start.")))
  }
  tryCatch({
    report("Starting the server.")
    system2(binary, "serve", wait = FALSE,
            stdout = file.path(tessera_dir("data"), "ollama-serve.log"),
            stderr = file.path(tessera_dir("data"), "ollama-serve.log"))
    # A first start takes longer than a later one, because the runtime
    # sets up its own store before it binds a port. Six seconds was not
    # enough and reported failure on a server that was simply still
    # getting ready. Thirty is, and the wait says what it is doing
    # rather than going quiet.
    for (i in 1:30) {
      Sys.sleep(1)
      if (ollama_status(base_url)$running) {
        return(list(ok = TRUE, message = "The server is answering."))
      }
      report(sprintf("Waiting for the server to answer (%d seconds).", i))
    }
    list(ok = FALSE, message = paste(
      "The server was started but has not answered in thirty seconds.",
      "It may still be setting itself up. Press Check again in a",
      "moment, and see the log at",
      file.path(tessera_dir("data"), "ollama-serve.log"), "if it does",
      "not appear."))
  }, error = function(e) {
    list(ok = FALSE, message = paste("The server did not start:",
                                     conditionMessage(e)))
  })
}

# Downloads one model through whichever binary is present. This is a
# fetch into the runtime's own store rather than a system install, which
# is why it can be offered on both routes.
# A model name is handed to another program as an argument. system2()
# passes arguments without a shell, so there is no shell to inject into,
# but a name beginning with a dash would still arrive as an option
# rather than as a name. The shape a model name is allowed to have is
# narrow and well known, so it is checked rather than trusted.
valid_model_name <- function(name) {
  is.character(name) && length(name) == 1 && nzchar(name) &&
    nchar(name) <= 128 &&
    grepl("^[A-Za-z0-9][A-Za-z0-9._/:-]*$", name)
}

pull_model <- function(name, report = function(text) invisible(NULL)) {
  if (!valid_model_name(name)) {
    return(list(ok = FALSE, message = paste(
      "That is not a model name. Names are letters, numbers, and the",
      "punctuation a registry uses, such as llama3.2 or qwen2.5:7b.")))
  }
  binary <- managed_binary()
  if (is.na(binary)) binary <- system_binary()
  if (is.na(binary)) {
    return(list(ok = FALSE, message = paste(
      "No runtime is installed, so there is nothing to download a model",
      "with. Set one up first.")))
  }
  tryCatch({
    report(paste("Downloading", name, "through the runtime."))
    code <- system2(binary, c("pull", name), stdout = TRUE, stderr = TRUE)
    status <- attr(code, "status")
    if (!is.null(status) && status != 0) {
      stop(paste(utils::tail(code, 3), collapse = " "))
    }
    list(ok = TRUE, message = paste(name, "is ready."))
  }, error = function(e) {
    list(ok = FALSE, message = paste("That model did not download:",
                                     conditionMessage(e)))
  })
}

# Removes one model from the runtime's store. This is the counterpart to
# a download and belongs beside it: an app that can fill a disk should
# be able to empty it again without sending the reader to a terminal.
remove_model <- function(name) {
  if (!valid_model_name(name)) {
    return(list(ok = FALSE, message = "That is not a model name."))
  }
  binary <- managed_binary()
  if (is.na(binary)) binary <- system_binary()
  if (is.na(binary)) {
    return(list(ok = FALSE, message = "No runtime is installed."))
  }
  tryCatch({
    out <- system2(binary, c("rm", name), stdout = TRUE, stderr = TRUE)
    status <- attr(out, "status")
    if (!is.null(status) && status != 0) {
      stop(paste(utils::tail(out, 2), collapse = " "))
    }
    list(ok = TRUE, message = paste(name, "has been removed."))
  }, error = function(e) {
    list(ok = FALSE, message = paste("That model was not removed:",
                                     conditionMessage(e)))
  })
}

# Removes the managed runtime and everything it downloaded. Only the
# managed copy can be removed this way, and that is the honest limit:
# the app put that folder there and can take it away, while a runtime
# installed through a package manager belongs to the system and should
# be removed the same way it arrived.
remove_runtime <- function() {
  if (is.na(managed_binary())) {
    return(list(ok = FALSE, message = paste(
      "There is no managed runtime to remove. A runtime installed",
      "another way should be removed the way it was installed, which",
      "for Homebrew is brew uninstall ollama.")))
  }
  root <- managed_root()
  tryCatch({
    unlink(root, recursive = TRUE, force = TRUE)
    if (dir.exists(root)) stop("the folder could not be deleted")
    list(ok = TRUE, message = paste(
      "The managed runtime and every model it held have been removed",
      "from", root))
  }, error = function(e) {
    list(ok = FALSE, message = paste("The runtime was not removed:",
                                     conditionMessage(e),
                                     "The folder is at", root))
  })
}

# Which of the catalogue models fit the machine that was reported. The
# memory figures are the working set each model needs with room for the
# rest of the machine, which is why they sit above the download size.
model_fit <- function(report) {
  ram <- report$ram_gb
  vapply(model_options(), function(m) {
    needs <- m$min_ram
    if (!is.finite(ram)) return("unknown")
    if (ram >= needs + 4) "comfortable"
    else if (ram >= needs) "workable"
    else "too large"
  }, "")
}

# The model the app suggests, given what was reported. The rule is
# plain: the largest model that is comfortable, or the smallest one in
# the catalogue when nothing is.
recommended_model <- function(report) {
  fits <- model_fit(report)
  opts <- model_options()
  comfortable <- which(fits == "comfortable")
  if (length(comfortable) > 0) {
    return(opts[[utils::tail(comfortable, 1)]]$id)
  }
  opts[[1]]$id
}
