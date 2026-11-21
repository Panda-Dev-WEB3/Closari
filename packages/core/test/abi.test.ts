import { describe, expect, test } from "bun:test";
import { abiHash, interfaceDrift } from "../scripts/abi.ts";
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

  test("abiHash changes when an input type changes", () => {
    const a = [{ type: "function", name: "f", inputs: [{ type: "uint256" }] }];
    const b = [{ type: "function", name: "f", inputs: [{ type: "uint128" }] }];
    expect(abiHash(a)).not.toBe(abiHash(b));
  });
});

describe("interfaceDrift", () => {
  const lock = { IA: "aa", IB: "bb" };

  test("is empty when the hashes match the lock", () => {
    expect(interfaceDrift(lock, { IA: "aa", IB: "bb" })).toEqual([]);
  });

  test("reports a changed hash", () => {
    const drift = interfaceDrift(lock, { IA: "aa", IB: "cc" });
    expect(drift).toHaveLength(1);
    expect(drift[0]).toContain("IB");
  });

  test("reports an interface missing from the lock", () => {
    const drift = interfaceDrift(lock, { IA: "aa", IB: "bb", IC: "cc" });
    expect(drift).toHaveLength(1);
    expect(drift[0]).toContain("IC");
  });

  test("reports an extra lock entry", () => {
    const drift = interfaceDrift({ ...lock, IOld: "dd" }, { IA: "aa", IB: "bb" });
    expect(drift).toHaveLength(1);
    expect(drift[0]).toContain("IOld");
  });
});
