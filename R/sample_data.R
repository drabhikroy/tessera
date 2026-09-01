# sample_data.R
# Two built in networks so the app demonstrates itself with no upload. Both
# are generated with a fixed seed: the same picture appears on every launch,
# which matters for a demo that a reviewer may open twice.
#
# Copyright Abhik Roy. Released under the PolyForm Noncommercial
# License 1.0.0. See LICENSE.md.

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(tibble)
})

first_names <- c(
  "Maria", "James", "Aisha", "Daniel", "Priya", "Marcus", "Elena", "Tom",
  "Yuki", "Sofia", "Andre", "Grace", "Omar", "Lily", "Victor", "Nadia",
  "Sam", "Ruth", "Diego", "Hana", "Paul", "Ines", "Kwame", "Clara",
  "Ravi", "Anna", "Leo", "Maya", "Erik", "Tara", "Jonas", "Rosa",
  "Felix", "Nina", "Amir", "Joy", "Pablo", "Vera", "Kenji", "Dana",
  "Lucas", "Mira", "Owen", "Zara", "Ivan", "Ada", "Noel", "Bea",
  "Hugo", "Lena", "Rafael", "June", "Carl", "Asha", "Peter", "Gita"
)

# A product studio of about fifty five people in five working teams plus a
# small management circle. Cross team ties are sparse on purpose so the map
# shows honest structure: clear groups, a few brokers, one fragile spot.
sample_org_network <- function() {
  set.seed(2026)
  teams <- list(
    Design      = 1:10,
    Engineering = 11:24,
    Sales       = 25:34,
    Support     = 35:44,
    Operations  = 45:52,
    Leadership  = 53:56
  )
  people <- first_names[1:56]

  # Inside each team, ties form densely but not completely. Real teams
  # have pairs who rarely work together, and the map should show that
  # texture. crossing() builds each within team pair once.
  within_team <- imap(teams, function(ids, nm) {
    tidyr::crossing(a = ids, b = ids) |>
      filter(a < b) |>
      slice_sample(prop = 0.45)
  }) |>
    list_rbind()

  # Leadership reaches into every team through a couple of contacts each.
  lead_ties <- tidyr::crossing(
    lead = teams$Leadership,
    team = names(teams)[names(teams) != "Leadership"]
  ) |>
    pmap(function(lead, team) {
      tibble(a = lead, b = sample(teams[[team]], 2))
    }) |>
    list_rbind() |>
    slice_sample(prop = 0.8)

  # A handful of chosen brokers connect neighboring teams. These are the
  # people the betweenness reading should surface.
  broker_ties <- tribble(
    ~a, ~b,
     3, 15,   # Design and Engineering share a product pair
     3, 18,
    27, 36,   # Sales hands accounts to Support through one person
    27, 39,
    46, 12,   # Operations keeps one line into Engineering
    38, 47    # one extra Support to Operations line
  )

  named <- bind_rows(within_team, lead_ties, broker_ties) |>
    transmute(from = people[a], to = people[b])

  # Two contractors work with the studio through a single Design contact.
  # This is a common real arrangement and it gives the map a true single
  # point of failure for the fragility paragraph to name.
  contractors <- tribble(
    ~from,      ~to,
    people[9], "Noor",
    people[9], "Wren",
    "Noor",    "Wren"
  )

  bind_rows(named, contractors) |>
    mutate(weight = sample(1:4, n(), replace = TRUE))
}

# A customer referral network: forty customers where a few early adopters
# brought in most of the rest. Hub heavy by construction, so degree and
# betweenness tell different stories than the org network does.
sample_referral_network <- function() {
  set.seed(7)
  # A neighborhood word of mouth network for a small business. A few
  # early customers brought in most of the rest, so the map shows clear
  # connectors rather than an even mesh. Real names keep it readable.
  people <- c(
    "Rosa", "Malik", "Jen", "Theo", "Amara", "Sam", "Priya", "Luis",
    "Grace", "Owen", "Fatima", "Cole", "Nadia", "Wes", "Bea", "Hugo",
    "Iris", "Dev", "Mona", "Kai", "Elle", "Ravi", "Nora", "Jonah",
    "Sana", "Pax", "Vera", "Tariq", "Lena", "Marco", "Ada", "Reed",
    "Yara", "Finn", "Nia", "Omar", "Cleo", "Zane", "Ivy", "Boone"
  )
  n <- length(people)
  # Preferential attachment by hand: each newcomer ties to one or two
  # existing customers, with the better connected ones more likely
  # picked. The degree vector must update as each newcomer arrives, so
  # map() walks the sequence in order and the updates happen in place.
  deg <- rep(1, n)
  ties <- map(3:n, function(i) {
    k <- if (runif(1) < 0.3) 2 else 1
    targets <- sample(seq_len(i - 1), k, prob = deg[seq_len(i - 1)])
    deg[targets] <<- deg[targets] + 1
    deg[i] <<- k
    tibble(from = people[targets], to = people[i])
  })

  bind_rows(tibble(from = people[1], to = people[2]), list_rbind(ties)) |>
    mutate(weight = 1)
}

# Optional local language model hook. The app never needs this to work: the
# built in interpretation covers everything. When a local Ollama server is
# running, this asks it to restate the computed summary in its own words,
# with the numbers passed in so the model cannot invent new ones.
# Two directed samples, added so the dyad and triad census has something
# to work on. Both are the same size and shape family as the undirected
# samples, and they differ from each other in exactly the way the census
# measures, which is the point of having two.
#
# The census counts how often a tie is returned. In an advice network
# almost none are: people ask upward and answers come back as advice
# rather than as a matching question, so the dyad census is mostly
# asymmetric and the triads lean toward the transitive classes. In a
# messaging network most ties are returned, so the same census comes
# back mostly mutual. Reading the two side by side is the fastest way to
# see what the census is actually telling you.
#
# Direction is carried on the edge table as an attribute rather than as
# a fourth column, because the file format a reader brings has three
# columns and this is a property of the whole network rather than of any
# one tie.
mark_directed <- function(ed) {
  attr(ed, "directed") <- TRUE
  ed
}

# Who asks whom for advice in a mid sized department. Ties run from the
# person asking to the person asked, so the senior people accumulate
# incoming ties and return very few.
sample_advice_network <- function() {
  seniors <- c("Rosa", "Idris", "Meera")
  leads <- c("Tomas", "Yara", "Owen", "Bess")
  staff <- c("Kian", "Lucia", "Petra", "Sven", "Aditi", "Marco",
             "Freya", "Noor", "Emil", "Talia", "Jonas", "Rhea")

  set.seed(19)
  # Staff ask their lead, and about a third also ask a second lead,
  # which is what puts any structure in the picture at all.
  from <- character(0)
  to <- character(0)
  for (i in seq_along(staff)) {
    lead <- leads[[(i - 1) %% length(leads) + 1]]
    from <- c(from, staff[i])
    to <- c(to, lead)
    if (runif(1) < 0.35) {
      other <- sample(setdiff(leads, lead), 1)
      from <- c(from, staff[i])
      to <- c(to, other)
    }
    # A few go straight to a senior, skipping their lead.
    if (runif(1) < 0.25) {
      from <- c(from, staff[i])
      to <- c(to, sample(seniors, 1))
    }
  }
  # Leads ask seniors, and seniors ask each other, which is the only
  # place mutual ties appear.
  for (lead in leads) {
    from <- c(from, lead, lead)
    to <- c(to, seniors[[1]], sample(seniors[-1], 1))
  }
  from <- c(from, "Rosa", "Idris", "Meera")
  to <- c(to, "Idris", "Rosa", "Rosa")
  # A handful of staff ask each other sideways.
  sideways <- sample(staff, 8)
  from <- c(from, sideways[1:4])
  to <- c(to, sideways[5:8])

  mark_directed(tibble(from = from, to = to,
                       weight = rep(1, length(from))))
}

# Who messages whom in the same department. Most conversations go both
# ways, so this network is mutual where the advice network is
# asymmetric, on a cast of the same size.
sample_message_network <- function() {
  people <- c("Rosa", "Idris", "Meera", "Tomas", "Yara", "Owen", "Bess",
              "Kian", "Lucia", "Petra", "Sven", "Aditi", "Marco",
              "Freya", "Noor", "Emil", "Talia", "Jonas", "Rhea")
  set.seed(23)
  from <- character(0)
  to <- character(0)
  for (i in seq_along(people)) {
    partners <- sample(setdiff(people, people[i]),
                       sample(2:4, 1))
    for (partner in partners) {
      from <- c(from, people[i])
      to <- c(to, partner)
      # Four in five conversations are answered, which is what makes
      # the dyad census come back mostly mutual.
      if (runif(1) < 0.8) {
        from <- c(from, partner)
        to <- c(to, people[i])
      }
    }
  }
  mark_directed(tibble(from = from, to = to,
                       weight = rep(1, length(from))))
}

# What a reader can ask a local model to do with a set of findings.
#
# One button that always does the same thing is the wrong shape for
# this. A reader looking at a page of proportions wants one of three
# things, and which one depends on why they came: the results in plain
# words, the paragraph they would write in a paper, or the objection a
# reviewer is going to raise. Each is a different instruction, and none
# of them is a different set of numbers.
#
# Every mode is bound by the same rules about the numbers. The model
# rewords findings; it never computes, never adds a claim, and never
# sees the network.
model_modes <- function() {
  list(
    plain = list(
      label = "In plain words",
      task = paste(
        "Write what these findings say about this particular network,",
        "for someone who does not know the vocabulary. Lead with what",
        "was actually found here and what it would mean for the people",
        "in it. Name the measures in ordinary words rather than by",
        "their technical names. Three or four short paragraphs.")),
    methods = list(
      label = "As a methods paragraph",
      task = paste(
        "Write the paragraph a researcher would put in the methods and",
        "results section of a paper about this network. Say what was",
        "compared against what, report the results that were beyond",
        "chance and say plainly that the rest were not, and use the",
        "past tense. One or two paragraphs.")),
    caution = list(
      label = "What to be careful about",
      task = paste(
        "Write what a careful reviewer would say about these results.",
        "Work from the findings themselves: which results sit close to",
        "the edge, which rest on one person, which could not be",
        "computed, and which are being read as more than they are.",
        "End with the limits of the method itself: it compares one",
        "network against random ones, so it says nothing about cause",
        "and nothing about change over time. Three or four short",
        "paragraphs."))
  )
}

rewrite_with_local_model <- function(paragraphs, base_url, model,
                                     mode = "plain") {
  if (!requireNamespace("curl", quietly = TRUE)) {
    return(list(ok = FALSE,
                message = "The curl package is not installed, so the local model connection is unavailable."))
  }
  modes <- model_modes()
  task <- if (!is.null(modes[[mode]])) {
    modes[[mode]]$task
  } else {
    modes$plain$task
  }
  # The instructions are specific about shape as well as about content.
  # Asking only for a restatement produced one unbroken block opening
  # with a sentence announcing that a restatement follows, which is the
  # model talking about its work rather than doing it.
  prompt <- paste(
    "Below is a description of one network and what was found about it.",
    "Each finding already says what this network has, what random",
    "networks produced, and what the difference amounts to.",
    task,
    "Rules, all of them strict:",
    "1. Write about this network. Every paragraph has to say something",
    "   that is true of it in particular and would be false of a",
    "   different network. A sentence that would fit any network at all",
    "   is a sentence to cut.",
    "2. Do not list the measures one after another with their numbers.",
    "   That list is already on the reader's screen and repeating it is",
    "   the one thing this is not for. Group the findings that point",
    "   the same way and say what they add up to.",
    "3. Use at most four numbers in the whole piece, and only where a",
    "   number carries the point. Keep any you use exactly as given.",
    "4. Say plainly which findings were beyond chance and which were",
    "   not. A result inside the range chance produces is a real",
    "   answer, not a missing one, and most results here will be that.",
    "5. Add no claim that is not in the findings. Never say what caused",
    "   anything: this is one snapshot of recorded ties.",
    "6. Separate paragraphs with a blank line. Start with the first",
    "   sentence itself. Do not introduce it, do not describe what you",
    "   are about to do, and do not summarize what you did.",
    "", paste(paragraphs, collapse = "\n"), sep = "\n")
  body <- jsonlite::toJSON(list(model = model, prompt = prompt,
                                stream = FALSE), auto_unbox = TRUE)
  h <- curl::new_handle()
  curl::handle_setopt(h, post = TRUE, postfields = body,
                      timeout = 60, connecttimeout = 5)
  curl::handle_setheaders(h, "Content-Type" = "application/json")
  out <- try(curl::curl_fetch_memory(paste0(base_url, "/api/generate"), h),
             silent = TRUE)
  if (inherits(out, "try-error") || out$status_code != 200) {
    return(list(ok = FALSE,
                message = "No local model answered. Check that Ollama is running and the address is right, then try again."))
  }
  parsed <- try(jsonlite::fromJSON(rawToChar(out$content)), silent = TRUE)
  if (inherits(parsed, "try-error") || is.null(parsed$response)) {
    return(list(ok = FALSE,
                message = "The local model answered in a form this app could not read."))
  }
  # Models ignore the no preamble rule often enough that it is worth
  # removing one anyway. A first paragraph that announces a restatement
  # rather than being one ends in a colon and mentions the task, which
  # is a narrow enough shape to strip without touching real content.
  text <- trimws(parsed$response)
  first_break <- regexpr("\n\\s*\n", text)
  if (first_break > 0) {
    opening <- substr(text, 1, first_break - 1)
    announces <- grepl(":\\s*$", opening) &&
      grepl("restat|summar|plain|rewritt", opening, ignore.case = TRUE)
    if (announces) text <- trimws(substr(text, first_break, nchar(text)))
  }
  list(ok = TRUE, text = text)
}
