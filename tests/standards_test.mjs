/* standards_test.mjs
   The house style gate. Four rules, checked over every source and
   documentation file in the repository.

   Run with: node tests/standards_test.mjs

   1. No em or en dashes anywhere, including code comments, commit
      ready documentation, and user facing strings.
   2. No contractions in prose.
   3. No word from the banned lexicon in prose.
   4. At least fifteen percent of the lines in a source file are
      comments, counting only lines that hold something.

   The first three are writing rules and are checked against writing:
   comments, string literals, and markdown. The fourth is checked
   against the file as a whole. A rule that lives only in someone's
   memory is a rule that survives until the first hurried commit, which
   is the reason this file exists rather than a paragraph in
   CONTRIBUTING.md saying the same thing. */

import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, extname } from "node:path";
import { findBanned } from "../standards/lexicon.mjs";

const COMMENT_FLOOR = 0.15;

/* Directories with nothing of ours in them, or with content that is not
   ours to hold to a writing standard. */
const SKIP_DIRECTORIES = [".git", "node_modules", "docs", "icons", "data"];

/* The license text is quoted from PolyForm and the citation file is
   machine written, so neither is edited to suit a house rule. The
   lexicon holds the banned list itself and would report every entry in
   it, so it is checked for dashes and contractions elsewhere in this
   walk but not searched against its own contents. */
const SKIP_FILES = ["LICENSE.md", "CITATION.cff", "lexicon.mjs"];

const SOURCE_EXTENSIONS = [".R", ".r", ".js", ".mjs", ".css"];
const PROSE_EXTENSIONS = [".md", ".yml", ".yaml", ".sh"];

const failures = [];
let filesChecked = 0;

function walk(directory) {
  const found = [];
  readdirSync(directory).forEach(function (entry) {
    if (SKIP_DIRECTORIES.includes(entry) || SKIP_FILES.includes(entry)) return;
    const path = join(directory, entry);
    if (statSync(path).isDirectory()) {
      found.push(...walk(path));
      return;
    }
    const extension = extname(entry);
    if (SOURCE_EXTENSIONS.includes(extension) ||
        PROSE_EXTENSIONS.includes(extension) ||
        entry === "DESCRIPTION" || entry === "NOTICE") {
      found.push(path);
    }
  });
  return found;
}

/* Pulls the writing out of a source file: comment bodies and string
   literals. Everything else is the language, not the author. */
function prose(path, text) {
  const extension = extname(path);
  if (PROSE_EXTENSIONS.includes(extension) || extension === "") return text;
  if (extension === ".css") {
    return (text.match(/\/\*[\s\S]*?\*\//g) || []).join("\n");
  }
  const pieces = [];
  const blockComments = text.match(/\/\*[\s\S]*?\*\//g) || [];
  pieces.push(...blockComments);
  text.split("\n").forEach(function (line) {
    const hash = line.match(/#.*$/);
    if (hash && (extension === ".R" || extension === ".r")) pieces.push(hash[0]);
    const slashes = line.match(/\/\/.*$/);
    if (slashes) pieces.push(slashes[0]);
  });
  const strings = text.match(/"[^"\n]*"|'[^'\n]*'/g) || [];
  pieces.push(...strings);
  return pieces.join("\n");
}

/* Counts comment lines against lines that hold anything at all. Blank
   lines are excluded from both sides, so whitespace can neither help
   nor hurt a file's standing. */
function commentDensity(path, text) {
  const extension = extname(path);
  const lines = text.split("\n");
  let comments = 0;
  let code = 0;
  let inBlock = false;
  lines.forEach(function (raw) {
    const line = raw.trim();
    if (line === "") return;
    if (extension === ".R" || extension === ".r") {
      if (line.startsWith("#")) comments += 1;
      else code += 1;
      return;
    }
    if (inBlock) {
      comments += 1;
      if (line.includes("*/")) inBlock = false;
      return;
    }
    if (line.startsWith("/*")) {
      comments += 1;
      if (!line.includes("*/")) inBlock = true;
      return;
    }
    if (line.startsWith("//")) {
      comments += 1;
      return;
    }
    code += 1;
  });
  const total = comments + code;
  return { comments: comments, total: total, share: total === 0 ? 1 : comments / total };
}

const CONTRACTIONS = /\b(can't|won't|don't|doesn't|isn't|aren't|wasn't|weren't|hasn't|haven't|hadn't|didn't|wouldn't|couldn't|shouldn't|it's|you're|we're|they're|i'm|that's|there's|here's|let's|what's|who's)\b/gi;

walk(".").forEach(function (path) {
  filesChecked += 1;
  const text = readFileSync(path, "utf8");

  const dashes = text.split("\n").filter(function (line) {
    return line.includes("\u2014") || line.includes("\u2013");
  });
  if (dashes.length > 0) {
    failures.push(path + ": " + dashes.length + " line(s) hold an em or en dash");
  }

  const written = prose(path, text);

  const contractions = written.match(CONTRACTIONS) || [];
  if (contractions.length > 0) {
    failures.push(path + ": contraction " + contractions[0]);
  }

  findBanned(written).forEach(function (hit) {
    failures.push(path + ": banned word " + hit.word);
  });

  if (SOURCE_EXTENSIONS.includes(extname(path))) {
    const density = commentDensity(path, text);
    if (density.share < COMMENT_FLOOR) {
      failures.push(path + ": comments are " +
        (density.share * 100).toFixed(1) + " percent of " +
        density.total + " lines, floor is " +
        (COMMENT_FLOOR * 100).toFixed(0));
    }
  }
});

if (failures.length === 0) {
  console.log("ok   standards: " + filesChecked + " files clear");
  process.exit(0);
}

console.log("FAIL standards: " + failures.length + " problems in " +
  filesChecked + " files");
failures.forEach(function (line) { console.log("  " + line); });
process.exit(1);
