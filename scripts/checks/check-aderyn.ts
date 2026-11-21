// Fails on any Aderyn high-severity issue whose title is not listed in security/triage.md.
import { readFileSync } from "node:fs";

const report = JSON.parse(readFileSync(process.argv[2] ?? "contracts/aderyn.json", "utf8")) as {
  high_issues?: { issues?: { title: string }[] };
};
const triage = readFileSync("security/triage.md", "utf8");
const open = (report.high_issues?.issues ?? []).filter((i) => !triage.includes(i.title));
if (open.length) {
  console.error(`untriaged Aderyn high findings:\n${open.map((i) => `- ${i.title}`).join("\n")}`);
  process.exit(1);
}
console.log("aderyn: no untriaged high findings");
