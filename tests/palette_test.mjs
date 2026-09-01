/* palette_test.mjs
   Measures every color the stylesheet can put on screen, in all ten
   states the app supports, and fails when one of them falls below the
   thresholds the project holds itself to.

   Run with: node tests/palette_test.mjs

   A comment in the stylesheet saying the colors have been checked
   cannot fail a build. This file can, which is the whole reason it
   exists.

   Two thresholds are in force. Text clears 4.5 to 1 against the surface
   behind it, and interface parts and graphical objects clear 3 to 1,
   both from WCAG 2.2 AA. On top of that, the twelve group colors stay a
   measured distance apart from one another once the color vision
   simulation for their palette has been applied, so a reader using the
   deuteranopia setting is not handed two groups that arrive as the same
   color.

   Group identity never rests on color alone. Every node also carries a
   shape and a fill variant, and the legend repeats both, so the
   separation floor below asks color to assist rather than to carry. */

import { contrastRatio, simulate, deltaE, toLab, luminance }
  from "../standards/color.mjs";
import {
  loadStylesheet, allStates, GROUP_TOKENS, PALETTES, MODES
} from "../standards/tokens.mjs";
import { readFileSync } from "node:fs";

const TEXT_MINIMUM = 4.5;
const COMPONENT_MINIMUM = 3.0;

/* The hairline used for row rules and section dividers carries no
   information, so it is held to a presence floor rather than to the
   interface threshold. A divider set at 3 to 1 boxes in every table
   row and competes with the content it separates. Anything that bounds
   a control or a container uses --line instead, which is audited at the
   full interface threshold below. */
const SEAM_MINIMUM = 1.5;

/* CIE76 units between any two group colors after simulation. The just
   noticeable difference is near 2.3, so this floor is several times the
   point at which two colors stop being the same color, while staying
   reachable for twelve groups inside one palette. */
const SEPARATION_MINIMUM = 11;

/* Monochrome has no hue to spend, so its twelve groups are a lightness
   ramp and the measurement is the lightness step rather than the full
   color difference. Twelve steps inside the range that still clears 3
   to 1 against the panel leaves room for about this much, which is near
   twice the just noticeable difference. Shape and fill variant carry
   group identity in this setting; the ramp only has to stay countable. */
const MONO_SEPARATION_MINIMUM = 4.5;

const failures = [];
let checks = 0;

function check(name, measured, minimum) {
  checks += 1;
  if (measured + 1e-9 < minimum) {
    failures.push(name + ": " + measured.toFixed(2) +
      ", needs " + minimum.toFixed(2));
    return false;
  }
  return true;
}

/* Text and interface tokens, each named with the surface it is painted
   on, because contrast is a property of the pair and not of the color. */
const PAIRS = [
  { fg: "--text", bg: "--bg", minimum: TEXT_MINIMUM },
  { fg: "--text", bg: "--surface", minimum: TEXT_MINIMUM },
  { fg: "--text", bg: "--raised", minimum: TEXT_MINIMUM },
  { fg: "--muted", bg: "--bg", minimum: TEXT_MINIMUM },
  { fg: "--muted", bg: "--surface", minimum: TEXT_MINIMUM },
  { fg: "--accent", bg: "--surface", minimum: TEXT_MINIMUM },
  /* --line borders three different grounds: panels and buttons paint
     --surface, model cards paint --raised, and inline code paints --bg,
     so all three are measured. */
  { fg: "--line", bg: "--surface", minimum: COMPONENT_MINIMUM },
  { fg: "--line", bg: "--raised", minimum: COMPONENT_MINIMUM },
  { fg: "--line", bg: "--bg", minimum: COMPONENT_MINIMUM },
  /* Ties belong to the map panel only, and are painted at full opacity, so the
     token value is what a reader sees. */
  { fg: "--edge", bg: "--surface", minimum: COMPONENT_MINIMUM },
  { fg: "--focus", bg: "--surface", minimum: COMPONENT_MINIMUM },
  { fg: "--focus", bg: "--bg", minimum: COMPONENT_MINIMUM },
  { fg: "--seam", bg: "--surface", minimum: SEAM_MINIMUM }
];

const states = allStates(loadStylesheet("www/styles.css"));

states.forEach(function (state) {
  const token = function (name) {
    const value = state.tokens[name];
    if (!value) throw new Error("Missing " + name + " in " + state.label);
    return value;
  };

  PAIRS.forEach(function (pair) {
    check(
      state.label + " " + pair.fg + " on " + pair.bg,
      contrastRatio(token(pair.fg), token(pair.bg)),
      pair.minimum
    );
  });

  /* Group colors are graphical objects, so they are held to the 3 to 1
     interface threshold against the panel they are painted on rather than
     the text threshold. */
  GROUP_TOKENS.forEach(function (name) {
    check(
      state.label + " " + name + " on the map panel",
      contrastRatio(token(name), token("--surface")),
      COMPONENT_MINIMUM
    );
  });

  /* Separation between groups, measured after the simulation that
     matches what this palette is for. Monochrome is measured on
     lightness alone, since that is the only channel it uses. */
  const monotone = state.palette === "mono";
  const floor = monotone ? MONO_SEPARATION_MINIMUM : SEPARATION_MINIMUM;
  const seen = GROUP_TOKENS.map(function (name) {
    return { name: name, hex: simulate(token(name), state.deficiency) };
  });

  for (let i = 0; i < seen.length; i += 1) {
    for (let j = i + 1; j < seen.length; j += 1) {
      const measured = monotone
        ? Math.abs(toLab(seen[i].hex)[0] - toLab(seen[j].hex)[0])
        : deltaE(seen[i].hex, seen[j].hex);
      check(
        state.label + " " + seen[i].name + " against " + seen[j].name,
        measured,
        floor
      );
    }
  }
});

/* The exported figure keeps its own copy of the palettes, because
   ggplot2 cannot read a stylesheet. A second copy is the thing that
   drifts, so it is compared here against the light mode blocks it is
   supposed to mirror. */
const figureSource = readFileSync("R/figure.R", "utf8");

Object.keys(PALETTES).forEach(function (palette) {
  const block = new RegExp(
    palette + "\\s*=\\s*c\\(([^)]*)\\)"
  ).exec(figureSource);
  checks += 1;
  if (!block) {
    failures.push("R/figure.R has no palette named " + palette);
    return;
  }
  const declared = block[1].match(/#[0-9a-fA-F]{6}/g) || [];
  const expected = allStates(loadStylesheet("www/styles.css"))
    .find(function (state) {
      return state.mode === "light" && state.palette === palette;
    });
  GROUP_TOKENS.forEach(function (name, index) {
    checks += 1;
    const wanted = expected.tokens[name].toLowerCase();
    const found = (declared[index] || "").toLowerCase();
    if (wanted !== found) {
      failures.push("R/figure.R " + palette + " color " + (index + 1) +
        " is " + found + ", stylesheet says " + wanted);
    }
  });
});

/* Two conditions the protanopia palette exists to satisfy, checked here
   rather than trusted to a comment. The first release of it looked
   almost identical to the deuteranopia palette, which is what happens
   when two settings are given the same constraints and no reason to
   differ.

   Protanopia darkens the long wavelength end, so a color that keeps its
   hue distance can still arrive muddy. No color in that palette may
   lose more than about a third of its light under the simulation. And
   every color must sit a measured distance from the one holding the
   same slot in the deuteranopia palette, since two settings that look
   alike are one setting shown twice. */
const LIGHT_KEPT_MINIMUM = 0.55;
const PALETTE_GAP_MINIMUM = 10;

MODES.forEach(function (mode) {
  const protan = allStates(loadStylesheet("www/styles.css"))
    .find(function (s) { return s.mode === mode && s.palette === "protan"; });
  const deutan = allStates(loadStylesheet("www/styles.css"))
    .find(function (s) { return s.mode === mode && s.palette === "deutan"; });

  GROUP_TOKENS.forEach(function (name) {
    const hex = protan.tokens[name];
    const before = luminance(hex);
    const after = luminance(simulate(hex, "protan"));
    checks += 1;
    const kept = before > 0 ? after / before : 1;
    if (kept + 1e-9 < LIGHT_KEPT_MINIMUM) {
      failures.push("Protanopia on " + mode + " " + name +
        " keeps only " + (kept * 100).toFixed(0) +
        " percent of its light under simulation");
    }
    check("Protanopia on " + mode + " " + name + " against deuteranopia",
      deltaE(hex, deutan.tokens[name]), PALETTE_GAP_MINIMUM);
  });
});

if (failures.length === 0) {
  console.log("ok   palettes: " + checks + " measurements across " +
    states.length + " states");
  process.exit(0);
}

console.log("FAIL palettes: " + failures.length + " of " + checks +
  " measurements below threshold");
failures.forEach(function (line) { console.log("  " + line); });
process.exit(1);
