/* graph.js
   Renders the network map as plain SVG. No chart library sits underneath:
   every element is built by hand so the accessibility choices hold in all
   theme and palette combinations. Panning and zooming move the viewBox
   rather than the elements, which keeps coordinates stable for hit
   testing and keeps the code free of transform bookkeeping. */

(function () {
  "use strict";

  var state = {
    data: null,          /* nodes, edges, meta from the server */
    sizeBy: "degree",
    sizeMax: 0,          /* largest value of the chosen measure */
    labelMode: "key",    /* key, all, none */
    depth: 1,            /* spotlight reach in steps */
    selected: null,      /* node id or null */
    groupFocus: null,    /* group number or null */
    reach: {},           /* ids within depth steps of the selection */
    neighbors: {},       /* adjacency list, built once per dataset */
    index: {},           /* id to node lookup, built with the adjacency */
    view: null,          /* current viewBox as an x y w h record */
    svg: null,
    layerEdges: null,
    layerNodes: null,
    tooltip: null,
    sim: null,           /* the live force layout, while one is running */
    simFrame: null,      /* the pending animation frame, or null */
    simCap: null,        /* largest network live layout is offered for */
    home: null,          /* the coordinates the server sent, for Settle */
    held: {},            /* nodes a reader has pinned in place, by id */
    spread: 1            /* how far apart the live layout holds people */
  };

  var WORLD = 1000;      /* layout coordinates scale to this square */
  var PAD = 70;

  /* Read once at load. A person who changes this system setting mid
     session gets the new behavior on the next render. */
  var reducedMotion = window.matchMedia &&
    window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  /* Wire format guard. The server sends rows. If some later change
     sends columns instead, the renderer reshapes them rather than
     going blank, which is the failure that is hardest to notice. */
  function normalize(table) {
    if (Array.isArray(table)) return table;
    if (table && typeof table === "object") {
      var keys = Object.keys(table);
      if (keys.length === 0) return [];
      var first = table[keys[0]];
      if (!Array.isArray(first)) return [table];
      return first.map(function (unused, i) {
        var row = {};
        keys.forEach(function (k) { row[k] = table[k][i]; });
        return row;
      });
    }
    return [];
  }

  /* Glyph system. A group appears as one of twelve base shapes, in one
     of three fill variants, in one of twelve colors. Shape and variant
     alone give thirty six combinations that survive the monochrome
     palette, and color multiplies that further. Nothing depends on
     color by itself. */
  var N_SHAPES = 12, N_VARIANTS = 3, N_COLORS = 12;

  function glyphFor(group) {
    var i = Math.max(0, group - 1);
    return {
      shape:   i % N_SHAPES,
      variant: Math.floor(i / N_SHAPES) % N_VARIANTS,
      color:   (i % N_COLORS) + 1
    };
  }

  /* All coordinates are absolute around the given center. Returning
     null means a plain circle, which uses its own element. */
  function shapePath(shape, r, cx, cy) {
    var k = Math.max(r, 4);
    switch (shape) {
      case 0: return null;                       /* circle */
      case 1: return regular(4, k * 1.16, cx, cy, Math.PI / 4);  /* square */
      case 2: return regular(4, k * 1.28, cx, cy, 0);            /* diamond */
      case 3: return regular(3, k * 1.3, cx, cy, 0);             /* triangle */
      case 4: return regular(3, k * 1.3, cx, cy, Math.PI);       /* inverted */
      case 5: return regular(6, k * 1.2, cx, cy, 0);             /* hexagon */
      case 6: return regular(5, k * 1.22, cx, cy, 0);            /* pentagon */
      case 7: return star(k, 5, 0.62, cx, cy);                   /* star */
      case 8: return cross(k, 0.36, cx, cy, 0);                  /* plus */
      case 9: return regular(8, k * 1.16, cx, cy, Math.PI / 8);  /* octagon */
      case 10: return cross(k, 0.36, cx, cy, Math.PI / 4);       /* saltire */
      case 11: return bowtie(k, cx, cy);                         /* bowtie */
      default: return null;
    }
  }

  /* A regular polygon with the first point at the top, rotated by the
     given offset. Every polygon shape above is one call to this. */
  function regular(sides, radius, cx, cy, rot) {
    var pts = [];
    for (var i = 0; i < sides; i++) {
      var a = (Math.PI * 2 * i) / sides - Math.PI / 2 + rot;
      pts.push([cx + Math.cos(a) * radius, cy + Math.sin(a) * radius]);
    }
    return toPath(pts);
  }

  function star(k, points, innerRatio, cx, cy) {
    var pts = [];
    for (var i = 0; i < points * 2; i++) {
      var rr = i % 2 === 0 ? k * 1.42 : k * 1.42 * innerRatio;
      var a = (Math.PI * i) / points - Math.PI / 2;
      pts.push([cx + Math.cos(a) * rr, cy + Math.sin(a) * rr]);
    }
    return toPath(pts);
  }

  /* A thick plus, rotated by the offset to make a saltire. Built from
     twelve points so it fills like any other closed shape. */
  function cross(k, thick, cx, cy, rot) {
    var o = k * 1.3, w = k * thick * 1.9;
    var raw = [[-w, -o], [w, -o], [w, -w], [o, -w], [o, w], [w, w],
               [w, o], [-w, o], [-w, w], [-o, w], [-o, -w], [-w, -w]];
    var cos = Math.cos(rot), sin = Math.sin(rot);
    return toPath(raw.map(function (p) {
      return [cx + p[0] * cos - p[1] * sin, cy + p[0] * sin + p[1] * cos];
    }));
  }

  function bowtie(k, cx, cy) {
    var w = k * 1.3, h = k * 1.1;
    return toPath([[cx - w, cy - h], [cx + w, cy + h], [cx + w, cy - h],
                   [cx - w, cy + h]]);
  }

  function toPath(pts) {
    return "M" + pts.map(function (p) {
      return p[0].toFixed(1) + "," + p[1].toFixed(1);
    }).join("L") + "Z";
  }

  /* Node radius maps the chosen measure onto a bounded range. A square
     root keeps big values from swallowing the map. */
  /* Square root scaling, because a reader compares node areas rather
     than radii, and a linear radius exaggerates the busiest person by
     roughly the square of their lead. */
  function refreshScale() {
    var max = 0;
    state.data.nodes.forEach(function (n) {
      if (n[state.sizeBy] > max) max = n[state.sizeBy];
    });
    state.sizeMax = max;
  }

  function radiusFor(node) {
    if (!state.sizeMax) return 9;
    return 7 + 13 * Math.sqrt(node[state.sizeBy] / state.sizeMax);
  }

  /* Positions are stored on the node in world units when first read,
     then reused. Dragging and the live layout both edit these
     directly, so an arrangement made by hand lasts until the next
     dataset loads. */
  function px(node) {
    if (node._x === undefined) node._x = PAD + node.x * (WORLD - 2 * PAD);
    return node._x;
  }
  function py(node) {
    if (node._y === undefined) node._y = PAD + node.y * (WORLD - 2 * PAD);
    return node._y;
  }

  /* One place writes the viewBox, so pan, zoom, fit, and the full
     screen switch cannot disagree about where the view is. */
  function setViewBox() {
    var v = state.view;
    state.svg.setAttribute("viewBox",
      v.x + " " + v.y + " " + v.w + " " + v.h);
  }

  /* Adjacency is built once per dataset and reused by the spotlight,
     so a depth two reach costs two lookups rather than an edge scan. */
  function nodeById(id) {
    return state.index[id] || null;
  }

  function buildAdjacency() {
    state.neighbors = {};
    /* An id to node map so drag redraws and edge lookups are constant
       time rather than a scan of every person on each pointer move. */
    state.index = {};
    state.data.nodes.forEach(function (n) { state.index[n.id] = n; });
    state.data.nodes.forEach(function (n) { state.neighbors[n.id] = []; });
    state.data.edges.forEach(function (e) {
      state.neighbors[e.from].push(e.to);
      state.neighbors[e.to].push(e.from);
    });
  }

  /* Breadth first out from one person to the requested depth. Depth is
     one or two in practice: past two steps almost everyone in a
     connected network is included and the spotlight stops saying
     anything. */
  function computeReach(id, depth) {
    var seen = {};
    seen[id] = true;
    var frontier = [id];
    for (var step = 0; step < depth; step++) {
      var next = [];
      frontier.forEach(function (a) {
        (state.neighbors[a] || []).forEach(function (b) {
          if (!seen[b]) { seen[b] = true; next.push(b); }
        });
      });
      frontier = next;
    }
    return seen;
  }

  /* Selection dims everything past the chosen reach. The server gets
     the id and answers with the matching reading panel. */
  function select(id, quiet) {
    state.selected = id;
    state.groupFocus = null;
    state.reach = id === null ? {} : computeReach(id, state.depth);
    applyDimming();
    if (window.Shiny && !quiet) {
      Shiny.setInputValue("selected_node", id, { priority: "event" });
    }
  }

  /* Group focus is the legend acting as a filter: one group stays lit
     so its footprint on the map reads at a glance. */
  /* Passing the group already in focus turns the filter off, so the
     same legend chip both lights a group and releases it. */
  function focusGroup(group) {
    state.selected = null;
    state.groupFocus = group;
    state.reach = {};
    applyDimming();
    if (window.Shiny) {
      Shiny.setInputValue("selected_node", null);
    }
  }

  function nodeVisibleInFocus(node) {
    if (state.selected !== null) return !!state.reach[node.id];
    if (state.groupFocus !== null) return node.group === state.groupFocus;
    return true;
  }

  /* Dimming is a class on each node and tie rather than a redraw. The
     positions must not move when the spotlight changes, or the reader
     loses the map they had just learned. */
  function clearRoute() {
    state.route = null;
    if (!state.svg) return;
    state.svg.classList.remove("routing");
    state.svg.querySelectorAll(".on-route").forEach(function (el) {
      el.classList.remove("on-route");
    });
    updateLabels();
  }

  function applyDimming() {
    var focusOn = state.selected !== null || state.groupFocus !== null;
    var byId = {};
    state.data.nodes.forEach(function (n) { byId[n.id] = n; });
    state.svg.classList.toggle("spotlight", focusOn);
    state.layerNodes.querySelectorAll(".node").forEach(function (el) {
      var node = byId[Number(el.getAttribute("data-id"))];
      el.classList.toggle("dim", focusOn && !nodeVisibleInFocus(node));
      el.classList.toggle("chosen", node.id === state.selected);
    });
    state.layerEdges.querySelectorAll("path").forEach(function (el) {
      var a = byId[Number(el.getAttribute("data-from"))];
      var b = byId[Number(el.getAttribute("data-to"))];
      var keep;
      if (state.selected !== null) {
        keep = a.id === state.selected || b.id === state.selected;
      } else if (state.groupFocus !== null) {
        keep = a.group === state.groupFocus && b.group === state.groupFocus;
      } else {
        keep = true;
      }
      el.classList.toggle("dim", focusOn && !keep);
    });
    updateLabels();
  }

  /* Which labels show depends on the mode and the moment: key people
     by default, everyone on request, and always the spotlight party. */
  function labelWanted(node, keyIds) {
    if (state.selected !== null) return !!state.reach[node.id];
    if (state.groupFocus !== null) return node.group === state.groupFocus;
    if (state.labelMode === "all") return true;
    if (state.labelMode === "none") return false;
    return !!keyIds[node.id];
  }

  /* The key people are the highest scorers on the measure currently
     sizing the map, so the names on screen always explain the sizes on
     screen. */
  function routeNames() {
    var on = {};
    if (state.route && state.route.ids) {
      state.route.ids.forEach(function (id) { on[id] = true; });
    }
    return on;
  }

  function keyPeople() {
    var ranked = state.data.nodes.slice().sort(function (a, b) {
      return b[state.sizeBy] - a[state.sizeBy];
    });
    var ids = {};
    ranked.slice(0, 8).forEach(function (n) { ids[n.id] = true; });
    state.data.nodes.forEach(function (n) {
      if (n.is_cut) ids[n.id] = true;
    });
    return ids;
  }

  /* Labels are recomputed rather than toggled, since which names count
     as key changes with the sizing measure and with the selection. */
  function updateLabels() {
    var keys = keyPeople();
    var onRoute = routeNames();
    var byId = {};
    state.data.nodes.forEach(function (n) { byId[n.id] = n; });
    state.layerNodes.querySelectorAll(".node").forEach(function (el) {
      var node = byId[Number(el.getAttribute("data-id"))];
      var t = el.querySelector(".node-label");
      /* Names along a route are always shown, whatever the label
         setting says. A route whose stops cannot be read is a shape. */
      var wanted = onRoute[node.id] === true || labelWanted(node, keys);
      if (t) t.classList.toggle("hide", !wanted);
    });
  }

  /* The tooltip is one shared element repositioned per node, built with
     DOM calls rather than markup strings so names never need escaping. */
  function showTip(node, clientX, clientY) {
    var t = state.tooltip;
    t.innerHTML = "";
    var name = document.createElement("strong");
    name.textContent = node.label;
    var line = document.createElement("span");
    line.textContent = node.degree + " direct ties, group " + node.group +
      (node.is_cut ? ", single point of failure" : "");
    t.appendChild(name);
    t.appendChild(line);
    t.style.left = Math.min(clientX + 14, window.innerWidth - 240) + "px";
    t.style.top = (clientY + 14) + "px";
    t.classList.add("show");
  }
  function hideTip() { state.tooltip.classList.remove("show"); }

  /* Builds one person as a group element holding a shape, an optional
     pip, an optional fragility ring, a label, and every interaction the
     node answers to. The whole node is assembled in one place rather
     than in a chain of decorating passes, because a node that is half
     built is a node that draws wrong for one frame. */
  function buildNode(node) {
    var g = document.createElementNS("http://www.w3.org/2000/svg", "g");
    var gl = glyphFor(node.group);
    /* Three classes carry the three visual channels: the real group for
       filtering, the color slot, and the fill variant. */
    g.setAttribute("class", "node group-" + node.group +
      " color-" + gl.color + " var-" + gl.variant +
      (node.is_cut ? " cut" : ""));
    g.setAttribute("data-id", node.id);
    var cx = px(node), cy = py(node);
    var r = radiusFor(node);

    var d = shapePath(gl.shape, r, cx, cy);
    var mark;
    if (d === null) {
      mark = document.createElementNS("http://www.w3.org/2000/svg", "circle");
      mark.setAttribute("r", r);
      mark.setAttribute("cx", cx);
      mark.setAttribute("cy", cy);
    } else {
      mark = document.createElementNS("http://www.w3.org/2000/svg", "path");
      mark.setAttribute("d", d);
    }
    mark.setAttribute("class", "mark");
    g.appendChild(mark);

    /* Variant two adds a small centered dot. It is a real element so it
       reads at any zoom and in every palette. */
    if (gl.variant === 2) {
      var pip = document.createElementNS("http://www.w3.org/2000/svg",
                                         "circle");
      pip.setAttribute("class", "pip");
      pip.setAttribute("r", Math.max(r * 0.3, 2.5));
      pip.setAttribute("cx", cx);
      pip.setAttribute("cy", cy);
      g.appendChild(pip);
    }

    /* Single points of failure carry a second ring. The warning must
       survive the monochrome palette, so it is geometry, not color. */
    if (node.is_cut) {
      var ring = document.createElementNS("http://www.w3.org/2000/svg", "circle");
      ring.setAttribute("class", "cut-ring");
      ring.setAttribute("r", r + 7);
      ring.setAttribute("cx", cx);
      ring.setAttribute("cy", cy);
      g.appendChild(ring);
    }

    /* The label sits below the node rather than beside it, so a dense
       cluster spreads its names vertically instead of overlapping them
       in one horizontal band. */
    var label = document.createElementNS("http://www.w3.org/2000/svg", "text");
    label.setAttribute("x", cx);
    label.setAttribute("y", cy + r + 17);
    label.setAttribute("class", "node-label");
    label.textContent = node.label;
    g.appendChild(label);

    /* Every node is a real keyboard stop with a spoken description, so
       the map itself works for a screen reader, not only the table. */
    g.setAttribute("tabindex", "0");
    g.setAttribute("role", "button");
    g.setAttribute("aria-label", node.label + ", " + node.degree +
      " direct ties, group " + node.group +
      (node.is_cut ? ", single point of failure" : "") +
      ". Press Enter to focus the map on this person.");

    /* Pointer down starts a potential drag. Movement past a few pixels
       becomes a drag that moves the node and its ties; a press that
       never moves is treated as a click and toggles the spotlight. */
    var down = null, moved = false;
    g.addEventListener("pointerdown", function (ev) {
      ev.stopPropagation();
      down = svgPoint(ev);
      moved = false;
      g.setPointerCapture(ev.pointerId);
    });
    g.addEventListener("pointermove", function (ev) {
      if (down === null) return;
      var p = svgPoint(ev);
      if (!moved &&
          Math.hypot(p.x - down.x, p.y - down.y) < 5) return;
      moved = true;
      node._x = p.x;
      node._y = p.y;
      /* While the live layout is running, a node being held is pinned
         rather than merely moved, so the forces treat it as fixed and
         everything attached to it follows the hand instead of fighting
         it back toward where it was. */
      pinDragged(node, true);
      redrawNode(node);
    });
    g.addEventListener("pointerup", function (ev) {
      g.releasePointerCapture(ev.pointerId);
      if (!moved) {
        select(state.selected === node.id ? null : node.id);
      } else {
        pinDragged(node, false);
      }
      down = null;
    });
    g.addEventListener("dblclick", function (ev) {
      ev.preventDefault();
      ev.stopPropagation();
      toggleHold(node);
    });
    /* Enter and Space both toggle, matching what a button does
       elsewhere on the page. The default is suppressed because Space
       would otherwise scroll the map out from under the person who
       just pressed it. */
    g.addEventListener("keydown", function (ev) {
      if (ev.key === "Enter" || ev.key === " ") {
        ev.preventDefault();
        select(state.selected === node.id ? null : node.id);
        return;
      }
      /* The keyboard equivalent of a double press. Pinning is the one
         thing on this map that only the mouse could reach otherwise,
         and a control only the mouse can reach is not a control. */
      if (ev.key === "p" || ev.key === "P") {
        ev.preventDefault();
        toggleHold(node);
      }
    });
    /* Focus raises the same tooltip a hover does, positioned from the
       node box rather than a pointer. A keyboard reader gets the same
       information as a mouse reader, at the same moment. */
    g.addEventListener("mouseenter", function (ev) {
      showTip(node, ev.clientX, ev.clientY);
    });
    g.addEventListener("mousemove", function (ev) {
      showTip(node, ev.clientX, ev.clientY);
    });
    g.addEventListener("mouseleave", hideTip);
    g.addEventListener("focus", function () {
      var box = g.getBoundingClientRect();
      showTip(node, box.left, box.top);
    });
    g.addEventListener("blur", hideTip);
    return g;
  }

  /* A pointer event in screen pixels becomes a point in world units by
     reading the live viewBox. Every drag needs this, so it is one
     shared helper. */
  function svgPoint(ev) {
    var box = state.svg.getBoundingClientRect();
    var v = state.view;
    return {
      x: v.x + ((ev.clientX - box.left) / box.width) * v.w,
      y: v.y + ((ev.clientY - box.top) / box.height) * v.h
    };
  }

  /* Moving one node repositions its own marks and every tie that
     touches it, so an edge never lags behind the node it joins. */
  /* Only the moved node and the ties touching it are rewritten. A full
     render on every pointer move would be correct and unusable. */
  function redrawNode(node) {
    var g = state.layerNodes.querySelector(
      '.node[data-id="' + node.id + '"]');
    if (!g) return;
    var cx = node._x, cy = node._y, r = radiusFor(node);
    var mark = g.querySelector(".mark");
    var d = shapePath(glyphFor(node.group).shape, r, cx, cy);
    if (d === null) {
      mark.setAttribute("cx", cx); mark.setAttribute("cy", cy);
    } else {
      mark.setAttribute("d", d);
    }
    var pip = g.querySelector(".pip");
    if (pip) { pip.setAttribute("cx", cx); pip.setAttribute("cy", cy); }
    var ring = g.querySelector(".cut-ring");
    if (ring) { ring.setAttribute("cx", cx); ring.setAttribute("cy", cy); }
    var label = g.querySelector(".node-label");
    label.setAttribute("x", cx);
    label.setAttribute("y", cy + r + 17);
    state.layerEdges.querySelectorAll(
      'path[data-from="' + node.id + '"], path[data-to="' + node.id + '"]')
      .forEach(function (p) {
        var a = nodeById(Number(p.getAttribute("data-from")));
        var b = nodeById(Number(p.getAttribute("data-to")));
        p.setAttribute("d", edgePath(a, b));
      });
  }

  /* ---- Live layout ---------------------------------------------------

     The map arrives with coordinates the server computed in three
     passes, and that arrangement is better than anything a few hundred
     frames of physics will find, because it knows which people are in
     which community and it separates overlapping nodes at the end.
     Nothing here replaces it. This is the other thing a reader wants,
     which is to take hold of a node, pull it out of the knot it is in,
     and watch what it is attached to come with it.

     The physics is in www/layout.js and is not the expensive part. What
     is expensive is writing several thousand positions back into the
     document sixty times a second, so the size at which this is offered
     is decided by measuring a redraw rather than by measuring the
     forces. Above that size the control says why it is off instead of
     going quiet or going slow. */

  /* Largest network the live layout is offered for. Measured once, on
     the machine the app is running on, because the answer on a desktop
     and the answer on a phone are not the same answer. */
  /* How far apart the live layout holds people. Three settings rather
     than a slider: a slider inside a row of square controls is a
     different kind of thing in a place with no room for it, and three
     steps cover the reason anyone reaches for this, which is a map
     that came out too dense to read or too sparse to see. */
  var SPREADS = [
    { label: "close together", value: 1100 },
    { label: "the usual distance", value: 2400 },
    { label: "spread out", value: 5200 }
  ];

  function liveLayoutCap() {
    if (state.simCap !== null) return state.simCap;
    var cap = 1200;
    if (window.TesseraLayout && window.TesseraLayout.measure) {
      /* One frame of forces at a size in the middle of the range. The
         redraw costs several times this, so the budget is a fraction of
         a sixty per second frame rather than all of it. */
      var ms = window.TesseraLayout.measure(600, 1800, 6);
      if (ms > 4) cap = 600;
      if (ms > 12) cap = 250;
    }
    state.simCap = cap;
    return cap;
  }

  function liveLayoutAvailable() {
    return Boolean(window.TesseraLayout) && Boolean(state.data) &&
      state.data.nodes.length <= liveLayoutCap();
  }

  /* Node objects the simulation can move, sharing nothing with the
     renderer except the numbers that come back out of them. */
  function buildSimulation() {
    var order = {};
    var points = state.data.nodes.map(function (n, i) {
      order[n.id] = i;
      return { x: px(n), y: py(n) };
    });
    var pairs = [];
    state.data.edges.forEach(function (e) {
      var a = order[e.from];
      var b = order[e.to];
      if (a !== undefined && b !== undefined && a !== b) pairs.push([a, b]);
    });
    var sim = window.TesseraLayout.create(points, pairs);
    sim.order = order;
    Object.keys(state.held).forEach(function (id) {
      var i = order[id];
      if (i !== undefined) sim.pin(i);
    });
    if (state.spread !== 1) sim.setSpread(SPREADS[state.spread].value);
    return sim;
  }

  function pinDragged(node, held) {
    if (!state.sim) return;
    var i = state.sim.order[node.id];
    if (i === undefined) return;
    if (held) {
      state.sim.nodes[i].x = node._x;
      state.sim.nodes[i].y = node._y;
      state.sim.pin(i);
      /* A drag is a new question, so the arrangement gets to move
         again. Without this a settled map lets one node be pulled out
         and nothing follows it. */
      state.sim.reheat();
    } else if (!state.held[node.id]) {
      state.sim.unpin(i);
      state.sim.reheat();
    }
  }

  /* A node a reader has pinned for good.

     Dragging one out of a knot only helps while the forces are running;
     the moment they settle again the arrangement has forgotten. Pinning
     is how a reader says where someone belongs and has it stay there,
     which is the thing an arranged layout is for. Double press to pin,
     double press again to release. */
  function toggleHold(node) {
    var id = node.id;
    if (state.held[id]) {
      delete state.held[id];
    } else {
      state.held[id] = true;
    }
    if (state.sim) {
      var i = state.sim.order[id];
      if (i !== undefined) {
        if (state.held[id]) {
          state.sim.nodes[i].x = node._x;
          state.sim.nodes[i].y = node._y;
          state.sim.pin(i);
        } else {
          state.sim.unpin(i);
        }
        state.sim.reheat();
      }
    }
    markHeld();
  }

  /* Pinned people are marked on the map. A pin that cannot be seen is a
     pin a reader loses track of, and then the arrangement has parts
     that will not move for reasons nobody remembers. */
  function markHeld() {
    if (!state.layerNodes) return;
    state.layerNodes.querySelectorAll(".node").forEach(function (el) {
      var id = Number(el.getAttribute("data-id"));
      el.classList.toggle("held", Boolean(state.held[id]));
    });
  }

  function releaseHeld() {
    state.held = {};
    if (state.sim) {
      state.sim.unpinAll();
      state.sim.reheat(0.8);
    }
    markHeld();
  }

  /* One frame: step the forces, copy the coordinates back onto the
     nodes, redraw. Every node and every tie moves, so this rewrites the
     whole drawing rather than the parts around one node. */
  function simFrame() {
    if (!state.sim) return;
    var largest = state.sim.step();
    state.data.nodes.forEach(function (n, i) {
      n._x = state.sim.nodes[i].x;
      n._y = state.sim.nodes[i].y;
    });
    redrawAll();
    if (largest < 0.05) {
      /* It has stopped changing in any way a reader could see. The
         simulation stays in place so a drag can wake it, but no frames
         are spent on it. */
      state.simFrame = null;
      return;
    }
    state.simFrame = window.requestAnimationFrame(simFrame);
  }

  function startLiveLayout() {
    if (!liveLayoutAvailable()) return false;
    if (state.home === null) {
      state.home = state.data.nodes.map(function (n) {
        return { x: px(n), y: py(n) };
      });
    }
    state.sim = buildSimulation();
    if (state.simFrame === null) {
      state.simFrame = window.requestAnimationFrame(simFrame);
    }
    return true;
  }

  function stopLiveLayout() {
    if (state.simFrame !== null) {
      window.cancelAnimationFrame(state.simFrame);
      state.simFrame = null;
    }
    state.sim = null;
  }

  /* Back to the arrangement the server sent. A reader who has pushed
     the map into a shape they cannot read needs one press that undoes
     all of it, and the computed layout is the thing to go back to
     rather than a random restart. */
  function restoreLayout() {
    stopLiveLayout();
    /* Back to the computed arrangement means back to all of it, pins
       included. A reader pressing this wants the map they started with,
       not the map they started with plus six people nailed down. */
    state.held = {};
    state.spread = 1;
    if (state.home !== null) {
      state.data.nodes.forEach(function (n, i) {
        n._x = state.home[i].x;
        n._y = state.home[i].y;
      });
    } else {
      state.data.nodes.forEach(function (n) {
        n._x = undefined;
        n._y = undefined;
      });
    }
    redrawAll();
    markHeld();
  }

  /* Every position written in one pass. The per node redraw looks up
     its elements by selector, which is fine once per drag and far too
     slow sixty times a second across every node, so this walks the two
     layers it already has. */
  function redrawAll() {
    if (!state.layerNodes || !state.layerEdges) return;
    var byId = {};
    state.data.nodes.forEach(function (n) { byId[n.id] = n; });
    state.layerNodes.querySelectorAll(".node").forEach(function (el) {
      var node = byId[Number(el.getAttribute("data-id"))];
      if (!node) return;
      var cx = node._x, cy = node._y, r = radiusFor(node);
      var mark = el.querySelector(".mark");
      if (mark) {
        var d = shapePath(glyphFor(node.group).shape, r, cx, cy);
        if (d === null) {
          mark.setAttribute("cx", cx);
          mark.setAttribute("cy", cy);
        } else {
          mark.setAttribute("d", d);
        }
      }
      var pip = el.querySelector(".pip");
      if (pip) { pip.setAttribute("cx", cx); pip.setAttribute("cy", cy); }
      var ring = el.querySelector(".cut-ring");
      if (ring) { ring.setAttribute("cx", cx); ring.setAttribute("cy", cy); }
      var label = el.querySelector(".node-label");
      if (label) {
        label.setAttribute("x", cx);
        label.setAttribute("y", cy + r + 17);
      }
    });
    state.layerEdges.querySelectorAll("path").forEach(function (p) {
      var a = byId[Number(p.getAttribute("data-from"))];
      var b = byId[Number(p.getAttribute("data-to"))];
      if (a && b) p.setAttribute("d", edgePath(a, b));
    });
  }

  /* Ties bend gently rather than running straight. The curve is a small
     fixed fraction of each tie length, which keeps parallel runs apart
     and reads calmer at every zoom. */
  function edgePath(a, b) {
    var x1 = px(a), y1 = py(a), x2 = px(b), y2 = py(b);
    var mx = (x1 + x2) / 2, my = (y1 + y2) / 2;
    var dx = x2 - x1, dy = y2 - y1;
    var bend = 0.12;
    return "M" + x1.toFixed(1) + "," + y1.toFixed(1) +
      " Q" + (mx - dy * bend).toFixed(1) + "," +
      (my + dx * bend).toFixed(1) + " " +
      x2.toFixed(1) + "," + y2.toFixed(1);
  }

  /* The view is fitted to where the people actually landed, with a
     margin, so the whole network sits inside the panel from the first
     paint rather than drifting against an edge. */
  function fitView() {
    var xs = state.data.nodes.map(px);
    var ys = state.data.nodes.map(py);
    var minX = Math.min.apply(null, xs), maxX = Math.max.apply(null, xs);
    var minY = Math.min.apply(null, ys), maxY = Math.max.apply(null, ys);
    var margin = 60;
    var w = Math.max(maxX - minX + margin * 2, 200);
    var h = Math.max(maxY - minY + margin * 2, 200);
    var cx = (minX + maxX) / 2, cy = (minY + maxY) / 2;

    /* The view is fitted to the shape of the panel rather than to a
       square. A square viewBox inside a wide panel is letterboxed by
       the browser, which leaves the network in a tall strip down the
       middle with dead space on either side. Growing the tight box out
       to the panel ratio spends the whole panel on the network. */
    var box = state.svg.getBoundingClientRect();
    var ratio = box.width > 0 && box.height > 0
      ? box.width / box.height
      : 1;
    if (w / h < ratio) {
      w = h * ratio;
    } else {
      h = w / ratio;
    }
    return { x: cx - w / 2, y: cy - h / 2, w: w, h: h };
  }

  /* A full rebuild per dataset keeps the code simple and honest; at
     this scale, diffing the scene would add machinery without a
     visible payoff. The view survives rebuilds so zoom is never lost. */
  function render() {
    if (!state.data) return;
    var host = document.getElementById("map-host");
    if (!host) return;
    host.innerHTML = "";

    var svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    svg.setAttribute("id", "network-map");
    svg.setAttribute("role", "group");
    svg.setAttribute("aria-label", "Network map. " + state.data.meta.n +
      " people in " + state.data.meta.n_groups +
      " groups. Use Tab to move between people.");
    state.svg = svg;
    if (!state.view) {
      state.view = fitView();
    }
    setViewBox();

    var edges = document.createElementNS("http://www.w3.org/2000/svg", "g");
    var nodes = document.createElementNS("http://www.w3.org/2000/svg", "g");
    state.layerEdges = edges;
    state.layerNodes = nodes;

    var byId = {};
    state.data.nodes.forEach(function (n) { byId[n.id] = n; });
    var maxW = 1;
    state.data.edges.forEach(function (e) {
      if (e.weight > maxW) maxW = e.weight;
    });
    state.data.edges.forEach(function (e) {
      var p = document.createElementNS("http://www.w3.org/2000/svg", "path");
      p.setAttribute("d", edgePath(byId[e.from], byId[e.to]));
      /* Tie strength appears as thickness, one more channel that never
         depends on color. */
      p.setAttribute("stroke-width", (1 + 2.6 * (e.weight / maxW)).toFixed(1));
      p.setAttribute("fill", "none");
      p.setAttribute("data-from", e.from);
      p.setAttribute("data-to", e.to);
      /* Two properties of the tie itself. A bridge is the only route
         between what sits on either side of it; a crossing tie joins
         two groups. Both are carried as classes so the stylesheet
         decides whether they are shown, and the toggle above the map
         is one class on the drawing rather than a redraw. */
      if (e.bridge) p.classList.add("tie-bridge");
      if (e.crossing) p.classList.add("tie-crossing");
      edges.appendChild(p);
    });
    state.data.nodes.forEach(function (n) {
      nodes.appendChild(buildNode(n));
    });

    svg.appendChild(edges);
    svg.appendChild(nodes);
    host.appendChild(svg);

    svg.addEventListener("click", function () { select(null); });

    wireViewControls(svg, host);
    updateLabels();
    document.dispatchEvent(new CustomEvent("tessera:map-rendered"));
    if (!reducedMotion) {
      svg.classList.add("enter");
      window.setTimeout(function () { svg.classList.remove("enter"); }, 700);
    }
  }

  /* Zoom keeps the point under the pointer fixed, which is what a hand
     expects a map to do. Buttons repeat the same moves for anyone who
     prefers clicks or keys over gestures. */
  function wireViewControls(svg, host) {
    svg.addEventListener("wheel", function (ev) {
      ev.preventDefault();
      var v = state.view;
      var factor = ev.deltaY > 0 ? 1.12 : 0.9;
      var box = svg.getBoundingClientRect();
      var mx = v.x + ((ev.clientX - box.left) / box.width) * v.w;
      var my = v.y + ((ev.clientY - box.top) / box.height) * v.h;
      var w = Math.min(Math.max(v.w * factor, 140), WORLD * 2.2);
      state.view = { x: mx - (mx - v.x) * (w / v.w),
                     y: my - (my - v.y) * (w / v.h), w: w, h: w };
      setViewBox();
    }, { passive: false });

    var dragging = false, sx = 0, sy = 0;
    svg.addEventListener("pointerdown", function (ev) {
      if (ev.target.closest(".node")) return;
      dragging = true; sx = ev.clientX; sy = ev.clientY;
      svg.setPointerCapture(ev.pointerId);
    });
    svg.addEventListener("pointermove", function (ev) {
      if (!dragging) return;
      var box = svg.getBoundingClientRect();
      var v = state.view;
      state.view.x -= ((ev.clientX - sx) / box.width) * v.w;
      state.view.y -= ((ev.clientY - sy) / box.height) * v.h;
      sx = ev.clientX; sy = ev.clientY;
      setViewBox();
    });
    svg.addEventListener("pointerup", function () { dragging = false; });

    var bar = document.createElement("div");
    bar.className = "map-buttons";
    /* Icons rather than characters. A plus, a minus sign, and a circled
       dot are three glyphs from three parts of a font, with three
       different optical centers and three different weights, which is
       why they never sat straight in their buttons however the box was
       centered. These are one geometry on one 20 unit grid. */
    var ICONS = {
      plus: '<path d="M10 4.5v11M4.5 10h11"/>',
      minus: '<path d="M4.5 10h11"/>',
      reset: '<circle cx="10" cy="10" r="6.2"/><circle cx="10" cy="10" ' +
        'r="1.6" fill="currentColor" stroke="none"/>',
      /* Three bodies joined by two links, which is what the control
         does to the map. */
      live: '<circle cx="5" cy="6" r="2.1"/><circle cx="15" cy="8" ' +
        'r="2.1"/><circle cx="9" cy="15" r="2.1"/>' +
        '<path d="M7 6.4L13 7.6M14 10L10.2 13.2"/>',
      /* An arrow returning to a point: back to the computed layout. */
      home: '<path d="M4 10.5a6 6 0 106-6H5.5"/><path d="M8 1.8L5 4.7l3 ' +
        '2.9"/>',
      /* Two bodies with arrows pushing them apart. */
      spread: '<circle cx="4.5" cy="10" r="2"/><circle cx="15.5" cy="10" ' +
        'r="2"/><path d="M8 10h4M9.6 8.4L8 10l1.6 1.6M10.4 8.4L12 10l-1.6 ' +
        '1.6"/>'
    };
    function iconMarkup(name) {
      return '<svg viewBox="0 0 20 20" aria-hidden="true" class="map-icon" ' +
        'fill="none" stroke="currentColor" stroke-width="1.8" ' +
        'stroke-linecap="round">' + ICONS[name] + "</svg>";
    }

    [["plus", "Zoom in"], ["minus", "Zoom out"], ["reset", "Reset the view"]]
      .forEach(function (spec, i) {
        var b = document.createElement("button");
        b.type = "button";
        b.innerHTML = iconMarkup(spec[0]);
        b.setAttribute("aria-label", spec[1]);
        b.title = spec[1];
        b.addEventListener("click", function () {
          var v = state.view;
          if (i === 2) {
            /* Reset is a deliberate request, so it refits whether or
               not the panel has changed size. */
            state.view = fitView();
          } else {
            /* Zoom keeps the ratio the view already has. Forcing a
               square here would undo the aspect fit on the first
               press of a zoom button. */
            var f = i === 0 ? 0.82 : 1.22;
            var ratio = v.w / v.h;
            var cx = v.x + v.w / 2, cy = v.y + v.h / 2;
            var w = Math.min(Math.max(v.w * f, 140), WORLD * 2.2);
            var h = w / ratio;
            state.view = { x: cx - w / 2, y: cy - h / 2, w: w, h: h };
          }
          setViewBox();
        });
        bar.appendChild(b);
      });

    /* Live layout and the way back from it. Both are only offered when
       the network is small enough for a redraw of every node to fit
       inside a frame; above that the first control says so rather than
       going quiet or going slow, because a control that does nothing is
       worse than one that is not there. */
    var live = document.createElement("button");
    live.type = "button";
    live.className = "map-live";
    live.innerHTML = iconMarkup("live");
    var setLiveLabel = function () {
      var running = state.simFrame !== null || state.sim !== null;
      var label = !liveLayoutAvailable()
        ? "Live layout is off for networks this large, because moving " +
          "every person on screen sixty times a second would not keep up"
        : running ? "Stop the live layout" : "Start the live layout";
      live.setAttribute("aria-label", label);
      live.setAttribute("aria-pressed", running ? "true" : "false");
      live.title = label;
      live.disabled = !liveLayoutAvailable();
      live.classList.toggle("on", running);
    };
    live.addEventListener("click", function () {
      if (state.sim) {
        stopLiveLayout();
      } else {
        startLiveLayout();
      }
      setLiveLabel();
    });
    setLiveLabel();
    bar.appendChild(live);

    /* How far apart to hold people. Cycles through three settings and
       says which one it is on, since a control that changes something
       without naming its state leaves a reader guessing what they just
       did. */
    var spread = document.createElement("button");
    spread.type = "button";
    spread.className = "map-spread";
    spread.innerHTML = iconMarkup("spread");
    var setSpreadLabel = function () {
      var label = "Spacing: " + SPREADS[state.spread].label +
        ". Press for the next setting.";
      spread.setAttribute("aria-label", label);
      spread.title = label;
      spread.disabled = !liveLayoutAvailable();
    };
    spread.addEventListener("click", function () {
      state.spread = (state.spread + 1) % SPREADS.length;
      setSpreadLabel();
      if (!state.sim) startLiveLayout();
      if (state.sim) {
        state.sim.setSpread(SPREADS[state.spread].value);
        if (state.simFrame === null) {
          state.simFrame = window.requestAnimationFrame(simFrame);
        }
      }
      setLiveLabel();
    });
    setSpreadLabel();
    bar.appendChild(spread);

    var home = document.createElement("button");
    home.type = "button";
    home.innerHTML = iconMarkup("home");
    home.setAttribute("aria-label", "Back to the computed layout");
    home.title = "Back to the computed layout";
    home.addEventListener("click", function () {
      restoreLayout();
      setSpreadLabel();
      setLiveLabel();
    });
    bar.appendChild(home);

    /* Full screen also belongs here. It had one control only, sitting
       at the far right of the row above the map under the label Map
       size, which is a long way from where a person looks for a view
       control and easy to miss entirely. Both controls drive the same
       toggle. */
    var full = document.createElement("button");
    full.type = "button";
    full.setAttribute("data-fs-toggle", "");
    full.setAttribute("aria-pressed", "false");
    full.setAttribute("aria-label", "Full screen map");
    full.title = "Full screen map";
    full.innerHTML = '<svg viewBox="0 0 20 20" aria-hidden="true" ' +
      'class="map-icon"><path d="M3 7.5V3h4.5M12.5 3H17v4.5M17 12.5V17' +
      'h-4.5M7.5 17H3v-4.5" fill="none" stroke="currentColor" ' +
      'stroke-width="1.8" stroke-linecap="round"/></svg>';
    bar.appendChild(full);

    host.appendChild(bar);
  }

  /* Server messages. The graph arrives once per dataset; cosmetic
     choices ride their own messages so the map never recomputes for a
     switch of size, labels, or depth. */
  function handlers() {
    Shiny.addCustomMessageHandler("graph-data", function (payload) {
      state.data = {
        nodes: normalize(payload.nodes),
        edges: normalize(payload.edges),
        meta: payload.meta
      };
      state.selected = null;
      state.groupFocus = null;
      state.reach = {};
      state.view = null;
      /* A running simulation belongs to the network it was built for.
         Left alive across a dataset change it would be stepping an
         index into an array that is no longer there. */
      stopLiveLayout();
      state.home = null;
      state.held = {};
      state.data.nodes.forEach(function (n) {
        n._x = undefined; n._y = undefined;
      });
      buildAdjacency();
      refreshScale();
      Shiny.setInputValue("selected_node", null);
      render();
    });
    Shiny.addCustomMessageHandler("size-by", function (metric) {
      state.sizeBy = metric;
      if (!state.data) return;
      refreshScale();
      var keep = state.selected;
      render();
      if (keep !== null) select(keep, true);
    });
    Shiny.addCustomMessageHandler("label-mode", function (mode) {
      state.labelMode = mode;
      if (state.data) updateLabels();
    });
    Shiny.addCustomMessageHandler("reach-depth", function (d) {
      state.depth = Number(d);
      if (state.selected !== null) select(state.selected, true);
    });
    Shiny.addCustomMessageHandler("select-node", function (id) {
      if (state.data) select(id === null ? null : Number(id));
    });
    Shiny.addCustomMessageHandler("focus-group", function (group) {
      if (state.data) focusGroup(Number(group));
    });
    Shiny.addCustomMessageHandler("clear-selection", function (unused) {
      if (state.data) select(null);
    });
    /* Which ties to mark: none, the bridges, or every tie that crosses
       between groups. The class goes on the drawing rather than on each
       tie, so switching is one attribute change and the positions never
       move. */
    Shiny.addCustomMessageHandler("tie-marks", function (mode) {
      if (!state.svg) return;
      state.svg.classList.remove("show-bridges", "show-crossing");
      if (mode === "bridges") state.svg.classList.add("show-bridges");
      if (mode === "crossing") state.svg.classList.add("show-crossing");
    });

    /* Highlights one route through the network. The route is computed
       in R, where the graph already is, and arrives as the people along
       it in order. Everything else dims, so a path of four ties inside
       a network of two hundred is findable. */
    Shiny.addCustomMessageHandler("show-route", function (route) {
      if (!state.svg) return;
      clearRoute();
      if (!route || !route.ids || route.ids.length < 2) return;
      state.route = route;
      var onPath = {};
      route.ids.forEach(function (id) { onPath[id] = true; });
      state.svg.classList.add("routing");
      state.layerNodes.querySelectorAll(".node").forEach(function (el) {
        var id = Number(el.getAttribute("data-id"));
        el.classList.toggle("on-route", onPath[id] === true);
      });
      /* A tie is on the route only if it joins two people who are
         adjacent along it. Marking every tie between two people on the
         route would light shortcuts the route does not take. */
      var steps = {};
      route.steps.forEach(function (step) {
        steps[step.from + ":" + step.to] = true;
        steps[step.to + ":" + step.from] = true;
      });
      state.layerEdges.querySelectorAll("path").forEach(function (el) {
        var key = el.getAttribute("data-from") + ":" + el.getAttribute("data-to");
        el.classList.toggle("on-route", steps[key] === true);
      });
      updateLabels();
    });

    Shiny.addCustomMessageHandler("clear-route", function (unused) {
      clearRoute();
    });

    Shiny.addCustomMessageHandler("clear-graph", function (unused) {
      state.data = null;
      state.selected = null;
      state.groupFocus = null;
      state.reach = {};
      state.neighbors = {};
      state.index = {};
      state.view = null;
      state.svg = null;
      var host = document.getElementById("map-host");
      if (host) host.innerHTML = "";
      document.dispatchEvent(new CustomEvent("tessera:map-cleared"));
    });
  }
  if (window.Shiny) handlers();

  /* Anything that changes the drawing area changes what fits in it, so
     the view is refitted. A window resize is the obvious case, but not
     the only one: the panel also changes shape when the reading panel
     beside it grows, when full screen is entered or left, and when a
     phone is turned. A ResizeObserver on the panel itself catches all
     of them, and the window listener stays as the fallback for
     browsers without one. */
  /* The refit is guarded on the measured size of the drawing area.
     Anything that repaints without resizing, such as the see through
     toggle, would otherwise arrive through the resize event and throw
     away the reader's zoom and pan. The map should move when the space
     it has changes, and at no other time. */
  var lastFit = { w: 0, h: 0 };

  function refit(force) {
    if (!state.data || !state.svg) return;
    var box = state.svg.getBoundingClientRect();
    if (box.width < 1 || box.height < 1) return;
    var changed = Math.abs(box.width - lastFit.w) > 1 ||
                  Math.abs(box.height - lastFit.h) > 1;
    if (!changed && force !== true) return;
    lastFit = { w: box.width, h: box.height };
    state.view = fitView();
    setViewBox();
  }

  var refitPending = false;
  function refitSoon() {
    if (refitPending) return;
    refitPending = true;
    window.requestAnimationFrame(function () {
      refitPending = false;
      refit();
    });
  }

  window.addEventListener("resize", refitSoon);

  function watchPanel() {
    if (!window.ResizeObserver) return;
    var host = document.getElementById("map-host");
    if (!host) return;
    new window.ResizeObserver(refitSoon).observe(host);
  }

  function ready() {
    watchPanel();
    state.tooltip = document.createElement("div");
    state.tooltip.id = "map-tooltip";
    state.tooltip.setAttribute("role", "status");
    document.body.appendChild(state.tooltip);
  }
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", ready);
  } else {
    ready();
  }
})();

/* fullscreen.js is folded in here so the map and its full screen mode
   share one file and one set of state. The mode moves the map panel to
   a fixed overlay and lifts the reading panel into a floating card, so
   the network gets the whole window while the interpretation stays in
   view. */
(function () {
  "use strict";

  var on = false, seeThrough = false;

  /* The two states of the see through control, on the same 20 unit grid
     as the map controls so the whole set matches. */
  var EYE_OPEN = '<svg viewBox="0 0 20 20" aria-hidden="true" ' +
    'class="map-icon" fill="none" stroke="currentColor" ' +
    'stroke-width="1.6" stroke-linecap="round"><path d="M1.6 10S4.8 4.6 ' +
    '10 4.6 18.4 10 18.4 10 15.2 15.4 10 15.4 1.6 10 1.6 10Z"/>' +
    '<circle cx="10" cy="10" r="2.4"/></svg>';
  var EYE_CLOSED = '<svg viewBox="0 0 20 20" aria-hidden="true" ' +
    'class="map-icon" fill="none" stroke="currentColor" ' +
    'stroke-width="1.6" stroke-linecap="round"><path d="M1.6 10S4.8 4.6 ' +
    '10 4.6 18.4 10 18.4 10 15.2 15.4 10 15.4 1.6 10 1.6 10Z"/>' +
    '<circle cx="10" cy="10" r="2.4"/><path d="M3.4 16.6 16.6 3.4"/></svg>';

  function panel() { return document.querySelector(".map-panel"); }
  function reading() { return document.querySelector(".reading-panel"); }

  function setLabels() {
    /* The control in the row above the map carries a word; the one on
       the map carries an icon and keeps it. Both report their state. */
    var b = document.getElementById("fs-toggle");
    if (b) {
      b.textContent = on ? "Exit full screen" : "Full screen";
      b.setAttribute("aria-pressed", on ? "true" : "false");
    }
    Array.prototype.forEach.call(
      document.querySelectorAll(".map-buttons [data-fs-toggle]"),
      function (m) {
        m.setAttribute("aria-pressed", on ? "true" : "false");
        var label = on ? "Exit full screen map" : "Full screen map";
        m.setAttribute("aria-label", label);
        m.title = label;
      });
    var t = document.getElementById("fs-transparent");
    if (t) {
      /* An icon rather than a label that swaps between two phrases. A
         control whose words change is a control a reader has to read
         twice to find out what state they are in; aria-pressed says the
         same thing to a screen reader without the swap. */
      t.innerHTML = seeThrough ? EYE_OPEN : EYE_CLOSED;
      t.setAttribute("aria-pressed", seeThrough ? "true" : "false");
      var label = seeThrough
        ? "Make the reading panel solid again"
        : "See the map through the reading panel";
      t.setAttribute("aria-label", label);
      t.title = label;
    }
  }

  /* Markers left behind so each panel returns to its original place and
     order when full screen ends. */
  var mapHome = null, readingHome = null, overlay = null;

  function overlayActive() {
    return !!(overlay && overlay.parentNode);
  }

  /* The floating panel had a fixed width and no way to change it, so a
     long card stack in full screen was a column of text a reader could
     neither widen nor put away. Both controls are added on entering and
     removed on leaving, so nothing of them exists in the split view. */
  var PANEL_MIN = 300, PANEL_MAX_SHARE = 0.62;

  function buildPanelChrome(r) {
    if (r.querySelector(".panel-chrome")) return;
    var chrome = document.createElement("div");
    chrome.className = "panel-chrome";

    var fold = document.createElement("button");
    fold.type = "button";
    fold.className = "btn fs-icon-btn panel-fold";
    fold.setAttribute("aria-pressed", "false");
    fold.setAttribute("aria-label", "Fold the reading panel away");
    fold.title = "Fold the reading panel away";
    fold.innerHTML = '<svg viewBox="0 0 20 20" aria-hidden="true" ' +
      'class="map-icon" fill="none" stroke="currentColor" ' +
      'stroke-width="1.8" stroke-linecap="round">' +
      '<path d="M4.5 10h11"/></svg>';
    fold.addEventListener("click", function () {
      var folded = r.classList.toggle("folded");
      fold.setAttribute("aria-pressed", folded ? "true" : "false");
      var label = folded
        ? "Unfold the reading panel"
        : "Fold the reading panel away";
      fold.setAttribute("aria-label", label);
      fold.title = label;
      fold.innerHTML = '<svg viewBox="0 0 20 20" aria-hidden="true" ' +
        'class="map-icon" fill="none" stroke="currentColor" ' +
        'stroke-width="1.8" stroke-linecap="round"><path d="' +
        (folded ? "M10 4.5v11M4.5 10h11" : "M4.5 10h11") + '"/></svg>';
    });

    var title = document.createElement("span");
    title.className = "panel-chrome-title";
    title.textContent = "What this network says";

    chrome.appendChild(title);
    chrome.appendChild(fold);
    r.insertBefore(chrome, r.firstChild);

    /* The grip changes the width. It is a pointer drag rather than a
       set of size presets, because the right width depends on the
       network under the panel and only the reader can see that. */
    var grip = document.createElement("div");
    grip.className = "panel-grip";
    grip.setAttribute("role", "separator");
    grip.setAttribute("aria-orientation", "vertical");
    grip.setAttribute("aria-label", "Drag to change the panel width");
    grip.setAttribute("tabindex", "0");
    var dragging = false;
    function widthFrom(clientX) {
      var right = window.innerWidth - 22;
      var wanted = right - clientX;
      var max = window.innerWidth * PANEL_MAX_SHARE;
      return Math.min(Math.max(wanted, PANEL_MIN), max);
    }
    grip.addEventListener("pointerdown", function (ev) {
      dragging = true;
      grip.setPointerCapture(ev.pointerId);
      ev.preventDefault();
    });
    grip.addEventListener("pointermove", function (ev) {
      if (!dragging) return;
      r.style.width = widthFrom(ev.clientX) + "px";
    });
    grip.addEventListener("pointerup", function (ev) {
      dragging = false;
      grip.releasePointerCapture(ev.pointerId);
    });
    /* The same adjustment from the keyboard, since a drag is not
       available to everyone. */
    grip.addEventListener("keydown", function (ev) {
      var step = ev.key === "ArrowLeft" ? 40
        : ev.key === "ArrowRight" ? -40 : 0;
      if (step === 0) return;
      ev.preventDefault();
      var now = r.getBoundingClientRect().width;
      var max = window.innerWidth * PANEL_MAX_SHARE;
      r.style.width = Math.min(Math.max(now + step, PANEL_MIN), max) + "px";
    });
    r.appendChild(grip);
  }

  function stripPanelChrome(r) {
    var chrome = r.querySelector(".panel-chrome");
    if (chrome) chrome.remove();
    var grip = r.querySelector(".panel-grip");
    if (grip) grip.remove();
    r.classList.remove("folded");
    r.style.width = "";
  }

  function enter(p, r) {
    if (!overlay) {
      overlay = document.createElement("div");
      overlay.id = "fs-overlay";
      overlay.style.cssText = [
        "position:fixed", "top:0", "left:0", "right:0", "bottom:0",
        "width:100vw", "height:100vh", "z-index:2147483646",
        "margin:0", "padding:0"
      ].join(";");
    }
    mapHome = document.createComment("map panel home");
    readingHome = document.createComment("reading panel home");
    p.parentNode.insertBefore(mapHome, p);
    r.parentNode.insertBefore(readingHome, r);
    overlay.appendChild(p);
    overlay.appendChild(r);
    document.body.appendChild(overlay);
  }

  function leave(p, r) {
    if (mapHome && mapHome.parentNode) {
      mapHome.parentNode.replaceChild(p, mapHome);
    }
    if (readingHome && readingHome.parentNode) {
      readingHome.parentNode.replaceChild(r, readingHome);
    }
    mapHome = null;
    readingHome = null;
    if (overlay && overlay.parentNode) overlay.remove();
  }

  /* The browser primitives, named differently across engines. */
  function requestNative(el) {
    var fn = el.requestFullscreen || el.webkitRequestFullscreen ||
             el.mozRequestFullScreen || el.msRequestFullscreen;
    if (!fn) return null;
    try {
      return fn.call(el);
    } catch (e) {
      return null;
    }
  }
  function exitNative() {
    var fn = document.exitFullscreen || document.webkitExitFullscreen ||
             document.mozCancelFullScreen || document.msExitFullscreen;
    if (!fn) return;
    if (!nativeElement()) return;
    try {
      fn.call(document);
    } catch (e) {
      /* Leaving is best effort; the panels are restored either way. */
    }
  }
  function nativeElement() {
    return document.fullscreenElement || document.webkitFullscreenElement ||
           document.mozFullScreenElement || document.msFullscreenElement;
  }

  function inFrame() {
    try {
      return window.self !== window.top;
    } catch (e) {
      return true;
    }
  }

  /* Measures the overlay against the window. Anything materially
     smaller means the overlay is trapped inside the page layout rather
     than covering it. */
  function overlayCovers() {
    if (!overlay) return false;
    var box = overlay.getBoundingClientRect();
    return box.width >= window.innerWidth - 2 &&
           box.height >= window.innerHeight - 2;
  }

  function reportTrouble(nativeAvailable, nativeGranted) {
    var old = document.getElementById("fs-trouble");
    if (old) old.remove();
    var note = document.createElement("div");
    note.id = "fs-trouble";
    note.setAttribute("role", "alert");
    var why;
    if (inFrame() && !nativeGranted) {
      why = "This page is running inside a frame, such as the viewer " +
        "pane of an editor, where browsers block full screen. Open the " +
        "app in a browser window instead.";
    } else if (!nativeAvailable) {
      why = "This browser does not offer a full screen mode to the page.";
    } else {
      why = "The browser declined the request and the fallback could " +
        "not cover the window.";
    }
    note.textContent = "Full screen could not open. " + why;
    var close = document.createElement("button");
    close.type = "button";
    close.textContent = "Dismiss";
    close.className = "btn";
    close.addEventListener("click", function () { note.remove(); });
    note.appendChild(close);
    document.body.appendChild(note);
  }

  function apply() {
    var p = panel(), r = reading();
    if (!p || !r) return;
    var nativeAvailable = false, nativeGranted = false;
    if (on && !overlayActive()) {
      enter(p, r);
      buildOverlayControls();
      buildPanelChrome(r);
      var req = requestNative(overlay);
      nativeAvailable = req !== null;
      if (req && typeof req.then === "function") {
        req.then(function () { nativeGranted = true; })
           .catch(function () { /* the overlay is the fallback */ });
      }
    } else if (!on && overlayActive()) {
      exitNative();
      stripPanelChrome(r);
      leave(p, r);
      var stale = document.getElementById("fs-trouble");
      if (stale) stale.remove();
    }

    p.classList.toggle("fullscreen", on);
    document.body.classList.toggle("map-fullscreen", on);
    r.classList.toggle("floating-reading", on);
    r.classList.toggle("see-through", on && seeThrough);
    setLabels();
    if (window.Shiny) {
      Shiny.setInputValue("fullscreen_on", on);
    }
    /* The drawing area changed size, so the view is refitted to keep
       the whole network on screen. */
    window.dispatchEvent(new Event("resize"));

    /* Checked on the next frame, after layout has settled. */
    if (on && window.requestAnimationFrame) {
      window.requestAnimationFrame(function () {
        if (!overlayCovers() && !nativeElement()) {
          reportTrouble(nativeAvailable, nativeGranted);
        }
      });
    }
  }

  /* Leaving full screen through the browser, by Escape or by its own
     control, must put the panels back too. */
  ["fullscreenchange", "webkitfullscreenchange", "mozfullscreenchange",
   "MSFullscreenChange"].forEach(function (evt) {
    document.addEventListener(evt, function () {
      if (!nativeElement() && on) {
        on = false;
        apply();
      }
    });
  });

  /* The toggle lives in the control row, which Shiny re-renders when the
     network changes, so the click is caught at the document level rather
     than bound to an element that may be replaced. */
  document.addEventListener("click", function (ev) {
    /* Either handle answers. The control in the row above the map keeps
       its id, since that is what the suites and any bookmarklet reach
       for, and the copy on the map carries the attribute, because two
       elements cannot share an id. Matching both means neither control
       depends on the other being present. */
    var hit = ev.target.closest("#fs-toggle, [data-fs-toggle]");
    if (hit) { on = !on; apply(); return; }
    if (ev.target.closest("#fs-exit")) { on = false; apply(); return; }
    var see = ev.target.closest("#fs-transparent");
    if (see) { seeThrough = !seeThrough; apply(); }
  });

  /* Both full screen controls live inside the overlay, because a native
     full screen element is the only thing the browser paints. A control
     placed anywhere else is invisible at exactly the moment it is
     needed, which left Escape as the only way out. */
  function buildOverlayControls() {
    if (!overlay || overlay.querySelector(".fs-bar")) return;
    var bar = document.createElement("div");
    bar.className = "fs-bar";

    var see = document.createElement("button");
    see.id = "fs-transparent";
    see.type = "button";
    see.className = "btn fs-bar-btn fs-icon-btn";
    see.setAttribute("aria-pressed", "false");

    var exit = document.createElement("button");
    exit.id = "fs-exit";
    exit.type = "button";
    exit.className = "btn fs-bar-btn fs-icon-btn fs-exit";
    /* The same four corners as the control that enters full screen,
       turned inward and crossed, so the pair reads as one idea in two
       states rather than as an icon and a sentence. */
    exit.innerHTML = '<svg viewBox="0 0 20 20" aria-hidden="true" ' +
      'class="map-icon" fill="none" stroke="currentColor" ' +
      'stroke-width="1.8" stroke-linecap="round">' +
      '<path d="M8 3v5H3M17 8h-5V3M12 17v-5h5M3 12h5v5"/></svg>';
    exit.title = "Exit full screen (Escape)";
    exit.setAttribute("aria-label",
      "Exit full screen. The Escape key also works.");

    bar.appendChild(see);
    bar.appendChild(exit);
    overlay.appendChild(bar);
  }

  /* Escape leaves full screen, which is what every full screen view
     trains people to expect. */
  document.addEventListener("keydown", function (ev) {
    if (ev.key === "Escape" && on) { on = false; apply(); }
  });

  document.addEventListener("tessera:map-rendered", setLabels);

  document.addEventListener("tessera:map-cleared", function () {
    if (on) { on = false; apply(); }
  });

  function ready() { setLabels(); }
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", ready);
  } else {
    ready();
  }
})();
