#!/usr/bin/env node
// Records the molfile-write corpus (the cross-runtime writer contract,
// asciichem-rs#86's follow-up wave): each row's `writtenMolfile` golden
// embeds the reference writer's exact bytes, driven from a BUILT
// asciichem-ts dist whose writer is byte-verified against the rs
// writer on this battery (the corpus's write authority is the
// geometry-aware claims semantic the identity batteries prove).
//
//   node scripts/record-molfile-write.mjs
//
// Environment:
//   ASCIICHEM_TS_DIST  the built dist directory
//                      (default ../../asciichem-ts/dist)

import { writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const dist = resolve(here, process.env.ASCIICHEM_TS_DIST ?? "../../asciichem-ts/dist");

const { parseSmiles } = await import(pathToFileURL(join(dist, "smiles.js")));
await import(pathToFileURL(join(dist, "index.js")));
const { writeMolfile } = await import(pathToFileURL(join(dist, "molfile.js")));

// The write battery: the enantiomer pairs are the identity-facing
// acceptance (the drawn hand must pair with the wedge code so the
// engine reads the source configuration — the rs and py identity
// batteries gate that end); the achiral controls pin the plain bytes.
const SEEDS = [
  ["alanine-pair-l", "C[C@H](O)N", ["stereo", "enantiomer-pair", "write-golden"]],
  ["alanine-pair-d", "C[C@@H](O)N", ["stereo", "enantiomer-pair", "write-golden"]],
  ["l-alanine", "N[C@@H](C)C(=O)O", ["stereo", "write-golden"]],
  ["d-alanine", "N[C@H](C)C(=O)O", ["stereo", "write-golden"]],
  ["bromochlorofluoromethane-l", "F[C@](Cl)(Br)I", ["stereo", "enantiomer-pair", "no-stated-h", "write-golden"]],
  ["bromochlorofluoromethane-d", "F[C@@](Cl)(Br)I", ["stereo", "enantiomer-pair", "no-stated-h", "write-golden"]],
  ["butanol-pair-l", "[C@H](O)(C)C", ["stereo", "enantiomer-pair", "write-golden"]],
  ["butanol-pair-d", "[C@@H](O)(C)C", ["stereo", "enantiomer-pair", "write-golden"]],
  ["ring-stereo", "C1[C@H](O)CCCC1", ["stereo", "ring", "write-golden"]],
  ["ethanol", "CCO", ["write-golden"]],
  ["benzene", "c1ccccc1", ["ring", "write-golden"]],
  ["aspirin", "CC(=O)OC1=CC=CC=C1C(=O)O", ["drug", "write-golden"]],
  ["caffeine", "Cn1cnc2c1c(=O)n(C)c(=O)n2C", ["drug-fused", "write-golden"]],
];

const written = new Map(
  SEEDS.map(([id, smiles]) => [id, writeMolfile(parseSmiles(smiles).nodes[0], "")]),
);
for (const [left, right] of [
  ["alanine-pair-l", "alanine-pair-d"],
  ["l-alanine", "d-alanine"],
  ["bromochlorofluoromethane-l", "bromochlorofluoromethane-d"],
  ["butanol-pair-l", "butanol-pair-d"],
]) {
  if (written.get(left) === written.get(right)) {
    throw new Error(`enantiomer pair writes identically: ${left} vs ${right}`);
  }
}

const rows = SEEDS.map(([id, smiles, tags]) => ({
  id: `molfile-write/${id}`,
  input: `@smiles(${JSON.stringify(smiles)})`,
  parses: true,
  smiles,
  writtenMolfile: written.get(id),
  tags,
  since: "0.31.0",
}));
writeFileSync(
  join(here, "..", "corpus", "fixtures", "molfile-write.json"),
  `${JSON.stringify(rows, null, 2)}\n`,
);
console.error(`molfile-write.json: ${rows.length} rows`);
