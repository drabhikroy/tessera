# guide.R
# The walkthrough and the local model guide. Both are content, kept out
# of app.R so the interface file stays about wiring. Every vignette is
# an inline SVG on a fixed stage that inherits the theme tokens, so the
# pictures match the app in every mode and palette.
#
# Copyright Abhik Roy. Released under the PolyForm Noncommercial
# License 1.0.0. See LICENSE.md.

# A small stage helper: consistent size, consistent breathing room.
stage <- function(inner) {
  sprintf('<svg class="vignette" viewBox="0 0 320 170" role="img" aria-hidden="true">%s</svg>', inner)
}

dot <- function(x, y, r, cls) {
  sprintf('<circle cx="%s" cy="%s" r="%s" class="v-%s"/>', x, y, r, cls)
}
sq <- function(x, y, s, cls) {
  sprintf('<rect x="%s" y="%s" width="%s" height="%s" class="v-%s"/>',
          x - s / 2, y - s / 2, s, s, cls)
}
tie <- function(x1, y1, x2, y2, w = 2, cls = "tie", delay = 0) {
  mx <- (x1 + x2) / 2; my <- (y1 + y2) / 2
  d <- sprintf("M%s,%s Q%s,%s %s,%s", x1, y1,
               mx - (y2 - y1) * 0.15, my + (x2 - x1) * 0.15, x2, y2)
  # The tie draws itself in by animating a large dash offset down to
  # zero. The path length is approximate but always larger than the
  # true length, so the line is fully hidden at the start.
  len <- 500
  sprintf(paste0('<path d="%s" class="v-%s" stroke-width="%s" ',
                 'fill="none" stroke-dasharray="%s" ',
                 'stroke-dashoffset="%s"><animate ',
                 'attributeName="stroke-dashoffset" from="%s" to="0" ',
                 'begin="%ss" dur="0.5s" fill="freeze"/></path>'),
          d, cls, w, len, len, len, delay)
}

# A node that fades and grows into place after its ties arrive.
adot <- function(x, y, r, cls, delay = 0) {
  sprintf(paste0('<circle cx="%s" cy="%s" r="%s" class="v-%s" ',
                 'opacity="0"><animate attributeName="opacity" ',
                 'from="0" to="1" begin="%ss" dur="0.3s" fill="freeze"/>',
                 '<animate attributeName="r" from="%s" to="%s" ',
                 'begin="%ss" dur="0.3s" fill="freeze"/></circle>'),
          x, y, r, cls, delay, r * 0.3, r, delay)
}
asq <- function(x, y, s, cls, delay = 0) {
  sprintf(paste0('<rect x="%s" y="%s" width="%s" height="%s" ',
                 'class="v-%s" opacity="0"><animate ',
                 'attributeName="opacity" from="0" to="1" begin="%ss" ',
                 'dur="0.3s" fill="freeze"/></rect>'),
          x - s / 2, y - s / 2, s, s, cls, delay)
}

# The seven slides of the first run walkthrough. Each one makes a single
# point, in the order a new person meets the app: what it is, what to
# feed it, how to read it, then the two deeper readings and the privacy
# ground rules.
tour_slides <- function() {
  list(
    list(
      title = "Welcome to Tessera",
      text  = paste("Tessera turns a list of who works with whom into a",
                    "map, then explains the map in plain English. This",
                    "short tour shows the four things worth knowing."),
      art   = stage(paste0(
        tie(70, 90, 140, 55, 2, "tie", 0.0),
        tie(140, 55, 215, 85, 2, "tie", 0.15),
        tie(140, 55, 150, 125, 2, "tie", 0.3),
        tie(70, 90, 150, 125, 2, "tie", 0.45),
        tie(215, 85, 250, 120, 2, "tie", 0.6),
        tie(215, 85, 262, 52, 2, "tie", 0.6),
        adot(70, 90, 12, "n1", 0.5), adot(140, 55, 16, "n2", 0.65),
        adot(150, 125, 10, "n1", 0.8), adot(215, 85, 13, "n3", 0.8),
        adot(250, 120, 9, "n3", 1.0), adot(262, 52, 9, "n3", 1.0)
      ))
    ),
    list(
      title = "Bring a simple list of ties",
      text  = paste("A spreadsheet with two or three columns is enough:",
                    "who the tie is from, who it is to, and, if you have",
                    "it, how strong. Save it as a CSV and drop it in, or",
                    "start with a built in sample."),
      art   = stage(paste0(
        '<rect x="34" y="30" width="110" height="110" rx="8" class="v-card"/>',
        '<text x="52" y="56" class="v-code">from, to</text>',
        '<text x="52" y="76" class="v-code">Maya, Tom</text>',
        '<text x="52" y="96" class="v-code">Tom, Ines</text>',
        '<text x="52" y="116" class="v-code">Ines, Maya</text>',
        # The arrow slides right, carrying the eye from list to map.
        '<path d="M158,85 H210 M198,73 L212,85 L198,97" class="v-arrow" ',
        'fill="none"><animate attributeName="opacity" values="0.2;1;0.2" ',
        'dur="1.8s" repeatCount="indefinite"/></path>',
        tie(238, 60, 276, 95, 2, "tie", 0.4),
        tie(276, 95, 240, 120, 2, "tie", 0.55),
        tie(240, 120, 238, 60, 2, "tie", 0.7),
        adot(238, 60, 11, "n2", 0.9), adot(276, 95, 11, "n1", 1.0),
        adot(240, 120, 11, "n3", 1.1)
      ))
    ),
    list(
      title = "Shapes and colors mark the groups",
      text  = paste("Groups come from the tie pattern alone. Each group",
                    "gets a color and a shape, so the map stays readable",
                    "for every kind of color vision, including none."),
      art   = stage(paste0(
        tie(70, 60, 115, 95, 2, "tie", 0.0),
        tie(115, 95, 68, 122, 2, "tie", 0.15),
        tie(68, 122, 70, 60, 2, "tie", 0.3),
        tie(210, 58, 255, 90, 2, "tie", 0.15),
        tie(255, 90, 212, 122, 2, "tie", 0.3),
        tie(212, 122, 210, 58, 2, "tie", 0.45),
        tie(115, 95, 210, 58, 2, "tie-far", 0.6),
        adot(70, 60, 12, "n1", 0.5), adot(115, 95, 12, "n1", 0.6),
        adot(68, 122, 12, "n1", 0.7),
        asq(210, 58, 20, "n2", 0.7), asq(255, 90, 20, "n2", 0.8),
        asq(212, 122, 20, "n2", 0.9)
      ))
    ),
    list(
      title = "Size people by what matters",
      text  = paste("Node size follows a measure you choose: direct",
                    "ties, positions between groups, quick reach, or a",
                    "well connected circle. Switch measures and watch",
                    "who grows."),
      art   = stage(paste0(
        tie(80, 85, 160, 85, 2, "tie", 0.0),
        tie(160, 85, 240, 85, 2, "tie", 0.1),
        tie(160, 85, 120, 135, 2, "tie", 0.2),
        tie(160, 85, 200, 135, 2, "tie", 0.3),
        adot(80, 85, 9, "n1", 0.4), adot(240, 85, 9, "n1", 0.5),
        adot(120, 135, 7, "n3", 0.6), adot(200, 135, 7, "n3", 0.6),
        # The central hub pulses between small and large to show the
        # effect of changing the sizing measure.
        '<circle cx="160" cy="85" r="12" class="v-n2" opacity="0">',
        '<animate attributeName="opacity" from="0" to="1" begin="0.5s" ',
        'dur="0.3s" fill="freeze"/>',
        '<animate attributeName="r" values="12;22;12" begin="1s" ',
        'dur="2.4s" repeatCount="indefinite"/></circle>'
      ))
    ),
    list(
      title = "Click a person for the spotlight",
      text  = paste("Clicking a person, or pressing Tab and Enter, dims",
                    "everything past their reach and rewrites the",
                    "reading panel for them. Click open space to step",
                    "back out."),
      art   = stage(paste0(
        tie(90, 60, 160, 85, 2, "tie-dim", 0.0),
        tie(230, 60, 160, 85, 2, "tie", 0.1),
        tie(160, 85, 160, 135, 2, "tie", 0.2),
        tie(90, 130, 160, 135, 2, "tie-dim", 0.3),
        adot(90, 60, 10, "dim", 0.4), adot(90, 130, 10, "dim", 0.4),
        adot(230, 60, 12, "n2", 0.5), adot(160, 135, 11, "n1", 0.6),
        adot(160, 85, 15, "lit", 0.6),
        # The spotlight halo pulses outward from the chosen person.
        '<circle cx="160" cy="85" r="18" class="v-halo" opacity="0">',
        '<animate attributeName="r" values="18;30;18" begin="1s" ',
        'dur="2.2s" repeatCount="indefinite"/>',
        '<animate attributeName="opacity" values="0;0.7;0" begin="1s" ',
        'dur="2.2s" repeatCount="indefinite"/></circle>'
      ))
    ),
    list(
      title = "Watch for the weak joints",
      text  = paste("A dashed ring marks a single point of failure:",
                    "someone whose absence would split the network into",
                    "pieces. The reading panel names them and says why",
                    "the position deserves a closer look."),
      art   = stage(paste0(
        tie(66, 70, 120, 92, 2, "tie", 0.0),
        tie(66, 118, 120, 92, 2, "tie", 0.15),
        tie(66, 70, 66, 118, 2, "tie", 0.3),
        tie(120, 92, 190, 92, 2.5, "tie", 0.45),
        tie(190, 92, 250, 66, 2, "tie", 0.6),
        tie(190, 92, 252, 122, 2, "tie", 0.7),
        tie(250, 66, 252, 122, 2, "tie", 0.8),
        adot(66, 70, 11, "n1", 0.5), adot(66, 118, 11, "n1", 0.6),
        adot(120, 92, 11, "n1", 0.7),
        asq(250, 66, 18, "n2", 0.9), asq(252, 122, 18, "n2", 1.0),
        adot(190, 92, 12, "n3", 0.8),
        # The fragility ring breathes so the single joint draws the eye.
        '<circle cx="190" cy="92" r="20" class="v-ring" opacity="0">',
        '<animate attributeName="opacity" from="0" to="1" begin="1.1s" ',
        'dur="0.4s" fill="freeze"/>',
        '<animate attributeName="r" values="20;24;20" begin="1.5s" ',
        'dur="2s" repeatCount="indefinite"/></circle>'
      ))
    ),
    list(
      title = "Yours alone",
      text  = paste("Everything runs on this machine. No account, no",
                    "server, nothing sent anywhere. If you connect a",
                    "local language model later, that runs here too.",
                    "The Local models guide in the header explains how."),
      art   = stage(paste0(
        '<path d="M92,72 L160,34 L228,72 V138 H92 Z" class="v-house" ',
        'stroke-dasharray="360" stroke-dashoffset="360"><animate ',
        'attributeName="stroke-dashoffset" from="360" to="0" begin="0s" ',
        'dur="1s" fill="freeze"/></path>',
        tie(126, 96, 160, 80, 2, "tie", 0.9),
        tie(160, 80, 194, 100, 2, "tie", 1.0),
        tie(126, 96, 160, 120, 2, "tie", 1.1),
        tie(160, 120, 194, 100, 2, "tie", 1.2),
        adot(126, 96, 9, "n1", 1.3), adot(160, 80, 11, "n2", 1.4),
        adot(194, 100, 9, "n3", 1.5), adot(160, 120, 8, "n1", 1.6)
      ))
    )
  )
}

# The local model guide. Written for someone who has never heard of a
# local model. Structure: what it is, what stays private, how to set it
# up, and an honest comparison of four models worth considering.
model_options <- function() {
  list(
    list(
      name = "Llama 3.2 (3B)", pull = "ollama pull llama3.2",
      download = "About a 2 GB download",
      memory = "Comfortable on 8 GB of memory",
      speed = "Fast, answers in a few seconds",
      good = "The best first pick. Small, quick, and fully able to reword a summary without changing the numbers.",
      tradeoff = "Prose is plain. On long summaries it can flatten wording rather than improve it."
    ),
    list(
      name = "Gemma 3 (4B)", pull = "ollama pull gemma3",
      download = "About a 3 GB download",
      memory = "Comfortable on 8 GB of memory",
      speed = "Fast",
      good = "A newer small model with noticeably natural wording for its size.",
      tradeoff = "Slightly larger download than Llama 3.2 for a similar job."
    ),
    list(
      name = "Qwen 2.5 (7B)", pull = "ollama pull qwen2.5",
      download = "About a 4.5 GB download",
      memory = "Happiest with 16 GB of memory",
      speed = "Moderate",
      good = "Strong with numbers and careful phrasing, which suits a report that must keep every figure intact.",
      tradeoff = "Wording can read stiff. Slower on machines with 8 GB."
    ),
    list(
      name = "Llama 3.1 (8B)", pull = "ollama pull llama3.1",
      download = "About a 4.7 GB download",
      memory = "Happiest with 16 GB of memory",
      speed = "Moderate",
      good = "The best prose of the four. Summaries come back reading like a person wrote them.",
      tradeoff = "The largest download here, and the slowest on modest machines."
    )
  )
}
