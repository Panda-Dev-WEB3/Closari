# Closari

Monorepo: `apps/site` (paper-trading website), `contracts` (Foundry), `packages/core` (ABIs + references), `infra` (OVH VPS). Start with `README.md`. The design spec and plan live in `docs/superpowers/`. The briefs are in `docs/briefs/` (the Backend brief's 2026-11-18 audit log governs the void rule: 60-minute TWAP, lifetime window for guardian voids).

Rules:
- Keep paper fills and illustrative chart histories visibly labeled. The protocol is undeployed. A code change never authorizes publication, real transactions, contract deployment or a VPS deploy.
- Private briefs and handoff docs stay outside `apps/site/public` and `apps/site/dist`.
- Run `bun run site:build` and check phone and desktop after substantive site changes.
- Contracts: follow `docs/briefs/CLOSARI_Backend.md` §3 and the frozen interfaces (`contracts/interfaces.lock.json`). Changing an interface needs an "Interface change" entry in the spec.
- Graphics work uses the `closari-graphics` skill. Media masters are outside git in the local media folder.
