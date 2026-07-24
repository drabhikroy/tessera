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
rewrite_with_local_model <- function(paragraphs, base_url, model) {
  if (!requireNamespace("curl", quietly = TRUE)) {
    return(list(ok = FALSE,
                message = "The curl package is not installed, so the local model connection is unavailable."))
  }
  prompt <- paste(
    "Restate the following network summary in plain, calm English for a",
    "general business reader. Keep every number exactly as given. Do not",
    "add claims that are not in the text. Keep the hedged tone.",
    "", paste(paragraphs, collapse = "\n\n"), sep = "\n")
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
  list(ok = TRUE, text = parsed$response)
}
