// Live checks against chain 4663 that the contracts rely on. Exits 1 on any failure.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { type Address, createPublicClient, type Hex, http, keccak256, parseAbi } from "viem";

const RPC = process.env.RPC_4663 ?? "https://rpc.mainnet.chain.robinhood.com";
const client = createPublicClient({ transport: http(RPC, { retryCount: 3 }) });
const assets = JSON.parse(
  readFileSync(
    join(import.meta.dir, "..", "..", "..", "contracts", "deployments", "4663-assets.json"),
    "utf8",
  ),
) as { proxyCodehash: Hex; beacon: Address; tokens: Record<string, Address> };

const failures: string[] = [];
const check = (ok: boolean, what: string) => {
  console.log(`${ok ? "ok  " : "FAIL"} ${what}`);
  if (!ok) failures.push(what);
};

// PUSH1 1, PUSH0, TSTORE, PUSH0, TLOAD, PUSH0, MSTORE, PUSH1 0x20, PUSH0, PUSH1 0x20, MCOPY, PUSH1 0x20, PUSH1 0x20, RETURN
const CANCUN_PROBE = "0x60015f5d5f5c5f5260205f60205e60206020f3";
const call = (data: Hex) =>
  client.request({ method: "eth_call", params: [{ data }, "latest"] }) as Promise<Hex>;

const chainId = await client.getChainId();
check(chainId === 4663, `chain id is 4663 (got ${chainId})`);
check(BigInt(await call(CANCUN_PROBE)) === 1n, "PUSH0 / TSTORE / TLOAD / MCOPY execute");
let blobRejected = false;
try {
  await call("0x4a5f5260205ff3");
} catch {
  blobRejected = true;
}
check(blobRejected, "BLOBBASEFEE is rejected (Arbitrum) — contracts must not use blob opcodes");

const present: Record<string, Address> = {
  USDG: "0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168",
  PythCore: "0x8250f4aF4B972684F7b336503E2D6dFeDeB1487a",
  Multicall3: "0xcA11bde05977b3631167028862bE2a173976CA11",
  Create2Deployer: "0x4e59b44847b379578588920ca78fbf26c0b4956c",
  Permit2: "0x000000000022D473030F116dDEE9F6B43aC78BA3",
  Beacon: assets.beacon,
};
for (const [name, address] of Object.entries(present)) {
  const code = await client.getCode({ address });
  check(!!code && code !== "0x", `${name} has code at ${address}`);
}
const impl = await client.readContract({
  address: assets.beacon,
  abi: parseAbi(["function implementation() view returns (address)"]),
  functionName: "implementation",
});
check(impl !== "0x0000000000000000000000000000000000000000", `beacon implementation ${impl}`);
for (const t of ["NVDA", "SPY", "SOXX"]) {
  const address = assets.tokens[t] as Address;
  const hash = keccak256((await client.getCode({ address })) ?? "0x");
  check(hash === assets.proxyCodehash, `${t} codehash matches the pinned proxy codehash`);
}

if (failures.length) process.exit(1);
