// ≥95% line and branch coverage on contracts/src (vendor, test and script excluded), from forge's lcov output.
import { readFileSync } from "node:fs";

export function coverageOf(lcov: string): { lines: number; branches: number; files: string[] } {
  let lf = 0;
  let lh = 0;
  let brf = 0;
  let brh = 0;
  const files: string[] = [];
  let include = false;
  for (const line of lcov.split("\n")) {
    const [k, v] = line.split(":");
    if (k === "SF") {
      const p = (v ?? "").replaceAll("\\", "/");
      // Only this repo's contracts/src: not dependencies whose own layout also contains src/ (node_modules/solady/src).
      include =
        /^(.*\/contracts\/)?src\//.test(p) &&
        !p.includes("node_modules") &&
        !p.includes("/vendor/");
      if (include) files.push(p);
    } else if (include && k === "LF") lf += Number(v);
    else if (include && k === "LH") lh += Number(v);
    else if (include && k === "BRF") brf += Number(v);
    else if (include && k === "BRH") brh += Number(v);
  }
  return { lines: lf ? lh / lf : 1, branches: brf ? brh / brf : 1, files };
}

if (import.meta.main) {
  const path = process.argv[2] ?? "contracts/lcov.info";
  const c = coverageOf(readFileSync(path, "utf8"));
  console.log(
    `lines ${(c.lines * 100).toFixed(2)}%  branches ${(c.branches * 100).toFixed(2)}%  over ${c.files.length} files`,
  );
  if (c.lines < 0.95 || c.branches < 0.95) {
    console.error("coverage below 95% (Backend §10)");
    process.exit(1);
  }
}
