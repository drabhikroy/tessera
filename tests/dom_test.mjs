// dom_test.mjs
// Loads the real renderer inside jsdom with a Shiny stub, feeds it the
// same wire format the server sends, and asserts on the resulting SVG.
// This is the test that would have caught the blank map: the renderer
// is exercised end to end without a browser.

import { JSDOM } from "jsdom";
import { readFileSync } from "fs";
import assert from "assert";

const dom = new JSDOM(
  '<body><div id="map-host"></div></body>',
  { pretendToBeVisual: true, runScripts: "outside-only" }
);
const { window } = dom;

// Minimal Shiny stand in: handlers register, inputs record.
const handlers = {};
const inputs = {};
function makeShinyStub(handlers, inputs) {
  return {
    addCustomMessageHandler: (name, fn) => {
      // Shiny itself refuses a handler that does not take exactly one
      // argument, and the refusal throws, which aborts the rest of the
      // file. Reproducing that here is the whole point of this stub.
      if (typeof fn !== "function" || fn.length !== 1) {
        throw new Error(
          "handler must be a function that takes one argument: " + name);
      }
      handlers[name] = fn;
    },
    setInputValue: (name, value) => { inputs[name] = value; }
  };
}

window.Shiny = makeShinyStub(handlers, inputs);
window.matchMedia = () => ({ matches: true });

global.window = window;
global.document = window.document;

const code = readFileSync("www/graph.js", "utf8");
try {
  window.eval(code);
  window.document.dispatchEvent(new window.Event("DOMContentLoaded"));
} catch (err) {
  console.log("FAIL the client script threw while loading: " + err.message);
  console.log("\nEverything defined below the throw never runs, which is " +
    "how a whole module can vanish without a visible error.");
  process.exit(1);
}

let pass = 0, fail = 0;
const check = (label, ok) => {
  if (ok) { pass++; console.log("ok  ", label); }
  else { fail++; console.log("FAIL", label); }
};

// A small network in the exact row record format payload_wire() sends:
// four people, two groups, one cut point, spanning two shape kinds.
const payload = {
  nodes: [
    { id: 1, label: "Ada",  x: 0.1, y: 0.1, degree: 2, between: 0.5,
      close: 0.8, eigen: 0.9, group: 1, is_cut: false },
    { id: 2, label: "Bez",  x: 0.9, y: 0.1, degree: 3, between: 0.9,
      close: 0.9, eigen: 1.0, group: 1, is_cut: true },
    { id: 3, label: "Cato", x: 0.9, y: 0.9, degree: 2, between: 0.0,
      close: 0.6, eigen: 0.4, group: 2, is_cut: false },
    { id: 4, label: "Didi", x: 0.1, y: 0.9, degree: 1, between: 0.0,
      close: 0.5, eigen: 0.2, group: 2, is_cut: false }
  ],
  edges: [
    { from: 1, to: 2, weight: 2 },
    { from: 2, to: 3, weight: 1 },
    { from: 3, to: 4, weight: 3 },
    { from: 1, to: 3, weight: 1 }
  ],
  meta: { n: 4, m: 4, n_groups: 2 }
};

handlers["graph-data"](payload);

const svg = window.document.getElementById("network-map");
check("the map svg exists after data arrives", !!svg);
check("all four people render", svg.querySelectorAll(".node").length === 4);
check("all four ties render as curved paths",
  svg.querySelectorAll("g:first-child path").length === 4);

// The shape regression: a group 2 square must sit at its own center,
// not at the origin corner.
const square = svg.querySelector(".node.group-2 .mark");
const d = square.getAttribute("d");
const firstX = parseFloat(d.slice(1).split(",")[0]);
check("square shape is placed at its center, not the corner",
  firstX > 700);
check("the cut point carries its warning ring",
  !!svg.querySelector(".node.cut .cut-ring"));
check("nodes are keyboard stops with spoken labels",
  svg.querySelectorAll('.node[tabindex="0"][aria-label]').length === 4);

// Column form healing: the same data sent the broken way still renders.
handlers["graph-data"]({
  nodes: {
    id: [1, 2], label: ["A", "B"], x: [0.2, 0.8], y: [0.5, 0.5],
    degree: [1, 1], between: [0, 0], close: [1, 1], eigen: [1, 1],
    group: [1, 1], is_cut: [false, false]
  },
  edges: { from: [1], to: [2], weight: [1] },
  meta: { n: 2, m: 1, n_groups: 1 }
});
check("column form data heals into a rendered map",
  window.document.querySelectorAll("#network-map .node").length === 2);

// Interaction: reload the full payload, then select and verify the
// spotlight dims exactly the out of reach person at depth one.
handlers["graph-data"](payload);
handlers["select-node"](1);
const dimmed = [...window.document.querySelectorAll(".node.dim")]
  .map((el) => el.getAttribute("data-id"));
check("depth one spotlight dims only the person two steps out",
  dimmed.length === 1 && dimmed[0] === "4");
check("the server hears about the selection", inputs.selected_node === 1);

handlers["reach-depth"](2);
check("depth two brings everyone into reach",
  window.document.querySelectorAll(".node.dim").length === 0);

handlers["focus-group"](2);
const litIds = [...window.document.querySelectorAll(".node:not(.dim)")]
  .map((el) => el.getAttribute("data-id")).sort();
check("group focus lights exactly that group",
  litIds.join(",") === "3,4");

handlers["label-mode"]("none");
handlers["clear-selection"]();
check("label mode none hides every label",
  window.document.querySelectorAll(".node-label.hide").length === 4);

// The view fits the network with a margin, so the fitted viewBox is
// larger than the node spread but not the whole world square.
handlers["graph-data"](payload);
const vb = window.document.getElementById("network-map")
  .getAttribute("viewBox").split(" ").map(Number);
check("the fitted view is a bounded square, not the raw world",
  vb[2] > 100 && vb[2] < 2200 && vb[2] === vb[3]);

// Dragging a node moves it and redraws its ties. Simulate a pointer
// press, a move past the threshold, and a release, then confirm the
// node center and an incident edge endpoint both moved.
const map = window.document.getElementById("network-map");
const nodeEl = map.querySelector('.node[data-id="1"]');
const beforeLabel = nodeEl.querySelector(".node-label").getAttribute("x");
function pointer(type, x, y) {
  const ev = new window.Event(type, { bubbles: true });
  ev.clientX = x; ev.clientY = y; ev.pointerId = 1;
  nodeEl.dispatchEvent(ev);
}
nodeEl.setPointerCapture = () => {};
nodeEl.releasePointerCapture = () => {};
map.getBoundingClientRect = () => ({ left: 0, top: 0, width: 500, height: 500 });
const incident = map.querySelector('path[data-from="1"], path[data-to="1"]');
const edgeBefore = incident.getAttribute("d");
pointer("pointerdown", 50, 50);
pointer("pointermove", 200, 200);
pointer("pointerup", 200, 200);
const afterLabel = nodeEl.querySelector(".node-label").getAttribute("x");
check("dragging a node moves it", beforeLabel !== afterLabel);
check("an incident tie follows the dragged node",
  edgeBefore !== incident.getAttribute("d"));

// A press with no movement is still a click that selects.
pointer("pointerdown", 60, 60);
pointer("pointerup", 61, 61);
check("a press without movement still selects the person",
  inputs.selected_node === 1);

// The glyph system: many groups stay visually distinct. Build a payload
// with thirty six groups and confirm no two share a shape, variant, and
// color triple, which is what keeps them apart on screen.
const manyNodes = [];
const manyEdges = [];
for (let i = 1; i <= 36; i++) {
  manyNodes.push({ id: i, label: "P" + i, x: (i % 6) / 6, y: Math.floor(i / 6) / 6,
    degree: 1, between: 0, close: 1, eigen: 1, group: i, is_cut: false });
  if (i > 1) manyEdges.push({ from: i - 1, to: i, weight: 1 });
}
handlers["graph-data"]({ nodes: manyNodes, edges: manyEdges,
  meta: { n: 36, m: 35, n_groups: 36 } });
const seen = new Set();
[...window.document.querySelectorAll("#network-map .node")].forEach((el) => {
  const cls = [...el.classList];
  const color = cls.find((c) => c.startsWith("color-"));
  const variant = cls.find((c) => c.startsWith("var-"));
  const mark = el.querySelector(".mark");
  const shape = mark.tagName === "circle" ? "circle" : mark.getAttribute("d");
  seen.add(color + "|" + variant + "|" + shape);
});
check("thirty six groups get thirty six distinct glyphs", seen.size === 36);
check("groups past twelve use fill variants, not repeats",
  window.document.querySelectorAll("#network-map .node.var-1").length === 12 &&
  window.document.querySelectorAll("#network-map .node.var-2").length === 12);
check("variant two draws a centered pip",
  window.document.querySelectorAll("#network-map .node.var-2 .pip").length === 12);

// Full screen: the toggle moves the map and reading panel into the
// overlay layout, and Escape restores the split view.
// The panels are nested the way the real app nests them, several
// containers deep, because that nesting is what broke the overlay.
const shell = window.document.createElement("div");
shell.innerHTML =
  '<div class="tab-content"><div class="tab-pane">' +
  '<div class="control-row">' +
  '<button id="fs-toggle" type="button">Full screen</button></div>' +
  '<div class="main-grid"><div class="map-panel"></div>' +
  '<div class="reading-panel"></div></div></div></div>';
window.document.body.appendChild(shell);
window.document.dispatchEvent(new window.CustomEvent("tessera:map-rendered"));
const fsBtn = window.document.getElementById("fs-toggle");
check("the full screen control is present in the interface", !!fsBtn);

const mapPanel = window.document.querySelector(".map-panel");
const readPanel = window.document.querySelector(".reading-panel");
const gridBefore = mapPanel.parentElement;

fsBtn.dispatchEvent(new window.Event("click", { bubbles: true }));
check("full screen expands the map and floats the reading panel",
  mapPanel.classList.contains("fullscreen") &&
  readPanel.classList.contains("floating-reading"));
// The overlay must be a direct child of the body, or a transform on any
// ancestor would trap it inside the page layout instead of covering it.
const overlay = window.document.getElementById("fs-overlay");
check("an overlay is attached directly to the body",
  !!overlay && overlay.parentElement === window.document.body);
check("both panels move into the overlay",
  mapPanel.parentElement === overlay &&
  readPanel.parentElement === overlay);
check("the toggle reports its state for assistive technology",
  fsBtn.getAttribute("aria-pressed") === "true" &&
  fsBtn.textContent === "Exit full screen");
const seeBtn = window.document.getElementById("fs-transparent");
seeBtn.dispatchEvent(new window.Event("click", { bubbles: true }));
check("the floating panel can be made see through",
  window.document.querySelector(".reading-panel").classList.contains("see-through"));
const esc = new window.Event("keydown", { bubbles: true });
esc.key = "Escape";
window.document.dispatchEvent(esc);
check("Escape leaves full screen",
  !mapPanel.classList.contains("fullscreen"));
check("the overlay is removed on leaving",
  !window.document.getElementById("fs-overlay"));
check("the panels return to where they came from",
  mapPanel.parentElement === gridBefore &&
  readPanel.parentElement === gridBefore);
check("the map still precedes the reading panel after returning",
  mapPanel.nextElementSibling === readPanel);

// Changing the data source away from a loaded network must wipe the
// map rather than leaving the previous one on screen.
handlers["graph-data"](payload);
check("a map is present before clearing",
  !!window.document.getElementById("network-map"));
handlers["clear-graph"]();
check("clearing removes the drawing",
  !window.document.getElementById("network-map"));
check("clearing leaves full screen behind",
  !window.document.querySelector(".map-panel.fullscreen"));

// When the overlay cannot cover the window, the control says so. The
// simulated browser reports a zero sized overlay, which is exactly the
// condition the check exists to catch.
window.requestAnimationFrame = (fn) => fn();
window.innerWidth = 1200;
window.innerHeight = 800;
const btn2 = window.document.getElementById("fs-toggle");
if (btn2) {
  btn2.dispatchEvent(new window.Event("click", { bubbles: true }));
  check("a full screen that does not cover the window reports itself",
    !!window.document.getElementById("fs-trouble"));
  btn2.dispatchEvent(new window.Event("click", { bubbles: true }));
  check("the report clears on leaving full screen",
    !window.document.getElementById("fs-trouble"));
}

// The whole client script must load without throwing. A handler that
// does not take exactly one argument aborts the file at that point, and
// everything defined below it, including entire modules, never runs.
const probe = new JSDOM('<body><div id="map-host"></div></body>',
  { pretendToBeVisual: true, runScripts: "outside-only" });
probe.window.matchMedia = () => ({ matches: true });
const probeHandlers = {}, probeInputs = {};
probe.window.Shiny = makeShinyStub(probeHandlers, probeInputs);
let loadError = null;
try {
  probe.window.eval(code);
  probe.window.document.dispatchEvent(
    new probe.window.Event("DOMContentLoaded"));
} catch (err) {
  loadError = err.message;
}
check("the client script loads without throwing", loadError === null);
check("every message handler takes exactly one argument",
  Object.values(probeHandlers).every((fn) => fn.length === 1));
check("the handlers defined after the first clear one still register",
  !!probeHandlers["clear-selection"] && !!probeHandlers["clear-graph"]);

console.log("\n" + pass + " passed, " + fail + " failed");
process.exit(fail > 0 ? 1 : 0);
