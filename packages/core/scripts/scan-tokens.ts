// Enumerates every Robinhood Chain stock token from the stock-token factory's events and pins the launch set.
// The token address is the first 32-byte word of the event data (verified on NVDA's creation tx, 2026-11-21).
// --check: compare with the pinned file without writing it. Exits 1 if a launch token's address, the proxy
// codehash or the beacon changed (or a launch token is missing); only warns when new tokens appeared.
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import {
  type Address,
  createPublicClient,
  getAddress,
  type Hex,
  http,
  keccak256,
  parseAbi,
  toHex,
} from "viem";

const RPC = process.env.RPC_4663 ?? "https://rpc.mainnet.chain.robinhood.com";
const FACTORY = "0x4783c67b63de2b358ac5951a7d41f47a38f3c046";
const TOPIC = "0xd9b0c6a1c0de228715ad0fa09f3259686ee84f8cc675e03ef7e47a9cdafa76d6";
const BEACON = "0xe10b6f6b275de231345c20d14ab812db62151b00";
const NVDA = "0xd0601ce157db5bdc3162bbac2a2c8af5320d9eec";
const EXPECTED_CODEHASH = "0x6c1fdd40002dcb440c7fff6a84171404d279ccb057803b65826f7546acd65630";
const WANTED = [
  "NVDA",
  "TSLA",
  "SPY",
  "QQQ",
  "AAPL",
  "META",
  "AMZN",
  "MSFT",
  "GOOGL",
  "AMD",
  "PLTR",
  "MU",
  "SOXX",
  "SPCX",
  "GME",
  "CRCL",
];
const STEP = 5_000_000n;
const OUT = join(import.meta.dir, "..", "..", "..", "contracts", "deployments", "4663-assets.json");

export type PinnedScan = {
  beacon: string;
  proxyCodehash: string;
  totalTokens: number;
  tokens: Record<string, string | undefined>;
};

/** Compares a fresh scan with the pinned file. Errors fail the nightly job; warnings do not. */
export function pinDrift(
  pinned: PinnedScan,
  scanned: PinnedScan,
  wanted: readonly string[],
): { errors: string[]; warnings: string[] } {
  const errors: string[] = [];
  const warnings: string[] = [];
  const same = (a: string, b: string) => a.toLowerCase() === b.toLowerCase();
  for (const s of wanted) {
    const pin = pinned.tokens[s];
    const now = scanned.tokens[s];
    if (!pin) errors.push(`${s} is not pinned in 4663-assets.json`);
    else if (!now) errors.push(`${s} is missing from the scan (pinned ${pin})`);
    else if (!same(pin, now)) errors.push(`${s} moved: pinned ${pin}, scanned ${now}`);
  }
  if (!same(pinned.proxyCodehash, scanned.proxyCodehash))
    errors.push(
      `proxyCodehash changed: pinned ${pinned.proxyCodehash}, now ${scanned.proxyCodehash}`,
    );
  if (!same(pinned.beacon, scanned.beacon))
    errors.push(`beacon changed: pinned ${pinned.beacon}, now ${scanned.beacon}`);
  if (scanned.totalTokens > pinned.totalTokens)
    warnings.push(
      `::warning::new stock tokens since the pinned scan (${pinned.totalTokens} -> ${scanned.totalTokens})`,
    );
  return { errors, warnings };
}

const client = createPublicClient({ transport: http(RPC, { batch: true, retryCount: 3 }) });
const symbolAbi = parseAbi(["function symbol() view returns (string)"]);
const beaconAbi = parseAbi(["function implementation() view returns (address)"]);

async function main(check: boolean): Promise<void> {
  const head = await client.getBlockNumber();
  const tokens: Address[] = [];
  for (let from = 0n; from <= head; from += STEP) {
    const to = from + STEP - 1n > head ? head : from + STEP - 1n;
    const logs = (await client.request({
      method: "eth_getLogs",
      params: [{ address: FACTORY, topics: [TOPIC], fromBlock: toHex(from), toBlock: toHex(to) }],
    })) as { data: Hex }[];
    for (const l of logs) tokens.push(getAddress(`0x${l.data.slice(26, 66)}`));
  }

  const unique = [...new Set(tokens)];
  tokens.length = 0;
  tokens.push(...unique);

  const nvdaHash = keccak256((await client.getCode({ address: NVDA })) ?? "0x");
  if (nvdaHash !== EXPECTED_CODEHASH)
    throw new Error(`NVDA codehash ${nvdaHash} != ${EXPECTED_CODEHASH}`);

  const bySymbol: Record<string, Address> = {};
  let genuine = 0;
  for (let i = 0; i < tokens.length; i += 12) {
    const batch = tokens.slice(i, i + 12);
    const rows = await Promise.all(
      batch.map(async (address) => {
        const code = (await client.getCode({ address })) ?? "0x";
        const symbol = await client.readContract({
          address,
          abi: symbolAbi,
          functionName: "symbol",
        });
        return { address, symbol, genuine: keccak256(code) === EXPECTED_CODEHASH };
      }),
    );
    for (const r of rows) {
      if (r.genuine) genuine++;
      if (!WANTED.includes(r.symbol)) continue;
      if (!r.genuine)
        throw new Error(`launch symbol ${r.symbol} on non-genuine token ${r.address}`);
      const prior = bySymbol[r.symbol];
      if (prior)
        throw new Error(
          `launch symbol ${r.symbol} is on two genuine tokens: ${prior} and ${r.address}`,
        );
      bySymbol[r.symbol] = r.address;
    }
  }
  const missing = WANTED.filter((s) => !bySymbol[s]);
  if (missing.length && !check) throw new Error(`missing tokens: ${missing.join(", ")}`);

  const beaconImplementation = await client.readContract({
    address: BEACON,
    abi: beaconAbi,
    functionName: "implementation",
  });
  const out = {
    chainId: 4663,
    scanBlock: Number(head),
    scannedAt: new Date().toISOString(),
    stockTokenFactory: FACTORY,
    factoryTopic: TOPIC,
    beacon: BEACON,
    beaconImplementation,
    proxyCodehash: EXPECTED_CODEHASH,
    totalTokens: tokens.length,
    genuineTokens: genuine,
    tokens: Object.fromEntries(WANTED.map((s) => [s, bySymbol[s]])),
  };
  if (check) {
    const pinned = JSON.parse(readFileSync(OUT, "utf8")) as PinnedScan;
    const { errors, warnings } = pinDrift(pinned, out, WANTED);
    for (const w of warnings) console.log(w);
    if (errors.length) {
      for (const e of errors) console.error(`::error::${e}`);
      process.exit(1);
    }
    console.log("pinned tokens unchanged");
    return;
  }
  writeFileSync(OUT, `${JSON.stringify(out, null, 2)}\n`);
  console.log(`scanned ${tokens.length} tokens (${genuine} genuine) at block ${head}`);
}

if (import.meta.main) await main(process.argv.includes("--check"));
