# Security triage

Every Slither finding (Aderyn is retired upstream) at medium or above is either fixed or listed here with a reason. A triaged Slither finding also carries `// slither-disable-next-line <detector>` at the site, with a pointer to the entry below.

| Tool | Detector / title | Location | Decision | Reason |
|---|---|---|---|---|
| Slither 0.11.6 | `reentrancy-eth` (T1) | `MarketFactory.listDay` | False positive | `listDay` is `nonReentrant`, so the Pyth refund/fee call cannot re-enter it. The only other readers of `_days` (`dayInfo`, `marketsOf`) are views, and `pyth` is an immutable trusted contract. The ETH sent is the exact Pyth update fee; the surplus refund happens last. |
| Slither 0.11.6 | `divide-before-multiply` (T2) | `MarketFactory._open` (via `PriorMath.liquidity`), `PriorMath.cdf`, `PriorMath.uniform` | False positive | Intentional: `b` is floored in base units so that `b·ln(1/p_min) ≤ budget` holds, then scaled by `1e12` to WAD. `cdf` is fixed-point WAD maths whose truncation is bounded by the A&S error budget (`test/ffi/PriorReference.t.sol` and `test/PriorMath.t.sol` cover it). `uniform` computes `(1e18/n)·n` on purpose to give the rounding dust to outcome 0. Slither 0.11.6 reports none of these today; the entry covers them if a later version does. |
| Slither 0.11.6 | `incorrect-equality` (T3) | `MarketFactory._createMarkets`, `_open`, `_prior` | False positive | The comparisons are against sentinel values (`strikes[i] == 0` for a collapsed strike, `edges.length == 0`, `b == 0` from `PriorMath.liquidity` for an out-of-range budget) and an enum kind (`sp.kind == Kind.UPDOWN`). None depends on a balance an attacker can manipulate. |
| Slither 0.11.6 | `unused-return` (T4) | `MarketFactory._open` | False positive | `cloneDeterministic` returns the address that `predictDeterministicAddress` already computed from the same salt and was registered in `isMarket`. `initialize` is then called on that address, and a mismatch would revert. |
| Slither 0.11.6 | `incorrect-equality` (T5) | `LMSRMarket._bookFee` | False positive | `fee == 0` only skips bookkeeping when the computed fee is zero (a tiny trade or a zero-fee config). It is a value computed in the same call from `gross` and the fee schedule, not a balance an attacker can manipulate, and both branches leave the accounting consistent. |
| Slither 0.11.6 | `reentrancy-eth` (T6) | `SettlementOracle.submitClose`, `recordOpen` | False positive | Both are `nonReentrant`, as is every oracle function that makes an external call (`setBounties` is not: it is timelock-only and makes no external call), so the Pyth update-fee call and the router `creditBounty` call cannot re-enter. `pyth` and `router` are immutable trusted contracts. The ETH sent is the exact Pyth fee quoted by `pyth.getUpdateFee`, and the surplus is refunded last. The only unguarded readers of `_close` and `_open` are views (`closeResult`, `openResult`). |
| Slither 0.11.6 | `reentrancy-no-eth` (T7) | `SettlementOracle.settleMarkets` | False positive | `nonReentrant`. The calls are to markets created by the factory (`resolve`, `voidMarket`, `setOpenReference`), which revert `NotTrading` on a final market, and to the immutable router's `creditBounty`. `batchPaid` is written after the loop, but a re-entrant `settleMarkets` is blocked by the guard, and `settleMarkets` pre-checks `state() == Trading` and skips markets that are no longer in Trading, so a second pass never re-calls them. |
| Slither 0.11.6 | `uninitialized-local` (T8) | `SettlementOracle.settleMarkets` (`settled`), `_settle` (`o`, `w`) | False positive | Zero is the intended initial value (a counter, an unset open price, a bucket index that is counted up from 0). Solidity zero-initialises memory and stack locals. |
| Slither 0.11.6 | `unused-return` (T9) | `SettlementOracle._locate` | False positive | The Chainlink round tuples are destructured on purpose and only the fields used for the round location (round id, answer, `updatedAt`) are read. The other fields (`startedAt`, `answeredInRound`) carry no information the oracle needs, and every used field is validated (`updatedAt != 0`, `≤ closeTs`, phase match, next-round check). |
| Aderyn | n/a | n/a | Not run | Aderyn has been retired upstream: the npm package, release binaries and crates.io versions are withdrawn, so it cannot be installed. `scripts/checks/check-aderyn.ts` is kept and will gate again if a report is supplied. Slither is the CI static-analysis gate. |
| forge coverage | uncovered lines and branches (M2) | Lines: `LMSRMarket.sol` 470-472 (the `_discount` assembly block), `MarketFactory.sol` 283-284 (clone and `initialize`), `PriorMath.sol` 79, `StrikeMath.sol` 32. Branches: `LMSRMarket.sol` 375 and 471, `PriorMath.sol` 32 and 33 | Accepted | Overall 98.92% lines (644/651) and 97.14% branches (136/140) on 2026-11-22, with the coverage profile's fuzz seed fixed (`0x4d32`), so the figures repeat run to run. The listed lines all run in ordinary tests (every listing test, every trade, `test_stakingWithoutCode_noDiscount`); their zero hits are an artifact of `--ir-minimum` source mapping, which also hides the assembly branch at 471. Branch 375 (`TradeTooLarge` once `x/1e12` exceeds `uint128`) is a defensive guard that cannot be reached: one trade adds at most `20·b` with `b ≤ uint128`, so it would take ~1e10 trades inside the price clamp. `PriorMath` 32-33 clamp the A&S tail to [0, 1e18]; the polynomial and density keep it inside that range for every input, so the clamps are defensive. |
| Decision (d), accepted risk | Pyth reference on the listing path | `MarketFactory._referenceFromPyth` | Accepted | The listing reference uses the non-Unique parse, so a lister may choose any update within 120 s. The reference only centres the strikes and the prior; it never settles anything (settlement uses the oracle's Unique parse and the tiers). Decided 2026-11-22; see the M1 spec's open decisions. |
| M3 release gates | Real Hermes fixtures | `test/fork/OracleFork.t.sol` | Gate before M8 | `test_pythUnique_realFixture` and `test_soxx_multiplierAppliedOnce` skip without Hermes fixtures in the environment. Both must pass with real fixtures before M8 (they confirm `parsePriceFeedUpdatesUnique` semantics on the deployed Pyth and that the SOXX multiplier is applied once, I11). The Chainlink round tests run against chain 4663 whenever `RPC_4663` is set. Regular-session feed ids in `config/assets.4663.json` are to be confirmed per feed before M8. |

## Gas

| Measurement | Gas | Brief estimate |
|---|---|---|
| `listDay` (8 markets, mock pool), `test_firstListing_createsEightConfiguredMarkets` | 4,037,449 (`.gas-snapshot`) | ≈ 1.6M |

Forge's per-test gas excludes `setUp`, so this figure is the `listDay` call itself plus the mock market's storage-heavy `initialize` (the mock stores the whole `Config`, including the edges array, for test assertions), plus the test body's own calls (building the Pyth update, predicting addresses, assertions). It exceeds the brief's estimate and is recorded so later changes are compared against the snapshot (`snapshot:check`, tolerance 5). Re-measure with the real `LMSRMarket` in M2 for the keeper's gas budget.

## Gas (M2)

Measured 2026-11-21.

| Measurement | Gas | Target |
|---|---|---|
| `listDay` (8 real `LMSRMarket` clones, mock pool), `MarketFactoryLMSR.t.sol` `test_listDay_gas_realMarket` (`gasleft()` around `_listFri()`) | 5,592,172 | < 8,000,000 (asserted) |
| `buy` of 10 shares, first-time buyer, cold storage (`vm.cool` on market, USDG, NVDA and pool), real USDG and NVDA on a 4663 fork, `test/fork/MarketFork.t.sol` | 262,143 | 180,000 (reported, not asserted; sanity bound 300,000 asserted) |

`listDay` rose from 4.04M (mock market) to 5.59M: each real clone stores its prior, edges, virtual quantities and checkpoints at `initialize`. The keeper's gas budget must cover this per token and day.

Buy target missed by 82,143 (re-measured 2026-11-22 after the single-rounding fee fix, +418 gas); CA stop = 4 cold staticcalls; decision deferred to M8 (M2 spec §13). The figure also includes the mock pool's `onMark` writes (one of them a first write to a zero slot), which the M7 pool replaces.

## Gas (M3)

Measured 2026-11-23 with `forge test --gas-report`. The first five come from `test/SettlementE2E.t.sol` (one SettlementOracle and 8 real markets); `voidMarket` is the median from `test/LMSRMarketClaims.t.sol` (direct call on a market, 4 calls), because the end-to-end day does not void.

| Call | Gas |
|---|---|
| `submitClose` | 276,952 |
| `recordOpen` | 421,942 |
| `settleMarkets` (8 markets, resolve each) | 662,526 |
| `claim` (resolved winner; range 22,831 to 87,466) | 87,466 |
| `sweep` (median of 8; range 202,359 to 264,703) | 210,917 |
| `voidMarket` | 170,309 |

Final runtime sizes: `LMSRMarket` 23,419 B (gate 23,500), `SettlementOracle` 17,854 B, `MarketSettlement` 13,195 B.
