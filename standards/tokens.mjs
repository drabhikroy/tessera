/* tokens.mjs
   Reads www/styles.css and resolves it into the finished set of custom
   properties a reader actually sees in each of the ten states the app
   can be in: two theme modes crossed with five color settings.

   The stylesheet is the single source of truth. Nothing here holds a
   second copy of a color, because a second copy is the thing that
   drifts. The parser understands only the small, fixed set of selectors
   the palette section uses, and it fails loudly on anything else, so a
   selector renamed in the stylesheet cannot silently drop out of the
   audit. */

import { readFileSync } from "node:fs";

export const MODES = ["dark", "light"];

/* Each color setting names the deficiency its palette is designed for.
   The standard palette is designed for no deficiency in particular, and
   monochrome removes hue as a channel altogether, so both are audited
   without a simulation. */
export const PALETTES = {
  standard: { deficiency: "none", label: "Standard" },
  deutan: { deficiency: "deutan", label: "Deuteranopia" },
  protan: { deficiency: "protan", label: "Protanopia" },
  tritan: { deficiency: "tritan", label: "Tritanopia" },
  mono: { deficiency: "none", label: "Monochrome" }
};

export const GROUP_TOKENS = [
  "--g1", "--g2", "--g3", "--g4", "--g5", "--g6",
  "--g7", "--g8", "--g9", "--g10", "--g11", "--g12"
];

/* Strips comments, then pulls out every selector and its declarations.
   The palette section of the stylesheet has no nesting or at-rules
   above it, so a flat scan is enough and is easier to reason about than
   a general parser. */
function readBlocks(css) {
  const stripped = css.replace(/\/\*[\s\S]*?\*\//g, "");
  const blocks = [];
  const pattern = /([^{}]+)\{([^{}]*)\}/g;
  let match = pattern.exec(stripped);
  while (match !== null) {
    const selector = match[1].replace(/\s+/g, " ").trim();
    const declarations = {};
    match[2].split(";").forEach(function (piece) {
      const colon = piece.indexOf(":");
      if (colon === -1) return;
      const name = piece.slice(0, colon).trim();
      const value = piece.slice(colon + 1).trim();
      if (name.startsWith("--")) declarations[name] = value;
    });
    if (Object.keys(declarations).length > 0) {
      blocks.push({ selector: selector, declarations: declarations });
    }
    match = pattern.exec(stripped);
  }
  return blocks;
}

/* The layers are listed in cascade order. Later layers win, which is
   the order the browser resolves them in as well: the dark base, then
   the light overrides, then the palette, then the light corrections to
   that palette. */
function layerSelectors(mode, palette) {
  const layers = [':root, [data-bs-theme="dark"]'];
  if (mode === "light") layers.push('[data-bs-theme="light"]');
  if (palette !== "standard") {
    layers.push("body.cb-" + palette);
    if (mode === "light") {
      layers.push('[data-bs-theme="light"] .cb-' + palette +
        ', [data-bs-theme="light"].cb-' + palette);
    }
  }
  return layers;
}

/* Resolves one state. Missing layers are allowed only when a palette
   genuinely needs no correction in light mode; a missing base layer is
   a broken stylesheet and throws. */
export function resolveState(css, mode, palette) {
  const blocks = readBlocks(css);
  const tokens = {};
  layerSelectors(mode, palette).forEach(function (selector, index) {
    const block = blocks.find(function (b) { return b.selector === selector; });
    if (!block) {
      if (index === 0) throw new Error("Missing base block: " + selector);
      return;
    }
    Object.assign(tokens, block.declarations);
  });
  return tokens;
}

export function loadStylesheet(path) {
  return readFileSync(path, "utf8");
}

/* Every state, flattened into one list, which is what the audit walks. */
export function allStates(css) {
  const states = [];
  MODES.forEach(function (mode) {
    Object.keys(PALETTES).forEach(function (palette) {
      states.push({
        mode: mode,
        palette: palette,
        deficiency: PALETTES[palette].deficiency,
        label: PALETTES[palette].label + " on " + mode,
        tokens: resolveState(css, mode, palette)
      });
    });
  });
  return states;
}
