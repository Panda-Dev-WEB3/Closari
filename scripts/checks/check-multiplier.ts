// I11: a stock-token multiplier only appears in arithmetic inside contracts/src/lib/PriceMath.sol.
// Known gap (review-only): aliasing a multiplier into another variable name evades this check.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { Glob } from "bun";

const ALLOWED = "src/lib/PriceMath.sol";
const MULT = /multiplier|\bmult\b/i;
const ARITH = /[*/%]|\b(mulDiv\w*|mulWad\w*|divWad\w*|fullMul\w*|rpow|sMulWad|sDivWad)\b/;

export function multiplierViolations(file: string, text: string): string[] {
  if (file.replaceAll("\\", "/").endsWith(ALLOWED)) return [];
  const out: string[] = [];
  const lines = text.replace(/\/\*[\s\S]*?\*\//g, "").split("\n");
  lines.forEach((raw, i) => {
    const line = raw.replace(/\/\/.*$/, "");
    if (MULT.test(line) && ARITH.test(line)) out.push(`${file}:${i + 1}: ${line.trim()}`);
  });
  return out;
}

if (import.meta.main) {
  const root = join(import.meta.dir, "..", "..", "contracts");
  const errors: string[] = [];
  for (const f of new Glob("src/**/*.sol").scanSync(root)) {
    if (f.replaceAll("\\", "/").includes("src/vendor/")) continue;
    errors.push(...multiplierViolations(f, readFileSync(join(root, f), "utf8")));
  }
  if (errors.length) {
    console.error(`multiplier arithmetic outside PriceMath (I11):\n${errors.join("\n")}`);
    process.exit(1);
  }
  console.log("I11 multiplier rule holds");
}
