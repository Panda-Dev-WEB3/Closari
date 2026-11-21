# Closari monorepo + M1 — design

_Date: 2026-11-21. Status: approved in brainstorming, pending written-spec review._
_Sources: `CLOSARI_Overview.md`, `CLOSARI_Backend.md` (incl. the 2026-11-18 audit log), `CLOSARI-Website-Handoff.zip` (START-HERE, AGENTS, Dashboard-Audit, DESIGN-AND-STATUS)._

## 1. Goal and scope

Set up the single Closari repository and deliver milestone **M1** of the Backend brief (§11):

- one Bun-workspace monorepo holding the existing website, the Foundry contracts, the shared TypeScript core and placeholders for the services;
- pinned toolchain and the §10 CI pipeline on GitHub Actions;
- `ExchangeCalendar`, `StockTokenAllowList` and `MarketFactory` implemented and tested, with mocks for every other contract;
- **all contract interfaces frozen** and their ABIs generated into `@closari/core`;
- OVH VPS infrastructure written, but not deployed.

**Out of scope for M1:** LMSR math and trading (M2), settlement and void accounting (M3), keeper/Hermes (M4), indexer/API (M5), MCP (M6), HousePool/FeeRouter/$CLSR (M7), security pass and launch (M8), any live deployment, any change to the website's design or behaviour.

## 2. Decisions taken

| Decision | Choice | Why |
|---|---|---|
| First sub-project | Monorepo + M1 | Every later milestone builds on M1's frozen interfaces |
| Code host / CI | GitHub, private repo under **Panda-Dev-WEB3**, GitHub Actions | Matches §10 (Actions, Renovate) |
| Runtime target | OVH VPS (Docker Compose) | User's hosting choice |
| Repo layout | One Bun-workspace monorepo (option A) | ABIs flow from `forge build` into `@closari/core` with no cross-repo publishing |
| Package manager | Bun for everything, including the site | The site has three exact-pinned deps (react 19.2.0, react-dom 19.2.0, vite 7.2.2), so moving off pnpm is trivial; §10 requires `bun install --frozen-lockfile` |
| Media | Outside git, in the local media folder | ~180 MB of films, campaign and raster masters the site does not load |
| Web server | Caddy | SPA fallback and automatic TLS in a few lines |
| Licence | `SPDX-License-Identifier: UNLICENSED` | Open question 12 (MIT vs BUSL) is undecided; switching later is a one-line search-and-replace |
| Void rule | The audit's 60-minute TWAP rule (lifetime window for guardian voids) | The audit log amends the Overview; interfaces must match it |

**GitHub access:** pushes use a per-repository deploy key with write access; repository settings are managed in the GitHub UI by the repository owner.

## 3. Repository layout

```
<repo root>                 (repo root, branch main)
  package.json                      Bun workspaces: apps/*, packages/*, contracts; exact versions only
  bun.lock  .bun-version  .foundry-version  .nvmrc
  DEPENDENCIES.lock                 submodule → commit table, checked in CI
  AGENTS.md  CLAUDE.md              from the handoff, paths updated to this layout
  .claude/skills/closari-graphics/  from the handoff; media paths point at Closari-media
  contracts/                        Foundry project, package @closari/contracts
    foundry.toml                    solc 0.8.28, evm_version cancun, fuzz/invariant profiles
    lib/                            git submodules: solady, pyth (interfaces), chainlink (interfaces), permit2 (interfaces)
    src/interfaces/                 frozen I*.sol (§4.1)
    src/                            ExchangeCalendar, StockTokenAllowList, MarketFactory, lib/StrikeMath
    test/                           unit, fuzz, invariant, fork; test/mocks/
    script/                         Deploy.s.sol (CREATE2, deterministic), ScanBeacon.s.sol
    deployments/4663-assets.json    pinned token addresses + scan block
  packages/core/                    @closari/core
    src/abi/                        generated, typed `as const`
    src/calendar/                   NYSE 2026–27 tables, DST → UTC sessions
    src/strikes/                    TS reference for strike/edge generation
    scripts/gen-abi.ts
  apps/site/                        the website (moved, unchanged behaviour)
    src/  public/  index.html  package.json  vite config
    serve-preview.mjs
    verification/                   the handoff's check scripts (+ result JSON); screenshots live in media
  apps/{keeper,indexer,api,mcp,calendar,hermes}/   README placeholders only
  infra/
    docker-compose.yml              Caddy (site) now; Postgres/Timescale, Redis, services as commented stubs
    Caddyfile
    README.md                       VPS hardening + deploy runbook
  security/triage.md                Slither/Aderyn triage log
  docs/
    briefs/                         CLOSARI_Overview.md, CLOSARI_Backend.md (one copy each)
    handoff/                        Dashboard-Audit, DESIGN-AND-STATUS, art-direction, GRAPHICS, inspo-research, token-sources, Backend-Handoff.pdf
    superpowers/specs/              this file
  .github/workflows/                ci.yml, nightly.yml, deploy-site.yml
  .github/renovate.json
```

**Kept outside git, in the local media folder:** the original ZIP (untouched archive), `artwork/`, `art-source/`, `campaign/`, verification screenshots. `.gitignore` also excludes `*.zip`, `apps/site/dist/`, `contracts/out/`, `contracts/cache/`, `node_modules/`, `.env*`.

The site's runtime images and fonts are under `apps/site/public` and stay in git (about 4 MB), so the site builds from a clean clone.

## 4. Contracts (M1)

Solidity 0.8.28, Foundry 1.8.1, Solady for math, clones, safe transfers, reentrancy guard, EIP-712, ECDSA and `Timelock`. Pyth `IPyth`/`PythStructs`, Chainlink `AggregatorV3Interface` and Permit2 `ISignatureTransfer` are vendored as interfaces only, at pinned commits.

### 4.1 Frozen interfaces

Copied from Backend §3 with the audit amendments, then frozen:

| Interface | Source |
|---|---|
| `IExchangeCalendar` | §3.1 |
| `IStockTokenAllowList` | §3.2 (incl. `Asset` struct) |
| `IMarketFactory` | §3.3 (incl. `DayInfo` snapshot fields `openTs`, `closeTs`, `pythId`, `clFeed`; `setSkip`; `guardianVoid`) |
| `ILMSRMarket` | §3.4 (incl. `TradeIntent`, the `ClaimDeferred` event) |
| `ISettlementOracle` | §3.5 (phase-safe `clRoundId`, `VoidReason` incl. `GUARDIAN`) |
| `IHousePool` | §3.7 (incl. `depositWithAuthorization` with `salt`) |
| `IFeeRouter` | §3.8 |
| `IClsrStaking` | §3.9 |
| `IStockToken` | ERC-8056 subset: `uiMultiplier`, `newUIMultiplier`, `effectiveAt`, `oraclePaused` |
| `IUSDG` | EIP-3009 (`receiveWithAuthorization`, `cancelAuthorization`, `authorizationState`) + EIP-2612 `permit` |

After M1, changing an interface needs an "Interface change" entry appended to this spec, stating the reason and which milestones it affects.

### 4.2 ExchangeCalendar

- Stores `Session {openTs, closeTs}` per `dayId`. A day with no session is closed.
- `setSessions` is `onlyTimelock`. It checks `openTs < closeTs`, `closeTs − openTs ∈ {12_600, 23_400}` and `openTs` within `dayId`'s UTC day, and reverts for any `dayId` that `factory.hasMarkets(dayId)` reports as listed.
- **Calendar ↔ factory cycle:** the calendar takes the factory address as a constructor immutable. `Deploy.s.sol` deploys through CREATE2 with fixed salts, so the factory address is known before either contract exists.
- `prevTradingDay(dayId, maxLookback)` walks back over closed days within the bound.

### 4.3 StockTokenAllowList

- Immutables: `BEACON` (`0xe10b6f6b275de231345c20d14ab812db62151b00`) and `PROXY_CODEHASH`. In the deploy script, `PROXY_CODEHASH` is read from the NVDA token (`0xd0601ce157db5bdc3162bbac2a2c8af5320d9eec`) and passed in at construction.
- `isGenuine(token)`: `token.codehash == PROXY_CODEHASH && IBeacon(BEACON).implementation() != address(0)`.
- `setAsset` is `onlyTimelock`. It requires `isGenuine` and `AggregatorV3Interface(clFeed).decimals() == 8`.

### 4.4 MarketFactory

- **Checks in `listDay`, in order** (each with its own custom error):
  1. not listing-paused;
  2. the asset is listed and genuine;
  3. a session exists;
  4. `block.timestamp < closeTs − 600 − 3600`;
  5. the (token, dayId) has not been listed;
  6. not skipped;
  7. `!oraclePaused()`;
  8. no pending multiplier change with `effectiveAt ≤ closeTs + 3600`;
  9. the pool has no matured, unprocessed queue;
  10. the previous trading day's close is final in the oracle, **or** more than 3 trading days have passed without a final close. In that case `refPythUpdate` is parsed and must have `|publishTime − now| ≤ 120 s` and `conf/price ≤ 0.5%`.
- **Snapshots into `DayInfo`:** `createdTs`, `openTs`, `closeTs`, `pythId`, `clFeed`, `multiplierSnapshot = uiMultiplier()` and `refPrice8`. Nothing in `DayInfo` is re-read later (I17).
- **Reference price:** `ref = prevClose.price8 × currentMultiplier / prevSnapshot`. This is the factory's one allowed use of a multiplier in arithmetic, together with `_toTokenTerms` in M3 (I11).
- **Strikes** come from `lib/StrikeMath.sol`: `roundHalfUp(ref × (10_000 + k) / 10_000, tickPrice8)`. Duplicates collapse, and the result must be strictly increasing. RANGE uses `edgeBps`, giving `n = edges + 1` buckets. UPDOWN has no edge at listing.
- **Clones:** `LibClone.cloneDeterministic(marketImpl, keccak256(abi.encode(token, dayId, index)))`, then `initialize(Config, pool, oracle, router, staking)`. Each market gets `budget` from its `Asset` field for its kind and `b = floor(budget × 1e18 / (lnWad(n) + 1))`.
- **Budgets:** for each template index, the factory calls `pool.allocate(predicted, budget)` inside `try`/`catch`, using the predicted clone address. Only if that succeeds does it deploy and initialise the clone. A refused allocation leaves no clone, and that index stays empty. Indices are positional, so every address remains predictable. The rest of the day still lists. A view `predictMarket(token, dayId, index)` exposes the addresses before listing.
- **First listing of a token** (no previous trading day was ever listed): this follows the same `refPythUpdate` path as the more-than-3-days case.
- **Admin functions:**
  - `setTemplate` (`onlyTimelock`): at most 8 ABOVE strikes and at most 8 buckets; bps sorted strictly increasing.
  - `setListingPaused` and `setSkip` (`onlyGuardian`): they only stop new listings.
  - `guardianVoid` (`onlyGuardian`): requires `isMarket(m)` and `block.timestamp < haltTs`, then calls `market.voidMarket(GUARDIAN)`.
- **Bounty:** `router.creditBounty(msg.sender, LISTING_BOUNTY)` once per (token, dayId).
- **`hasMarkets(dayId)`:** set on the first listing of that day. The calendar reads it.
- **Launch template:** `strikeBps = [-500,-200,-100,100,200,500]`, `edgeBps = [-200,-50,50,200]`, `upDown = true`. That is 8 markets per token per day.

### 4.5 Mocks (`test/mocks/`, never deployed to 4663)

| Mock | Behaviour needed in M1 |
|---|---|
| `MockMarket` | Implements `initialize` and `voidMarket`. Records its config so tests can assert snapshots |
| `MockHousePool` | `allocate` can be told to refuse. Settable "matured queue pending" flag |
| `MockFeeRouter` | Records `creditBounty` calls |
| `MockSettlementOracle` | Settable final/non-final close results per (token, dayId) |
| `MockPyth` | Returns configured price feeds for `parsePriceFeedUpdates*`. Charges a configurable update fee |
| `MockStockToken` | Settable `uiMultiplier`, `newUIMultiplier`, `effectiveAt` and `oraclePaused`. Same proxy shape for codehash tests where possible |
| `MockAggregator` | Settable decimals, description and rounds |
| `MockUSDG` | ERC-20 with freeze and pause switches (used from M2 on, but defined now) |

### 4.6 Roles

- **Timelock:** Solady `Timelock`, 48 h in production and a short delay on anvil. Its proposer and executor is a multisig address passed to the deploy script.
- **Guardian:** an address passed to the deploy script.
- **Deployer:** holds no roles after deployment. A post-deploy test checks this.
- **No contract in M1 holds or moves USDG**, apart from the factory calling `pool.allocate`.

## 5. `@closari/core`

- **ABIs.** `scripts/gen-abi.ts` reads `contracts/out/**.json` for every `I*.sol` and deployable contract and writes `src/abi/*.ts` as `as const`, so viem types follow. A CI check fails if the generated files differ from a fresh generation.
- **Calendar.** `src/calendar/` holds the NYSE 2026–2027 holiday and early-close tables from Overview §11 and Backend §1. It computes `openTs`/`closeTs` in UTC with DST via `Intl` (America/New_York), along with `dayId`, `haltTs = closeTs − 600`, and the fee-ramp start `haltTs − 1800`.
- **Strikes.** `src/strikes/` is a bigint TS reference of `StrikeMath`. A shared JSON vector (`contracts/test/vectors/strikes.json`) is produced from it and checked by both `bun test` and a Foundry test that reads it with `vm.readFile`.

## 6. Website move

- Move the handoff's `site/` into `apps/site/` with source, public and config unchanged. Delete `pnpm-lock.yaml` and `pnpm-workspace.yaml`. Generate `bun.lock` at the root. Keep the scripts `dev`, `build` and `preview`.
- Root scripts: `bun run site:dev`, `site:build`, `site:preview`.
- **Verification:** `apps/site` builds with `bun run site:build`. `serve-preview.mjs` serves the build. The landing page and `/terminal/nvda` load. The handoff's `verification/*` scripts that need Playwright are run once locally and their results recorded; they are not added to CI in M1.
- The `docs/` and `.claude/` paths in AGENTS.md and CLAUDE.md are updated. The private briefs stay outside `apps/site/public` and `dist` (per AGENTS.md).

## 7. CI and VPS

### 7.1 `ci.yml` (push and PR)

1. `forge fmt --check`, `bun run lint`, `bun run typecheck`
2. `forge build --sizes`. Fails if any contract is over 24 KB
3. Unit, fuzz (10k runs) and invariant (1,000 × 200) tests
4. Fork tests at a pinned block on 4663. `RPC_4663` is a repository secret, defaulting to `https://rpc.mainnet.chain.robinhood.com`
5. `forge coverage`, 95% or more for line and branch coverage on `src/` (mocks and scripts excluded)
6. Slither and Aderyn. Any high or medium finding fails the run unless it is listed in `security/triage.md`
7. `forge snapshot --check`. Fails on a gas regression over 5%
8. Grep tests: `uiMultiplier`/`multiplierSnapshot` in arithmetic only where allowed (I11). The banned words from Overview §14 must not appear in identifiers or API strings
9. Gitleaks. The submodule commits must match `DEPENDENCIES.lock`. The ABI-generation diff must be clean
10. `bun run site:build`

Every action is pinned by commit SHA. `nightly.yml` runs 50k invariant runs. Renovate opens PRs weekly and nothing auto-merges.

### 7.2 OVH VPS

- **`infra/docker-compose.yml`:** a Caddy service serving the built `apps/site/dist` with `try_files {path} /index.html` and automatic TLS for a domain set in `.env`. Postgres 16 + Timescale, Redis and the service containers are present as commented stubs for M4–M6.
- **`infra/README.md`:** hardening (SSH keys only, a non-root `deploy` user, ufw allowing 22/80/443, unattended upgrades, fail2ban) and the deploy runbook.
- **`deploy-site.yml`:** `workflow_dispatch` only. It builds the site and rsyncs over SSH using `VPS_HOST`, `VPS_USER` and `VPS_SSH_KEY` secrets, then reloads Caddy. **It does not run until the user adds the secrets and triggers it.**

### 7.3 GitHub

Private repo `Panda-Dev-WEB3/closari` (name to confirm). Once the repo exists: branch protection on `main` (CI required, no force pushes) and Renovate enabled.

## 8. Tests (M1 acceptance)

| Area | Tests |
|---|---|
| Calendar | Early closes 2026-11-27 and 2026-12-24. DST edges 2026-11-01 and 2027-03-14. Rejection of wrong lengths, out-of-day sessions and `openTs ≥ closeTs`. Lock on listed days. `onlyTimelock`. `prevTradingDay` across weekends and holidays |
| Strikes | All 12 assets from the shared vector. Round-half-up at tick boundaries. Duplicate collapse. Strictly increasing. Multiplier rescale |
| AllowList (fork) | `isGenuine` true for NVDA, SPY and SOXX; false for SBXSTK and ACME. Each launch feed has `decimals() == 8` and `description() == "RH<TICKER> / USD"` |
| `listDay` refusals | One test per check in §4.4, plus the second-listing refusal |
| `listDay` success | Predicted addresses match. `DayInfo` snapshot fields are unaffected by later timelock edits (I17). 8 markets with the right `Config`/`b`. Refused budget skips only that market. Bounty credited once. `hasMarkets` is set |
| Roles | Every external function is called by timelock, guardian and an arbitrary account, and the expected ones revert |
| Fuzz | Strike generation vs the TS reference over random refs, ticks and bps. Random session validity |
| Fork, environment | 4663 accepts Cancun bytecode (deploy a contract that uses `MCOPY`/`TSTORE`) |
| TS (`bun test`) | Calendar sessions match the on-chain vectors. Strike reference matches the vector. Generated ABIs match `forge inspect` |
| Deploy | `Deploy.s.sol` on anvil, and on an anvil fork of 4663 with mocks: calendar seeded, assets set, `listDay` succeeds. Post-deploy: the deployer holds no role |

## 9. Definition of done

1. The repo is pushed to GitHub and every `ci.yml` job is green on `main`.
2. All interfaces in §4.1 are committed and frozen.
3. `@closari/core` exports typed ABIs and the calendar and strike references.
4. `apps/site` builds and serves the landing page and `/terminal/nvda`.
5. `contracts/deployments/4663-assets.json` holds the twelve launch tokens plus SOXX, SBXSTK and ACME, with the scan block.
6. The anvil deploy script runs end to end.
7. `infra/` and `deploy-site.yml` exist. Nothing is deployed.

## 10. Prerequisites and risks

- **Bun** is not installed. It comes from the official installer, needs the user's approval, and the version is pinned in `.bun-version`.
- **GitHub access** to Panda-Dev-WEB3 (see §2).
- **Public-RPC rate limits** may throttle fork tests in CI. If so, a paid RPC URL goes into `RPC_4663`.
- **Two unconfirmed (U) facts are checked live in M1:** that 4663 accepts Cancun, and that SBXSTK/ACME are not genuine. If either result differs from the brief, work stops and the finding is reported before the design is changed.
- **Windows host:** Slither and Aderyn run in CI (Linux). Locally they run in Docker if needed.
