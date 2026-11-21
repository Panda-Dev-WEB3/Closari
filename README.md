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

Media (films, campaign, art masters) lives outside git in the local media folder.
