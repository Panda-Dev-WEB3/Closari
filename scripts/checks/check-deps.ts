// Fails if a submodule commit, a vendored file, or a Solidity npm dependency drifts from DEPENDENCIES.lock.
import { readFileSync } from "node:fs";
import { join } from "node:path";

const ROOT = join(import.meta.dir, "..", "..");
type Lock = {
  submodules: Record<string, { commit: string }>;
  vendored: Record<string, { sha256: string }>;
  npm: Record<string, string>;
};
const lock = JSON.parse(readFileSync(join(ROOT, "DEPENDENCIES.lock"), "utf8")) as Lock;
const errors: string[] = [];

for (const [path, { commit }] of Object.entries(lock.submodules)) {
  const out = Bun.spawnSync(["git", "-C", ROOT, "ls-tree", "HEAD", path]).stdout.toString().trim();
  const actual = out.split(/\s+/)[2];
  if (actual !== commit)
    errors.push(`submodule ${path}: tree has ${actual ?? "nothing"}, lock has ${commit}`);
}

for (const [path, { sha256 }] of Object.entries(lock.vendored)) {
  const hasher = new Bun.CryptoHasher("sha256");
  hasher.update(readFileSync(join(ROOT, path)));
  const actual = hasher.digest("hex");
  if (actual !== sha256) errors.push(`vendored ${path}: sha256 ${actual}, lock has ${sha256}`);
}

const contractsPkg = JSON.parse(readFileSync(join(ROOT, "contracts", "package.json"), "utf8"));
for (const [name, version] of Object.entries(lock.npm)) {
  const declared = contractsPkg.devDependencies?.[name];
  if (declared !== version)
    errors.push(`npm ${name}: contracts/package.json has ${declared}, lock has ${version}`);
  const installed = JSON.parse(
    readFileSync(join(ROOT, "node_modules", name, "package.json"), "utf8"),
  ).version;
  if (installed !== version)
    errors.push(`npm ${name}: installed ${installed}, lock has ${version}`);
}

if (errors.length) {
  console.error(errors.join("\n"));
  process.exit(1);
}
console.log("dependencies match DEPENDENCIES.lock");
