// Enumerates every Robinhood Chain stock token from the stock-token factory's events and pins the launch set.
// The token address is the first 32-byte word of the event data (verified on NVDA's creation tx, 2026-11-21).
import { writeFileSync } from "node:fs";
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

const client = createPublicClient({ transport: http(RPC, { batch: true, retryCount: 3 }) });
const symbolAbi = parseAbi(["function symbol() view returns (string)"]);
const beaconAbi = parseAbi(["function implementation() view returns (address)"]);

async function main(): Promise<void> {
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
      if (WANTED.includes(r.symbol) && !bySymbol[r.symbol]) bySymbol[r.symbol] = r.address;
    }
  }
  const missing = WANTED.filter((s) => !bySymbol[s]);
  if (missing.length) throw new Error(`missing tokens: ${missing.join(", ")}`);

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
  writeFileSync(OUT, `${JSON.stringify(out, null, 2)}\n`);
  console.log(`scanned ${tokens.length} tokens (${genuine} genuine) at block ${head}`);
}

await main();
