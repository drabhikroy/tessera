# compat.R
# One place that knows which igraph this machine has.
#
# Copyright Abhik Roy. Released under the PolyForm Noncommercial
# License 1.0.0. See LICENSE.md.
#
# igraph renamed several functions between 1.6 and 2.1 and changed what
# one of them returns. The renames are warnings rather than errors, but
# a deprecation warning is a promise that the call will stop working,
# and one printed once per session in a running app is a warning nobody
# reads. The return change is harder: a list element is present on one
# release and absent on another, so code that reads it fails with a
# message naming neither the element nor the package.
#
# Each wrapper below asks the installed igraph what it offers, calls
# whichever name is there, and returns the same shape either way, so
# nothing else in the app branches on a version number. None of these
# does any math; each one is a name.

suppressPackageStartupMessages({
  library(igraph)
})

# Whether the installed igraph exports a name. Used instead of a version
# comparison because a version number says which release this is and
# this question is about which functions came with it, and the two have
# come apart before.
igraph_has <- function(name) {
  exists(name, envir = asNamespace("igraph"), inherits = FALSE)
}

# Whether a function accepts an argument, for the case where the name
# survived and the arguments moved.
igraph_accepts <- function(name, argument) {
  if (!igraph_has(name)) return(FALSE)
  argument %in% names(formals(get(name, envir = asNamespace("igraph"))))
}

# as_undirected() in igraph 2.1 and later, as.undirected() before it.
# Same arguments, same return.
net_as_undirected <- function(g, mode = "collapse", ...) {
  fn <- if (igraph_has("as_undirected")) {
    get("as_undirected", envir = asNamespace("igraph"))
  } else {
    get("as.undirected", envir = asNamespace("igraph"))
  }
  fn(g, mode = mode, ...)
}

# as_directed() in igraph 2.1 and later, as.directed() before it.
net_as_directed <- function(g, mode = "mutual", ...) {
  fn <- if (igraph_has("as_directed")) {
    get("as_directed", envir = asNamespace("igraph"))
  } else {
    get("as.directed", envir = asNamespace("igraph"))
  }
  fn(g, mode = mode, ...)
}

# The HITS pair. igraph 2.0.3 folded hub_score() and authority_score()
# into one hits_scores() call that returns both, which is also the
# cheaper thing to do since the two share an eigenproblem. Returns a
# list of two numeric vectors under both igraph versions.
net_hits <- function(g, weights = NULL) {
  n <- vcount(g)
  empty <- list(hub = rep(0, n), authority = rep(0, n))
  if (n == 0 || ecount(g) == 0) return(empty)
  out <- tryCatch({
    if (igraph_has("hits_scores")) {
      h <- hits_scores(g, weights = weights)
      list(hub = as.numeric(h$hub), authority = as.numeric(h$authority))
    } else {
      list(
        hub = as.numeric(
          get("hub_score", envir = asNamespace("igraph"))(
            g, weights = weights)$vector),
        authority = as.numeric(
          get("authority_score", envir = asNamespace("igraph"))(
            g, weights = weights)$vector))
    }
  }, error = function(e) empty)
  # A failed eigen solve returns a vector of the wrong length rather
  # than an error on some inputs, so the length is checked rather than
  # trusted.
  if (length(out$hub) != n || length(out$authority) != n) return(empty)
  out
}

# The power law tail fit.
#
# igraph 2.0 moved the Kolmogorov-Smirnov proportion behind an argument
# that is off by default, because the correct calculation resamples and
# is slow. On those releases fit$KS.p is NULL, and assigning NULL into a
# list drops the element rather than storing it, so a caller reading
# that element gets nothing at all.
#
# This wrapper always returns three numbers of length one. When the
# proportion cannot be had it is NA rather than absent, which is a value
# a caller can test.
net_power_law <- function(x, precision = 0.03) {
  blank <- list(alpha = NA_real_, xmin = NA_real_, ks_p = NA_real_)
  x <- x[is.finite(x) & x > 0]
  # The fit needs a tail to fit. Below this the plfit routine either
  # errors or returns an exponent that means nothing.
  if (length(x) < 10 || length(unique(x)) < 3) return(blank)

  fit <- if (igraph_accepts("fit_power_law", "p.value")) {
    tryCatch(fit_power_law(x, p.value = TRUE, p.precision = precision),
             error = function(e) NULL)
  } else {
    tryCatch(fit_power_law(x), error = function(e) NULL)
  }
  if (is.null(fit)) return(blank)

  one <- function(value) {
    if (is.null(value) || length(value) != 1 || !is.numeric(value)) {
      return(NA_real_)
    }
    as.numeric(value)
  }
  list(alpha = one(fit$alpha), xmin = one(fit$xmin), ks_p = one(fit$KS.p))
}

# A scalar or NA, never a zero length vector and never NULL. Applied
# where a value is read as well as where it is made, since a value that
# should be one number and arrives as none fails inside whatever if() or
# sprintf() reads it, a long way from wherever it went missing.
one_number <- function(value) {
  if (is.null(value) || length(value) == 0) return(NA_real_)
  value <- suppressWarnings(as.numeric(value[[1]]))
  if (is.na(value)) NA_real_ else value
}

# Whether a value can be shown as a number at all.
has_number <- function(value) {
  v <- one_number(value)
  !is.na(v) && is.finite(v)
}
