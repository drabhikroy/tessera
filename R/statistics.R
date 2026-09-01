# statistics.R
# Inference for a single observed network.
#
# Copyright Abhik Roy. Released under the PolyForm Noncommercial
# License 1.0.0. See LICENSE.md.
#
# Everything in the Research tab describes what is in front of you. This
# file answers a different question: is what is in front of you more
# than the size and density of the network would produce on their own.
#
# The method is the conditional uniform graph test, the standard tool
# for this in social network analysis since Anderson, Butts, and Carley
# (1999) showed how strongly size and density alone drive most graph
# level indices. A network of fifty people at nine percent density has a
# transitivity, a centralization, and a modularity before anyone has
# done anything social at all. The test compares the observed value
# against many random networks that share the feature being conditioned
# on, and reports where the observation falls in that distribution.
#
# Two null models are offered because they answer different questions.
# Conditioning on density asks whether the pattern exceeds what this
# many ties among this many people would give. Conditioning on the
# degree sequence asks a harder question: whether the pattern exceeds
# what these particular people, with exactly the numbers of ties they
# each have, would give. A result that survives the second is a claim
# about arrangement rather than about volume.
#
# What this file deliberately does not do: model the network. Modeling
# who connects to whom, with covariates, is what exponential random
# graph and latent space models are for, and both need decisions about
# specification that no tool should make on a reader's behalf. The
# reproducible script in the Research tab is the exit into that work.
#
# Two structural rules hold everywhere below.
#
# First, every number this file returns has length one. A measure that
# cannot be computed comes back as NA, never as NULL and never as a zero
# length vector. The screen reads these values inside if() and sprintf()
# calls, and a value of length zero there fails with a message that
# names neither the measure nor the file it came from.
#
# Second, the undirected graph tested here is the same object the rest
# of the app measures, rather than one rebuilt from the directed copy.
# Two graphs built from the same ties can carry their people in
# different orders, and a grouping vector indexed by position is quietly
# wrong the moment the orders differ.

suppressPackageStartupMessages({
  library(igraph)
  library(tibble)
  library(dplyr)
})

# The number of random networks behind each test. More is steadier and
# slower; the relationship between the two is linear and obvious, which
# is why the choice is the reader's rather than a constant here.
STAT_REPS <- c("Quick (200)" = 200, "Standard (500)" = 500,
               "Careful (2000)" = 2000)

# Above this many people the triad census is left out of the battery.
# The census itself is fast, but running it several hundred times over
# a large directed graph is the one part of this file that can turn a
# few seconds into a few minutes.
TRIAD_LIMIT <- 400

# Above this many people the path concentration test is left out.
# Betweenness costs a full breadth first search from every person, so
# its cost per random network grows with people times ties, and it is
# the one measure here that can make a run take minutes rather than
# seconds. The limit is stated on screen when it applies rather than
# left as a measure that quietly went missing.
BETWEENNESS_LIMIT <- 300

# One sample from the null model. Conditioning on edges holds the number
# of people and the number of ties and shuffles everything else.
# Conditioning on degree holds each person's number of ties as well,
# which is a far stronger condition and a far weaker claim if the
# observation survives it.
null_draw <- function(gi, conditioning) {
  if (identical(conditioning, "degree") && ecount(gi) > 0) {
    # Ten passes per tie is the usual guidance for a rewiring to lose
    # its memory of where it started.
    return(rewire(gi, keeping_degseq(niter = 10 * ecount(gi))))
  }
  sample_gnm(vcount(gi), ecount(gi), directed = is_directed(gi))
}

# Where the observation falls in the null distribution.
#
# The two one sided proportions are reported rather than a single two
# sided number, because the interesting question is directional: is
# there more clustering than chance would give, or less. Both are
# computed with the observation included in the count, which is the
# conventional correction and keeps a proportion from ever being zero,
# since zero would claim more certainty than a finite number of samples
# can support.
#
# The standardized score sits beside them because a proportion hits its
# floor as soon as every sample falls on one side, and two results that
# both read as 0.002 can be two standard deviations apart or twenty.
cug_summary <- function(observed, null_values) {
  observed <- one_number(observed)
  null_values <- suppressWarnings(as.numeric(null_values))
  null_values <- null_values[is.finite(null_values)]
  reps <- length(null_values)
  blank <- list(observed = observed, mean = NA_real_, sd = NA_real_,
                lo = NA_real_, hi = NA_real_, difference = NA_real_,
                ratio = NA_real_, p_greater = NA_real_, p_less = NA_real_,
                p_error = NA_real_, z = NA_real_, reps = 0L)
  if (reps == 0 || !is.finite(observed)) return(blank)
  mu <- mean(null_values)
  sigma <- stats::sd(null_values)
  p_greater <- (sum(null_values >= observed) + 1) / (reps + 1)
  p_less <- (sum(null_values <= observed) + 1) / (reps + 1)
  p <- min(p_greater, p_less)
  band <- stats::quantile(null_values, c(0.025, 0.975), names = FALSE,
                          type = 7)
  list(
    observed  = observed,
    mean      = mu,
    sd        = sigma,
    # The middle of the null distribution, as an interval. A proportion
    # says how often chance beat the observation; this says what chance
    # actually produced, which is the thing a reader can picture and
    # the thing they can compare a second network against.
    lo        = band[[1]],
    hi        = band[[2]],
    difference = observed - mu,
    ratio     = if (is.finite(mu) && abs(mu) > 1e-9) observed / mu else NA_real_,
    p_greater = p_greater,
    p_less    = p_less,
    # How much of the proportion is the sampling and not the network.
    # A proportion computed from five hundred random networks carries
    # its own error, and quoting three decimal places of it without
    # saying so claims a precision the method does not have.
    p_error   = sqrt(p * (1 - p) / reps),
    z         = if (is.finite(sigma) && sigma > 0) {
      (observed - mu) / sigma
    } else {
      NA_real_
    },
    reps      = as.integer(reps)
  )
}

# The smaller of the two one sided proportions, or NA when the test did
# not run. Pulled out because four places wanted it and each of them
# wrote its own guard.
cug_p <- function(summary) {
  p <- suppressWarnings(min(summary$p_greater, summary$p_less,
                            na.rm = TRUE))
  if (!is.finite(p)) NA_real_ else p
}

# What each measure is a share of, in this network.
#
# A proportion is not a thing a reader can picture. "Twenty two percent
# of connected triples close" means nothing until you know there are a
# hundred and thirty connected triples and that chance would have closed
# about twenty one of them, at which point the finding is "six more
# triangles than chance", which is a sentence about this network rather
# than about proportions.
#
# Measures with no countable denominator return NULL and are described
# in their own units instead.
natural_units <- function(gu, gd, membership) {
  degrees <- degree(gu)
  connected_triples <- sum(choose(degrees, 2))
  people <- vcount(gu)
  list(
    clustering = list(total = connected_triples, noun = "connected triples",
                      verb = "close"),
    giant_share = list(total = people, noun = "people",
                       verb = "sit in the largest piece"),
    reciprocity = if (is.null(gd)) NULL else {
      list(total = ecount(gd), noun = "ties", verb = "are answered")
    },
    transitive_triads = if (is.null(gd)) NULL else {
      list(total = choose(vcount(gd), 3), noun = "triples",
           verb = "are closed chains")
    },
    cyclic_triads = if (is.null(gd)) NULL else {
      list(total = choose(vcount(gd), 3), noun = "triples",
           verb = "are loops of three")
    },
    ei = if (is.null(membership)) NULL else {
      list(total = ecount(gu), noun = "ties", verb = "cross between groups",
           # The E-I index runs from minus one to plus one rather than
           # from zero to one, so the share it implies has to be
           # recovered before it can be counted.
           from_index = TRUE)
    }
  )
}

# A share turned back into a count of things in this network.
as_count <- function(value, unit) {
  if (is.null(unit) || !has_number(value)) return(NA_real_)
  share <- if (isTRUE(unit$from_index)) (value + 1) / 2 else value
  share * unit$total
}

# Whether one person is carrying the finding.
#
# A network level number computed from twenty people can rest almost
# entirely on one of them, and a proportion cannot tell you that. This
# recomputes every measure with the most connected person removed and
# reports how far each one moved. It is one extra pass over one graph,
# which is nothing beside the several hundred random ones, and it
# answers a question a reader would otherwise have to ask by hand.
#
# This is a jackknife with a single deletion, chosen rather than the
# full leave one out because the person most able to move a network
# level statistic is almost always its best connected member, and the
# full version costs a pass per person.
drop_busiest <- function(gu, gd, want_triads, want_betweenness) {
  if (vcount(gu) < 5) return(NULL)
  drop <- which.max(degree(gu))
  smaller <- induced_subgraph(gu, setdiff(seq_len(vcount(gu)), drop))
  if (ecount(smaller) < 2) return(NULL)
  without <- graph_profile(smaller, FALSE, want_betweenness)
  if (!is.null(gd)) {
    keep <- setdiff(V(gd)$name, V(gu)$name[drop])
    smaller_directed <- induced_subgraph(gd, which(V(gd)$name %in% keep))
    if (ecount(smaller_directed) >= 2) {
      directed_without <- graph_profile(smaller_directed, want_triads, FALSE)
      for (nm in DIRECTED_MEASURES) without[[nm]] <- directed_without[[nm]]
    }
  }
  list(person = V(gu)$name[drop], values = without)
}

# Rounded, and readable at whatever size the number is. A share near
# zero needs three places and a mean distance needs two, and one rule
# for both prints either 0.000 or 2.41521.
show_number <- function(value, digits = 3) {
  value <- one_number(value)
  if (!is.finite(value)) return("not available")
  formatC(value, format = "f", digits = digits)
}

show_count <- function(value) {
  value <- one_number(value)
  if (!is.finite(value)) return("some")
  format(round(value), big.mark = ",")
}

show_percent <- function(value) {
  value <- one_number(value)
  if (!is.finite(value)) return("not available")
  paste0(formatC(100 * value, format = "f", digits = 1), " percent")
}

# What a test is worth, taking more than one thing into account.
#
# A proportion below a threshold is not a finding. The American
# Statistical Association said so plainly in 2016, and the reason is
# arithmetic rather than fashion: a proportion answers how often chance
# would beat this observation, which is not the same question as whether
# the difference is large, whether it would survive a second sample, or
# whether it rests on one person. Any of those three can fail while the
# proportion looks convincing.
#
# So four things are weighed here, and a result has to survive all of
# them to be called a finding:
#
#   the proportion, as before;
#   whether the observation falls outside the middle of what chance
#     actually produced, which is where the proportion came from and is
#     the thing a reader can picture;
#   the sampling error on the proportion itself, since one computed from
#     five hundred random networks is an estimate and quoting it to three
#     places without saying so claims a precision the method lacks;
#   and whether removing the best connected person moves the observation
#     back inside the range chance produces, which is the difference
#     between a property of the network and a property of one member.
#
# The verdict names which of them failed rather than only reporting that
# something did.
assess <- function(summary, without = NA_real_) {
  p <- suppressWarnings(min(summary$p_greater, summary$p_less, na.rm = TRUE))
  if (!is.finite(p) || !has_number(summary$mean) ||
      !has_number(summary$observed)) {
    return(list(band = "unknown", label = "No comparison possible",
                p = NA_real_, fragile = FALSE, steady = FALSE))
  }
  if (has_number(summary$sd) && summary$sd == 0) {
    return(list(band = "unknown", label = "No comparison possible",
                p = p, fragile = FALSE, steady = FALSE))
  }

  outside <- has_number(summary$lo) && has_number(summary$hi) &&
    (summary$observed < summary$lo || summary$observed > summary$hi)
  # Two sampling errors either side of the proportion. If that interval
  # crosses the threshold, the sampling and not the network is deciding
  # the verdict, and the cure is more random networks rather than a
  # firmer sentence.
  steady <- !has_number(summary$p_error) ||
    (p + 2 * summary$p_error) <= 0.05
  # Does the finding survive losing its best connected member.
  fragile <- FALSE
  if (has_number(without) && has_number(summary$lo)) {
    fragile <- outside &&
      without >= summary$lo && without <= summary$hi
  }

  band <- if (p > 0.10) {
    "none"
  } else if (!outside) {
    "edge"
  } else if (fragile) {
    "fragile"
  } else if (!steady) {
    "edge"
  } else if (p <= 0.01) {
    "strong"
  } else {
    "clear"
  }
  list(
    band = band,
    label = switch(band,
      strong = "Clearly beyond chance",
      clear = "Beyond chance",
      fragile = "Rests on one person",
      edge = "Near the edge",
      "Within chance"),
    p = p,
    fragile = fragile,
    steady = steady,
    outside = outside
  )
}

# The reading of a test, written about this network rather than about
# proportions.
#
# Three sentences, and every one of them names something in the data in
# front of the reader: how many of what this network has, what the same
# many people and ties produced when the ties were shuffled, and what
# the difference amounts to in the same units. A reading that says a
# proportion was above a threshold is a reading of the method.
cug_reading <- function(label, summary, meanings, unit = NULL,
                        without = NA_real_, person = NULL, digits = 3,
                        subject = NULL, null_text = NULL) {
  subject <- subject %||% tolower(label)
  verdict <- assess(summary, without)
  if (identical(verdict$band, "unknown")) {
    if (has_number(summary$sd) && summary$sd == 0) {
      return(paste0("Every random network returned ",
                    show_number(summary$observed, digits),
                    ", the same value this network has, so there is ",
                    "nothing here to compare against."))
    }
    return("This one could not be computed for this network.")
  }

  # What is actually in this network, in things rather than in shares.
  here <- if (is.null(unit)) {
    paste0("This network scores ", show_number(summary$observed, digits), ".")
  } else {
    paste0("Here ", show_count(as_count(summary$observed, unit)), " of this ",
           "network's ", show_count(unit$total), " ", unit$noun, " ",
           unit$verb, ", which is ",
           show_number(summary$observed, digits), ".")
  }

  # What chance produced, as a range rather than as a threshold.
  chance <- paste0("Across ", summary$reps, " ",
                   null_text %||% paste("networks with these same people and",
                                        "this same number of ties, shuffled"),
                   ", that came out between ", show_number(summary$lo, digits),
                   " and ", show_number(summary$hi, digits), ", averaging ",
                   show_number(summary$mean, digits), ".")

  # What the gap amounts to.
  gap <- if (is.null(unit)) {
    paste0("The gap is ", show_number(abs(summary$difference), digits),
           ", which is ", show_number(abs(summary$z), 1),
           " times the spread chance produces.")
  } else {
    paste0("The gap is about ",
           show_count(abs(as_count(summary$observed, unit) -
                            as_count(summary$mean, unit))), " ", unit$noun,
           ", or ", show_number(abs(summary$z), 1),
           " times the spread chance produces.")
  }

  direction <- if (summary$observed >= summary$mean) "higher" else "lower"
  meaning <- switch(verdict$band,
    none = paste0("That sits inside the range, so ", subject,
                  " here is what a network of this size and density gives ",
                  "on its own."),
    edge = paste0("That is ", direction, " than the average but not ",
                  "clearly outside the range, so it is worth noting and ",
                  "not worth resting an argument on."),
    fragile = paste0("Take out ", person %||% "the best connected person",
                     ", the most connected person here, and the figure ",
                     "moves to ", show_number(without, digits),
                     ", back inside what chance produces. So this is a ",
                     "fact about ", person %||% "one person",
                     " rather than about the network."),
    paste0("Reading it: ", meanings[[direction]]))

  extra <- character(0)
  if (verdict$band %in% c("strong", "clear") && !verdict$steady) {
    extra <- c(extra, paste0("The proportion itself carries about ",
                             show_number(summary$p_error, 3),
                             " of sampling error, so run more random ",
                             "networks before quoting it."))
  }
  if (verdict$band %in% c("strong", "clear") && has_number(without) &&
      !is.null(person)) {
    extra <- c(extra, paste0("It holds without ", person,
                             ", the most connected person here, which gives ",
                             show_number(without, digits), "."))
  }
  paste(c(here, chance, gap, meaning, extra), collapse = " ")
}

# The E-I index under label permutation rather than under a random
# graph. Krackhardt and Stern's measure is about the grouping, so the
# right null holds the network fixed and shuffles who is in which
# group, which is a permutation test rather than a graph test.
ei_index <- function(gi, membership) {
  if (ecount(gi) == 0) return(NA_real_)
  pairs <- ends(gi, E(gi), names = FALSE)
  internal <- sum(membership[pairs[, 1]] == membership[pairs[, 2]])
  external <- ecount(gi) - internal
  (external - internal) / ecount(gi)
}

ei_permutation <- function(gi, membership, reps) {
  observed <- ei_index(gi, membership)
  if (!is.finite(observed)) {
    return(list(summary = cug_summary(NA_real_, numeric(0)),
                observed = NA_real_))
  }
  samples <- vapply(seq_len(reps), function(i) {
    ei_index(gi, sample(membership))
  }, numeric(1))
  list(summary = cug_summary(observed, samples), observed = observed)
}

# The largest connected piece of a graph, or NULL when there is nothing
# to take. Four measures wanted this and three of them called
# decompose() twice apiece to get it.
giant_piece <- function(gi) {
  if (vcount(gi) == 0) return(NULL)
  comp <- components(gi, mode = "weak")
  keep <- which(comp$membership == which.max(comp$csize))
  if (length(keep) == 0) return(NULL)
  induced_subgraph(gi, keep)
}

# Share of the network sitting in its largest piece. A network that
# comes apart into fragments is a different object from one that does
# not, and this share is the plainest reading of which one is in front
# of you.
giant_share <- function(gi) {
  if (vcount(gi) == 0) return(NA_real_)
  comp <- components(gi, mode = "weak")
  max(comp$csize) / vcount(gi)
}

# Freeman betweenness centralization. Degree centralization asks whether
# the ties pile up on a few people; this asks whether the paths do, and
# the two come apart in exactly the case worth knowing about, which is a
# person of modest degree sitting between two halves of a network.
betweenness_centralization <- function(gi) {
  if (vcount(gi) < 3) return(NA_real_)
  out <- suppressWarnings(
    tryCatch(centr_betw(gi, directed = FALSE,
                        normalized = TRUE)$centralization,
             error = function(e) NA_real_))
  one_number(out)
}

# Every graph level statistic this file tests, computed on one graph in
# one pass.
#
# One pass rather than one per measure. Each random graph is made,
# measured, and thrown away, so the memory cost is one graph and the
# time cost is one pass however many measures are on the list. Holding
# the graphs and walking them once per measure would make every new
# measure cost another few seconds and another few hundred graphs.
graph_profile <- function(gi, want_triads = FALSE,
                          want_betweenness = TRUE) {
  undirected_view <- if (is_directed(gi)) {
    net_as_undirected(gi, mode = "collapse")
  } else {
    gi
  }
  giant <- giant_piece(undirected_view)

  out <- c(
    clustering = one_number(transitivity(undirected_view, type = "global")),
    degree_centralization = one_number(suppressWarnings(
      centr_degree(undirected_view, normalized = TRUE)$centralization)),
    betweenness_centralization = if (want_betweenness) {
      betweenness_centralization(undirected_view)
    } else {
      NA_real_
    },
    modularity = one_number(tryCatch(
      modularity(cluster_louvain(undirected_view)),
      error = function(e) NA_real_)),
    # weights = NA counts steps. The observed graph carries a tie
    # weight column and the random ones do not, so without this the
    # observation is measured in weighted cost and compared against a
    # chance average measured in steps.
    mean_distance = if (is.null(giant)) {
      NA_real_
    } else {
      one_number(mean_distance(giant, weights = NA))
    },
    assortativity = one_number(suppressWarnings(
      tryCatch(assortativity_degree(undirected_view),
               error = function(e) NA_real_))),
    giant_share = one_number(giant_share(undirected_view)),
    reciprocity = if (is_directed(gi)) {
      one_number(reciprocity(gi))
    } else {
      NA_real_
    },
    transitive_triads = NA_real_,
    cyclic_triads = NA_real_
  )

  # The triad census is the only directed measure that says anything
  # about closure, which is the question the undirected clustering
  # number answers for everyone else. 030T is a chain that also closes
  # its shortcut, the directed reading of a closed triangle; 030C is a
  # loop of three, which is the arrangement a ranking cannot produce.
  if (want_triads && is_directed(gi) && vcount(gi) >= 3) {
    census <- tryCatch(triad_census(gi), error = function(e) NULL)
    if (!is.null(census) && length(census) == 16) {
      total <- sum(census)
      if (is.finite(total) && total > 0) {
        out[["transitive_triads"]] <- census[[9]] / total
        out[["cyclic_triads"]] <- census[[10]] / total
      }
    }
  }
  out
}

# The null distribution of every measure at once, as a matrix with one
# row per random network. on_step is called with a fraction so the
# screen can show progress rather than a spinner that says nothing about
# how much is left.
null_profiles <- function(gi, conditioning, reps, want_triads = FALSE,
                          want_betweenness = TRUE, on_step = NULL) {
  first <- graph_profile(null_draw(gi, conditioning), want_triads,
                         want_betweenness)
  out <- matrix(NA_real_, nrow = reps, ncol = length(first),
                dimnames = list(NULL, names(first)))
  out[1, ] <- first
  if (reps < 2) return(out)
  step_at <- max(1L, floor(reps / 20))
  for (i in 2:reps) {
    out[i, ] <- graph_profile(null_draw(gi, conditioning), want_triads,
                              want_betweenness)
    if (!is.null(on_step) && i %% step_at == 0) on_step(i / reps)
  }
  out
}

# Whether the spread of connection counts is heavy tailed.
#
# igraph fits the tail by the Clauset, Shalizi, and Newman method. The
# goodness of fit proportion is read the opposite way from every other
# proportion on this screen: a small value means the fitted shape does
# not describe the data. From igraph 2.0 that proportion is computed
# only when asked for, which is what R/compat.R handles; before that
# release it came back whether or not anyone wanted it.
degree_shape <- function(gi) {
  d <- degree(gi)
  if (length(d) == 0) {
    return(list(mean = NA_real_, sd = NA_real_, max = NA_real_,
                ratio = NA_real_, alpha = NA_real_, xmin = NA_real_,
                ks_p = NA_real_))
  }
  fit <- net_power_law(d)
  list(
    mean  = one_number(mean(d)),
    sd    = one_number(stats::sd(d)),
    max   = one_number(max(d)),
    ratio = if (mean(d) > 0) one_number(stats::sd(d) / mean(d)) else NA_real_,
    alpha = one_number(fit$alpha),
    xmin  = one_number(fit$xmin),
    ks_p  = one_number(fit$ks_p)
  )
}

# Watts and Strogatz asked whether a network is clustered like a lattice
# while staying short like a random graph. The two halves are reported
# separately rather than as one small world coefficient, because the
# single number hides which half is doing the work and is easy to
# over-read.
#
# The comparison is against a random graph of the same size and density
# whichever null the reader chose above, because that is the comparison
# Watts and Strogatz defined. A degree preserving null would answer a
# different question and would still be labelled small world.
small_world <- function(gi, reps, null_matrix = NULL) {
  observed_c <- one_number(transitivity(gi, type = "global"))
  giant <- giant_piece(gi)
  observed_l <- if (is.null(giant)) {
    NA_real_
  } else {
    one_number(mean_distance(giant, weights = NA))
  }

  if (!is.null(null_matrix)) {
    cs <- null_matrix[, "clustering"]
    ls <- null_matrix[, "mean_distance"]
  } else {
    profiles <- null_profiles(gi, "edges", reps)
    cs <- profiles[, "clustering"]
    ls <- profiles[, "mean_distance"]
  }
  cs <- cs[is.finite(cs)]
  ls <- ls[is.finite(ls)]

  safe_ratio <- function(observed, values) {
    if (!is.finite(observed) || length(values) == 0) return(NA_real_)
    base <- mean(values)
    if (!is.finite(base) || base == 0) return(NA_real_)
    observed / base
  }
  list(
    ratio_c = safe_ratio(observed_c, cs),
    ratio_l = safe_ratio(observed_l, ls)
  )
}

# The plain names, notes, and readings for every measure in the battery,
# kept in one table so the screen, the download, and the model summary
# all say the same thing about the same number.
stat_definitions <- function() {
  list(
    clustering = list(
      label = "Clustering",
      subject = "the way triangles close",
      note = "Share of connected triples that are closed.",
      higher = paste("people here close their triangles more than chance,",
                     "which is the signature of a network built out of",
                     "small groups rather than scattered pairs."),
      lower = paste("triangles close less often than chance, which points",
                    "to a network organized around hubs or a ranking",
                    "rather than around cliques.")),
    degree_centralization = list(
      label = "Degree centralization",
      subject = "the way ties pile up on a few people",
      note = paste("How far the network is from one where one person",
                   "holds every tie."),
      higher = paste("connections are concentrated in fewer people than",
                     "chance would give, so this network leans on its",
                     "hubs."),
      lower = paste("connections are spread more evenly than chance would",
                    "give, so no small set of people holds it together.")),
    betweenness_centralization = list(
      label = "Path concentration",
      subject = "the way paths funnel through a few people",
      note = paste("How far the network is from one where every path",
                   "between two people runs through the same person."),
      higher = paste("the paths through this network funnel through a few",
                     "people more than chance would give. Degree says who",
                     "has the most ties; this says who sits between, and",
                     "those are different people often enough to be worth",
                     "checking."),
      lower = paste("paths are spread across many people, so removing any",
                    "one of them would leave the rest still reachable.")),
    modularity = list(
      label = "Group separation",
      subject = "the separation between the groups",
      note = "Modularity of the detected communities.",
      higher = paste("the groups are more separated than chance would",
                     "give, so the grouping is describing something in the",
                     "ties rather than an artifact of the algorithm."),
      lower = paste("the groups are less separated than chance produces,",
                    "which means the boundaries should not be leaned on.")),
    mean_distance = list(
      label = "Mean distance",
      subject = "the distance between people",
      note = "Average steps between two people in the largest piece.",
      higher = paste("people are further apart than chance would give,",
                     "which usually means the network is strung out rather",
                     "than compact."),
      lower = paste("people are closer together than chance would give, so",
                    "anything moving through this network has short paths",
                    "available to it.")),
    assortativity = list(
      label = "Like connects to like",
      subject = "who the well connected people connect to",
      note = paste("Whether well connected people connect to other well",
                   "connected people. Degree assortativity, running from",
                   "minus one to plus one."),
      higher = paste("well connected people here connect to each other",
                     "more than chance would give, which is the pattern",
                     "of a core with a fringe around it."),
      lower = paste("well connected people connect to poorly connected",
                    "ones more than chance would give, which is the hub",
                    "and spoke pattern and is worth stopping on, since",
                    "the hubs are then the whole network.")),
    giant_share = list(
      label = "Held together",
      subject = "the way this network holds together",
      note = "Share of people sitting in the largest connected piece.",
      higher = paste("more of the network hangs together than chance",
                     "would give at this density."),
      lower = paste("the network is in more pieces than chance would",
                    "give, so any reading of it as one network is a",
                    "reading of several.")),
    reciprocity = list(
      label = "Reciprocity",
      subject = "the rate at which ties are answered",
      note = "Share of ties that are answered.",
      higher = paste("ties are returned more often than chance would",
                     "give, which is the mark of exchange rather than of",
                     "one way flow."),
      lower = paste("ties are returned less often than chance would give,",
                    "which points to a ranking or a broadcast pattern.")),
    transitive_triads = list(
      label = "Closed threes",
      subject = "the rate at which chains close",
      note = paste("Share of all triples arranged so that a chain also",
                   "closes its shortcut. The 030T class of the triad",
                   "census."),
      higher = paste("chains close on themselves more than chance would",
                     "give, which is the directed reading of a network",
                     "built out of settled groups."),
      lower = paste("chains rarely close, so reaching a second step in",
                    "this network usually means going through someone",
                    "rather than around them.")),
    cyclic_triads = list(
      label = "Loops of three",
      subject = "the rate of loops of three",
      note = paste("Share of all triples arranged as a loop, each person",
                   "reaching the next. The 030C class of the triad",
                   "census."),
      higher = paste("loops of three are commoner than chance would give,",
                     "and a network with many of them is not a ranking,",
                     "since a ranking cannot produce a loop."),
      lower = paste("loops of three are rarer than chance would give,",
                    "which is what a network with a settled pecking order",
                    "looks like."))
  )
}

# Which measures are read off the directed copy rather than the
# undirected one. Named here because three places ask.
DIRECTED_MEASURES <- c("reciprocity", "transitive_triads", "cyclic_triads")

# The whole battery, as one table the screen and the download both read.
#
# Each row carries the numbers and the sentence together on purpose. A
# table of proportions with the readings somewhere else is how a reader
# ends up quoting a number whose meaning they never saw.
network_statistics <- function(metrics, reps = 500,
                               conditioning = c("edges", "degree"),
                               seed = 42, on_step = NULL) {
  conditioning <- match.arg(conditioning)
  reps <- max(20L, as.integer(reps))
  set.seed(seed)

  # The undirected graph the rest of the app measures, not one rebuilt
  # from the directed copy. The two list their people in the same order
  # only as long as every person appears in the ties, so rebuilding it
  # would put the grouping vector out of step with the graph the moment
  # a node table arrives carrying people who have none.
  gu <- as_plain_igraph(metrics$graph)
  gd <- metrics$digraph
  if (!is.null(gd)) gd <- as_plain_igraph(gd)

  if (vcount(gu) < 4) {
    stop("These tests need at least four people to say anything.")
  }
  if (ecount(gu) < 3) {
    stop("These tests need at least three ties to say anything.")
  }

  # The grouping travels by name rather than by position, so it stays
  # correct even if some later change reorders either graph.
  membership <- metrics$membership
  if (!is.null(membership) && !is.null(metrics$names) &&
      length(membership) == length(metrics$names)) {
    membership <- membership[match(V(gu)$name, metrics$names)]
    if (anyNA(membership)) membership <- NULL
  } else if (!is.null(membership) && length(membership) != vcount(gu)) {
    membership <- NULL
  }

  want_triads <- !is.null(gd) && vcount(gd) <= TRIAD_LIMIT
  want_betweenness <- vcount(gu) <= BETWEENNESS_LIMIT
  units <- natural_units(gu, gd, membership)

  # Measures left out of this run, each with the reason, so the screen
  # can say what is missing. A test that disappears without a word is
  # read as a test that passed.
  skipped <- list()
  note_skip <- function(label, why) {
    skipped[[length(skipped) + 1]] <<- list(measure = label, why = why)
  }
  if (!want_betweenness) {
    note_skip("Path concentration", paste(
      "left out because this network has more than", BETWEENNESS_LIMIT,
      "people and the measure costs a search from every one of them in",
      "every random network."))
  }
  if (!is.null(gd) && !want_triads) {
    note_skip("Closed threes and loops of three", paste(
      "left out because this network has more than", TRIAD_LIMIT,
      "people and the triad census would be counted once per random",
      "network."))
  }
  # Holding each person's number of ties fixed holds degree
  # centralization fixed too, since the measure is a function of the
  # degree sequence and nothing else. Every random network returns the
  # observed value exactly, so the comparison is not a weak result, it
  # is not a result. It is left out rather than reported as one.
  if (identical(conditioning, "degree")) {
    note_skip("Degree centralization", paste(
      "left out because it is computed from each person's number of",
      "ties alone, and this null model holds those fixed, so every",
      "random network returns the value that was observed."))
  }

  # Reciprocity and the two triad classes are read off the directed
  # copy; everything else is read off the undirected graph that carries
  # the grouping.
  observed <- graph_profile(gu, FALSE, want_betweenness)
  if (!is.null(gd)) {
    directed_observed <- graph_profile(gd, want_triads, FALSE)
    for (nm in DIRECTED_MEASURES) observed[[nm]] <- directed_observed[[nm]]
  }

  # One pass over the undirected null model, and one over the directed
  # null model when there is a directed copy to test.
  undirected_nulls <- null_profiles(gu, conditioning, reps, FALSE,
                                    want_betweenness, on_step = on_step)
  directed_nulls <- if (!is.null(gd)) {
    null_profiles(gd, conditioning, reps, want_triads, FALSE)
  } else {
    NULL
  }

  # What every measure looks like with the best connected person taken
  # out. One extra pass over one graph, and it answers the question a
  # proportion cannot: whether the finding is a property of the network
  # or a property of its most connected member.
  dropped <- drop_busiest(gu, gd, want_triads, want_betweenness)

  definitions <- stat_definitions()
  if (identical(conditioning, "degree")) {
    definitions[["degree_centralization"]] <- NULL
  }

  rows <- lapply(names(definitions), function(key) {
    from_directed <- key %in% DIRECTED_MEASURES
    if (from_directed && is.null(directed_nulls)) return(NULL)
    samples <- if (from_directed) {
      directed_nulls[, key]
    } else {
      undirected_nulls[, key]
    }
    if (all(!is.finite(samples))) return(NULL)
    if (!has_number(observed[[key]])) return(NULL)
    d <- definitions[[key]]
    s <- cug_summary(observed[[key]], samples)
    without <- if (is.null(dropped)) NA_real_ else dropped$values[[key]]
    person <- if (is.null(dropped)) NULL else dropped$person
    # Named apart from the column it fills. tibble() evaluates its
    # arguments where the earlier ones are already visible, so a column
    # called verdict hides a local called verdict from every argument
    # after it.
    weighed <- assess(s, without)
    digits <- if (identical(key, "mean_distance")) 2 else 3
    # What the random networks held fixed, named in the reader's terms
    # rather than left as the word "null". Which one is in force changes
    # what the result means, so it belongs in the sentence.
    null_text <- if (identical(conditioning, "degree")) {
      paste("networks in which every person kept exactly the number of",
            "ties they have here and everything else was shuffled")
    } else {
      "networks with these same people and this same number of ties, shuffled"
    }
    tibble(
      key          = key,
      measure      = d$label,
      observed     = round(s$observed, 4),
      chance_mean  = round(s$mean, 4),
      chance_low   = round(s$lo, 4),
      chance_high  = round(s$hi, 4),
      chance_sd    = round(s$sd, 4),
      z            = round(s$z, 3),
      p_higher     = round(s$p_greater, 4),
      p_lower      = round(s$p_less, 4),
      p_error      = round(s$p_error, 4),
      without_top  = round(one_number(without), 4),
      top_person   = person %||% NA_character_,
      verdict      = weighed$label,
      band         = weighed$band,
      reading      = cug_reading(d$label, s,
                                 list(higher = d$higher, lower = d$lower),
                                 units[[key]], without, person, digits,
                                 d$subject, null_text),
      note         = d$note
    )
  })
  rows <- rows[!vapply(rows, is.null, logical(1))]

  # The E-I index is not a graph test, so it is added after the battery
  # rather than inside it. Its null holds the network fixed and shuffles
  # who is in which group, since the question is about the grouping.
  if (!is.null(membership) && length(membership) == vcount(gu)) {
    perm <- ei_permutation(gu, membership, reps)
    s <- perm$summary
    if (has_number(s$observed) && has_number(s$mean)) {
      ei_verdict <- assess(s)
      rows[[length(rows) + 1]] <- tibble(
        key         = "ei",
        measure     = "Group crossing (E-I)",
        observed    = round(s$observed, 4),
        chance_mean = round(s$mean, 4),
        chance_low  = round(s$lo, 4),
        chance_high = round(s$hi, 4),
        chance_sd   = round(s$sd, 4),
        z           = round(s$z, 3),
        p_higher    = round(s$p_greater, 4),
        p_lower     = round(s$p_less, 4),
        p_error     = round(s$p_error, 4),
        without_top = NA_real_,
        top_person  = NA_character_,
        verdict     = ei_verdict$label,
        band        = ei_verdict$band,
        reading     = cug_reading("Group crossing", s, list(
          higher = paste("ties cross between groups more than the same",
                         "network would with people shuffled between",
                         "groups, so the grouping is not holding ties in."),
          lower = paste("ties stay inside groups more than shuffling",
                        "would produce, which is the pattern people",
                        "usually mean by siloed.")), units$ei,
          NA_real_, NULL, 3,
          "the tendency of ties to stay inside groups",
          "shufflings of who is in which group, with the ties held fixed"),
        note = paste("Compared against the same network with people",
                     "shuffled between groups, since the question is",
                     "about the grouping rather than about the ties.")
      )
    }
  }

  # Watts and Strogatz compare against a random graph of the same size
  # and density, so the null pass already computed is reused when that
  # is what the reader chose and a small separate one is taken when it
  # is not.
  sw <- if (identical(conditioning, "edges")) {
    small_world(gu, reps, null_matrix = undirected_nulls)
  } else {
    small_world(gu, min(reps, 200L))
  }

  list(
    table = bind_rows(rows),
    conditioning = conditioning,
    reps = reps,
    n = vcount(gu),
    m = ecount(gu),
    small_world = sw,
    degree = degree_shape(gu),
    skipped = skipped,
    dropped = dropped,
    groups = if (is.null(membership)) NA_integer_ else {
      length(unique(membership))
    },
    triads_tested = isTRUE(want_triads),
    directed = !is.null(gd)
  )
}

# What the local model is given.
#
# The model was previously handed three numbers per measure and asked to
# write about them, which is a task with exactly one honest answer: read
# the numbers back. Everything it produced was a list of numbers because
# a list of numbers is all it had.
#
# So it gets the network instead. How many people, how many ties, how
# dense, how many groups, directed or not; then for each measure the
# whole reading, which already says what this network has, what chance
# produced, what the gap amounts to in things rather than in shares, and
# whether one person is carrying it. A model given that can write about
# this network, because this network is what it was told about.
#
# It still computes nothing. Every number below was computed in R and
# every sentence about what a number means was written in R. The model
# arranges them.
stats_facts <- function(res, title = NULL) {
  density_here <- if (res$n > 1) {
    2 * res$m / (res$n * (res$n - 1))
  } else {
    NA_real_
  }
  opening <- paste0(
    "The network: ",
    if (is.null(title)) "" else paste0(title, ", "),
    show_count(res$n), " people and ", show_count(res$m), " ties, a density of ",
    show_number(density_here, 3),
    if (isTRUE(res$directed)) ", directed" else ", undirected",
    if (has_number(res$groups)) {
      paste0(", with ", show_count(res$groups),
             " groups found by community detection")
    } else {
      ""
    },
    ".")

  method <- paste0(
    "How the comparison was made: each measure below was computed for ",
    "this network and then for ", res$reps,
    " random networks that held ",
    if (identical(res$conditioning, "degree")) {
      "each person's number of ties"
    } else {
      "the number of people and the number of ties"
    },
    " fixed. The range given for each measure is the middle 95 percent ",
    "of what those random networks produced.")

  dropped <- if (is.null(res$dropped)) {
    NULL
  } else {
    paste0("Every measure was also recomputed with ", res$dropped$person,
           ", the most connected person here, removed, to see whether any ",
           "finding rests on one member.")
  }

  findings <- vapply(seq_len(nrow(res$table)), function(i) {
    row <- res$table[i, ]
    paste0(row$measure, " (", tolower(row$verdict), "). ", row$reading)
  }, "")

  c(opening, method, dropped, "Findings:", findings)
}
