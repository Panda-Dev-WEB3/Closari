# Closari M3: settlement, voids, claims and sweep, design

Date: 2026-11-22. Builds on the M1 design (`2026-11-21-closari-monorepo-m1-design.md`) and the M2 design (`2026-11-21-closari-m2-lmsr-market-design.md`). The M1 spec's "Cross-milestone obligations" and "Interface change log" stay binding. Sources: Backend §3.4 (settlement hooks), §3.5, §3.6, §3.7 (sweep only), §3.8 (fee pull and bounties), §3.11 and §3.12.

## 1. Goal and scope

M3 makes every listed market end, and pays everyone out:

- `SettlementOracle`: close results (Pyth tiers, Chainlink cross-check, corporate-action freeze), opens for UPDOWN markets, `settleMarkets`, and settler bounties;
- `LMSRMarket`: `resolve`, `voidMarket`, `claim`, `claimMany`, `sweep` and `pullFees`, which revert `NotYetImplemented()` in M2;
- the guardian path: `MarketFactory.guardianVoid` now works end to end;
- the checks deferred from M2 (`initialize` self-checks, `setOpenReference` timing).

**Out of scope:** the real `HousePool` and `FeeRouter` (M7), the keeper (M4) and the Hermes fetcher (M4). The pool and the router stay mocks.

## 2. Decisions taken

| Topic | Decision |
|---|---|
| Market size | `LMSRMarket` is 20,169 B of the 24,576 B limit. The settlement logic goes into a linked library, `MarketSettlement` (§3), like `PriorMath`. Lowering the optimizer runs (trade gas) and a delegate settlement contract (shared storage layout) were rejected |
| Hermes key | None yet. Unit tests use the SDK's `MockPyth`. The real-update fixture tests are written but skipped until a key is set in a local env var or a CI secret, never committed. They are a release gate before M8 |
| Void price window per reason | Settlement voids: the 60 min before `haltTs`. An UPDOWN market with no open recorded: the window ending at `openTs`, whatever the reason. Guardian: `[createdTs, now]` (§5) |
| Open finality | Same tier rules as the close. Tier A is final at once; tier B or C needs the new `finalizeOpen` after `IMPROVE_WINDOW`. UPDOWN trading can stay paused up to 30 min longer in that case; accepted, so the submitter cannot choose the open |
| Claims to frozen accounts | A refused transfer leaves the claim unclaimed and emits `ClaimDeferred`; the call does not revert (§6) |
| Void sweep reserve | `Σ_i ceil(t_i · v_i / 1e18)`, an upper bound on the per-account floored payouts. A few base units of dust stay in the market |
| Bounties | Set through the timelock with `setBounties`, each capped at 5 USDG in code. Proposed values: 2 USDG per final close, 1 per token-day's settlement, 0.5 per final open |
| Devnet | The devnet deploy wires the real oracle with `MockPyth`. End-to-end settlement is proven by the in-process smoke test, because the devnet runs in real time; devnet settlement waits for the M4 keeper |
| M1 open decision (d) | The listing reference stays caller-chosen within 120 s (non-Unique parse). It is documented as an accepted risk in `security/triage.md` |
| Unique-parse mock (planning) | SDK `MockPyth.parsePriceFeedUpdatesUnique` skips the uniqueness check. Tests and `DeployLocal` use `test/mocks/MockPythUnique.sol`, a forwarder that enforces it. Real Pyth behaviour stays a fork-fixture release gate |
| `paidOut` (planning) | Public getter on the market (not in the interface): share payouts claimed, fee refunds excluded. After final, I2 is `balance ≥ cash + feeEscrow − paidOut − sweptReturned` |
| Deployment order (planning) | The oracle deploys after the calendar and allow-list and before the factory (factory predicted at `nonce + 3`), because it takes the factory address |
| Kind arity (planning) | `validateConfig` also requires `n == 2` for ABOVE and UPDOWN, and reverts `ILMSRMarket.BadConfig()` |
| Finalise and expiry reverts (planning) | `finalizeClose`/`finalizeOpen`: `AlreadyFinal` if final, `TooEarly` if nothing stored or the window is open. `voidExpired`/`voidNoOpen`: `AlreadyFinal` if final, `TooEarly` if something is stored or the window has not passed |

## 3. Architecture

| Unit | Responsibility |
|---|---|
| `SettlementOracle` (new, one per deployment) | Close and open results per (token, dayId), the Chainlink cross-check, the CA freeze, `settleMarkets`, bounties. Constructor immutables: `pyth`, `factory`, `router`, `timelock` |
| `LMSRMarket` | Storage, access checks and every token transfer: `resolve`, `voidMarket`, `claim`, `claimMany`, `sweep`, `pullFees`, plus the new views `claimable` and `finalInfo` |
| `MarketSettlement` (new linked library, `public` functions) | Pure computation: `validateConfig` (the `initialize` checks, §8), `voidPrices` (§5), `voidOwed` (one account's void payout, §6) and `voidReserve` (§7) |
| `MarketFactory` | Unchanged code. `guardianVoid` now reaches a real `voidMarket` |
| `PriceMath` (existing) | `to8`, `toTokenTerms`, `toTokenTermsConf`: still the only multiplier arithmetic (I11) |

The library adds no gas to trades: only settlement paths call it. **Size gate:** `LMSRMarket` runtime ≤ 23,500 B, which leaves about 1 KB below the 24,576 B limit for M7. `SettlementOracle` must stay under 24,576 B.

## 4. Market: final states and who may call

| Function | Caller | Requires |
|---|---|---|
| `resolve(winner, settlePrice8)` | oracle only | state `Trading`; `block.timestamp ≥ closeTs`; `winner < n` |
| `voidMarket(reason)` from the oracle | oracle | state `Trading`; `reason ∉ {NONE, GUARDIAN}` and `≤ GUARDIAN`; `block.timestamp ≥ haltTs`, except `NO_OPEN`, which needs an UPDOWN market with no open and `block.timestamp ≥ openTs` |
| `voidMarket(GUARDIAN)` | factory only | state `Trading`; `block.timestamp < haltTs` |

- The oracle already enforces its own timing. The market checks again (defence in depth): an oracle bug cannot end a market early.
- A market ends once. A second `resolve` or `voidMarket` reverts `NotTrading`. The oracle skips final markets before calling (M1 obligation 2), so a batch never reverts.
- On resolve the market stores the winner and the reserve `t_w` (trader shares of the winner), sets `Resolved` and emits `Resolved(winner, settlePrice8)`.
- On void it stores the reason, the void prices (§5) and the reserve (§7), sets `Voided` and emits `Voided(reason, voidPricesWad)`.
- Wrong caller: `NotOracle` / `NotFactory`. Bad reason: `BadReason`. Timing: `TooEarly`.

## 5. Void prices

`v_i = floor((cum_i(t_stop) − cum_i(t_start)) / W)` with `W = t_stop − t_start`, WAD, read from the M2 accumulator.

| Case | `t_start` | `t_stop` |
|---|---|---|
| UPDOWN with no open recorded and `now ≥ openTs` (any reason, guardian included) | checkpoint 1: `max(openTs − 3600, createdTs)` | `openTs` |
| Any other oracle void | checkpoint 0: `max(haltTs − 3600, createdTs)` | `haltTs` |
| Guardian void (other cases) | `createdTs` (cumulative 0) | `block.timestamp` |

- `cum(t_start)` comes from the stored checkpoint, or from `cumulativeAt(t_start)` when no trade crossed it (exact, as in M2). `cum(t_stop)` is `cumulativeAt(t_stop)`; no trade can happen after `t_stop`, so `_lastTs ≤ t_stop`.
- **Zero-length window** (a guardian void in the listing block): `v = priorWad`. No time has passed, so the prior is the only price the window has.
- Each `v_i` is floored, so `Σ v_i ≤ 1e18` (I16). Packed as 8 × `uint64` in two slots, written once.
- Backend §3.6's solvency proof holds for any `v` in the simplex, with `t` (trader liability, M2 spec §3) in place of `q`.

## 6. Claims

- `claim(account)`: anyone may call; it always pays `account`. Returns the amount paid.
  - Resolved: `shares[account][winner]`.
  - Voided: `voidOwed = Σ_i floor(shares[account][i] · v_i / 1e18) + feesPaid[account]`. The fee part reduces `feeEscrow`.
- The account is marked claimed, then the transfer is attempted with a non-reverting transfer. If USDG refuses it (frozen recipient, paused token), the mark and any `feeEscrow` change are undone, `ClaimDeferred(account, amount)` is emitted, and the call returns 0. The account can claim again later.
- An account owed nothing returns 0 with no event and no mark.
- `claimMany(accounts)` runs the same logic per account; one refused transfer never blocks the others.
- `claimable(account)` returns what `claim` would pay now (0 before final or once claimed).
- Claims never touch `cash`, so claims and the sweep can happen in any order. Totals paid are tracked in `paidOut` for I2.
- Reverts: `NotFinal` before the market is final. Protected by the existing reentrancy guard.

## 7. Sweep and fees

- `sweep()`: permissionless, once, after final (`NotFinal`, `AlreadySwept`).
  - Reserve: `t_w` on resolve; `voidReserve = Σ_i ceil(t_i · v_i / 1e18)` on void.
  - `returned = cash > reserve ? cash − reserve : 0`.
  - Transfers `returned` to the pool, then calls `pool.onSweep(budget, returned, lastWorst, lastBest)`, where `lastWorst = cash − max_i t_i` and `lastBest = cash − min_i t_i` are the marks the pool holds for this market.
  - Emits `Swept(returned, feesAlreadyPulled)`.
  - If USDG refuses, the sweep reverts with no state change. Claims are unaffected.
- `liability()` after final returns the reserve (it does not shrink as claims are paid). Before final it is `max_i t_i`, as in M2.
- `pullFees()`: the router only (`NotRouter`), only when `Resolved` (`NotResolved`). Sends `feeEscrow` to the router and sets it to 0; a second call returns 0.
- On a void the fees stay in the market for the refunds and are never pulled.
- `finalInfo()` returns `(winner, voidReason, voidPricesWad)`; `voidPricesWad` is empty unless voided.

## 8. Checks deferred from M2

`MarketSettlement.validateConfig`, called from `initialize`, reverts `BadConfig` unless:

- `token != address(0)`;
- `B_MIN · 1e12 ≤ bWad ≤ B_MAX · 1e12`;
- the loss bound holds: `bWad · lnWad(1e36 / p_min) / 1e18 ≤ budget · 1e12`, with `p_min = min_i priorWad[i]`;
- edges match the kind: ABOVE exactly 1; RANGE exactly `n − 1`, strictly increasing; UPDOWN none; every edge `> 0`;
- UPDOWN: `createdTs < openTs < haltTs`;
- `haltTs > RAMP_WINDOW` (removes the `_rampElapsed` underflow found in the M2 final review);
- the existing M2 checks (n, prior, fees, times, non-zero pool and oracle) still apply.

`setOpenReference` also requires `openTs ≤ block.timestamp < haltTs` (`TooEarly`, `Halted`). Accepting it after the halt would roll the accumulator past `haltTs`, and `cumulativeAt(haltTs)` would then revert for a later void.

## 9. SettlementOracle

### 9.1 Constants (code, no setters)

`CONF_MAX_BPS = 50`, `CL_FRESH = 900`, `CL_DIVERGE_BPS = 100`, `SETTLE_WINDOW = 7200`, `IMPROVE_WINDOW = 1800`, `OPEN_WINDOW = 7200`, `MAX_BOUNTY = 5e6` (5 USDG). `CA_AFTER` comes from `Constants.sol` (M1 obligation 5).

### 9.2 Binding

Every function reads `factory.dayInfo(token, dayId)`. A day with `createdTs == 0` reverts `NotListed`. The feed ID, `openTs`, `closeTs`, `clFeed`, `multiplierSnapshot`, `createdTs` and the market list come from that snapshot, never from the caller or the live allow-list (I17). Pyth's update fee is paid from `msg.value` (`InsufficientFee`); any excess is refunded. Payable functions are reentrancy-guarded.

### 9.3 Close

**Tier windows** (`parsePriceFeedUpdatesUnique`): A `[closeTs, closeTs]`, B `[closeTs − 5, closeTs]`, C `[closeTs − 60, closeTs]`.

`submitClose(token, dayId, tier, pythUpdate, clRoundId)`:

1. Timing: `now ≥ closeTs` (`TooEarly`). With nothing stored, `now ≤ closeTs + SETTLE_WINDOW`; otherwise `now < firstSubmitTs + IMPROVE_WINDOW` (`TooLate`). Not final (`AlreadyFinal`). `tier > stored.tier` (`TierNotHigher`; `NONE` never passes).
2. Parse with the tier's window and `[day.pythId]`; require `feeds[0].id == day.pythId` (`WrongFeed`).
3. `PriceMath.to8`, then the per-submission checks: `price ≤ 0` → `BAD_PRICE`; `conf × 10_000 > price × CONF_MAX_BPS` → `CONF_WIDE`.
4. Token terms: `toTokenTerms` and `toTokenTermsConf` with `day.multiplierSnapshot` (the only multiplication, I11).
5. **First submission only:**
   - **CA freeze:** `uiMultiplier() != snapshot` or (`newUIMultiplier() != snapshot` and `effectiveAt() ∈ [createdTs, closeTs + CA_AFTER]`) → `CORP_ACTION`; `oraclePaused()` → `ORACLE_PAUSED`. Stored and never re-evaluated.
   - **Chainlink round**, phase-safe, with `P = latestRoundData().roundId >> 64`:
     - `clRoundId != 0`: require `clRoundId >> 64 == P` (`PhaseMismatch`), `0 < updatedAt ≤ closeTs`, and round + 1 absent (reverts, or `updatedAt == 0`) or `updatedAt > closeTs` (else `BadRound`).
     - `clRoundId == 0`: require `getRoundData((P << 64) | 1).updatedAt > closeTs` (else `BadRound`); the cross-check is then unavailable.
     - `answer ≤ 0` also makes it unavailable. The answer is token terms with 8 decimals (the allow-list enforces 8 at `setAsset`) and is **never** multiplied.
     - Stored once: available, fresh (`closeTs − updatedAt ≤ CL_FRESH`), answer. `CrossCheck` is emitted.
6. **Divergence**, on every submission, against the stored round: fresh and `|cl − pyth| × 10_000 > pyth × CL_DIVERGE_BPS` → `DIVERGENCE`.
7. **Day void precedence:** the frozen CA/pause reason, else `BAD_PRICE`, else `CONF_WIDE`, else `DIVERGENCE`, else `NONE`. A higher tier can clear the last three, never the first.
8. Store the result and the submitter. Set `firstSubmitTs` if unset. Emit `CloseSubmitted`. Tier A is final at once (§9.5).

`finalizeClose`: a stored tier B or C, not final, `now ≥ firstSubmitTs + IMPROVE_WINDOW` → final. It reverts `AlreadyFinal` if the result is final, and `TooEarly` if nothing is stored or the window is still open.

`voidExpired`: nothing stored and `now > closeTs + SETTLE_WINDOW` → final with `dayVoid = NO_PRICE`, no bounty.

### 9.4 Open (UPDOWN)

The UPDOWN market is the day's last market (the factory always places it last); the oracle checks it is non-zero and its `config().kind == UPDOWN`, else `NoUpDownMarket`.

**Tier windows:** A `[openTs, openTs]`, B `[openTs, openTs + 5]`, C `[openTs, openTs + 60]`.

- `recordOpen(token, dayId, tier, pythUpdate)`: same timing rules as the close around `openTs` and `OPEN_WINDOW`; same parse and binding; no Chainlink check, no CA check. `price ≤ 0` or wide confidence reverts `BadOpen`, so the open stays unset and a higher tier can still land. Emits `OpenRecorded`. Tier A is final at once.
- `finalizeOpen(token, dayId)` (new): a stored tier B or C after `IMPROVE_WINDOW` → final.
- `voidNoOpen(token, dayId)`: nothing stored and `now > openTs + OPEN_WINDOW` → open final with `dayVoid = NO_OPEN`; the market is voided with `NO_OPEN` if still trading.
- **When an open becomes final**, the oracle calls `market.setOpenReference(price8, conf8)` only if the market is still trading and `now < haltTs`, credits the open bounty to the submitter, and emits `OpenFinal`. After the halt the market never receives the open: it stayed paused all day, settlement uses the oracle's final open directly, and a void uses the window ending at `openTs` (§5).

### 9.5 Finality and bounties

When a close result becomes final (tier A on submit, `finalizeClose`, or `voidExpired`), it is frozen (I8) and `DayFinal` is emitted. The close bounty goes to the submitter of the final result (not for `voidExpired`). Bounties are credited with `router.creditBounty(settler, amount)` and skipped when the amount is 0; the router must never revert (M1 obligation 4). Each bounty pays at most once per (action, token, day).

`setBounties(closeBounty, batchBounty, openBounty)`: `onlyTimelock` (`NotTimelock`), each `≤ MAX_BOUNTY` (`BountyTooHigh`), emits `BountiesSet`. `bounties()` returns the three values. They start at 0; deploy scripts set them.

### 9.6 settleMarkets(token, dayId, from, to)

- Requires a final close (`NotFinal`). `to` is clamped to the market count. Skips `address(0)` and markets not in `Trading` (M1 obligation 2).
- UPDOWN first brings the open up to date: a stored B/C open past its window is finalised (§9.4; no push after the halt), and an empty open past `OPEN_WINDOW` becomes `NO_OPEN`.
- Per market, with `S = price8`, `c = conf8`:
  - `dayVoid != NONE` → `voidMarket(dayVoid)`;
  - ABOVE (`K = edges[0]`): `|S − K| ≤ c` → `TIE_ZONE`; else winner 1 if `S > K`, else 0;
  - RANGE: any `|S − E_j| ≤ c` → `TIE_ZONE`; else the winner is the number of edges `≤ S`;
  - UPDOWN: no final valid open → `NO_OPEN`; `|S − O| ≤ c + c_o` → `TIE_ZONE`; else winner 1 (UP) if `S > O`, else 0.
- The batch bounty goes once per (token, day) to the first call that settles at least one market.
- Days with some or no markets created still reach a final close (M1 obligation 1). Every market can be final by `closeTs + SETTLE_WINDOW + IMPROVE_WINDOW` whatever the caller (I14).

## 10. Interface changes (approved 2026-11-22; logged in the M1 spec's change log by the implementing task)

| Interface | Change |
|---|---|
| `ISettlementOracle` | Adds `finalizeOpen(address token, uint32 dayId)`; `setBounties(uint96 closeBounty, uint96 batchBounty, uint96 openBounty)`; `bounties() returns (uint96, uint96, uint96)`; `event BountiesSet(uint96 closeBounty, uint96 batchBounty, uint96 openBounty)`; `event OpenFinal(address indexed token, uint32 indexed dayId, int64 price8, VoidReason dayVoid)`; errors `NotListed(address token, uint32 dayId)`, `TooEarly()`, `TooLate()`, `AlreadyFinal()`, `TierNotHigher()`, `WrongFeed(bytes32 got)`, `InsufficientFee(uint256 required)`, `NotFinal()`, `NoUpDownMarket()`, `BadOpen()`, `PhaseMismatch()`, `BadRound()`, `NotTimelock()`, `BountyTooHigh()` |
| `ILMSRMarket` | Adds `claimable(address account) view returns (uint256)`; `finalInfo() view returns (uint8 winner, uint8 voidReason, uint256[] memory voidPricesWad)`; errors `NotFactory()`, `NotRouter()`, `NotFinal()`, `NotResolved()`, `AlreadySwept()`, `BadReason()`, `TooEarly()` |
| `IMarketFactory`, `IHousePool`, `IFeeRouter` | No change |

No existing signature changes. `abi:freeze` is rerun and `interfaces.lock.json` is updated in the same commit as each change.

## 11. Factory, mocks, config and deploy

- `MarketFactory`: no code change. Its tests switch the guardian path from `NotYetImplemented` to a real void.
- Mocks: `MockHousePool.onSweep` records its arguments; `MockFeeRouter.creditBounty` records calls and can call `pullFees`; `MockUSDG` freeze and pause switches drive the deferred-claim tests; `MockAggregator` gains phased round IDs; `MockSettlementOracle` stays for the M1/M2 factory tests.
- `config/assets.4663.json`: fill `pythId` with the regular-session US equity feed IDs from Hermes's public `/v2/price_feeds` metadata, each marked "confirm before M8".
- `DeployLocal.s.sol`: deploys `MarketSettlement`, links it into `LMSRMarket`, deploys the real `SettlementOracle` with `MockPyth` (taking the nonce-predicted factory address, M1 obligation 7), and sets the bounties to 2 / 1 / 0.5 USDG. The cert-server devnet is redeployed with `REDEPLOY=1`.
- M8 deploy note: `MarketSettlement` is a second linked library, next to `PriorMath` (M1 obligation 9).

## 12. Tests (M3 acceptance)

| Area | Tests |
|---|---|
| Close tiers | Tier precedence (only strictly higher replaces), improvement window from the first submission, tier A final at once, `finalizeClose`, `voidExpired`, `TooLate` after `SETTLE_WINDOW`, refund of excess fee |
| Binding (I17) | An update for another feed or another second is rejected; the feed and times come from `DayInfo` even after the allow-list or calendar changes |
| Chainlink | Old-phase round rejected (`PhaseMismatch`); `clRoundId = 0` path; the not-the-last-round case (`BadRound`); stale round lets Pyth govern; divergence voids; later higher tiers are checked against the stored round; the answer is never multiplied |
| Day voids | conf, divergence, bad price, CA (each condition) and pause, for each kind; CA frozen at the first submission (a pause after it does not void) |
| Tie zones | ABOVE, RANGE (each edge) and UPDOWN boundaries, including `c = 0` |
| Opens | Tier A pushes at once; B/C via `finalizeOpen`; wide conf reverts `BadOpen`; `voidNoOpen`; `settleMarkets` catches up a missed `finalizeOpen`; guardian-voided UPDOWN is skipped |
| Market access | Every `resolve`/`voidMarket` caller and timing rule in §4; second final call reverts; `settleMarkets` skips empty and final markets |
| Void (Backend §3.6) | `test_void_washCycle_noDrain`, `testFuzz_void_bounded` (also with an arbitrary simplex `v`), `test_void_lastMinutePush_unprofitable`, `test_voidNoOpen_noAtomicPush`, `test_guardianVoid_lifetimeTWAP`, zero-length window uses the prior, `test_void_netPaidRule_isDrainable` (reference rule in the test folder only) |
| Claims | Resolve and void payouts; fee refunds; frozen recipient → `ClaimDeferred` while the others in `claimMany` are paid, and the deferred claim succeeds after unfreeze; claims and sweep in either order |
| Sweep and fees | `returned` and `onSweep` arguments on both outcomes; sweep once; sweep under a USDG pause reverts and later succeeds; settlement itself works while USDG is paused; `pullFees` router-only and resolved-only |
| Bounties | Each pays once per (action, token, day), to the right settler; caps and `onlyTimelock` |
| Init (deferred) | Each new `validateConfig` rule rejects; `setOpenReference` before `openTs` reverts |
| Invariants | The market handler can resolve or void at any step, then claims everyone: I2, I4, I5, I16. A new oracle handler with an adversarial settler: I8 and I14 |
| Smoke | List a day, trade, submit the close, settle, claim, sweep, all in one test with `MockPyth` |
| Fork (4663) | Chainlink round location for SPY and NVDA on 2026-11-17 (runs when `RPC_4663` is set). Pyth `parsePriceFeedUpdatesUnique` with real fixtures and the SOXX single-application test (I11): written, skipped without a Hermes key |
| Size and gas | `LMSRMarket` runtime ≤ 23,500 B; `submitClose` and `settleMarkets` gas recorded in `security/triage.md` |
| Static | The I11 grep test still passes with the oracle added |

## 13. Definition of done

1. The oracle, the market functions and `MarketSettlement` are implemented, and the §12 tests are green in CI. Coverage stays at 95% or more.
2. The §10 interface changes are made, frozen and logged. M1 obligations 1 and 2 are marked done; open decision (d) is recorded as accepted.
3. `DeployLocal` deploys the real oracle; the cert-server devnet is redeployed and the site still serves.
4. Slither has no untriaged medium or high findings. The `forge snapshot` baseline is updated.

## 14. Open points carried forward

- Real Pyth fixtures and the SOXX test need a Hermes key; they must pass before M8.
- The Pyth regular-session feed IDs are confirmed before M8.
- `creditBounty` must never revert (M7 router).
- Buy gas (262k vs the 180k target) is unchanged by M3; M8 decides.
