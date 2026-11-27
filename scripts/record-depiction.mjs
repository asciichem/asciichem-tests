#!/usr/bin/env node
// Records the depiction corpus (asciichem-rs#82: the enantiomer-pair
// visual rows) and regenerates the structural-SVG byte reference
// (svg-reference.jsonl) from a BUILT asciichem-ts dist — the TS
// implementation is the structural-SVG authority; the rs and py
// fixtures pin the same bytes.
//
//   node scripts/record-depiction.mjs
//
// Environment:
//   ASCIICHEM_TS_DIST  the built dist directory
//                      (default ../../asciichem-ts/dist)
//   SVG_REFERENCE      the existing svg-reference.jsonl whose input
//                      list is preserved and re-rendered
//                      (default ../../asciichem-rs/tests/fixtures/svg-reference.jsonl)
//   SVG_REFERENCE_OUT  comma-separated output paths for the
//                      regenerated jsonl (default: the rs and py
//                      fixture paths)
//
// The depiction goldens embed the reference's structural SVG bytes;
// a disagreement between the drawn geometry and the recorded identity
// is impossible here by construction — the enantiomer-pair oracle gate
// lives in asciichem-rs (tests/stereo_depiction.rs), which gates the
// synthesis polarity through the chemomer engine before any golden is
// recorded.

import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const dist = resolve(here, process.env.ASCIICHEM_TS_DIST ?? "../../asciichem-ts/dist");
const legacy = resolve(here, process.env.SVG_REFERENCE ?? "../../asciichem-rs/tests/fixtures/svg-reference.jsonl");
const outputs = (process.env.SVG_REFERENCE_OUT ?? "../../asciichem-rs/tests/fixtures/svg-reference.jsonl,../../asciichem-py/tests/fixtures/svg-reference.jsonl")
  .split(",")
  .map((p) => resolve(here, p));

const { parseText } = await import(pathToFileURL(join(dist, "parser.js")));
// The root module registers the built-in renderers (structural-svg).
await import(pathToFileURL(join(dist, "index.js")));

const renders = (input) => {
  const formula = parseText(input);
  return { svg: formula.toStructuralSvg(), linear: formula.toSvg() };
};

// The depiction rows (v0.30.0). The enantiomer pairs are the
// acceptance test: opposite parities must render distinguishable
// drawings; the no-hydrogen pair exercises the four-drawn-ligand
// construction.
const SEEDS = [
  ["alanine-pair-l", '@smiles("C[C@H](O)N")', "C[C@H](O)N", ["stereo", "enantiomer-pair"]],
  ["alanine-pair-d", '@smiles("C[C@@H](O)N")', "C[C@@H](O)N", ["stereo", "enantiomer-pair"]],
  ["l-alanine", '@smiles("N[C@@H](C)C(=O)O")', "N[C@@H](C)C(=O)O", ["stereo"]],
  ["d-alanine", '@smiles("N[C@H](C)C(=O)O")', "N[C@H](C)C(=O)O", ["stereo"]],
  ["bromochlorofluoromethane-l", '@smiles("F[C@](Cl)(Br)I")', "F[C@](Cl)(Br)I", ["stereo", "enantiomer-pair", "no-stated-h"]],
  ["bromochlorofluoromethane-d", '@smiles("F[C@@](Cl)(Br)I")', "F[C@@](Cl)(Br)I", ["stereo", "enantiomer-pair", "no-stated-h"]],
  ["ring-stereo", '@smiles("C1[C@H](O)CCCC1")', "C1[C@H](O)CCCC1", ["stereo", "ring"]],
];

// The rendered goldens must distinguish every enantiomer pair — a
// recorded pair of identical bytes is a recording bug, not a corpus
// row.
const drawn = new Map(SEEDS.map(([id, input]) => [id, renders(input).svg]));
for (const [left, right] of [
  ["alanine-pair-l", "alanine-pair-d"],
  ["l-alanine", "d-alanine"],
  ["bromochlorofluoromethane-l", "bromochlorofluoromethane-d"],
]) {
  if (drawn.get(left) === drawn.get(right)) {
    throw new Error(`enantiomer pair renders identically: ${left} vs ${right}`);
  }
}

const depiction = SEEDS.map(([id, input, smiles, tags]) => ({
  id: `depiction/${id}`,
  input,
  parses: true,
  smiles,
  svg: drawn.get(id),
  tags,
  since: "0.30.0",
}));
writeFileSync(
  join(here, "..", "corpus", "fixtures", "depiction.json"),
  `${JSON.stringify(depiction, null, 2)}\n`,
);
console.error(`depiction.json: ${depiction.length} rows`);

// The byte reference: every legacy input re-rendered through the
// current dist, then the depiction inputs appended.
const legacyRows = existsSync(legacy)
  ? readFileSync(legacy, "utf8")
      .split("\n")
      .filter((line) => line.trim() !== "")
      .map((line) => JSON.parse(line))
  : [];
const seen = new Set(legacyRows.map((row) => row.input));
const rows = legacyRows.map((row) => ({ input: row.input, ...renders(row.input) }));
for (const [, input] of SEEDS) {
  if (seen.has(input)) continue;
  rows.push({ input, ...renders(input) });
}
const jsonl = rows.map((row) => JSON.stringify(row)).join("\n") + "\n";
for (const output of outputs) {
  writeFileSync(output, jsonl);
}
console.error(`svg-reference.jsonl: ${rows.length} rows → ${outputs.length} fixtures`);
