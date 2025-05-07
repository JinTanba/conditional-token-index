Thought for 4 seconds


# CTF-Index Contracts

**Index product for prediction-market positions**

A minimal Solidity implementation that **wraps a basket of Gnosis Conditional Tokens (prediction-market positions, ERC-1155) into a single fungible ERC-20 *index token***.
Use it to build **index products on top of prediction markets**—so traders and DeFi protocols can hold one ERC-20 that tracks multiple market outcomes.

The design guarantees a *deterministic address*, a *constant 1 : 1 redemption ratio*, and *order-independent token-set hashing* so that identical baskets always map to the same index token.

---

## Contents

| File                  | Description                                                                                                                      |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `CTFIndexFactory.sol` | Deploys and registers `CTFIndexToken` contracts via **CREATE2**. Performs all on-chain validation of the basket definition.      |
| `CTFIndexToken.sol`   | ERC-20 implementation representing the basket. Handles mint ↔️ burn against the underlying ERC-1155 prediction-market positions. |

---

## Why an Index Product?

Prediction-market positions are issued as ERC-1155 tokens whose contract (`IConditionalTokens`) mints a unique token ID for **every outcome of every market**.
This fragmentation makes them awkward to plug into DeFi tooling. By wrapping a curated set of positions into a single ERC-20 you can:

* Offer a **prediction-market index product** that tracks a theme (e.g., “2025 US election outcomes”).
* LP the entire basket in any AMM that speaks ERC-20.
* Use it as collateral in lending protocols.
* Compose it with other ERC-20-based primitives (vaults, options, structured notes).

---

## Key Properties & Invariants

| ID      | Invariant                                                          | How it’s enforced                                                                                                |
| ------- | ------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------- |
| **I-1** | `1 CTFIndexToken == 1 unit` of *each* underlying ERC-1155 position | `mint` and `burn` transfer the same `amount` per-ID before/after `_mint` / `_burn`.                              |
| **I-2** | **Order-independence**: `{1,2,3}` ≡ `{3,1,2}`                      | Factory requires the ID list to be sorted ascending and hashes `abi.encodePacked(ids)` inside the salt.          |
| **I-3** | **Deterministic deployment**                                       | The salt is `keccak256(ctf, metadataHash, idsHash)`; `CREATE2` guarantees the same address for identical inputs. |

---

## Quick Start

### Requirements

* Solidity ^0.8.25
* Foundry ≥ 0.6 or Hardhat ≥ 2.22
* Access to a deployed **Gnosis Conditional Tokens** contract (`IConditionalTokens`) and its collateral ERC-20.

### 1. Compile

```bash
forge install
forge build
```

### 2. Prepare Your Prediction-Market Basket

```solidity
uint256;
ids[0] = getPositionId(conditionA, 0);   // YES of conditionA
ids[1] = getPositionId(conditionB, 1);   // NO  of conditionB
bytes   meta = abi.encode("US-Election-2025 Index");
```

> **Note:** `ids` must be strictly sorted (`<`) and contain no duplicates.

Call:

```solidity
(bytes32 salt, address predicted) = factory.prepareIndex(ids, meta);
```

### 3. Deploy the Index Token

```solidity
address index = factory.createIndex(ids, meta);
```

If an index with the same `(ids, meta)` already exists, `createIndex` reverts; use `factory.getIndex(salt)` to fetch it.

### 4. Mint / Burn

```solidity
// Approve the CTF contract once
ctf.setApprovalForAll(address(index), true);

// Wrap 100 units of each position into 100 index tokens
index.mint(100 ether);

// Unwrap later
index.burn(50 ether);
```

---

## Contract Interfaces

### `CTFIndexFactory`

| Function                                  | Purpose                                                           |
| ----------------------------------------- | ----------------------------------------------------------------- |
| `prepareIndex(uint256[] ids, bytes meta)` | Validates the basket and returns `(salt, predictedAddress)`.      |
| `createIndex(uint256[] ids, bytes meta)`  | Deploys the `CTFIndexToken` via CREATE2 and emits `IndexCreated`. |
| `getIndex(bytes32 salt)`                  | Deterministic lookup of an existing index.                        |

### `CTFIndexToken`

| Function               | Purpose                                                                                                          |
| ---------------------- | ---------------------------------------------------------------------------------------------------------------- |
| `mint(uint256 amount)` | Transfers `amount` of **each** underlying position from caller → contract, then mints `amount` ERC-20 to caller. |
| `burn(uint256 amount)` | Burns `amount` ERC-20 from caller, then returns `amount` of each position back to caller.                        |
| `ids()`                | Returns the ordered list of wrapped position IDs.                                                                |
| `metadata()`           | Arbitrary basket metadata set at creation.                                                                       |

---

## Security & Limitations

* **Unaudited code** – use at your own risk.
* No fee mechanism: mint and burn are always net-zero; if you need protocol revenue, layer it externally.
* Factory only checks that each `id` belongs to the supplied `conditionIds`. It does **not** verify market status (open/closed) or payout progress.
* Gas cost scales linearly with `ids.length` (max < 256 by design).

---

## Extending

* Add fee hooks to `mint` / `burn` (e.g., 10 bp protocol fee).
* Plug a price oracle into `CTFIndexToken` so the index can be used as collateral.
* Build UI helpers that generate the sorted ID list automatically from market URLs.

---

## Development Scripts (Foundry)

```bash
forge script scripts/Deploy.s.sol --rpc-url $RPC --private-key $PK --broadcast
forge script scripts/MintBurn.s.sol  --rpc-url $RPC --private-key $PK --broadcast
```

See the `scripts/` folder for template scripts.

---

## License

[MIT](LICENSE)

---

## Acknowledgements

Built on top of **Gnosis Conditional Tokens** and **OpenZeppelin Contracts**.
Special thanks to the research community exploring the intersection of prediction markets and DeFi index products.
