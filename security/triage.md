# Security triage

Every Slither finding (Aderyn is retired upstream) at medium or above is either fixed or listed here with a reason. A triaged Slither finding also carries `// slither-disable-next-line <detector>` at the site, with a pointer to the entry below.

| Tool | Detector / title | Location | Decision | Reason |
|---|---|---|---|---|
| Slither 0.11.6 | `reentrancy-eth` (T1) | `MarketFactory.listDay` | False positive | `listDay` is `nonReentrant`, so the Pyth refund/fee call cannot re-enter it. The only other readers of `_days` (`dayInfo`, `marketsOf`) are views, and `pyth` is an immutable trusted contract. The ETH sent is the exact Pyth update fee; the surplus refund happens last. |
| Slither 0.11.6 | `divide-before-multiply` (T2) | `MarketFactory._bWad` | False positive | Intentional: `b` is floored in base units so that `b·ln n ≤ budget` holds, then scaled by `1e12` to WAD. The scale is exact, so no precision is lost beyond the deliberate floor. |
| Slither 0.11.6 | `incorrect-equality` (T3) | `MarketFactory._createMarkets`, `_open` | False positive | The comparisons are against sentinel values (`strikes[i] == 0` for a collapsed strike, `edges.length == 0`, `bWad == 0` for out-of-range budget) and an enum kind. None depends on a balance an attacker can manipulate. |
| Slither 0.11.6 | `unused-return` (T4) | `MarketFactory._open` | False positive | `cloneDeterministic` returns the address that `predictDeterministicAddress` already computed from the same salt and was registered in `isMarket`. `initialize` is then called on that address, and a mismatch would revert. |
| Aderyn | n/a | n/a | Not run | Aderyn has been retired upstream: the npm package, release binaries and crates.io versions are withdrawn, so it cannot be installed. `scripts/checks/check-aderyn.ts` is kept and will gate again if a report is supplied. Slither is the CI static-analysis gate. |
| forge coverage | uncovered lines | `MarketFactory.sol` 281-282 (clone and `initialize`), `StockTokenAllowList.sol` branch at 31, `StrikeMath.sol` 32 | Accepted | Overall 98.96% lines and 98.67% branches (above the 95% bar). The MarketFactory lines run in every listing test, so their zero hits are an artifact of `--ir-minimum` line mapping, not missing tests. |

## Gas

| Measurement | Gas | Brief estimate |
|---|---|---|
| `listDay` (8 markets, mock pool), `test_firstListing_createsEightConfiguredMarkets` | 4,037,449 (`.gas-snapshot`) | ≈ 1.6M |

Forge's per-test gas excludes `setUp`, so this figure is the `listDay` call itself plus the mock market's storage-heavy `initialize` (the mock stores the whole `Config`, including the edges array, for test assertions), plus the test body's own calls (building the Pyth update, predicting addresses, assertions). It exceeds the brief's estimate and is recorded so later changes are compared against the snapshot (`snapshot:check`, tolerance 5). Re-measure with the real `LMSRMarket` in M2 for the keeper's gas budget.
