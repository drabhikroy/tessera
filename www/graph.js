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
    tooltip: null
  };

  var WORLD = 1000;      /* layout coordinates scale to this square */
  var PAD = 70;

  /* Read once at load. A person who changes this system setting mid
     session gets the new behavior on the next render. */
  var reducedMotion = window.matchMedia &&
    window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  /* Wire format guard. The server sends rows, but if a future change
     regresses to column form, the renderer heals it rather than going
     silently blank, which is how this bug hid the first time. */
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

  /* Positions are stored on the node in world units the first time
     they are read, then reused. Dragging edits these directly, so the
     layout the person arranges by hand persists until the next dataset
     loads. */
  function px(node) {
    if (node._x === undefined) node._x = PAD + node.x * (WORLD - 2 * PAD);
    return node._x;
  }
  function py(node) {
    if (node._y === undefined) node._y = PAD + node.y * (WORLD - 2 * PAD);
    return node._y;
  }

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

  function updateLabels() {
    var keys = keyPeople();
    var byId = {};
    state.data.nodes.forEach(function (n) { byId[n.id] = n; });
    state.layerNodes.querySelectorAll(".node").forEach(function (el) {
      var node = byId[Number(el.getAttribute("data-id"))];
      var t = el.querySelector(".node-label");
      if (t) t.classList.toggle("hide", !labelWanted(node, keys));
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
      redrawNode(node);
    });
    g.addEventListener("pointerup", function (ev) {
      g.releasePointerCapture(ev.pointerId);
      if (!moved) {
        select(state.selected === node.id ? null : node.id);
      }
      down = null;
    });
    g.addEventListener("keydown", function (ev) {
      if (ev.key === "Enter" || ev.key === " ") {
        ev.preventDefault();
        select(state.selected === node.id ? null : node.id);
      }
    });
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
    var side = Math.max(w, h);
    var cx = (minX + maxX) / 2, cy = (minY + maxY) / 2;
    return { x: cx - side / 2, y: cy - side / 2, w: side, h: side };
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
    [["+", "Zoom in"], ["\u2212", "Zoom out"], ["\u25CE", "Reset the view"]]
      .forEach(function (spec, i) {
        var b = document.createElement("button");
        b.type = "button";
        b.textContent = spec[0];
        b.setAttribute("aria-label", spec[1]);
        b.title = spec[1];
        b.addEventListener("click", function () {
          var v = state.view;
          if (i === 2) {
            state.view = fitView();
          } else {
            var f = i === 0 ? 0.82 : 1.22;
            var cx = v.x + v.w / 2, cy = v.y + v.h / 2;
            var w = Math.min(Math.max(v.w * f, 140), WORLD * 2.2);
            state.view = { x: cx - w / 2, y: cy - w / 2, w: w, h: w };
          }
          setViewBox();
        });
        bar.appendChild(b);
      });
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

  /* Entering or leaving full screen changes the drawing area, so the
     view is refitted to keep the whole network on screen. */
  window.addEventListener("resize", function () {
    if (!state.data || !state.svg) return;
    state.view = fitView();
    setViewBox();
  });

  function ready() {
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

  function panel() { return document.querySelector(".map-panel"); }
  function reading() { return document.querySelector(".reading-panel"); }

  function setLabels() {
    var b = document.getElementById("fs-toggle");
    if (b) {
      b.textContent = on ? "Exit full screen" : "Full screen";
      b.setAttribute("aria-pressed", on ? "true" : "false");
    }
    var t = document.getElementById("fs-transparent");
    if (t) {
      t.textContent = seeThrough ? "Solid panel" : "See through panel";
      t.setAttribute("aria-pressed", seeThrough ? "true" : "false");
    }
  }

  /* Markers left behind so each panel returns to its original place and
     order when full screen ends. */
  var mapHome = null, readingHome = null, overlay = null;

  function overlayActive() {
    return !!(overlay && overlay.parentNode);
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
      var req = requestNative(overlay);
      nativeAvailable = req !== null;
      if (req && typeof req.then === "function") {
        req.then(function () { nativeGranted = true; })
           .catch(function () { /* the overlay is the fallback */ });
      }
    } else if (!on && overlayActive()) {
      exitNative();
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
    var hit = ev.target.closest("#fs-toggle");
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
    see.className = "btn fs-bar-btn";
    see.setAttribute("aria-pressed", "false");

    var exit = document.createElement("button");
    exit.id = "fs-exit";
    exit.type = "button";
    exit.className = "btn fs-bar-btn fs-exit";
    exit.textContent = "Exit full screen";
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
