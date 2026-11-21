# Closari

Monorepo: `apps/site` (paper-trading website), `contracts` (Foundry), `packages/core` (ABIs + references), `infra` (OVH VPS). Start with `README.md`. The design spec lives in `docs/superpowers/specs/`.

This repository is **public**. Internal working documents (the product briefs, handoff notes, implementation plans and execution ledgers) live in `docs/internal/`, which is git-ignored and exists only on the maintainers' machines. The Backend brief there (`docs/internal/briefs/CLOSARI_Backend.md`) is the contract design source; its 2026-11-18 audit log governs the void rule (60-minute TWAP, lifetime window for guardian voids).

Rules:
- Never commit secrets, personal names or account details, machine-specific paths, or anything from `docs/internal/`. Keys and RPC URLs with credentials belong in GitHub secrets or on the server only.
- Keep paper fills and illustrative chart histories visibly labeled. The protocol is undeployed. A code change never authorizes publication, real transactions, contract deployment or a VPS deploy.
- Run `bun run site:build` and check phone and desktop after substantive site changes.
- Contracts: follow the Backend brief §3 and the frozen interfaces (`contracts/interfaces.lock.json`). Never edit an interface without first adding an entry to the spec's "Interface change log" (what, why, affected milestones); then run `bun run abi:write && bun run abi:freeze && bun run abi:check`. Never run `abi:freeze` to silence `abi:check` without that entry.
- Graphics work uses the `closari-graphics` skill. Media masters are kept outside git in the maintainers' local media folder.
