import { describe, expect, test } from "bun:test";
import { type PinnedScan, pinDrift } from "../scripts/scan-tokens.ts";

const pinned: PinnedScan = {
  beacon: "0xe10b6f6b275de231345c20d14ab812db62151b00",
  proxyCodehash: "0x6c1fdd40002dcb440c7fff6a84171404d279ccb057803b65826f7546acd65630",
  totalTokens: 213,
  tokens: {
    NVDA: "0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC",
    TSLA: "0x322F0929c4625eD5bAd873c95208D54E1c003b2d",
  },
};
const wanted = ["NVDA", "TSLA"];

describe("scan --check (pinDrift)", () => {
  test("silent when the pinned tokens are unchanged", () => {
    expect(pinDrift(pinned, { ...pinned }, wanted)).toEqual({ errors: [], warnings: [] });
  });

  test("address comparison ignores checksum case", () => {
    const scanned = {
      ...pinned,
      tokens: { ...pinned.tokens, NVDA: pinned.tokens.NVDA?.toLowerCase() },
    };
    expect(pinDrift(pinned, scanned, wanted).errors).toEqual([]);
  });

  test("error when a wanted symbol's address differs", () => {
    const scanned = {
      ...pinned,
      tokens: { ...pinned.tokens, TSLA: "0x0000000000000000000000000000000000000001" },
    };
    const { errors } = pinDrift(pinned, scanned, wanted);
    expect(errors).toHaveLength(1);
    expect(errors[0]).toContain("TSLA");
  });

  test("error when a wanted symbol is missing from the scan or the pin", () => {
    const scanned = { ...pinned, tokens: { NVDA: pinned.tokens.NVDA } };
    expect(pinDrift(pinned, scanned, wanted).errors[0]).toContain("TSLA");
    const pin = { ...pinned, tokens: { NVDA: pinned.tokens.NVDA } };
    expect(pinDrift(pin, pinned, wanted).errors[0]).toContain("TSLA");
  });

  test("error when proxyCodehash or beacon differ", () => {
    const scanned = {
      ...pinned,
      beacon: "0x0000000000000000000000000000000000000002",
      proxyCodehash: `0x${"11".repeat(32)}`,
    };
    const { errors } = pinDrift(pinned, scanned, wanted);
    expect(errors).toHaveLength(2);
    expect(errors.join("\n")).toContain("beacon");
    expect(errors.join("\n")).toContain("proxyCodehash");
  });

  test("warning only when totalTokens grew", () => {
    const { errors, warnings } = pinDrift(pinned, { ...pinned, totalTokens: 220 }, wanted);
    expect(errors).toEqual([]);
    expect(warnings).toHaveLength(1);
    expect(warnings[0]).toStartWith("::warning::");
    expect(warnings[0]).toContain("213");
    expect(warnings[0]).toContain("220");
  });
});
