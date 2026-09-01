// layout_test.mjs
/* The force layout, checked for correctness and then measured.
 *
 * The measurement is the point. The question that started this was
 * whether an interactive network plot slows the app down, and that is
 * not a question anyone should answer from memory of a library they
 * used a few years ago. It is a number, it is different on every
 * machine, and it is cheap to take.
 *
 * Run with: node tests/layout_test.mjs
 */

import { createRequire } from "node:module";
import assert from "node:assert";

const require = createRequire(import.meta.url);
const Layout = require("../www/layout.js");

let pass = 0;
let fail = 0;
function check(label, run) {
  try {
    run();
    pass += 1;
    console.log("ok  ", label);
  } catch (error) {
    fail += 1;
    console.log("FAIL", label, "\n     ", error.message);
  }
}

/* A ring of nodes started on top of one another has one arrangement
   the forces can reach: a ring. This is the check that the springs and
   the repulsion are pulling against each other rather than one of them
   doing nothing. */
check("nodes that start on one point spread out", () => {
  const nodes = [];
  const edges = [];
  const n = 24;
  for (let i = 0; i < n; i += 1) {
    nodes.push({ x: 500 + Math.random() * 0.5, y: 500 + Math.random() * 0.5 });
    edges.push([i, (i + 1) % n]);
  }
  const sim = Layout.create(nodes, edges);
  sim.settle(600);
  let smallest = Infinity;
  for (let i = 0; i < n; i += 1) {
    for (let j = i + 1; j < n; j += 1) {
      const d = Math.hypot(nodes[i].x - nodes[j].x, nodes[i].y - nodes[j].y);
      if (d < smallest) smallest = d;
    }
  }
  assert.ok(smallest > 5, `closest pair is ${smallest.toFixed(2)} apart`);
  nodes.forEach((node) => {
    assert.ok(Number.isFinite(node.x) && Number.isFinite(node.y),
      "a coordinate went to infinity or to not a number");
  });
});

/* Two groups joined by one tie have to end up as two groups. If the
   repulsion were being applied to the wrong nodes, or the quadtree were
   returning the wrong cell, this is where it would show. */
check("two joined groups settle as two groups", () => {
  const nodes = [];
  const edges = [];
  for (let i = 0; i < 16; i += 1) {
    nodes.push({ x: 400 + Math.random() * 200, y: 400 + Math.random() * 200 });
  }
  for (let i = 0; i < 8; i += 1) {
    for (let j = i + 1; j < 8; j += 1) edges.push([i, j]);
  }
  for (let i = 8; i < 16; i += 1) {
    for (let j = i + 1; j < 16; j += 1) edges.push([i, j]);
  }
  edges.push([0, 8]);
  const sim = Layout.create(nodes, edges);
  sim.settle(800);

  const spread = (from, to) => {
    let sum = 0;
    let count = 0;
    for (let i = from; i < to; i += 1) {
      for (let j = i + 1; j < to; j += 1) {
        sum += Math.hypot(nodes[i].x - nodes[j].x, nodes[i].y - nodes[j].y);
        count += 1;
      }
    }
    return sum / count;
  };
  const middle = (from, to) => {
    let x = 0;
    let y = 0;
    for (let i = from; i < to; i += 1) {
      x += nodes[i].x;
      y += nodes[i].y;
    }
    return { x: x / (to - from), y: y / (to - from) };
  };
  const a = middle(0, 8);
  const b = middle(8, 16);
  const between = Math.hypot(a.x - b.x, a.y - b.y);
  const within = (spread(0, 8) + spread(8, 16)) / 2;
  assert.ok(between > within,
    `groups sit ${between.toFixed(1)} apart but are ${within.toFixed(1)} wide`);
});

/* A pinned node is what dragging uses. It has to stay exactly where it
   was put while everything around it moves. */
check("a pinned node does not move", () => {
  const nodes = [];
  const edges = [];
  for (let i = 0; i < 20; i += 1) {
    nodes.push({ x: Math.random() * 1000, y: Math.random() * 1000 });
    if (i > 0) edges.push([0, i]);
  }
  nodes[0].x = 123;
  nodes[0].y = 456;
  const sim = Layout.create(nodes, edges);
  sim.pin(0);
  sim.settle(200);
  assert.strictEqual(nodes[0].x, 123);
  assert.strictEqual(nodes[0].y, 456);
  const moved = nodes.slice(1).some((n) => Math.abs(n.x - 500) > 1);
  assert.ok(moved, "nothing around the pinned node moved at all");
});

/* An arrangement that has stopped changing says so, rather than being
   run forever by a caller with no way to tell. */
check("a settled simulation reports that it is at rest", () => {
  const nodes = [{ x: 0, y: 0 }, { x: 70, y: 0 }, { x: 35, y: 60 }];
  const edges = [[0, 1], [1, 2], [0, 2]];
  const sim = Layout.create(nodes, edges);
  const frames = sim.settle(2000);
  assert.ok(sim.atRest, `still moving after ${frames} frames`);
});

/* An empty network and a single node are both things an upload can be,
   and neither may throw. */
check("an empty network and a lone node are handled", () => {
  assert.doesNotThrow(() => Layout.create([], []).step());
  assert.doesNotThrow(() => Layout.create([{ x: 1, y: 1 }], []).settle(10));
});

/* ---- The measurement --------------------------------------------- */

/* Barnes and Hut turns the repulsion term from one calculation per
   pair into node count times the log of node count. Doubling the nodes
   should therefore cost a little over twice as much, not four times.
   Checking the shape rather than a fixed millisecond number keeps this
   from failing on a slower machine for no reason. */
check("cost grows close to linearly rather than quadratically", () => {
  const small = Layout.measure(500, 1500, 12);
  const large = Layout.measure(2000, 6000, 12);
  const growth = large / Math.max(small, 0.0001);
  /* Four times the nodes. Quadratic would be sixteen. */
  assert.ok(growth < 9,
    `four times the nodes cost ${growth.toFixed(1)} times as much`);
});

console.log("\nCost of one frame, on this machine:");
[
  [100, 300], [300, 900], [500, 1500], [1000, 3000],
  [2000, 6000], [5000, 15000]
].forEach(([n, m]) => {
  const ms = Layout.measure(n, m, 12);
  const budget = ms <= 16 ? "inside a frame"
    : ms <= 33 ? "half rate"
      : "too slow to run live";
  console.log(
    `  ${String(n).padStart(5)} people, ${String(m).padStart(6)} ties: ` +
    `${ms.toFixed(2)} ms per frame  (${budget})`);
});

/* The jitter check.
 *
 * Every arrangement has forces still pulling on it once it has settled:
 * a spring wanting to be seventy units long and a repulsion wanting to
 * be further apart never both get their way. Friction alone does not
 * stop that leftover pull, so nodes shuffle back and forth by a pixel
 * indefinitely, which is what a reader sees as jitter. The cooling has
 * to bring that to nothing and hold it there. */
check("the arrangement stops moving and stays stopped", () => {
  // Seeded, since the test asserts a bound in world units and a random
  // network can settle into a state that meets rest on the temperature
  // but still has visibly moving nodes.
  let seed = 42;
  const random = () => {
    seed = (seed * 9301 + 49297) % 233280;
    return seed / 233280;
  };
  const nodes = [];
  const edges = [];
  for (let i = 0; i < 40; i += 1) {
    nodes.push({ x: random() * 1000, y: random() * 1000 });
  }
  for (let i = 0; i < 40; i += 1) {
    edges.push([i, (i + 1) % 40]);
    edges.push([i, (i + 7) % 40]);
  }
  const sim = Layout.create(nodes, edges);
  sim.settle(2000);
  assert.ok(sim.atRest, "never came to rest");

  // Two hundred more frames must move nothing a reader could see.
  const before = nodes.map((n) => ({ x: n.x, y: n.y }));
  for (let i = 0; i < 200; i += 1) sim.step();
  const moved = Math.max(...nodes.map((n, i) =>
    Math.hypot(n.x - before[i].x, n.y - before[i].y)));
  assert.ok(moved < 0.5,
    `still drifting ${moved.toFixed(3)} units after settling`);
});

/* And a settled map has to wake up when the reader touches it, or a
 * drag on a cold arrangement moves one node and nothing else. */
check("a settled arrangement wakes when it is disturbed", () => {
  const nodes = [];
  const edges = [];
  for (let i = 0; i < 20; i += 1) {
    nodes.push({ x: Math.random() * 400, y: Math.random() * 400 });
    if (i > 0) edges.push([i - 1, i]);
  }
  const sim = Layout.create(nodes, edges);
  sim.settle(2000);
  assert.ok(sim.atRest);

  nodes[0].x += 300;
  sim.reheat();
  assert.ok(!sim.atRest, "stayed cold after being disturbed");
  const before = nodes.slice(1).map((n) => ({ x: n.x, y: n.y }));
  for (let i = 0; i < 60; i += 1) sim.step();
  const moved = Math.max(...nodes.slice(1).map((n, i) =>
    Math.hypot(n.x - before[i].x, n.y - before[i].y)));
  assert.ok(moved > 1, "nothing followed the node that was moved");
});

/* Changing how far apart people should sit is a different question, so
 * it reheats too, and the arrangement has to actually spread out. */
check("asking for more room gives more room", () => {
  const build = () => {
    const nodes = [];
    const edges = [];
    for (let i = 0; i < 24; i += 1) {
      nodes.push({ x: 500 + Math.random() * 20, y: 500 + Math.random() * 20 });
      edges.push([i, (i + 1) % 24]);
    }
    return { nodes, edges };
  };
  const spanOf = (nodes) => {
    const xs = nodes.map((n) => n.x);
    const ys = nodes.map((n) => n.y);
    return Math.max(Math.max(...xs) - Math.min(...xs),
      Math.max(...ys) - Math.min(...ys));
  };
  const tight = build();
  const tightSim = Layout.create(tight.nodes, tight.edges);
  tightSim.setSpread(900);
  tightSim.settle(2000);

  const wide = build();
  const wideSim = Layout.create(wide.nodes, wide.edges);
  wideSim.setSpread(6000);
  wideSim.settle(2000);

  assert.ok(spanOf(wide.nodes) > spanOf(tight.nodes),
    `wide span ${spanOf(wide.nodes).toFixed(0)} is not above ` +
    `tight span ${spanOf(tight.nodes).toFixed(0)}`);
});

console.log(`\n${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
