/* layout.js
   A force layout that runs in the browser, so the map can be pushed
   around while it is being read.

   The server already computes a layout in three passes and sends
   coordinates, and that layout is better than anything a few hundred
   frames of physics will find, because it knows about the communities
   and it separates overlapping nodes at the end. This file is not a
   replacement for it. It is for the other thing a reader wants, which
   is to take hold of a node, pull it out of the knot it is sitting in,
   and watch what it is attached to follow.

   Why this rather than a library. The map is already rendered by hand
   here, in the app's own shapes and palettes, with keyboard access and
   a full screen mode built around it. A library that owns the drawing
   would have to be given all of that back, one setting at a time, in
   every one of the ten appearance states this app supports. What a
   library would actually have supplied is the physics, which is this
   file, and the physics is the part with a published algorithm.

   The algorithm is Barnes and Hut (1986). Repulsion between every pair
   of nodes is the expensive term: done directly it is one calculation
   per pair, so ten times the nodes is a hundred times the work, which
   is exactly the wall people hit with interactive network plots. Barnes
   and Hut group distant nodes into a quadtree cell and treat the cell
   as one body, which turns the same term into node count times the log
   of node count. The accuracy of the approximation is one number,
   theta, below.

   Nothing here touches the DOM. It takes an array of positions, moves
   them, and stops. The renderer decides what to do about that. */

(function (root, factory) {
  "use strict";
  var api = factory();
  /* The browser gets a global; Node gets an export, because the
     benchmark and the tests run without a browser. */
  if (typeof module === "object" && module.exports) module.exports = api;
  if (root) root.TesseraLayout = api;
}(typeof self !== "undefined" ? self : null, function () {
  "use strict";

  /* Barnes and Hut's opening angle. A cell is treated as one body when
     its width divided by its distance is under this. Zero is an exact
     calculation and infinitely slow; one is fast and visibly wrong.
     The usual value is 0.9, and the usual value is right here. */
  var THETA = 0.9;

  /* How much of its speed a node keeps between frames. Below about 0.6
     the map stops before it has arranged itself; above about 0.95 it
     oscillates and never settles. */
  var FRICTION = 0.86;

  /* When the largest movement in a frame falls under this many world
     units, the arrangement has stopped changing in any way a reader
     could see, and the simulation stops on its own. A simulation that
     runs forever is a fan that runs forever. */
  var REST = 0.4;

  /* Cooling.

     Friction alone does not settle a network. Every arrangement has
     forces still pulling on it at rest, since a spring wanting to be
     seventy units long and a repulsion wanting to be further apart
     never both get their way, so the leftover pull keeps shuffling
     nodes back and forth by a pixel forever. That shuffle is what a
     reader sees as jitter, and it never stops on its own because
     nothing about it is decaying.

     So the forces are scaled by a temperature that falls a little every
     frame. Early on the map arranges itself freely; later the same
     leftover pull moves nothing, and the whole thing comes to a stop
     and stays there. Taking hold of a node reheats it, because a drag
     is a new question and deserves a fresh answer.

     This is the same device simulated annealing uses, and the same one
     the alpha parameter does in d3-force. */
  var COOLING = 0.985;
  var REHEAT = 0.55;
  var COLD = 0.02;

  /* ---- The quadtree ------------------------------------------------ */

  function makeCell(x, y, size) {
    return {
      x: x, y: y, size: size,
      mass: 0, cx: 0, cy: 0,
      body: null,        /* the single node here, while there is one */
      children: null
    };
  }

  function quadrantOf(cell, node) {
    var half = cell.size / 2;
    return (node.x >= cell.x + half ? 1 : 0) +
           (node.y >= cell.y + half ? 2 : 0);
  }

  function subdivide(cell) {
    var half = cell.size / 2;
    cell.children = [
      makeCell(cell.x, cell.y, half),
      makeCell(cell.x + half, cell.y, half),
      makeCell(cell.x, cell.y + half, half),
      makeCell(cell.x + half, cell.y + half, half)
    ];
  }

  function insert(cell, node, depth) {
    /* Two nodes at the same coordinates would subdivide forever, so the
       recursion is capped and the deepest cell simply holds both. This
       happens more often than it sounds: an uploaded file with repeated
       ties can put two people on the same point. */
    if (depth > 24) {
      cell.mass += 1;
      cell.cx += node.x;
      cell.cy += node.y;
      return;
    }
    if (cell.mass === 0 && cell.children === null) {
      cell.body = node;
      cell.mass = 1;
      cell.cx = node.x;
      cell.cy = node.y;
      return;
    }
    if (cell.children === null) {
      var held = cell.body;
      cell.body = null;
      subdivide(cell);
      insert(cell.children[quadrantOf(cell, held)], held, depth + 1);
    }
    cell.mass += 1;
    cell.cx += node.x;
    cell.cy += node.y;
    insert(cell.children[quadrantOf(cell, node)], node, depth + 1);
  }

  function build(nodes) {
    var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    nodes.forEach(function (n) {
      if (n.x < minX) minX = n.x;
      if (n.y < minY) minY = n.y;
      if (n.x > maxX) maxX = n.x;
      if (n.y > maxY) maxY = n.y;
    });
    if (!isFinite(minX)) return null;
    var size = Math.max(maxX - minX, maxY - minY, 1) * 1.05;
    var root = makeCell(minX, minY, size);
    nodes.forEach(function (n) { insert(root, n, 0); });
    return root;
  }

  /* The repulsion one node feels from a whole cell. A cell far enough
     away is one body at its center of mass; a cell that is too close is
     opened and its children are asked instead. */
  function repel(cell, node, strength, out) {
    if (cell === null || cell.mass === 0) return;
    if (cell.body === node && cell.mass === 1) return;
    var cx = cell.body ? cell.body.x : cell.cx / cell.mass;
    var cy = cell.body ? cell.body.y : cell.cy / cell.mass;
    var dx = node.x - cx;
    var dy = node.y - cy;
    var distance2 = dx * dx + dy * dy;
    /* A floor on the distance keeps two nodes that land on the same
       point from being thrown to opposite ends of the world. */
    if (distance2 < 1e-4) {
      distance2 = 1e-4;
      dx = (Math.random() - 0.5) * 0.01;
      dy = (Math.random() - 0.5) * 0.01;
    }
    if (cell.children === null || (cell.size * cell.size) / distance2 <
        THETA * THETA) {
      var force = (strength * cell.mass) / distance2;
      out.x += dx * force;
      out.y += dy * force;
      return;
    }
    for (var i = 0; i < 4; i += 1) {
      repel(cell.children[i], node, strength, out);
    }
  }

  /* ---- The simulation ---------------------------------------------- */

  /* nodes: objects carrying x and y, which this mutates in place.
     edges: pairs of indices into that array.

     The tuning defaults are for a map in the app's world coordinates,
     which run zero to a thousand on a side. */
  function create(nodes, edges, options) {
    options = options || {};
    var repulsion = options.repulsion === undefined ? 2400 : options.repulsion;
    var springLength = options.springLength === undefined
      ? 70 : options.springLength;
    var springStrength = options.springStrength === undefined
      ? 0.035 : options.springStrength;
    var gravity = options.gravity === undefined ? 0.012 : options.gravity;
    var friction = options.friction === undefined ? FRICTION : options.friction;
    var rest = options.rest === undefined ? REST : options.rest;

    nodes.forEach(function (n) {
      if (typeof n.vx !== "number") n.vx = 0;
      if (typeof n.vy !== "number") n.vy = 0;
    });

    var centerX = 0, centerY = 0;
    nodes.forEach(function (n) { centerX += n.x; centerY += n.y; });
    if (nodes.length > 0) {
      centerX /= nodes.length;
      centerY /= nodes.length;
    }

    var api = {
      nodes: nodes,
      edges: edges,
      /* A pinned node is held where it is and pulls its neighbors
         toward it. Dragging pins for the length of the drag, and a
         reader can pin one for good. */
      pinned: {},
      atRest: false,
      heat: 1,

      pin: function (index) { api.pinned[index] = true; },
      unpin: function (index) { delete api.pinned[index]; },
      unpinAll: function () { api.pinned = {}; },

      /* Warms the map back up. Anything that changes the question the
         arrangement is answering calls this: a drag, a node pinned or
         released, a change to how far apart things should sit. */
      reheat: function (amount) {
        api.heat = Math.max(api.heat, amount === undefined ? REHEAT : amount);
        api.atRest = false;
      },

      /* How far apart the arrangement should hold people. Reheats,
         because the answer it was settling on is no longer the one
         being asked for. */
      setSpread: function (value) {
        repulsion = value;
        springLength = 40 + value / 60;
        api.reheat(0.8);
      },

      /* One frame. Returns the largest distance any node moved, so the
         caller can decide to stop. */
      step: function () {
        if (api.heat < COLD) {
          api.atRest = true;
          return 0;
        }
        var tree = build(nodes);
        var force = { x: 0, y: 0 };
        var i, n;

        for (i = 0; i < nodes.length; i += 1) {
          n = nodes[i];
          force.x = 0;
          force.y = 0;
          repel(tree, n, repulsion, force);
          /* A pull toward the middle, so a piece with no ties to the
             rest does not drift off the map forever. */
          force.x += (centerX - n.x) * gravity;
          force.y += (centerY - n.y) * gravity;
          n.fx = force.x;
          n.fy = force.y;
        }

        for (i = 0; i < edges.length; i += 1) {
          var a = nodes[edges[i][0]];
          var b = nodes[edges[i][1]];
          if (!a || !b) continue;
          var dx = b.x - a.x;
          var dy = b.y - a.y;
          var distance = Math.sqrt(dx * dx + dy * dy) || 0.001;
          var pull = (distance - springLength) * springStrength;
          var ux = (dx / distance) * pull;
          var uy = (dy / distance) * pull;
          a.fx += ux;
          a.fy += uy;
          b.fx -= ux;
          b.fy -= uy;
        }

        var largest = 0;
        for (i = 0; i < nodes.length; i += 1) {
          n = nodes[i];
          if (api.pinned[i]) {
            n.vx = 0;
            n.vy = 0;
            continue;
          }
          n.vx = (n.vx + n.fx * api.heat) * friction;
          n.vy = (n.vy + n.fy * api.heat) * friction;
          /* A speed limit. Without it a node that starts on top of
             another is thrown across the map in one frame and the whole
             arrangement has to recover from it. */
          var speed = Math.sqrt(n.vx * n.vx + n.vy * n.vy);
          if (speed > 30) {
            n.vx = (n.vx / speed) * 30;
            n.vy = (n.vy / speed) * 30;
            speed = 30;
          }
          n.x += n.vx;
          n.y += n.vy;
          if (speed > largest) largest = speed;
        }
        api.heat *= COOLING;
        api.atRest = api.heat < COLD || largest < rest;
        return largest;
      },

      /* Runs until it settles or until the frame budget runs out.
         Returns the number of frames taken. */
      /* Runs the whole arrangement without showing any of it. Watching
         a network shuffle itself into place is worth seeing once; on
         the tenth time a reader wants the answer. */
      settle: function (maxFrames) {
        var limit = maxFrames || 400;
        var frames = 0;
        while (frames < limit) {
          frames += 1;
          if (api.step() < rest || api.atRest) break;
        }
        return frames;
      }
    };
    return api;
  }

  /* What a network of this size costs per frame, in the terms that
     decide whether live layout is offered at all. Measured on the
     machine the app is running on rather than assumed, because the
     answer is different on a laptop and on a phone.

     The renderer calls this once and turns live layout off above the
     size where a frame stops fitting in a frame. */
  function measure(nodeCount, edgeCount, frames) {
    var nodes = [];
    var i;
    for (i = 0; i < nodeCount; i += 1) {
      nodes.push({ x: Math.random() * 1000, y: Math.random() * 1000 });
    }
    var edges = [];
    for (i = 0; i < edgeCount; i += 1) {
      edges.push([
        Math.floor(Math.random() * nodeCount),
        Math.floor(Math.random() * nodeCount)
      ]);
    }
    var sim = create(nodes, edges);
    var count = frames || 20;
    var started = Date.now();
    for (i = 0; i < count; i += 1) sim.step();
    return (Date.now() - started) / count;
  }

  return { create: create, measure: measure, THETA: THETA };
}));
