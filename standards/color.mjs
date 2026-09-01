/* color.mjs
   The color math behind the palette audit. Three questions get asked of
   every token in the stylesheet: how much contrast does it have against
   the surface it sits on, what does it look like to a reader with one
   of the common color vision deficiencies, and how far apart do two
   colors stay once that simulation has been applied.

   Nothing here is specific to Tessera. The file is arithmetic, kept
   separate from the test that uses it so the thresholds and the
   measurements can be read independently of each other. */

/* Parses the three and six digit hex forms the stylesheet uses and
   returns channels on the zero to 255 scale. */
export function hexToRgb(hex) {
  const clean = hex.trim().replace(/^#/, "");
  const full = clean.length === 3
    ? clean.split("").map(function (c) { return c + c; }).join("")
    : clean;
  if (!/^[0-9a-fA-F]{6}$/.test(full)) {
    throw new Error("Not a hex color: " + hex);
  }
  return [
    parseInt(full.slice(0, 2), 16),
    parseInt(full.slice(2, 4), 16),
    parseInt(full.slice(4, 6), 16)
  ];
}

/* Undoes the sRGB transfer curve. Every calculation below works on
   linear light, because contrast and color difference are both defined
   there rather than on the encoded values in the stylesheet. */
function toLinear(channel) {
  const v = channel / 255;
  return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
}

function fromLinear(value) {
  const v = Math.min(1, Math.max(0, value));
  const encoded = v <= 0.0031308
    ? v * 12.92
    : 1.055 * Math.pow(v, 1 / 2.4) - 0.055;
  return Math.round(encoded * 255);
}

/* Relative luminance as WCAG 2.2 defines it. */
export function luminance(hex) {
  const [r, g, b] = hexToRgb(hex).map(toLinear);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/* The WCAG 2.2 contrast ratio, which runs from 1 to 21. */
export function contrastRatio(foreground, background) {
  const a = luminance(foreground);
  const b = luminance(background);
  const light = Math.max(a, b);
  const dark = Math.min(a, b);
  return (light + 0.05) / (dark + 0.05);
}

/* Vienot, Brettel, and Mollon dichromat simulation, working in linear
   LMS. Each deficiency drops one cone class, and the missing response
   is rebuilt from the two that remain, which is why every simulated
   color lands on a single plane of the color space. The matrices are
   the published Hunt-Pointer-Estevez transform and its inverse. */
const RGB_TO_LMS = [
  [0.31399022, 0.63951294, 0.04649755],
  [0.15537241, 0.75789446, 0.08670142],
  [0.01775239, 0.10944209, 0.87256922]
];

const LMS_TO_RGB = [
  [5.47221206, -4.6419601, 0.16963708],
  [-1.1252419, 2.29317094, -0.1678952],
  [0.02980165, -0.19318073, 1.16364789]
];

/* Each entry rebuilds the missing cone response from the other two. */
const COLLAPSE = {
  deutan: [
    [1, 0, 0],
    [0.49421, 0, 1.24827],
    [0, 0, 1]
  ],
  protan: [
    [0, 1.05118294, -0.05116099],
    [0, 1, 0],
    [0, 0, 1]
  ],
  tritan: [
    [1, 0, 0],
    [0, 1, 0],
    [-0.86744736, 1.86727089, 0]
  ]
};

function apply(matrix, vector) {
  return matrix.map(function (row) {
    return row[0] * vector[0] + row[1] * vector[1] + row[2] * vector[2];
  });
}

/* Returns the hex a reader with the named deficiency sees. The name
   "none" passes the color through, so callers can hold one code path
   for every palette including the standard one. */
export function simulate(hex, deficiency) {
  if (!deficiency || deficiency === "none") return hex.toLowerCase();
  const collapse = COLLAPSE[deficiency];
  if (!collapse) throw new Error("Unknown deficiency: " + deficiency);
  const linear = hexToRgb(hex).map(toLinear);
  const lms = apply(RGB_TO_LMS, linear);
  const seen = apply(collapse, lms);
  const back = apply(LMS_TO_RGB, seen);
  return "#" + back.map(fromLinear).map(function (c) {
    return c.toString(16).padStart(2, "0");
  }).join("");
}

/* sRGB to CIE Lab under the D65 white point, which is the space the
   color difference below is defined in. */
export function toLab(hex) {
  const [r, g, b] = hexToRgb(hex).map(toLinear);
  const x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047;
  const y = (0.2126729 * r + 0.7151522 * g + 0.0721750 * b) / 1.0;
  const z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883;
  const f = function (t) {
    return t > 0.008856 ? Math.cbrt(t) : (7.787 * t) + (16 / 116);
  };
  const fx = f(x);
  const fy = f(y);
  const fz = f(z);
  return [(116 * fy) - 16, 500 * (fx - fy), 200 * (fy - fz)];
}

/* CIE76 color difference. Later formulas model human perception more
   closely, but CIE76 is the one whose thresholds are widely published,
   and a palette that clears it by a wide margin clears the others too.
   Roughly 2.3 units is the just noticeable difference. */
export function deltaE(hexA, hexB) {
  const a = toLab(hexA);
  const b = toLab(hexB);
  return Math.sqrt(
    Math.pow(a[0] - b[0], 2) +
    Math.pow(a[1] - b[1], 2) +
    Math.pow(a[2] - b[2], 2)
  );
}
