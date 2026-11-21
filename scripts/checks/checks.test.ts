import { describe, expect, test } from "bun:test";
import { bannedIn } from "./check-banned-words.ts";
import { coverageOf } from "./check-coverage.ts";
import { multiplierViolations } from "./check-multiplier.ts";

describe("multiplier rule (I11)", () => {
  test("flags multiplier arithmetic outside PriceMath", () => {
    expect(
      multiplierViolations("src/X.sol", "uint256 p = price * uiMultiplier / 1e18;"),
    ).toHaveLength(1);
    expect(multiplierViolations("src/X.sol", "x = a / day.multiplierSnapshot;")).toHaveLength(1);
  });
  test("flags evasive forms", () => {
    for (const l of [
      "price*uiMultiplier/1e18",
      "FixedPointMathLib.mulDiv(price, uiMultiplier, 1e18)",
      "price.mulWad(day.multiplierSnapshot)",
      "p ** mult",
    ])
      expect(multiplierViolations("src/X.sol", l)).toHaveLength(1);
  });
  test("allows assignments, comparisons, comments and PriceMath", () => {
    expect(multiplierViolations("src/X.sol", "day.multiplierSnapshot = mult;")).toHaveLength(0);
    expect(
      multiplierViolations("src/X.sol", "if (t.newUIMultiplier() != mult) revert X();"),
    ).toHaveLength(0);
    expect(multiplierViolations("src/X.sol", "// price * multiplier / 1e18")).toHaveLength(0);
    expect(
      multiplierViolations(
        "src/lib/PriceMath.sol",
        "return share8 * int256(multiplierWad) / 1e18;",
      ),
    ).toHaveLength(0);
  });
});

describe("banned words", () => {
  test("splits identifiers and finds banned words", () => {
    expect(bannedIn("function placeBet() external {}")).toEqual(["bet"]);
    expect(bannedIn('const label = "Expected yield";')).toEqual(["yield"]);
    expect(bannedIn("uint256 betweenTicks; // alphabet")).toEqual([]);
    expect(bannedIn('error RiskFree(); string s = "binary option";')).toEqual([
      "risk-free",
      "binary option",
    ]);
  });
});

describe("coverage", () => {
  test("sums src files only", () => {
    const lcov = [
      "SF:src/A.sol",
      "LF:10",
      "LH:10",
      "BRF:4",
      "BRH:4",
      "end_of_record",
      "SF:test/mocks/M.sol",
      "LF:10",
      "LH:0",
      "BRF:2",
      "BRH:0",
      "end_of_record",
      "SF:src/vendor/V.sol",
      "LF:5",
      "LH:0",
      "end_of_record",
    ].join("\n");
    expect(coverageOf(lcov)).toEqual({ lines: 1, branches: 1, files: ["src/A.sol"] });
  });
});
