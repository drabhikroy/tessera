# tables.R
# The wrapper that gives a table somewhere to go.
#
# Copyright Abhik Roy. Released under the PolyForm Noncommercial
# License 1.0.0. See LICENSE.md.
#
# Every table on screen is short on purpose. A card holding sixteen
# triad classes at full height pushes the cards under it off the page,
# and a card holding fifty eight people turns the tab into a scrollbar.
# Keeping them short costs a reader who wants the whole thing, so each
# one carries a control that opens it at full size with a search box,
# sortable headings, paging, and a file.
#
# The heading, the control, and the table travel together, because a
# control that opens something has to sit where the thing it opens is.
# The behavior is in www/tables.js; this file is the markup contract
# between the two, and the attribute names below are the whole of it.

# A card whose body is held to one height, with a control in the heading
# that opens the whole of it over the page.
#
# The three cards on the Research tab hold a twelve row table, a menu,
# and a census. Left to size themselves they are three very different
# heights, and side by side that reads as a broken layout however the
# space underneath is handled. Holding them to one height makes the row
# read as a row, and the control in the heading is where the rest of
# each card goes.
clipped_card <- function(title, ..., open_label = "Open") {
  div(class = "research-card-inner", `data-table-block` = NA,
      `data-table-title` = title,
    div(class = "card-clip-head",
      tags$h3(class = "card-clip-title", title),
      tags$button(type = "button",
                  class = "btn btn-quiet card-clip-open",
                  `data-panel-open` = "",
                  `data-table-title` = title,
                  open_label)),
    div(class = "card-clip", ...))
}

# One table, with its heading and its control.
#
# `preview` is what shows on the card. It is deliberately smaller than
# the full table: the card is for recognizing what is there, and the
# full view is for reading it.
table_block <- function(title, ..., open_label = "Open table",
                        note = NULL, actions = NULL, name = NULL) {
  div(class = "table-block", `data-table-block` = NA,
      `data-table-title` = title,
    div(class = "table-block-head",
      tags$h4(class = "table-block-title", title),
      tags$button(type = "button", class = "btn btn-quiet table-block-open",
                  `data-table-open` = if (is.null(name)) "" else name,
                  `data-table-title` = title,
                  open_label)),
    if (is.null(note)) NULL else tags$p(class = "helper-note", note),
    div(class = "table-block-body", ...),
    if (is.null(actions)) NULL else div(class = "btn-cluster", actions))
}

# A table written as markup rather than through renderTable.
#
# renderTable is fine for a table of numbers and wrong for a table that
# wants a magnitude bar in a cell or a plain sentence in a column, so
# the two hand written tables in this app already built their own
# markup. This is that markup in one place, so a change to how a table
# looks is one change rather than four.
#
# `columns` is a list of character vectors, one per heading, all the
# same length. A list rather than a data frame because half the columns
# here are already formatted text and putting them through a data frame
# only invents column names nobody reads.
#
# `justify` is a character vector, one entry per column, holding "left" or
# "num". Numbers set right and share one tabular figure width; anything
# else sets left.
html_table <- function(headers, columns, justify = NULL,
                       class = "people-table", name = NULL) {
  stopifnot(length(headers) == length(columns))
  if (is.null(justify)) justify <- rep("left", length(headers))
  n_rows <- if (length(columns) == 0) 0L else length(columns[[1]])
  head_cells <- paste(vapply(seq_along(headers), function(i) {
    paste0("<th", if (identical(justify[i], "num")) " class=\"num-head\"" else "",
           ">", htmltools::htmlEscape(headers[i]), "</th>")
  }, ""), collapse = "")
  body <- paste(vapply(seq_len(n_rows), function(r) {
    cells <- paste(vapply(seq_along(headers), function(i) {
      value <- as.character(columns[[i]][r])
      if (is.na(value)) value <- ""
      paste0("<td", if (identical(justify[i], "num")) " class=\"num\"" else "",
             ">", htmltools::htmlEscape(value), "</td>")
    }, ""), collapse = "")
    paste0("<tr>", cells, "</tr>")
  }, ""), collapse = "")
  HTML(paste0('<table class="', class, '"',
              if (is.null(name)) "" else paste0(' data-table-name="', name, '"'),
              "><thead><tr>", head_cells, "</tr></thead><tbody>",
              body, "</tbody></table>"))
}

# The first few rows of a table, with a line saying how many were left
# behind. Without the line a reader has no way to tell a short table
# from a long one that was cut, which is the difference between a
# summary and a wrong answer.
preview_note <- function(shown, total, noun = "rows") {
  if (total <= shown) return(NULL)
  tags$p(class = "helper-note table-block-more",
         paste("Showing", shown, "of", total, noun,
               "here. Open the table for the rest."))
}
