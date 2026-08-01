# Day 1 — Arc Testnet deployment record

Kill gate evidence. Everything below is reproducible from a public explorer.

## Network

| | |
|---|---|
| Chain | Arc Testnet |
| Chain ID | 5042002 (`0x4cef52`), confirmed via `eth_chainId` |
| RPC used | `https://rpc.testnet.arc.network` |
| Explorer | https://testnet.arcscan.app (Blockscout v11.2.3) |
| Native gas token | USDC, **18 decimals** — confirmed by transaction, not by docs |
| EVM baseline | Osaka (`PUSH0` available). Compiled against `cancun` as a safe subset. |

## Wallets

Two wallets, deliberately separate — the agent must be able to claim a bounty
on its own, without the deployer's key.

| Role | Address |
|---|---|
| Deployer | `0x6BA70dfb557EC0C4B7805b9728201aCC81111111` |
| Agent | `0xd3e23bA15A06B1DF14eF6daC73cF76DC9e888888` |

Both funded with 20 USDC from https://faucet.circle.com (20 USDC per address
per 2 hours). Private keys live only in `.env`, which was added to
`.gitignore` before the file was ever created.

## Deployed contract

`KillGateProbe` — throwaway environment probe, not product code.

| | |
|---|---|
| Address | [`0x8850a83Fc38b87453aeB4EEDb23c10f370A3A9e5`](https://testnet.arcscan.app/address/0x8850a83Fc38b87453aeB4EEDb23c10f370A3A9e5) |
| Deploy tx | `0x373310d96342015f17fbb5330cac3f8cbbe6dbdf8c0fcdbe0a515c63ad6c692e` |
| Block | 54747696 |
| Source verified | Yes — `is_verified: true`, `v0.8.28+commit.7893614a`, optimizer 200 runs |

### Full path proven

| Step | Evidence |
|---|---|
| compile | `forge build` — 21 files, solc 0.8.28 |
| test | `forge test` — 5 passed, incl. 256-run fuzz |
| deploy | tx `0x3733...692e`, status success |
| read state | `value()` returned `42` (constructor arg) |
| write state | `setValue(31337)` — tx `0xd13c92f11509895493e4316ae4e76ad5192d08b96639b0047cb360bab54f282e` |
| read back | `value()` returned `31337` |
| verify source | Blockscout `Pass - Verified` |

## Gas cost, measured

Arc's native unit is 18 decimals, so `cost_USDC = gasUsed × effectiveGasPrice / 1e18`.

| Operation | gasUsed | Gas price | Cost (USDC) | Cost (¢) |
|---|---|---|---|---|
| Deploy `KillGateProbe` | 163,023 | 23.21 gwei | 0.003783764 | 0.378 |
| `setValue(uint256)` | 28,167 | 23.21 gwei | 0.000653756 | 0.065 |

At the `setValue` rate, **1,000 fuzz attempts cost ~0.65 USDC**.

⚠️ Caveat, stated rather than buried: a real Proof-of-Break attempt is *not* a
bare `setValue`. It is check → execute → check routed through `BountyRegistry`,
which will cost several times more gas. Treat 0.065¢ as the floor, not the
expected per-attempt cost. The claim that survives this measurement is
"sub-cent per attempt", not "0.065¢ per attempt".

## Decimals confirmation (design doc §9, risk #3)

Sent exactly `1e18` wei from deployer to agent:

- tx `0xb0650d0f68d79a8c86d54855e9997cd242e4f33a232bf39a415ccde07310d31d`
- agent balance: `20000000000000000000` → `21000000000000000000`
- delta `1e18` reads as `1.000000` at 18 decimals

**Native gas unit is 18 decimals.** The ERC-20 interface of USDC on Arc
separately exposes 6 decimals over the same balance; that view is untested here
and matters only if a future version moves bounties to the ERC-20 path.
