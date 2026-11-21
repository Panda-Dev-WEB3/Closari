import { describe, expect, test } from "bun:test";
import { abiHash } from "../scripts/abi.ts";
import { iMarketFactoryAbi } from "../src/abi/index.ts";

describe("generated ABIs", () => {
  test("listDay is exported with the brief's inputs", () => {
    const listDay = iMarketFactoryAbi.find((i) => i.type === "function" && i.name === "listDay");
    expect(listDay).toBeDefined();
    expect(
      (listDay as unknown as { inputs: { type: string }[] }).inputs.map((x) => x.type),
    ).toEqual(["address", "uint32", "bytes[]"]);
  });

  test("abiHash ignores ordering", () => {
    const a = [
      { type: "function", name: "a", inputs: [] },
      { type: "function", name: "b", inputs: [{ type: "uint256" }] },
    ];
    expect(abiHash(a)).toBe(abiHash([...a].reverse()));
  });
});
