# Closari

Daily close and range markets on Robinhood Chain stock tokens. Design draft; nothing is deployed.

| Path | What |
|---|---|
| `apps/site` | The paper-trading website (React/Vite) |
| `contracts` | Foundry project (`@closari/contracts`) |
| `packages/core` | Generated ABIs, calendar and strike references (`@closari/core`) |
| `apps/{keeper,indexer,api,mcp,calendar,hermes}` | Services, from M4 on |
| `infra` | OVH VPS stack (Caddy now, services later) |
| `docs` | Briefs, handoff notes, specs and plans |

Setup: Bun 1.4.2 (`.bun-version`), Foundry 1.8.1 (`.foundry-version`), Node 24.

    bun install --frozen-lockfile
    git submodule update --init --recursive
    bun run site:build && bun run site:preview      # http://127.0.0.1:4173/
    bun run contracts:test

Checks (as CI runs them):

    bun run lint && bun run typecheck && bun test scripts/checks packages
    bun run checks                                  # dependency pins, I11 multiplier rule, banned words
    bun run contracts:build && bun run abi:check

Fork tests run against Robinhood Chain (4663). `RPC_4663` defaults to the public RPC, which serves state only for
recent blocks, so `FORK_BLOCK` (a pinned block) needs an archive RPC; without it the tests run at `latest`.

    RPC_4663=<archive rpc> FORK_BLOCK=<block> bun run contracts:test:fork

Local deploy (anvil only; mocks are never deployed to 4663). The script refuses unless `CLOSARI_LOCAL_DEPLOY=true`
and the chain is anvil (31337) or an anvil fork of 4663:

    anvil --port 8545                                              # or: anvil --fork-url "$RPC_4663" --port 8546
    cd contracts && CLOSARI_LOCAL_DEPLOY=true forge script script/DeployLocal.s.sol --rpc-url http://127.0.0.1:8545 --broadcast

Frozen interfaces (`contracts/src/interfaces`, hashes in `contracts/interfaces.lock.json`): never edit an interface
without first appending an entry to the "Interface change log" in
`docs/superpowers/specs/2026-11-21-closari-monorepo-m1-design.md` (what changed, why, which milestones it affects).
Then rebuild and re-freeze:

    bun run contracts:build && bun run abi:write && bun run abi:freeze && bun run abi:check

Media (films, campaign, art masters) lives outside git in the local media folder.
