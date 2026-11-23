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
| Code host / CI | GitHub (public repo `Panda-Dev-WEB3/Closari`), GitHub Actions | Matches §10 (Actions, Renovate) |
| Runtime target | OVH VPS (Docker Compose) | User's hosting choice |
| Repo layout | One Bun-workspace monorepo (option A) | ABIs flow from `forge build` into `@closari/core` with no cross-repo publishing |
| Package manager | Bun for everything, including the site | The site has three exact-pinned deps (react 19.2.0, react-dom 19.2.0, vite 7.2.2), so moving off pnpm is trivial; §10 requires `bun install --frozen-lockfile` |
| Media | Outside git, in a local media folder | ~180 MB of films, campaign and raster masters the site does not load |
| Web server | Caddy | SPA fallback and automatic TLS in a few lines |
| Licence | `SPDX-License-Identifier: UNLICENSED` | Open question 12 (MIT vs BUSL) is undecided; switching later is a one-line search-and-replace |
| Void rule | The audit's 60-minute TWAP rule (lifetime window for guardian voids) | The audit log amends the Overview; interfaces must match it |

**GitHub access:** pushes use a per-repository deploy key with write access; repository settings are managed in the GitHub UI by the repository owner.

## 3. Repository layout

```
<repo root>                         (branch main)
  package.json                      Bun workspaces: apps/*, packages/*, contracts; exact versions only
  bun.lock  .bun-version  .foundry-version  .nvmrc
  DEPENDENCIES.lock                 forge-std commit, vendored-file sha256s, npm and CI pins; checked in CI
  AGENTS.md  CLAUDE.md              from the handoff, paths updated to this layout
  .claude/skills/closari-graphics/  from the handoff; media paths point at Closari-media
  contracts/                        Foundry project, package @closari/contracts
    foundry.toml                    solc 0.8.28, evm_version cancun, fuzz/invariant profiles
    lib/                            git submodule: forge-std only (Solady and the Pyth SDK come from npm, see §4)
    src/vendor/                     vendored Chainlink and Permit2 interface files, pinned in DEPENDENCIES.lock
    src/interfaces/                 frozen I*.sol (§4.1)
    src/                            ExchangeCalendar, StockTokenAllowList, MarketFactory, lib/StrikeMath
    test/                           unit, fuzz, invariant, fork; test/mocks/
    script/                         DeployLocal.s.sol (anvil only; factory address predicted from the deployer nonce)
    deployments/4663-assets.json    pinned token addresses + scan block
  packages/core/                    @closari/core
    src/abi/                        generated, typed `as const`
    src/calendar/                   NYSE 2026–27 tables, DST → UTC sessions
    src/strikes/                    TS reference for strike/edge generation
    scripts/abi.ts                  ABI write/check/freeze; scan-tokens.ts, chain-probe.ts, gen-vectors.ts
  apps/site/                        the website (moved, unchanged behaviour)
    src/  public/  index.html  package.json  vite config
    serve-preview.mjs
    verification/                   the handoff's check scripts (+ result JSON); screenshots live in media
  apps/{keeper,indexer,api,mcp,calendar,hermes}/   README placeholders only
  infra/
    docker-compose.yml              Caddy (site) now; Postgres/Timescale, Redis, services as commented stubs
    Caddyfile
    README.md                       VPS hardening + deploy runbook
  security/triage.md                static-analysis triage log (Slither; Aderyn retired, §7.1)
  docs/
    internal/                       git-ignored, local only: product briefs, handoff notes, implementation plans, ledgers
    superpowers/specs/              this file
  .github/workflows/                ci.yml, nightly.yml, deploy-site.yml
  .github/renovate.json
```

**Kept outside git, in a local media folder:** the original ZIP (untouched archive), `artwork/`, `art-source/`, `campaign/`, verification screenshots. `.gitignore` also excludes `*.zip`, `apps/site/dist/`, `contracts/out/`, `contracts/cache/`, `node_modules/`, `.env*`.

The site's runtime images and fonts are under `apps/site/public` and stay in git (about 4 MB), so the site builds from a clean clone.

## 4. Contracts (M1)

Solidity 0.8.28, Foundry 1.8.1, Solady for math, clones, safe transfers, safe casts, reentrancy guard, EIP-712, ECDSA and `Timelock`.

**Dependencies (as built).** Solady 0.1.26 and the Pyth SDK 4.3.1 (`IPyth`, `PythStructs`, `MockPyth`; the old Pyth GitHub repo lacks `parsePriceFeedUpdatesUnique`) come from npm at exact versions, locked by `bun.lock` and listed in `DEPENDENCIES.lock`. `forge-std` is the only git submodule. Chainlink `AggregatorV3Interface` and Permit2 `ISignatureTransfer`/`IEIP712` are vendored files under `contracts/src/vendor/`, each pinned by upstream commit and sha256 in `DEPENDENCIES.lock` (the Chainlink repo cannot be checked out on Windows: paths too long). `scripts/checks/check-deps.ts` enforces the pins.

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

Additions made for M1's needs and frozen with the rest: `IMarketFactory` `hasMarkets`, `predictMarket`, `template`, `setListingBounty`, `listingBounty` and events `MarketSkipped`, `GuardianVoided`, `TemplateSet`, `SkipSet`; `ILMSRMarket` `config()`, `state()`; `IHousePool` `maturedQueuePending()`; external `IStockToken`, `IBeacon`, `IUSDG`.

After M1, changing an interface needs an "Interface change" entry appended to this spec, stating the reason and which milestones it affects, followed by `bun run abi:write && bun run abi:freeze && bun run abi:check`.

### 4.2 ExchangeCalendar

- Stores `Session {openTs, closeTs}` per `dayId`. A day with no session is closed.
- `setSessions` is `onlyTimelock`. It checks `openTs < closeTs`, `closeTs − openTs ∈ {12_600, 23_400}` and `openTs` within `dayId`'s UTC day, and reverts for any `dayId` that `factory.hasMarkets(dayId)` reports as listed.
- **Calendar ↔ factory cycle:** the calendar takes the factory address as a constructor immutable. CREATE2 cannot break this cycle, because each contract's initcode would contain the other's address. Instead the factory address is predicted from the deployer's nonce (`vm.computeCreateAddress`) and the factory deploys last; `DeployLocal.s.sol` and the test fixture assert the prediction. The mainnet deployment method is decided in M8 (see Cross-milestone obligations).
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
  10. the reference walk looks back up to 3 trading days: a listed day that is not final reverts `PreviousDayNotFinal`; a final day with `dayVoid == NONE` gives the reference; a voided or unlisted day is skipped. If no reference is found, `refPythUpdate` is parsed and must have `|publishTime − now| ≤ 120 s` and `conf/price ≤ 0.5%`.
  11. at least one template market opens, else `NoMarketsOpened` (see Interface change log).
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

- **ABIs.** `scripts/abi.ts write` reads `contracts/out/**.json` for every `I*.sol` and deployable contract and writes `src/abi/*.ts` as `as const`, so viem types follow. A CI check fails if the generated files differ from a fresh generation.
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
4. Fork tests on 4663. `RPC_4663` is a repository secret, defaulting to `https://rpc.mainnet.chain.robinhood.com`. The public RPC serves state only for recent blocks, so fork tests pin `FORK_BLOCK` only when it is set (which needs an archive RPC in `RPC_4663`) and otherwise run at `latest`
5. `forge coverage`, 95% or more for line and branch coverage on `src/` (mocks and scripts excluded)
6. Slither (`--fail-medium`). Any high or medium finding fails the run unless it is listed in `security/triage.md`. Aderyn was retired upstream (its repository is archived as "Retired and no longer maintained"; the npm package and binaries are withdrawn), so CI runs Slither only. `scripts/checks/check-aderyn.ts` is kept for a supplied report. **M8 must choose a second static analyser.**
7. `forge snapshot --check`. Fails on a gas regression over 5%
8. Grep tests: `uiMultiplier`/`multiplierSnapshot` in arithmetic only where allowed (I11). The banned words from Overview §14 must not appear in identifiers or API strings
9. Gitleaks. The forge-std submodule commit, vendored-file hashes and npm pins must match `DEPENDENCIES.lock`. The ABI-generation diff must be clean
10. `bun run site:build`

Every action is pinned by commit SHA. `nightly.yml` runs 50k invariant runs. Renovate opens PRs weekly and nothing auto-merges.

### 7.2 OVH VPS

- **`infra/docker-compose.yml`:** a Caddy service serving the built `apps/site/dist` with `try_files {path} /index.html` and automatic TLS for a domain set in `.env`. Postgres 16 + Timescale, Redis and the service containers are present as commented stubs for M4–M6.
- **`infra/README.md`:** hardening (SSH keys only, a non-root `deploy` user, ufw allowing 22/80/443, unattended upgrades, fail2ban) and the deploy runbook.
- **`deploy-site.yml`:** `workflow_dispatch` only. It builds the site and rsyncs over SSH using `VPS_HOST`, `VPS_USER` and `VPS_SSH_KEY` secrets, then reloads Caddy. **It does not run until the user adds the secrets and triggers it.**

### 7.3 GitHub

Public repo `Panda-Dev-WEB3/Closari`. Repository settings: branch protection on `main` (CI required, no force pushes) and Renovate enabled.

## 8. Tests (M1 acceptance)

| Area | Tests |
|---|---|
| Calendar | Early closes 2026-11-27 and 2026-12-24. DST edges 2026-11-01 and 2027-03-14. Rejection of wrong lengths, out-of-day sessions and `openTs ≥ closeTs`. Lock on listed days. `onlyTimelock`. `prevTradingDay` across weekends and holidays |
| Strikes | All 12 assets from the shared vector. Round-half-up at tick boundaries. Duplicate collapse. Strictly increasing. Multiplier rescale |
| AllowList (fork) | `isGenuine` true for NVDA, SPY and SOXX; false for USDG and for a look-alike made by `vm.etch`-ing NVDA's 283-byte proxy code with a different embedded beacon (SBXSTK and ACME are not deployed by the stock-token factory and have no known address). Each launch feed has `decimals() == 8` and `description()` of `"RH<TICKER> / USD"` or `"Robinhood <TICKER> / USD"` (six launch feeds use the latter) |
| `listDay` refusals | One test per check in §4.4, plus the second-listing refusal |
| `listDay` success | Predicted addresses match. `DayInfo` snapshot fields are unaffected by later timelock edits (I17). 8 markets with the right `Config`/`b`. Refused budget skips only that market. Bounty credited once. `hasMarkets` is set |
| Roles | Every external function is called by timelock, guardian and an arbitrary account, and the expected ones revert |
| Fuzz | Strike generation vs the TS reference over random refs, ticks and bps. Random session validity |
| Fork, environment | 4663 accepts Cancun bytecode (deploy a contract that uses `MCOPY`/`TSTORE`) |
| TS (`bun test`) | Calendar sessions match the on-chain vectors. Strike reference matches the vector. Generated ABIs match `forge inspect` |
| Deploy | `DeployLocal.s.sol` (`CLOSARI_LOCAL_DEPLOY=true`) on anvil, and on an anvil fork of 4663 with mocks: calendar seeded, assets set, `listDay` succeeds. Post-deploy: the deployer holds no role |

## 9. Definition of done

1. The repo is pushed to GitHub and every `ci.yml` job is green on `main`.
2. All interfaces in §4.1 are committed and frozen.
3. `@closari/core` exports typed ABIs and the calendar and strike references.
4. `apps/site` builds and serves the landing page and `/terminal/nvda`.
5. `contracts/deployments/4663-assets.json` holds the sixteen pinned launch symbols (incl. SOXX), with the scan block. SBXSTK and ACME have no known address (§8).
6. The anvil deploy script runs end to end.
7. `infra/` and `deploy-site.yml` exist. Nothing is deployed.

## 10. Prerequisites and risks

- **Bun** is not installed. It comes from the official installer, needs the user's approval, and the version is pinned in `.bun-version`.
- **GitHub access** via the repository's deploy key (see §2).
- **Public-RPC rate limits** may throttle fork tests in CI. If so, a paid RPC URL goes into `RPC_4663`.
- **Two unconfirmed (U) facts are checked live in M1:** that 4663 accepts Cancun, and that SBXSTK/ACME are not genuine (resolved: they are not deployed by the stock-token factory, so the look-alike etch test replaces them, §8). If either result differs from the brief, work stops and the finding is reported before the design is changed.
- **Windows host:** Slither runs in CI (Linux). Locally it runs in Docker if needed.

## Cross-milestone obligations

Found in the M1 final review. Each later milestone must honour these; the M1 factory relies on them.

1. **M3 oracle:** it must finalise close results for listed days with zero or partially created markets. Otherwise the factory's reference walk (§4.4, check 10) reverts `PreviousDayNotFinal` and blocks listing for the next 3 trading days. — done in M3: the oracle finalises any listed day's close independently of how many markets exist (SettlementOracle.submitClose/finalizeClose/voidExpired); SettlementE2E lists the next day from it.
2. **M3 `settleMarkets`:** it must skip `address(0)` entries in `DayInfo.markets`, and must treat `resolve`/`voidMarket` on an already-final market (for example after `guardianVoid`) as a no-op, so batches do not revert. — done in M3: settleMarkets skips address(0) and any market not in Trading before calling it (SettlementOracleSettle.test_settle_skipsEmptyAndFinal_batchBountyOnce).
3. **M7 pool:** refusals in `allocate` must revert with a non-empty custom error and must never wrap a gas-starved inner failure into one, because the factory treats empty revert data as `AllocationFailed` (and reverts the listing) while any non-empty revert skips the market.
4. **M7 router:** `creditBounty` must never revert for an insufficient balance. It accrues a debt or caps the amount instead, so `listDay` and settlement cannot halt (I14).
5. **`CA_AFTER = 3600`** must be identical in the factory, the market and the oracle. Move it into a shared constants library when M2 adds the market. — done in M2: `src/lib/Constants.sol` defines `CA_AFTER` once, and the factory and the market both read it.
6. **M2 market implementation:** block `initialize` on the implementation contract itself (its constructor marks it initialised). — done in M2: the `LMSRMarket` constructor sets `_core.initialized = true`, so `initialize` on the implementation reverts `AlreadyInitialized`.
7. **Deploy ordering:** the pool, oracle and router take the nonce-predicted factory address, and the factory deploys last (§4.2). The M8 script deploys and initialises the Timelock atomically, with a 48 h delay.
8. **Gas:** `listDay` measured 4.04M with mock markets (`security/triage.md`). Re-measure with the real `LMSRMarket` in M2 for the keeper's gas budget. — done in M2: re-measured with real `LMSRMarket` clones in the `security/triage.md` "Gas (M2)" section.
9. **M8 deploy:** `PriorMath` is a linked library (`raw`, `floorNormalize`, `liquidity` are public, to keep `MarketFactory` under 22 KB). The mainnet script must deploy it and link it into `MarketFactory`; `forge script` runs need `--sender`.

## Open decisions before M2/M7

- **(a) LMSR opening price (final-review #6).** Markets open at uniform prices. ABOVE ±2% and ±5% open at 0.50 against true chances of about 0.25 and 0.05, and the reviewer estimates about 1.8 budgets per token per day lost to the first arbitrageurs. Options: a factory-seeded prior (a `Config` change), near-money strikes only, or listing before the open only. Owner: the product owners. Must be decided before M2 freezes market initialisation.
- **(b) Listing vs. sweep ordering before M7.** Either a pool view such as `pendingSweeps()`, or a keeper rule to list only after the previous day's sweeps and `processQueue`.
- **(c) Early-close days.** No listing until the 13:00 feed behaviour is confirmed. Enforce it with guardian `setSkip` or in the M4 keeper.
- **(d) Pyth reference on the listing path.** The reference is caller-chosen within 120 s (the non-Unique parse). Document it as accepted, or switch to the Unique parse in M3. — decided 2026-11-22: kept as is (caller-chosen within 120 s); accepted risk recorded in security/triage.md.
- **(e) VPS.** Before M4, remove the `deploy` user from the `docker` group (use a forced-command/rrsync key) and add required reviewers to the `production` environment.

## Interface change log

### 2026-11-21 — IMarketFactory.TooEarly(uint32 dayId)
- Change: new error; `listDay(D)` reverts until the previous trading day's close has passed (no bound if no session exists in the prior 10 days).
- Why: the Task 9 review found that any caller could list far-future days with a stale Pyth reference, lock the calendar early, tie up pool budget and collect bounties. The Overview intends day D to be listed right after D−1 settles.
- Affects: M4 keeper (`listDay` job already runs after D−1 is final); M8 deploy scripts.

### 2026-11-21 — IMarketFactory.NoMarketsOpened(address token, uint32 dayId)
- Change: new error; `listDay` reverts `NoMarketsOpened` when every template market is skipped. The whole transaction reverts, so `createdTs`, `hasMarkets` and the listing bounty roll back and the day stays listable.
- Why: final-review finding #1a. A listing that opened nothing still paid the bounty, set `hasMarkets` (locking the calendar day) and blocked a retry, for example after a transient pool refusal or a budget misconfiguration.
- Affects: M4 keeper (treat `NoMarketsOpened` as retryable once the cause is fixed); M4 indexer (no `DayListed` for such a day).

### 2026-11-21 — IMarketFactory skip reason 5 (documentation of skip reason 5)
- Change: NatSpec only, no ABI change. `MarketSkipped(token, dayId, index, 5)`: the UPDOWN market is not listed when `block.timestamp >= openTs`.
- Why: final-review finding #2. An UP/DOWN market prices the move from the open; listing it after the open lets buyers trade on an already-known direction.
- Affects: M4 keeper and indexer (new skip reason value); M2 market (UPDOWN markets always have `createdTs < openTs`).

### 2026-11-21 — ILMSRMarket fee views and pullFees; IFeeRouter.fundBounty and bountyBalance
- Change: `ILMSRMarket` adds `feeEscrow()`, `feesPaid(address)`, `feesByBuilder(address)`, `builderFeesTotal()` and `pullFees() returns (uint256 amount)` (only the router, only when `state == Resolved`; transfers `feeEscrow` to the router; a second call returns 0). NatSpec on `sweep`/`Swept`: under the pull model `sweep` does not move fees, and `Swept.feesToRouter` reports fees already pulled, which may be 0. `IFeeRouter` adds `event BountyFunded(address indexed from, uint256 amount)`, `fundBounty(uint256)` (anyone; pulls USDG from the caller into the bounty balance) and `bountyBalance()`.
- Why: final-review finding #3. Backend §3.8 says "distribute pulls feeEscrow from a resolved market", but the frozen interfaces had no way for the router to read or pull a market's fees or builder attribution, and no way to fund the bounty balance that `creditBounty` draws on.
- Affects: M2/M3 market (implements the views and `pullFees`), M7 router (`distribute` calls `pullFees`; implements `fundBounty`/`bountyBalance`), M4 keeper and indexer (new event). No M1 contract calls these; `MockMarket` is unchanged.

### 2026-11-21 — M2: ILMSRMarket Config/errors/views, IStockTokenAllowList.Asset.volBps, IMarketFactory fees
- Change: `ILMSRMarket.Config` adds `priorWad`, `baseFeeBps`, `rampMaxBps`; `ILMSRMarket` adds trading errors and the views `cumulativeAt(uint64)` and `checkpoints()`. `IStockTokenAllowList.Asset` adds `uint16 volBps` (required in [25, 2000] when listed). `IMarketFactory` adds `setFees(uint16,uint16)`, `fees()`, `FeesSet`, `BadFees`. `Constants.B_MIN` is now 100 shares (no ABI change).
- Why: open decision (a), decided 2026-11-21 as a seeded opening price from per-asset volatility, with worst-case loss ≤ budget (M2 spec §3). Fee parameters are snapshotted per market (I9). The accumulator views feed the M3 void price.
- Affects: M3 (reads checkpoints; implements settlement), M4 keeper/indexer (new Config fields, FeesSet), M5 API (quotes use the prior-seeded state), M8 deploy (volBps and fee values).

### 2026-11-22 — ISettlementOracle: finalizeOpen, bounties, errors and events (M3)
- Change: adds `finalizeOpen(address,uint32)`, `setBounties(uint96,uint96,uint96)` (onlyTimelock, each ≤ 5 USDG), `bounties()`, events `OpenFinal` and `BountiesSet`, and 14 custom errors (`NotListed`, `TooEarly`, `TooLate`, `AlreadyFinal`, `TierNotHigher`, `WrongFeed`, `InsufficientFee`, `NotFinal`, `NoUpDownMarket`, `BadOpen`, `PhaseMismatch`, `BadRound`, `NotTimelock`, `BountyTooHigh`). No existing signature changes.
- Why: the open uses the same tier precedence as the close, so a tier B/C open needs a finalisation call after the improvement window (M3 spec §9.4); bounties are timelocked parameters (§9.5).
- Affects: M4 keeper (calls `finalizeOpen` 30 min after a B/C open; reads `OpenFinal`), M4 indexer, M8 deploy (sets bounties through the timelock).

### 2026-11-22 — ILMSRMarket: claimable, finalInfo and settlement errors (M3)
- Change: adds `claimable(address) view returns (uint256)`, `finalInfo() view returns (uint8 winner, uint8 voidReason, uint256[] voidPricesWad)`, and errors `NotFactory`, `NotRouter`, `NotFinal`, `NotResolved`, `AlreadySwept`, `BadReason`, `TooEarly`. No existing signature changes.
- Why: the UI, API and keeper need what an account can claim and the final outcome without replaying events (M3 spec §6–§7).
- Affects: M4 indexer and API, M5 web app.
