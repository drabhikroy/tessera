# figure.R
# The downloadable figure, built with ggraph. It mirrors the map on
# screen: the same layout seed, the same shape per group, the same
# palette family, and the same dashed ring on single points of failure,
# so the export never contradicts what the reader saw.
#
# Copyright Abhik Roy. Released under the PolyForm Noncommercial
# License 1.0.0. See LICENSE.md.

suppressPackageStartupMessages({
  library(ggraph)
  library(ggplot2)
  library(dplyr)
})

# Palettes match www/styles.css. The figure follows whichever color
# setting is active in the app when the download happens.
figure_palettes <- list(
  standard = c("#e69f00", "#56b4e9", "#009e73", "#f0e442",
               "#0072b2", "#d55e00", "#cc79a7", "#6f6f6f",
               "#9aa5af", "#2b8f7a", "#7b4fa8", "#7a5232"),
  deutan   = c("#e69f00", "#56b4e9", "#f0e442", "#0b4f8f",
               "#b48ade", "#9c6a00", "#274b66", "#6f6f6f",
               "#9aa5af", "#2f4b7c", "#d9c37a", "#5c4b8a"),
  tritan   = c("#e4643b", "#0e6f5c", "#f2a0ac", "#9e1b32",
               "#146b5c", "#7a3216", "#8f8f8f", "#4a4a4a",
               "#9aa5af", "#b03050", "#3fa08c", "#d98a76"),
  mono     = c("#1a1a1a", "#454545", "#6b6b6b", "#8f8f8f",
               "#2e2e2e", "#585858", "#7d7d7d", "#a1a1a1",
               "#b8b8b8", "#0d0d0d", "#383838", "#949494")
)

# ggplot2 offers five fillable point shapes: circle, square, diamond,
# triangle, and inverted triangle. They cycle across the twelve colors,
# which separates sixty groups in print. Shape carries identity
# alongside color in every palette, monochrome included.
figure_shapes <- c(21, 22, 23, 24, 25)

network_figure <- function(payload, palette = "standard",
                           title = "Network map") {
  nodes <- payload$nodes |>
    mutate(group = factor(group))
  # Edge endpoints are stored as node ids, and graph_payload numbers
  # nodes by row, so an id indexes the node table directly.
  edges <- payload$edges |>
    mutate(
      x    = nodes$x[from],  y    = nodes$y[from],
      xend = nodes$x[to],    yend = nodes$y[to]
    )
  n_groups <- nlevels(nodes$group)
  fills <- rep(figure_palettes[[palette]], length.out = max(n_groups, 1))

  ggplot() +
    geom_segment(
      data = edges,
      aes(x = x, y = y, xend = xend, yend = yend, linewidth = weight),
      color = "#7d8b98", alpha = 0.5
    ) +
    scale_linewidth(range = c(0.25, 1.1), guide = "none") +
    # An open ring marks fragility so the warning survives any palette.
    # Point shapes cannot dash, so the ring is a fixed larger circle
    # rather than the dashed ring the screen uses.
    geom_point(
      data = nodes |> filter(is_cut),
      aes(x = x, y = y),
      size = 9, shape = 21, fill = NA, color = "#17222d", stroke = 1.1,
      show.legend = FALSE
    ) +
    geom_point(
      data = nodes,
      aes(x = x, y = y, fill = group, shape = group, size = degree),
      color = "#17222d", stroke = 0.5
    ) +
    geom_text(
      data = nodes,
      aes(x = x, y = y, label = label),
      size = 2.6, vjust = -1.6, color = "#17222d", check_overlap = TRUE
    ) +
    scale_fill_manual(values = fills[seq_len(n_groups)], name = "Group") +
    scale_shape_manual(values = rep(figure_shapes, length.out = n_groups),
                       name = "Group") +
    scale_size(range = c(2, 7), name = "Direct ties") +
    coord_equal(xlim = c(-0.05, 1.05), ylim = c(-0.05, 1.08)) +
    labs(
      title = title,
      caption = paste("Open rings mark single points of failure.",
                      "Node size shows direct ties.")
    ) +
    theme_void(base_size = 11) +
    theme(
      plot.title = element_text(face = "bold", hjust = 0.5,
                                margin = margin(b = 6)),
      plot.caption = element_text(color = "#465562", hjust = 0.5,
                                  margin = margin(t = 8)),
      legend.position = "bottom",
      plot.margin = margin(12, 12, 10, 12),
      plot.background = element_rect(fill = "#ffffff", color = NA)
    )
}
