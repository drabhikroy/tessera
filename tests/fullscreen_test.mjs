// fullscreen_test.mjs
// Drives the full screen control against the page the server actually
// sends, with the control row rendered as the app renders it and the
// client script fetched from the server. Earlier suites built their own
// markup and passed while the running app did nothing, so this one
// starts from the real thing.
//
// Usage: node tests/fullscreen_test.mjs <page.html> <graph.js> <controls.html>

import { JSDOM } from "jsdom";
import { readFileSync } from "fs";

const [pageFile, scriptFile, controlsFile] = process.argv.slice(2);
const html = readFileSync(pageFile, "utf8");
const script = readFileSync(scriptFile, "utf8");
const controls = readFileSync(controlsFile, "utf8");

const dom = new JSDOM(html, {
  runScripts: "outside-only",
  url: "http://localhost/",
  pretendToBeVisual: true
});
const { window } = dom;
const doc = window.document;

let pass = 0, fail = 0;
const check = (label, ok) => {
  if (ok) { pass++; console.log("ok  ", label); }
  else { fail++; console.log("FAIL", label); }
};

// Put the rendered control row where Shiny would put it.
const slot = doc.querySelector("#view_controls");
check("the control row placeholder exists in the served page", !!slot);
if (slot) slot.innerHTML = controls;

const btn = doc.getElementById("fs-toggle");
check("the full screen control renders inside the control row", !!btn);

// Stubs for the pieces jsdom does not implement. Recording whether the
// browser primitive was asked for is the point of the first check.
let nativeAsked = false;
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

const stubHandlers = {}, stubInputs = {};
window.Shiny = makeShinyStub(stubHandlers, stubInputs);
window.matchMedia = () => ({ matches: false });
window.Element.prototype.requestFullscreen = function () {
  nativeAsked = true;
  return Promise.resolve();
};

// Run the served client script exactly as the browser would.
window.eval(script);
doc.dispatchEvent(new window.Event("DOMContentLoaded"));

const mapPanel = doc.querySelector(".map-panel");
const readPanel = doc.querySelector(".reading-panel");
check("the map panel is present in the served page", !!mapPanel);
check("the reading panel is present in the served page", !!readPanel);

const homeBefore = mapPanel && mapPanel.parentElement;

if (btn && mapPanel && readPanel) {
  btn.dispatchEvent(new window.Event("click", { bubbles: true }));

  check("the click reaches the handler and the overlay is created",
    !!doc.getElementById("fs-overlay"));
  check("the overlay is attached directly to the body",
    doc.getElementById("fs-overlay") &&
    doc.getElementById("fs-overlay").parentElement === doc.body);
  check("both panels move into the overlay",
    mapPanel.parentElement === doc.getElementById("fs-overlay") &&
    readPanel.parentElement === doc.getElementById("fs-overlay"));
  check("the browser full screen primitive is requested", nativeAsked);
  check("the control reports its new state",
    btn.getAttribute("aria-pressed") === "true" &&
    btn.textContent === "Exit full screen");

  btn.dispatchEvent(new window.Event("click", { bubbles: true }));
  check("a second click leaves full screen",
    !doc.getElementById("fs-overlay"));
  check("the panels return to where they started",
    mapPanel.parentElement === homeBefore &&
    readPanel.parentElement === homeBefore);
  check("the map still precedes the reading panel",
    mapPanel.nextElementSibling === readPanel);
}

console.log("\n" + pass + " passed, " + fail + " failed");
process.exit(fail > 0 ? 1 : 0);
