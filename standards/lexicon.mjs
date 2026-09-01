/* lexicon.mjs
   The words this project does not use, and the machinery for finding
   them. The list is a writing standard rather than a style suggestion,
   so it is enforced on every push instead of remembered.

   The ban covers writing: comments, user facing strings, and
   documentation. It does not cover the names of things the languages
   themselves define, which is why the exemptions below exist. A
   stylesheet has to say text-align, and refusing to let it say so would
   turn a writing rule into a reason to fight the platform. */

export const BANNED = [
  "actionable", "adept", "aim", "align", "bolster", "commendable",
  "craft", "delve", "drawn", "enable", "encompass", "enhance", "ensure",
  "equip", "esteemed", "facilitate", "foster", "friendly",
  "functionality", "grasp", "guarantee", "hone", "influence",
  "instrumental", "intersection", "intricate", "invaluable", "journey",
  "landscape", "leverage", "maximize", "meticulous", "multifaceted",
  "nuance", "passionate", "perspective", "pivotal", "plethora", "realm",
  "rigor", "sacrifice", "seamlessly", "showcasing", "streamline",
  "strengthen", "strive", "synergy", "techniques", "transformative",
  "translate", "tweak", "uncover", "utilize", "vital"
];

/* Names defined by CSS, SVG, the DOM, or a library the app depends on.
   Each one is removed from the text before the search runs, so the word
   inside it cannot register as prose. Anything added here should be a
   name that cannot be spelled differently, not a phrase someone found
   convenient. */
export const EXEMPT = [
  "text-align", "align-items", "align-self", "align-content",
  "vertical-align", "text-align-last", "translate", "translateX",
  "translateY", "translate3d", "aria-live", "grid-template",
  "enableBridge", "alignment-baseline", "dominant-baseline"
];

/* Builds the forms of a banned word that count as the same word.
   Spelling out the endings is deliberate. A trailing wildcard would
   match honest for hone and drawn for draw, and a gate that cries wolf
   gets switched off. */
export function variantsOf(word) {
  const stem = word.endsWith("e") ? word.slice(0, -1) : word;
  const forms = new Set([
    word,
    word + "s",
    word + "d",
    word + "ed",
    word + "ing",
    word + "ly",
    word + "ment",
    word + "ments",
    word + "ion",
    word + "ions",
    stem + "ing",
    stem + "ed",
    stem + "es",
    stem + "ion",
    stem + "ions",
    stem + "ation",
    stem + "ations"
  ]);
  return Array.from(forms);
}

const PATTERN = new RegExp(
  "\\b(" + BANNED.flatMap(variantsOf).join("|") + ")\\b",
  "gi"
);

/* Returns every banned word in a piece of writing, with the exempt
   technical names blanked out first so they cannot be reported. */
export function findBanned(text) {
  let searchable = text;
  EXEMPT.forEach(function (name) {
    searchable = searchable.split(name).join(" ".repeat(name.length));
  });
  const hits = [];
  let match = PATTERN.exec(searchable);
  while (match !== null) {
    hits.push({
      word: match[0],
      line: searchable.slice(0, match.index).split("\n").length
    });
    match = PATTERN.exec(searchable);
  }
  PATTERN.lastIndex = 0;
  return hits;
}
