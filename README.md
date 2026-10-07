# Imd6900 (IMD6900)

A fixed-supply ERC-20. The constructor mints the entire supply once to `msg.sender`.

| Parameter | Value |
| --- | --- |
| Contract | `src/Imd6900.sol:Imd6900` |
| Name | `Imd6900` |
| Symbol | `IMD6900` |
| Decimals | `18` |
| Human-readable supply | `1,000,000,000` |
| Supply in base units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`; ABI encoding `0x`) |
| Deployment value | `0` |
| Initial recipient | Immediate deploying address |
| Compiler / EVM target | Solidity `0.8.26` / Cancun |
| Optimizer / metadata hash | Enabled, 200 runs / `none` |

## Design and assumptions

The implementation extends the vendored OpenZeppelin Contracts v5.0.2 `ERC20`. It adds only the fixed constructor mint. Token amounts are integers in base units: one token is `10^18` units. There are no taxes, rebases, burns, mint entrypoints, ownership roles, pause or blacklist controls, proxies, upgrades, or external callbacks. Transfers deliver exactly the requested amount. Supply remains constant for the lifetime of the contract.

Standard `transfer`, `approve`, and `transferFrom` return `true` on success and revert with ERC-20 custom errors on invalid addresses, insufficient balances, or insufficient allowances. Zero-value transfers to nonzero recipients and self-transfers are supported. Approval replaces the previous allowance; finite allowances are consumed by `transferFrom`. The maximum `uint256` allowance is treated as unlimited and is not decremented. `Transfer` events cover minting and transfers; `Approval` events cover explicit approvals. OpenZeppelin v5 does not emit `Approval` when an allowance is spent; query `allowance` for current state.

The token needs no oracle, randomness, keeper, signature service, initialization call, or chain-specific address. It does not accept native currency through ordinary calls and has no asset recovery function. Tokens sent to an address that cannot transfer them, including this token contract itself, cannot be recovered by an administrator.

## Build and verification

Install Foundry and make Solidity 0.8.26 available to it, then run from the project root:

```sh
forge build
forge test
forge fmt --check
```

All Solidity dependencies and their licenses are ordinary files in `lib/`; no dependency installation, submodule, RPC connection, secret, or environment variable is required. Dependency versions and archive hashes are in `lib/README.md`. FFI is disabled and no filesystem cheatcode permissions are granted. The compiler is pinned by version; it is not vendored.

Tests cover constructor metadata, exact mint amount and event, factory CREATE2 deployment, exact distributor and pool-like transfer flows, transfers and approvals, allowance spending and revocation, infinite allowances, zero and self-transfers, expected revert reasons, rollback after failed transfers, rejected privileged entrypoints, native currency rejection, and prohibited runtime opcodes. Three fuzz tests each run 512 cases. A stateful invariant runs 128 sequences of 64 calls across four holders, checking fixed supply, balance conservation, exact transfer amounts, and allowance accounting. Tests create fresh fixtures and do not read or write environment variables.

The local transfer fixture exercises the token side of launch transfers. It does not run Uniswap v4 pool initialization, liquidity math, or swaps. The supplied protected test requires the network's factory support contracts, v4 dependencies, manifest, and environment configuration; that integration belongs to the independent launch verifier. This project does not invent those contracts or deployment economics.

## Deployment and responsibilities

Deploy the creation bytecode from `out/Imd6900.sol/Imd6900.json` with no appended arguments and zero native value. The ABI is in the same artifact. To inspect the bytecode without broadcasting:

```sh
forge inspect src/Imd6900.sol:Imd6900 bytecode
forge inspect src/Imd6900.sol:Imd6900 abi
```

For a direct deployment, the deploying account receives all tokens. For a factory deployment, the factory receives all tokens, regardless of the transaction origin or requester. A factory must implement the intended onward distribution. Deploy the concrete contract, not a proxy. CREATE2 addresses depend on the chosen factory, salt, and this exact creation bytecode; no salt or address is fixed by the token.

For IdentityMD integration, the later manifest should identify this contract, the parameters above, an empty constructor argument list, and no application contracts. The token does not implement the network's ten-percent distribution or pool allocation: the external launch factory performs those transfers. Network, factory, paired currency, pool parameters, opening capitalization, pool share, and remainder recipient were not supplied and must be set by the authorized launch process. The local test's pool allocation is illustrative only. No launch manifest or transaction is submitted by this project.

The deployment operator is responsible for selecting a Cancun-compatible chain, reviewing the factory and distribution configuration, checking the pinned compiler settings and bytecode, arranging independent adversarial review before release, and verifying the deployed source and metadata on the target explorer. Immediately after construction, verify the total supply and that the immediate deployer holds all of it; after a factory launch, reconcile the factory's transfers to the intended recipients. Supply custody and distribution are operational responsibilities, not token administrator powers.

Holders control transfers and approvals. Prefer bounded allowances to trusted spenders, revoke unused allowances, and account for the standard approval replacement race when changing an existing nonzero allowance (reset it to zero and confirm before granting a new amount). No operator can restore lost keys, seize balances, freeze transfers, or upgrade this contract.

Local Foundry tests are not a security audit. Slither and Mythril are not included in this verification. No wallet keys are accessed and no deployment is broadcast as part of this deliverable.
