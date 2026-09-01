/* tables.js
   A table that can be opened at full size, searched, sorted, paged, and
   taken away as a file.

   Every table in this app is short on screen on purpose: a card that
   holds sixteen triad classes at full height pushes everything under it
   off the page, and a card that holds fifty eight people pushes the rest
   of the tab into the scrollbar. The cost of keeping them short is that
   a reader who wants the whole thing has nowhere to go. This is that
   place.

   Written here rather than taken from a table library. Three reasons,
   in order of how much they mattered. The tables in this app are not all
   the same object: two of them are markup this app writes by hand with a
   magnitude bar inside a cell, and a library that owns its own rendering
   would either drop that or need it reimplemented as a formatter. The
   palette and the appearance modes are carried by the stylesheet, and a
   library ships its own stylesheet that would need overriding in every
   one of the ten states this app supports. And the whole of what is
   wanted is here in a few hundred lines, which is less than the
   configuration a library would need.

   The reader's table is never touched. The modal works on a copy, so
   sorting and filtering cannot leave the page underneath in a state the
   server did not put it in, and a redraw from Shiny cannot pull the
   ground out from under an open modal. */

(function () {
  "use strict";

  /* One modal at a time. Two open at once would be two copies of two
     tables competing for the same escape key, and there is no reading
     task that wants both. */
  var open = null;

  /* ---- Reading a table -------------------------------------------- */

  /* The text a cell sorts, searches, and exports by. Cells in this app
     can hold a magnitude bar beside their number, and the bar is built
     from empty elements, so the text content is the number alone. */
  function cellText(cell) {
    return (cell.textContent || "").replace(/\s+/g, " ").trim();
  }

  /* A cell's value as a number, or null when it is not one. Thousands
     separators, percent signs, and a leading currency mark are stripped
     first, because a column of shares is still a column of numbers and
     sorting it as text puts 9% above 10%. */
  function cellNumber(cell) {
    var text = cellText(cell).replace(/[,\s%$]/g, "");
    if (text === "" || text === "-" || text === "n/a") return null;
    var value = Number(text);
    return isFinite(value) ? value : null;
  }

  /* Whether a column is numeric. A column counts as numeric when most
     of what is in it parses as a number, so one "n/a" in a column of
     proportions does not turn the whole column into text. */
  function columnIsNumeric(rows, index) {
    var seen = 0, numeric = 0;
    rows.forEach(function (row) {
      var cell = row.cells[index];
      if (!cell) return;
      if (cellText(cell) === "") return;
      seen += 1;
      if (cellNumber(cell) !== null) numeric += 1;
    });
    return seen > 0 && numeric / seen >= 0.7;
  }

  /* The rows the table holds, as an array rather than the live
     collection. The live one changes underneath a sort, because moving
     a row in the document removes it from where it was. */
  function bodyRows(table) {
    var body = table.tBodies[0];
    return body ? Array.prototype.slice.call(body.rows) : [];
  }

  /* The last row of the heading, which is the one carrying the column
     names when a table has a grouped heading above it. */
  function headerCells(table) {
    var head = table.tHead;
    if (!head || head.rows.length === 0) return [];
    return Array.prototype.slice.call(head.rows[head.rows.length - 1].cells);
  }

  /* ---- The modal --------------------------------------------------- */

  /* Three lines of document work that appear thirty times below. */
  function element(tag, className, text) {
    var node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  }

  /* Closing puts the keyboard back where it came from. A reader who
     opened this with the keyboard and is left at the top of the
     document afterward has lost their place on the page. */
  function closeModal() {
    if (!open) return;
    document.removeEventListener("keydown", open.onKey, true);
    if (open.root.parentNode) open.root.parentNode.removeChild(open.root);
    if (open.opener && document.contains(open.opener)) open.opener.focus();
    open = null;
  }

  /* Turns the visible rows into comma separated text. What downloads is
     what is on screen: if a reader searched for one group and asked for
     the file, the file holds that group. A download that quietly ignores
     the filter above it is worse than no download, because the reader
     has no reason to check. */
  function toCsv(table, rows) {
    var quote = function (text) {
      return '"' + String(text).split('"').join('""') + '"';
    };
    var lines = [];
    var head = headerCells(table).map(function (cell) {
      return quote(cellText(cell));
    });
    if (head.length > 0) lines.push(head.join(","));
    rows.forEach(function (row) {
      lines.push(Array.prototype.slice.call(row.cells).map(function (cell) {
        return quote(cellText(cell));
      }).join(","));
    });
    return lines.join("\n");
  }

  /* A file made in the browser from text already on the page, so
     nothing is asked of the server and nothing leaves the machine. */
  function download(name, text) {
    var blob = new Blob([text], { type: "text/csv;charset=utf-8" });
    var url = URL.createObjectURL(blob);
    var link = document.createElement("a");
    link.href = url;
    link.download = name;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    setTimeout(function () { URL.revokeObjectURL(url); }, 1000);
  }

  /* A file name from the table's own heading, so several tables saved
     from one session do not overwrite each other in the folder. */
  function fileNameFor(title) {
    var slug = String(title || "table").toLowerCase()
      .replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
    return "tessera-" + (slug || "table") + ".csv";
  }

  /* The toolbar and behavior for one table: search, sortable headings,
     paging, a copy control, and a file. Returns the toolbar and the
     footer so the caller can place them around the table. */
  function enhanceTable(table, title) {
    table.classList.add("table-view-table");
    table.removeAttribute("id");

    var rows = bodyRows(table);
    var heads = headerCells(table);
    var numeric = heads.map(function (unused, index) {
      return columnIsNumeric(rows, index);
    });
    var state = { query: "", sort: -1, ascending: true, page: 0, size: 25 };
    var unique = String(Math.random()).slice(2, 8);

    var bar = element("div", "table-view-bar");

    var searchWrap = element("div", "table-view-search");
    var searchLabel = element("label", null, "Search");
    searchLabel.setAttribute("for", "tv-search-" + unique);
    var search = document.createElement("input");
    search.type = "search";
    search.id = "tv-search-" + unique;
    search.className = "table-view-input";
    search.placeholder = "Any word in any column";
    searchWrap.appendChild(searchLabel);
    searchWrap.appendChild(search);
    bar.appendChild(searchWrap);

    var sizeWrap = element("div", "table-view-size");
    var sizeLabel = element("label", null, "Rows");
    sizeLabel.setAttribute("for", "tv-size-" + unique);
    var size = document.createElement("select");
    size.id = "tv-size-" + unique;
    size.className = "table-view-input";
    [25, 50, 100, 0].forEach(function (n) {
      var option = document.createElement("option");
      option.value = String(n);
      option.textContent = n === 0 ? "All" : String(n);
      size.appendChild(option);
    });
    sizeWrap.appendChild(sizeLabel);
    sizeWrap.appendChild(size);
    bar.appendChild(sizeWrap);

    var actions = element("div", "table-view-actions");
    var csvButton = element("button", "btn", "Download (CSV)");
    csvButton.type = "button";
    var copyButton = element("button", "btn btn-quiet", "Copy");
    copyButton.type = "button";
    actions.appendChild(csvButton);
    actions.appendChild(copyButton);
    bar.appendChild(actions);

    var foot = element("div", "table-view-foot");
    var count = element("span", "table-view-count", "");
    var pager = element("div", "table-view-pager");
    var previous = element("button", "btn btn-quiet", "Previous");
    previous.type = "button";
    var next = element("button", "btn btn-quiet", "Next");
    next.type = "button";
    var position = element("span", "table-view-position", "");
    pager.appendChild(previous);
    pager.appendChild(position);
    pager.appendChild(next);
    foot.appendChild(count);
    foot.appendChild(pager);

    /* The search runs over the whole row rather than one column,
       because a reader looking for a name does not know which column
       holds it and should not have to. */
    function matching() {
      if (state.query === "") return rows;
      var needle = state.query.toLowerCase();
      return rows.filter(function (row) {
        return (row.textContent || "").toLowerCase().indexOf(needle) >= 0;
      });
    }

    function sorted(list) {
      if (state.sort < 0) return list;
      var index = state.sort;
      var direction = state.ascending ? 1 : -1;
      return list.slice().sort(function (a, b) {
        var ca = a.cells[index], cb = b.cells[index];
        if (!ca || !cb) return 0;
        if (numeric[index]) {
          var na = cellNumber(ca), nb = cellNumber(cb);
          /* A blank sorts to the bottom either way, so a column with
             gaps in it still reads from largest to smallest. */
          if (na === null && nb === null) return 0;
          if (na === null) return 1;
          if (nb === null) return -1;
          return (na - nb) * direction;
        }
        return cellText(ca).localeCompare(cellText(cb)) * direction;
      });
    }

    /* Filter, sort, page, and write the result into the table. One
       function for all three, since they compose and doing them apart
       would mean each having to know what the others did. */
    function draw() {
      var found = sorted(matching());
      var pageSize = state.size > 0 ? state.size : found.length;
      var pages = Math.max(1, Math.ceil(found.length / Math.max(1, pageSize)));
      if (state.page >= pages) state.page = pages - 1;
      if (state.page < 0) state.page = 0;
      var start = state.page * pageSize;
      var shown = found.slice(start, start + pageSize);

      var body = table.tBodies[0];
      if (body) {
        while (body.firstChild) body.removeChild(body.firstChild);
        shown.forEach(function (row) { body.appendChild(row); });
      }

      count.textContent = found.length === rows.length
        ? found.length + " rows"
        : found.length + " of " + rows.length + " rows";
      position.textContent = "Page " + (state.page + 1) + " of " + pages;
      previous.disabled = state.page === 0;
      next.disabled = state.page >= pages - 1;
      pager.style.display = pages > 1 ? "" : "none";

      heads.forEach(function (cell, index) {
        cell.setAttribute("aria-sort", index === state.sort
          ? (state.ascending ? "ascending" : "descending")
          : "none");
        cell.classList.toggle("sorted-up",
          index === state.sort && state.ascending);
        cell.classList.toggle("sorted-down",
          index === state.sort && !state.ascending);
      });
      return found;
    }

    /* Every heading is a control. It is reachable by keyboard and says
       which way it is sorting, because a sort mark that is only a
       character in the corner is not available to a screen reader. */
    heads.forEach(function (cell, index) {
      cell.classList.add("sortable");
      cell.setAttribute("tabindex", "0");
      cell.setAttribute("role", "columnheader");
      var activate = function () {
        if (state.sort === index) {
          state.ascending = !state.ascending;
        } else {
          state.sort = index;
          /* Numbers open largest first, names open A to Z. Both are
             what a reader who pressed that heading was after. */
          state.ascending = !numeric[index];
        }
        state.page = 0;
        draw();
      };
      cell.addEventListener("click", activate);
      cell.addEventListener("keydown", function (event) {
        if (event.key === "Enter" || event.key === " ") {
          event.preventDefault();
          activate();
        }
      });
    });

    search.addEventListener("input", function () {
      state.query = search.value.trim();
      state.page = 0;
      draw();
    });
    size.addEventListener("change", function () {
      state.size = Number(size.value);
      state.page = 0;
      draw();
    });
    previous.addEventListener("click", function () {
      state.page -= 1;
      draw();
    });
    next.addEventListener("click", function () {
      state.page += 1;
      draw();
    });
    csvButton.addEventListener("click", function () {
      download(fileNameFor(title), toCsv(table, sorted(matching())));
    });
    copyButton.addEventListener("click", function () {
      var text = toCsv(table, sorted(matching()));
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(function () {
          copyButton.textContent = "Copied";
        }, function () {});
      }
      setTimeout(function () { copyButton.textContent = "Copy"; }, 1600);
    });

    draw();
    return { bar: bar, foot: foot, focus: function () { search.focus(); } };
  }

  /* A copy of some part of the page, opened over it at full size.
     Working on a copy is what makes this safe: a redraw from the server
     cannot pull the ground out from under an open panel, and sorting a
     table here cannot leave the page underneath in an order the server
     did not put it in.

     Anything in the copy marked as a shortened stand in is dropped, and
     anything marked as the whole of it is shown, so a card that carries
     six rows of a table and the other ten out of sight opens as one
     table of sixteen. */
  function openPanel(source, title, opener) {
    closeModal();

    var content = source.cloneNode(true);
    content.removeAttribute("id");
    content.classList.remove("card-clip");
    content.classList.add("table-view-content");

    Array.prototype.slice.call(
      content.querySelectorAll("[data-panel-drop]")
    ).forEach(function (node) {
      if (node.parentNode) node.parentNode.removeChild(node);
    });
    Array.prototype.slice.call(
      content.querySelectorAll(".table-hidden")
    ).forEach(function (node) {
      node.classList.remove("table-hidden");
      node.removeAttribute("aria-hidden");
    });
    /* The controls that opened this panel have nothing to open from
       inside it. */
    Array.prototype.slice.call(
      content.querySelectorAll("[data-table-open], [data-panel-open]")
    ).forEach(function (node) {
      if (node.parentNode) node.parentNode.removeChild(node);
    });

    var root = element("div", "table-view");
    root.setAttribute("role", "dialog");
    root.setAttribute("aria-modal", "true");
    root.setAttribute("aria-label", title || "Details");

    var sheet = element("div", "table-view-sheet");
    var head = element("div", "table-view-head");
    head.appendChild(element("h2", null, title || "Details"));
    var closeButton = element("button", "btn btn-quiet table-view-close",
                              "Close");
    closeButton.type = "button";
    closeButton.addEventListener("click", closeModal);
    head.appendChild(closeButton);
    sheet.appendChild(head);

    var scroll = element("div", "table-view-scroll");
    scroll.appendChild(content);
    sheet.appendChild(scroll);
    root.appendChild(sheet);

    /* Every table in the copy gets its own toolbar, placed above it and
       its counter below it, so a panel holding two tables gives each of
       them a search box that searches that table. */
    var first = null;
    Array.prototype.slice.call(content.querySelectorAll("table"))
      .forEach(function (table) {
        var name = table.getAttribute("data-table-title") || title;
        var parts = enhanceTable(table, name);
        var wrap = element("div", "table-view-one");
        table.parentNode.insertBefore(wrap, table);
        wrap.appendChild(parts.bar);
        var box = element("div", "table-view-scroll-inner");
        wrap.appendChild(box);
        box.appendChild(table);
        wrap.appendChild(parts.foot);
        if (first === null) first = parts;
      });

    root.addEventListener("mousedown", function (event) {
      if (event.target === root) closeModal();
    });

    var onKey = function (event) {
      if (event.key === "Escape") {
        event.stopPropagation();
        closeModal();
        return;
      }
      /* A panel that lets the keyboard walk out of it behind the
         backdrop is a panel only for the mouse. */
      if (event.key !== "Tab") return;
      var focusable = sheet.querySelectorAll(
        "button:not([disabled]), input, select, [tabindex='0']");
      if (focusable.length === 0) return;
      var firstStop = focusable[0];
      var lastStop = focusable[focusable.length - 1];
      if (event.shiftKey && document.activeElement === firstStop) {
        event.preventDefault();
        lastStop.focus();
      } else if (!event.shiftKey && document.activeElement === lastStop) {
        event.preventDefault();
        firstStop.focus();
      }
    };
    document.addEventListener("keydown", onKey, true);

    document.body.appendChild(root);
    open = { root: root, onKey: onKey, opener: opener || null };
    if (first) {
      first.focus();
    } else {
      closeButton.focus();
    }
    return root;
  }

  /* One table, opened on its own. The panel opener does the work; this
     wraps the table so there is something to copy. */
  function openTable(table, title, opener) {
    var holder = document.createElement("div");
    holder.appendChild(table.cloneNode(true));
    return openPanel(holder, title, opener);
  }

  /* ---- Wiring ------------------------------------------------------ */

  /* The button sits beside the card heading and finds the table in its
     own block, so a card can hold two tables and each gets its own
     button without either of them knowing about the other. */
  function blockFor(button) {
    var block = button.closest ? button.closest("[data-table-block]") : null;
    if (block) return block;
    var node = button.parentNode;
    while (node && node.getAttribute &&
           !node.hasAttribute("data-table-block")) {
      node = node.parentNode;
    }
    return node && node.getAttribute ? node : null;
  }

  document.addEventListener("click", function (event) {
    var button = event.target;
    while (button && button !== document.body && !(button.getAttribute &&
           (button.hasAttribute("data-table-open") ||
            button.hasAttribute("data-panel-open")))) {
      button = button.parentNode;
    }
    if (!button || !button.getAttribute) return;
    var block = blockFor(button);
    if (!block) return;
    var title = button.getAttribute("data-table-title") ||
      block.getAttribute("data-table-title") || "Details";
    event.preventDefault();

    if (button.hasAttribute("data-panel-open")) {
      var target = button.getAttribute("data-panel-open");
      var panel = target
        ? block.querySelector("#" + target) || block.querySelector("." + target)
        : block.querySelector(".card-clip");
      if (panel) openPanel(panel, title, button);
      return;
    }
    var name = button.getAttribute("data-table-open");
    var table = name
      ? block.querySelector("table[data-table-name='" + name + "']")
      : block.querySelector("table");
    if (table) openTable(table, title, button);
  });

  /* The person chips in the reading panel. The name is on the control
     as an attribute rather than inside a line of script written around
     it, so a name from an uploaded file is data the whole way through
     and never becomes something the browser runs. One listener serves
     every chip, including chips that do not exist yet. */
  document.addEventListener("click", function (event) {
    var chip = event.target;
    while (chip && chip !== document.body &&
           !(chip.getAttribute && chip.hasAttribute("data-person"))) {
      chip = chip.parentNode;
    }
    if (!chip || !chip.getAttribute) return;
    if (!window.Shiny || !window.Shiny.setInputValue) return;
    event.preventDefault();
    window.Shiny.setInputValue("chip_person", chip.getAttribute("data-person"),
                               { priority: "event" });
  });

  /* The model cards on the setup screen, on the same footing as the
     chips above: the identifier is an attribute and this reads it. */
  document.addEventListener("click", function (event) {
    var card = event.target;
    while (card && card !== document.body &&
           !(card.getAttribute && card.hasAttribute("data-model"))) {
      card = card.parentNode;
    }
    if (!card || !card.getAttribute) return;
    if (!window.Shiny || !window.Shiny.setInputValue) return;
    event.preventDefault();
    window.Shiny.setInputValue("pull_choice", card.getAttribute("data-model"),
                               { priority: "event" });
  });

  /* ---- Which cards actually have more to show ----------------------

     A card held to one height does not always have more in it than
     fits. The community card holds a menu, two numbers, and a sentence,
     and it never fills the space, so a control offering to open it
     promises something that is not there and a fade at the foot hints
     at content that does not exist.

     Both are therefore driven by measurement rather than by markup: a
     card announces that it is cut off only when it is. The check runs
     on load, whenever Shiny redraws a value, and whenever a card
     changes size, since all three change the answer. */

  function measureClip(clip) {
    var block = clip.parentNode;
    if (!block || !block.classList) return;
    /* A couple of units of slack. Sub pixel rounding makes a card that
       fits exactly report one pixel of overflow, which would put a
       control on every card on the row. */
    var clipped = clip.scrollHeight > clip.clientHeight + 4;
    block.classList.toggle("is-clipped", clipped);
  }

  function measureAllClips() {
    Array.prototype.slice.call(document.querySelectorAll(".card-clip"))
      .forEach(measureClip);
  }

  var clipWatcher = null;
  function watchClips() {
    measureAllClips();
    if (typeof ResizeObserver !== "function") return;
    if (clipWatcher === null) {
      clipWatcher = new ResizeObserver(function (entries) {
        entries.forEach(function (entry) { measureClip(entry.target); });
      });
    }
    clipWatcher.disconnect();
    Array.prototype.slice.call(document.querySelectorAll(".card-clip"))
      .forEach(function (clip) { clipWatcher.observe(clip); });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", watchClips);
  } else {
    watchClips();
  }
  if (window.jQuery) {
    /* Shiny replaces the whole card when a value redraws, so the
       observer has to be pointed at the new elements rather than the
       ones it was holding. */
    window.jQuery(document).on("shiny:value shiny:visualchange", function () {
      window.setTimeout(watchClips, 0);
    });
  }

  window.TesseraTables = {
    measureClips: measureAllClips,
    open: openTable,
    openPanel: openPanel,
    close: closeModal,
    toCsv: toCsv,
    cellNumber: cellNumber,
    columnIsNumeric: columnIsNumeric
  };
}());
