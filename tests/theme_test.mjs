// theme_test.mjs
// An end to end check of the appearance toggle against the real page the
// server sends, not a reconstruction of it. Earlier rounds tested a
// hand built copy of the markup and passed while the running app failed,
// so this file starts from the served HTML and the served stylesheet.
//
// Usage: node tests/theme_test.mjs <page.html> <styles.css> <toggle.html>
//
// The toggle has lived in the Settings dialog since 0.21.0, so it is not
// in the served page. The third file is the button that dialog shows,
// written by tests/render_controls.R from the same function the app
// calls. Before this argument existed the suite found no button, failed
// two checks, and quietly skipped every check that pressed it.

import { JSDOM } from "jsdom";
import { readFileSync } from "fs";

const pageFile = process.argv[2];
const cssFile = process.argv[3];
const toggleFile = process.argv[4];
const html = readFileSync(pageFile, "utf8");
const css = readFileSync(cssFile, "utf8");

// A real origin is needed for localStorage, and the page's own inline
// boot script is executed below by hand because jsdom does not run
// page scripts in this mode.
const dom = new JSDOM(html, {
  runScripts: "outside-only",
  url: "http://localhost/"
});
const { window } = dom;
const doc = window.document;

let pass = 0, fail = 0;
const check = (label, ok) => {
  if (ok) { pass++; console.log("ok  ", label); }
  else { fail++; console.log("FAIL", label); }
};

// The starting mode must be written on the document, not merely implied
// by the stylesheet. This is the mismatch that made three earlier
// toggles appear dead: the page looked dark while the control believed
// it was light, so the first click changed nothing anyone could see.
// Only the boot script matters here; other inline scripts on the page
// belong to Shiny and its dependencies.
const bootScript = [...doc.querySelectorAll("script")]
  .map((s) => s.textContent || "")
  .find((text) => text.includes("data-bs-theme")) || "";
check("the page sets a starting theme before paint",
  bootScript.includes("data-bs-theme"));

// Run that boot script the way the browser would, so the rest of this
// file tests the state a person actually lands on.
window.eval(bootScript);
check("the starting theme is written onto the document",
  doc.documentElement.getAttribute("data-bs-theme") === "dark");

// Both modes name themselves in the stylesheet, so neither depends on
// being the unstated default.
check("the stylesheet defines dark explicitly",
  css.includes('[data-bs-theme="dark"]'));
check("the stylesheet defines light explicitly",
  css.includes('[data-bs-theme="light"]'));

// Every token that light overrides must also exist in the dark block,
// or a switch would leave some colors stranded in the other mode.
const blockFor = (selector) => {
  const at = css.indexOf(selector);
  if (at < 0) return "";
  return css.slice(at, css.indexOf("}", at));
};
const tokensIn = (block) =>
  (block.match(/--[a-z0-9-]+(?=\s*:)/g) || []).filter((t) =>
    !t.startsWith("--font"));
const darkTokens = new Set(tokensIn(blockFor(":root,")));
const lightTokens = tokensIn(blockFor('[data-bs-theme="light"] {'));
const stranded = lightTokens.filter((t) => !darkTokens.has(t));
check("no light token is missing from the dark block",
  stranded.length === 0);

// Static assets carry a version stamp. Without one, a browser can hold
// an old stylesheet against new markup, and every control that depends
// on that stylesheet appears dead.
const stamped = [...doc.querySelectorAll("link[rel=stylesheet], script[src]")]
  .map((el) => el.getAttribute("href") || el.getAttribute("src"))
  .filter((u) => u && /^(styles\.css|graph\.js|theme\.js)/.test(u));
check("the app's own assets are version stamped",
  stamped.length === 3 && stamped.every((u) => u.includes("?v=")));

// The toggle is put into the page the way opening Settings puts it
// there. A missing file is a failure, not a reason to skip the checks
// below, since a skipped check is how this suite went quiet before.
check("the toggle markup was given to the suite", !!toggleFile);
if (toggleFile) {
  const dialog = doc.createElement("div");
  dialog.className = "modal";
  dialog.innerHTML = readFileSync(toggleFile, "utf8");
  doc.body.appendChild(dialog);
}
const btn = doc.querySelector(".theme-toggle");
check("the appearance toggle renders from the app's own function", !!btn);
check("the toggle carries an inline handler",
  !!btn && !!btn.getAttribute("onclick"));

// Now actually operate it. The handler is inline, so it is run the way
// the browser would run it, with `this` bound to the button.
if (btn) {
  // jsdom supplies localStorage already, so the handler exercises the
  // same storage path a browser would.
  const fire = () => {
    const fn = new window.Function(btn.getAttribute("onclick"));
    fn.call(btn);
  };

  const start = doc.documentElement.getAttribute("data-bs-theme");
  fire();
  const afterOne = doc.documentElement.getAttribute("data-bs-theme");
  check("one click changes the theme attribute", start !== afterOne);
  check("one click lands on a real mode",
    afterOne === "light" || afterOne === "dark");
  check("the label follows the mode",
    btn.textContent === (afterOne === "dark" ? "Light mode" : "Dark mode"));

  fire();
  check("a second click returns to the starting mode",
    doc.documentElement.getAttribute("data-bs-theme") === start);

  check("the choice is remembered for the next visit",
    window.localStorage.getItem("tessera-theme") === start);
}

// Reopening Settings in light mode. The server rebuilds the button with
// the light mode label each time the dialog opens, so without a sync the
// label named the mode already on screen. theme.js listens for the
// dialog opening and sets the label from the page.
if (toggleFile) {
  window.eval(readFileSync(new URL("../www/theme.js", import.meta.url), "utf8"));
  doc.documentElement.setAttribute("data-bs-theme", "light");
  doc.querySelectorAll(".modal").forEach((m) => m.remove());
  const reopened = doc.createElement("div");
  reopened.className = "modal";
  reopened.innerHTML = readFileSync(toggleFile, "utf8");
  doc.body.appendChild(reopened);
  const fresh = reopened.querySelector(".theme-toggle");
  check("a freshly built button starts with the server label",
    fresh.textContent === "Light mode");
  reopened.dispatchEvent(new window.Event("show.bs.modal", { bubbles: true }));
  check("reopening Settings in light mode labels the button Dark mode",
    fresh.textContent === "Dark mode" &&
    fresh.getAttribute("aria-label") === "Switch to dark mode");
}

console.log("\n" + pass + " passed, " + fail + " failed");
process.exit(fail > 0 ? 1 : 0);
