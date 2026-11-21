// Overview §14: banned words must not appear in code identifiers or strings (comments are not scanned).
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { Glob } from "bun";

const WORDS = new Set([
  "bet",
  "bets",
  "betting",
  "wager",
  "wagers",
  "gamble",
  "gambling",
  "odds",
  "yield",
  "yields",
  "apy",
  "earn",
  "guaranteed",
]);
const PHRASES = ["risk-free", "binary option", "passive income"];

function words(token: string): string[] {
  return token
    .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
    .replace(/([A-Z])([A-Z][a-z])/g, "$1 $2")
    .split(/[^A-Za-z]+/)
    .filter(Boolean)
    .map((w) => w.toLowerCase());
}

export function bannedIn(source: string): string[] {
  const code = source.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/.*$/gm, "");
  const found: string[] = [];
  for (const id of code.match(/[A-Za-z_][A-Za-z0-9_]*/g) ?? []) {
    for (const w of words(id)) if (WORDS.has(w) && !found.includes(w)) found.push(w);
  }
  const flat = words(code).join(" ");
  for (const p of PHRASES) {
    const spaced = p.replace("-", " ");
    if (flat.includes(spaced) && !found.includes(p)) found.push(p);
  }
  return found;
}

if (import.meta.main) {
  const root = join(import.meta.dir, "..", "..");
  const globs = ["contracts/src/**/*.sol", "packages/*/src/**/*.ts", "packages/*/scripts/**/*.ts"];
  const errors: string[] = [];
  for (const g of globs) {
    for (const f of new Glob(g).scanSync(root)) {
      if (f.replaceAll("\\", "/").includes("contracts/src/vendor/")) continue;
      const hits = bannedIn(readFileSync(join(root, f), "utf8"));
      if (hits.length) errors.push(`${f}: ${hits.join(", ")}`);
    }
  }
  if (errors.length) {
    console.error(`banned words (Overview §14):\n${errors.join("\n")}`);
    process.exit(1);
  }
  console.log("no banned words in code or strings");
}
