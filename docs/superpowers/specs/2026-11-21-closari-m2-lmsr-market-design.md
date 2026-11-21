# Closari M2: LMSRMarket trading, design

Date: 2026-11-21. Builds on the M1 design (`2026-11-21-closari-monorepo-m1-design.md`), whose "Cross-milestone obligations" and "Interface change log" stay binding. The source for the market is Backend §3.4, §3.6 (the accumulator only), §3.10, §3.11 and §3.12.

## 1. Goal and scope

M2 delivers `LMSRMarket`, the clone implementation that `MarketFactory` opens eight times per token per day. It covers trading only:

- the fixed-b LMSR maths, house-favour rounding, the price clamp and trade-size limits;
- **a seeded opening price** (§3, decided 2026-11-21);
- fees, the late ramp, staking discounts, fee escrow and builder attribution;
- the halt, late-hour friction, the corporate-action trading stop and the UPDOWN open pause;
- three buy paths (plain `buy`, EIP-3009 `buyWithAuthorization`, Permit2 `buyWithPermit2`) and `sell`;
- marks to the pool (`onMark`, mocked);
- the price accumulator with exact checkpoints, which M3's void price reads.

**Out of scope (M3):** `resolve`, `voidMarket`, `claim`, `claimMany`, `sweep` and `pullFees`. In M2 they exist and revert `NotYetImplemented()`. That keeps the ABI frozen and makes the M3 boundary visible. `setOpenReference` is in M2, because the UPDOWN pause needs it.

## 2. Decisions taken

| Topic | Decision |
|---|---|
| Opening price | Seeded prior from a per-asset volatility (§3). UPDOWN opens at 50/50 |
| Loss bound | Worst-case loss ≤ budget is kept. `b = budget / ln(1 / p0_min)`, so far strikes get less depth per budget dollar |
| Prior floor | `PRIOR_MIN = 0.02` (code constant). No outcome opens below 2% or above 98%, so `b ≥ budget / ln 50 ≈ 0.256 · budget` |
| Fee parameters | Snapshotted into `Config` at listing (`baseFeeBps`, `rampMaxBps`), set on the factory by the timelock, with hard caps `base ≤ 200` and `rampMax ≤ 500` in code |
| B_MIN | 100 shares (was 1,000), so far strikes at launch budgets still list |
| Settlement functions | Present in the ABI, revert `NotYetImplemented()` until M3 |
| Shared constants | `src/lib/Constants.sol` holds `CA_AFTER`, `HALT_BEFORE_CLOSE`, `P_MIN`, `PRIOR_MIN` and `VOID_TWAP_WINDOW`. The factory switches to it (obligation 5) |
| Implementation lock | The `LMSRMarket` constructor marks the implementation initialised (obligation 6) |
| USDG and Permit2 | Constructor immutables of the implementation. Clones delegate to it, so every clone shares them |
| Differential reference | 60-digit decimal LMSR in `@closari/core` (`decimal.js`), called through `vm.ffi` only under `FOUNDRY_PROFILE=ffi` |

## 3. Seeded opening price

**Why:** with uniform opening prices, ABOVE ±2% and ±5% open at 0.50 against real chances of about 0.25 and 0.05. The first arbitrageurs take most of each budget (final-review #6, open decision (a)).

**Volatility per asset.** `IStockTokenAllowList.Asset` gains `uint16 volBps`: the close-to-close daily volatility in basis points (for example NVDA 300 = 3.0%). `setAsset` requires `volBps ∈ [25, 2_000]` for a listed asset, otherwise `BadAsset`. The proposed launch values go into `config/assets.4663.json`; the product owners confirm them before mainnet (M8).

**Prior at listing (factory, `src/lib/PriorMath.sol`).** With `ref` the listing reference, `σ = volBps / 1e4` and the lognormal zero-drift model:

- `P(close > K) = Φ(d)` with `d = (ln(ref / K) − σ² / 2) / σ`
- **ABOVE** strike `K`: `prior = [1 − Φ(d_K), Φ(d_K)]` for outcomes `[NO, YES]`
- **RANGE** edges `e_1 < … < e_{n−1}`: bucket `j` is `Φ(d_{e_j}) − Φ(d_{e_{j+1}})`, with `Φ(d_{e_0}) = 1` and `Φ(d_{e_n}) = 0`
- **UPDOWN:** `[0.5, 0.5]`
- `Φ` is a rational approximation with absolute error below 1e-7 (Abramowitz–Stegun 26.2.17), in WAD.
- **Floor and normalise:** each `p_i = max(p_i, PRIOR_MIN)`. Then subtract the excess from the largest entry so that `Σ p_i = 1e18` exactly. `PRIOR_MIN · n ≤ 0.16`, so the largest entry always absorbs it.

The factory snapshots the vector into `Config.priorWad`. The asset's `volBps` is read once at listing, so a later `setAsset` never changes a live market (I9, I17).

**Liquidity from the prior.** `b = floor(budget × 1e18 / (lnWad(1e36 / p_min) + 1))`, with `p_min = min_i priorWad[i]`. A uniform prior gives `ln n`, which is M1's formula. The `[B_MIN, B_MAX]` check is unchanged (a market outside it is skipped, reason 3).

**Seeding the market.** At `initialize`, the market sets virtual house quantities `q0_i = b · ln(p_i / p_min)` (all ≥ 0; the outcome with the smallest prior gets 0). Then `q_i = q0_i` and `p_i(q) = priorWad[i]` up to rounding. Virtual quantities are owed to nobody. **Trader liability** for outcome `i` is `t_i = q_i − q0_i`.

**Loss bound (replaces Backend §3.4's `b · ln n`).** Write `C` for the cost function.

1. Cash: `cash ≥ budget + C(q) − C(q0)`, because buy costs round up and sell proceeds round down.
2. If outcome `w` wins, the payout is `t_w = q_w − q0_w ≤ C(q) − q0_w`.
3. Pool result: `cash − t_w − budget ≥ q0_w − C(q0) = b · ln p_w ≥ −b · ln(1/p_min) ≥ −budget`.
4. Void (any `v` with `Σ v_i ≤ 1`): `L_void ≤ max_i t_i ≤ C(q) − C(q0) + b · ln(1/p_min) ≤ cash`. So Backend §3.6's proof holds with `t` in place of `q`.

M2 encodes this as invariant **I1′: `cash ≥ max_i t_i`**, the I1 restated for trader liability. It also checks I5 (pool loss ≤ budget) by fuzzing random resolutions.

## 4. Market maths

As in Backend §3.4, written from the published formulas on Solady `expWad`/`lnWad`:

- **Cost:** `C(x) = m + b · ln Σ_i exp((x_i − m) / b)` (log-sum-exp with `m = max x`). Inputs are WAD (`x_i = q_i × 1e12`).
- **Buy cost:** `ceil((C(q′) − C(q)) / 1e12) + 1`.
- **Sell proceeds:** `max(0, floor((C(q) − C(q′)) / 1e12) − 1)`.
- **Prices:** `p_i = exp((x_i − m)/b) / Σ`, floored. `prices()` returns them, with `Σ ≤ 1e18`.
- **Clamp:** after every trade, every `p_i ∈ [P_MIN, 1e18 − P_MIN]` with `P_MIN = 1e15`, otherwise `PriceOutOfBounds`. The prior floor of 0.02 is well inside the clamp.
- **Limits:** `shares ≤ 20 · b` per call; `q_i ≤ type(uint128).max`; `shares > 0`; outcome `< n`; sell `shares ≤` the caller's position.
- **Accounting:**
  - `cash = budget + Σ buy gross − Σ sell gross`. `feeEscrow` is separate.
  - `vWorst = cash − max_i t_i`, `vBest = cash − min_i t_i`.
  - After each trade the market calls `pool.onMark(ΔvWorst, ΔvBest)`. Before any trade both equal `budget`, so the pool's "untraded" test holds.
- **`liability()`:** `max_i t_i` while trading.

## 5. Fees, discounts, ramp

- The fee rate is the exact rational `feeBps(t, account) = base × (10_000 − discount) / 10_000 + rampMax × elapsed / 1800`, where `elapsed = clamp(t − (haltTs − 1800), 0, 1800)`. So the ramp is 0 before `haltTs − 1800`, then linear to `rampMax` at `haltTs`.
- The fee is rounded **once**, up, over that exact rate: `num = base × (10_000 − discount) × 1800 + rampMax × elapsed × 10_000`, `fee = ceil(gross × num / (10_000 × 10_000 × 1800))`. Neither the discounted base nor the ramp is floored first, so a 1-bp discount on a 50-bp base charges 49.995 bps (not 49), and rounding always favours the market. `quoteBuy`/`quoteSell` use the same function.
- On a buy the trader pays `gross + fee`, and that total must be `≤ maxTotal`. On a sell they receive `gross − fee`, which must be `≥ minNet`.
- **Discount:** read with a gas-capped `staticcall` (50k) to `staking.discountBps(account)`.
  - Any failure, a zero `staking` address, or a value above 3,000 counts as 0. A broken staking contract can never stop trading.
  - Discounts reduce `base` only (I15).
- **Fees are escrowed** in `feeEscrow`, along with `feesPaid[account]`, `feesByBuilder[builder]` and `builderFeesTotal`. `builder == address(0)` means no builder.
- **Factory side:** `setFees(uint16 baseFeeBps, uint16 rampMaxBps)` is timelocked. It enforces `base ≤ 200` and `rampMax ≤ 500` (`BadFees`) and emits `FeesSet`. The values are copied into each market's `Config` at listing.

## 6. Trading guards (every trade path, buy and sell)

In order, before any state change:

1. `state == Trading`, `block.timestamp < haltTs` (I7) and `block.timestamp ≤ deadline`.
2. **Corporate-action stop (I16):** `_caVoidVisible()`. Trading reverts `CorporateActionVisible` if any of these holds:
   - `token.uiMultiplier() != multiplierSnapshot`;
   - `token.newUIMultiplier() != multiplierSnapshot` with `effectiveAt ∈ [createdTs, closeTs + CA_AFTER]`;
   - `token.oraclePaused()`.

   Trading resumes if the change is cancelled.
3. **UPDOWN open pause:** for `kind == UPDOWN`, trades revert `AwaitingOpen` from `openTs` until `setOpenReference` has run. `setOpenReference` is oracle-only, UPDOWN-only and runs once. It stores the open as the single edge.
4. **Late-hour friction:** from `closeTs − 3600`, each account's net buys per outcome inside that hour are capped at `b / 4` shares (`LateHourCap`). Sells reduce the counter, but not below 0.

## 7. Entry paths

- **`buy(outcome, shares, maxTotal, deadline, builder)`:** `transferFrom(msg.sender, market, total)`. The position goes to `msg.sender`.
- **`buyWithAuthorization(t, validAfter, validBefore, v, r, s)`:** Backend §3.10, verbatim.
  - `t.market == this`;
  - `nonce = keccak256(abi.encode(TRADE_TYPEHASH, t.market, t.owner, t.outcome, t.shares, t.maxTotal, t.deadline, t.builder, t.salt))`;
  - `USDG.receiveWithAuthorization(t.owner, this, t.maxTotal, …, nonce, v, r, s)`;
  - the trade is credited to `t.owner`;
  - `maxTotal − total` is refunded to `t.owner`.

  Atomic: any failure reverts everything, and the authorisation stays unused.
- **`buyWithPermit2(t, permit, sig)`:**
  - `permitWitnessTransferFrom` with `witness = hashStruct(TradeIntent)` and the witness type string `ClosariTrade(...)` plus the Permit2 suffix;
  - the transfer amount is `t.maxTotal` to this market; any excess is refunded to `t.owner`;
  - `permit.permitted.token == USDG`.
- **`sell(outcome, shares, minNet, deadline, builder)`:** pays `msg.sender`. A frozen owner's sell reverts. There is no `claimTo` (Backend §3.10).
- **All paths:** they are `nonReentrant` and follow checks, effects, interactions, with the transfer-in before any external pool call. The `Trade` event carries the prices after the trade.

## 8. Price accumulator

Before each trade (and in `setOpenReference`) the market rolls the accumulator forward: `cum_i += p_i(q) × (now − lastTs)` for `i < n − 1` (the last is implied by `Σ = 1`). Values are packed in storage.

**Checkpoints:**
- at `haltTs − VOID_TWAP_WINDOW` (3,600 s);
- for UPDOWN, also at `openTs − VOID_TWAP_WINDOW`.

The cumulative is recorded at exactly that timestamp, by the first roll that crosses it, so each checkpoint is exact (prices are constant between trades).

M3 reads the checkpoints, plus the cumulative rolled forward to `t_stop`, through the new views `cumulativeAt(uint64 ts)` (it accepts `ts ≥ lastTs` and extrapolates from the current prices) and `checkpoints()`.

## 9. Interface changes (approved 2026-11-21; logged in the M1 spec's change log by the implementing task)

| Interface | Change |
|---|---|
| `ILMSRMarket.Config` | Adds `uint256[] priorWad`, `uint16 baseFeeBps` and `uint16 rampMaxBps` |
| `ILMSRMarket` | Adds `cumulativeAt(uint64) returns (uint256[] memory)`, `checkpoints() returns (uint64[2] memory ts, uint256[][2] memory cum)` and the custom errors of §6/§7 (`PriceOutOfBounds`, `TradeTooLarge`, `CorporateActionVisible`, `AwaitingOpen`, `LateHourCap`, `Halted`, `Expired`, `Slippage`, `WrongMarket`, `WrongToken`, `NotOracle`, `AlreadyInitialized`, `NotYetImplemented`) |
| `IStockTokenAllowList.Asset` | Adds `uint16 volBps` |
| `IMarketFactory` | Adds `setFees(uint16,uint16)`, `fees() returns (uint16,uint16)`, `event FeesSet(uint16,uint16)` and `error BadFees()` |

`abi:freeze` is rerun and `interfaces.lock.json` is updated in the same commit as each change.

## 10. Factory and deploy changes

- `MarketFactory._open` and `_config` compute the prior (§3), the new `b`, and copy the fee snapshot.
- `MockMarket` keeps working for the M1 tests: it accepts the new `Config`.
- `DeployLocal.s.sol` deploys the real `LMSRMarket` implementation (with `MockUSDG`, mock pool, oracle and router, and a mock staking), seeds `volBps` and fees, lists NVDA, then makes one buy and one sell as a smoke test. The cert-server devnet is redeployed with it.
- **Size:** `MarketFactory` stays under 24 KB (it is 18.9 KB at M1; `PriorMath` is an internal library). If it would cross 22 KB, `PriorMath` becomes a deployed library.

## 11. Tests (M2 acceptance)

| Area | Tests |
|---|---|
| Maths | `testFuzz_cost_vs_reference` (n ∈ [2,8], b, q, Δ, through ffi): the Solidity buy cost is ≥ the 60-digit reference and the sell proceeds are ≤ it, within 2 units. Price sum and clamp (I3). Overflow edges at `20·b` and `uint128` |
| Prior | `PriorMath` vs the TS reference over random `ref`/`σ`/strikes (ffi): Φ within 1e-7, sum exactly 1e18, floor respected. Prices at `initialize` equal `priorWad` within 1e-12. ABOVE ±5% on σ = 3% opens near 0.05/0.95 |
| Loss | `testFuzz_worstCaseLoss`: random trades by up to 16 actors, then a random winner. The pool's result is ≥ `−budget` (I5), and I1′ holds after every trade |
| Round trip | `testFuzz_roundTrip_noProfit`: buy then sell the same shares, the trader never gains (fees on or off) |
| Fees | Ramp shape, the caps, discount only on `base` (I15), staking that reverts or eats gas counts as 0, escrow and builder totals add up |
| Guards | `test_trade_reverts_atHalt` plus a warp fuzz (I7). `test_trade_reverts_whenCAVisible` for each of the three conditions, and trading resumes when the change is cancelled (I16). `test_upDown_pausedUntilOpen`. Late-hour cap. Deadline. Slippage both ways |
| Entry paths | EIP-3009 on `MockUSDG` (which gains `receiveWithAuthorization`). `testFuzz_intentTamper`: changing any `TradeIntent` field or `market` makes the authorisation fail. Permit2 against the canonical Permit2 runtime code etched from a pinned fixture: witness tamper and wrong token. Refunds go to `t.owner` |
| Accumulator | `test_twap_checkpoint_exact` against a reference integration of piecewise-constant prices, including no trade after the checkpoint and one exactly at it |
| Marks | `onMark` deltas reproduce `vWorst`/`vBest` from a fresh read after every trade (mock pool sums) |
| Invariant | A handler (buy, sell, warp, CA toggles, by up to 8 actors) asserts I1′, I2 (`balance ≥ cash + feeEscrow`), I3 and I7 |
| Init | Clones initialise once, only from the factory. The implementation itself cannot be initialised. `Config` fields never change (I9) |
| Factory | Listing gives each market the expected prior and `b`. `setFees` caps and roles. The M1 suite stays green |
| Fork (4663) | Buy, sell and `buyWithAuthorization` with real USDG and Permit2 on a fork. Gas for `buy` is recorded; the target is ≤ 180k, and an overrun is reported, not failed |
| Gas | `listDay` re-measured with the real market (obligation 8) and recorded in `security/triage.md` |

## 12. Definition of done

1. `LMSRMarket` and `PriorMath` are implemented, and the §11 tests are green in CI. Coverage stays at 95% or more.
2. The interface changes in §9 are made, frozen and logged.
3. The TS LMSR and prior references are in `@closari/core` with `bun test` vectors.
4. `DeployLocal` runs the real market end to end. The cert-server devnet is redeployed and the site still serves.
5. Slither has no untriaged medium or high findings. The `forge snapshot` baseline is updated.

## 13. Open points carried forward

- The launch `volBps` per asset and the fee launch values are product decisions, confirmed before M8.
- The fork gas target of 180k for `buy` may be missed because of the CA stop's 4 static calls. If so, M8 decides whether to accept it.
