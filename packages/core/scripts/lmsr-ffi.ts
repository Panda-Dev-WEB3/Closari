// vm.ffi entry for the Solidity differential tests (FOUNDRY_PROFILE=ffi). Prints ABI-encoded hex only.
import Decimal from "decimal.js";
import { encodeAbiParameters } from "viem";
import { buyExact, rawPrior, sellExact } from "../src/lmsr/index.ts";

const [mode, ...a] = process.argv.slice(2);
const toUint = (d: Decimal, up: boolean) =>
  BigInt(d.toDecimalPlaces(0, up ? Decimal.ROUND_CEIL : Decimal.ROUND_FLOOR).toFixed(0));

if (mode === "cost") {
  const [side = "", bWad = "0", k = "0", sh = "0", ...xs] = a;
  const x = xs.map((v) => BigInt(v));
  const exact =
    side === "buy"
      ? buyExact(x, BigInt(bWad), Number(k), BigInt(sh))
      : sellExact(x, BigInt(bWad), Number(k), BigInt(sh));
  process.stdout.write(encodeAbiParameters([{ type: "uint256" }], [toUint(exact, side === "buy")]));
} else if (mode === "prior") {
  const [ref8 = "0", vol = "0", ...edges] = a;
  const p = rawPrior(
    BigInt(ref8),
    edges.map((e) => BigInt(e)),
    Number(vol),
  );
  process.stdout.write(
    encodeAbiParameters([{ type: "uint256[]" }], [p.map((v) => toUint(v.mul("1e18"), false))]),
  );
} else {
  console.error(
    "usage: lmsr-ffi.ts cost <buy|sell> <bWad> <k> <sharesBase> <x...> | prior <ref8> <volBps> <edges...>",
  );
  process.exit(2);
}
