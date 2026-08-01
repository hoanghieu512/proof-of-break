// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {BountyRegistry} from "../src/BountyRegistry.sol";
import {DemoVault} from "../src/DemoVault.sol";
import {VaultChecker, IVaultLedger} from "../src/VaultChecker.sol";

/**
 * @notice Drives the Registry through random sequences of realistic actions.
 * @dev An earlier version of this handler shared five vaults across every
 *      bounty and let `grief` fire on a third of all calls. Every vault was
 *      broken within the first few calls, after which openBounty and attempt
 *      could only revert: 12,800 calls produced 5 bounties and ZERO payouts.
 *      All six invariants passed, and proved nothing — they had never seen the
 *      code path where money moves.
 *
 *      So: one fresh vault per bounty, capped so the O(n) invariant checks stay
 *      affordable, and griefing kept rare enough that claims actually happen.
 *      `invariant_CallSummary` prints the claim count precisely so this failure
 *      mode cannot come back unnoticed.
 */
contract RegistryHandler is Test {
    BountyRegistry public immutable registry;

    uint256 public constant MAX_BOUNTIES = 25;

    DemoVault[] public vaults;
    VaultChecker[] public checkers;
    address[4] public actors;

    uint256 public ghostDeposited;
    uint256 public ghostPaidOut;
    uint256 public opens;
    uint256 public successfulClaims;
    uint256 public griefs;

    string internal constant SIG = "deposit(uint256)";

    constructor(BountyRegistry registry_) {
        registry = registry_;
        actors[0] = makeAddr("actorA");
        actors[1] = makeAddr("actorB");
        actors[2] = makeAddr("actorC");
        actors[3] = makeAddr("actorD");
    }

    function openBounty(uint256 rewardSeed, uint256, uint256 actorSeed) external {
        if (registry.bountyCount() >= MAX_BOUNTIES) return;

        uint256 reward = bound(rewardSeed, 1, 50 ether);
        address actor = actors[bound(actorSeed, 0, actors.length - 1)];

        // A fresh target per bounty. Breaking one must not sterilise the rest.
        DemoVault v = new DemoVault();
        VaultChecker c = new VaultChecker(IVaultLedger(address(v)));

        vm.deal(actor, actor.balance + reward);
        vm.prank(actor);
        try registry.openBounty{value: reward}(address(v), c, SIG) returns (uint256) {
            vaults.push(v);
            checkers.push(c);
            ghostDeposited += reward;
            ++opens;
        } catch {}
    }

    function attempt(uint256 bountySeed, uint256 amountSeed, uint256 actorSeed) external {
        uint256 n = registry.bountyCount();
        if (n == 0) return;

        uint256 id = bound(bountySeed, 0, n - 1);
        address actor = actors[bound(actorSeed, 0, actors.length - 1)];

        // Weighted towards the boundary values a real agent would try first,
        // so claims actually happen instead of the run being all near-misses.
        uint256 amount;
        uint256 mode = amountSeed % 5;
        if (mode == 0) {
            amount = 1e18; // the planted bug
        } else if (mode == 1) {
            amount = 1e18 - 1;
        } else if (mode == 2) {
            amount = 1e18 + 1;
        } else {
            amount = bound(amountSeed, 1, type(uint128).max);
        }

        uint256 balanceBefore = actor.balance;
        vm.prank(actor);
        try registry.attempt(id, abi.encodeCall(DemoVault.deposit, (amount))) returns (bool broke) {
            if (broke) {
                ghostPaidOut += actor.balance - balanceBefore;
                ++successfulClaims;
            }
        } catch {
            // Reverts are normal: already paid, already broken, target refused.
        }
    }

    /**
     * @notice Someone breaks a target directly, bypassing the Registry.
     * @dev The accepted griefing vector from the README. Targets are public
     *      contracts and nothing stops this. The escrow accounting must survive
     *      it even though the bounties over that target become unclaimable.
     *
     *      Gated to roughly one call in eight. Griefing every time sterilises
     *      the whole run before any bounty can be claimed, which is how the
     *      first version of this handler managed to prove nothing.
     */
    function grief(uint256 poolSeed) external {
        if (vaults.length == 0) return;
        if (poolSeed % 8 != 0) return;

        uint256 p = bound(poolSeed, 0, vaults.length - 1);
        try vaults[p].deposit(1e18) {
            ++griefs;
        } catch {}
    }

    function claimedTotal() external view returns (uint256) {
        return ghostPaidOut;
    }
}

contract BountyRegistryInvariantTest is Test {
    BountyRegistry internal registry;
    RegistryHandler internal handler;

    function setUp() public {
        registry = new BountyRegistry();
        handler = new RegistryHandler(registry);

        // Restrict fuzzing to the handler's own entry points. Without this,
        // the fuzzer would also call every public function forge-std's Test
        // base contract exposes.
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = RegistryHandler.openBounty.selector;
        selectors[1] = RegistryHandler.attempt.selector;
        selectors[2] = RegistryHandler.grief.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    /// @notice The property the escrow exists to guarantee (design doc §9).
    function invariant_BalanceCoversEverythingStillOwed() public view {
        assertGe(
            address(registry).balance,
            registry.totalEscrowed(),
            "registry cannot cover its unpaid bounties"
        );
    }

    /// @notice Stronger form: nothing can put value in except `openBounty`, so
    ///         the balance should track the books exactly, not merely cover them.
    function invariant_BalanceEqualsEscrowExactly() public view {
        assertEq(
            address(registry).balance, registry.totalEscrowed(), "balance drifted from the books"
        );
    }

    /// @notice The running total must equal the sum of the individual records.
    function invariant_EscrowEqualsSumOfUnpaidRewards() public view {
        uint256 sum;
        uint256 n = registry.bountyCount();
        for (uint256 i = 0; i < n; ++i) {
            BountyRegistry.Bounty memory b = registry.getBounty(i);
            if (!b.paid) sum += b.reward;
        }
        assertEq(registry.totalEscrowed(), sum, "totalEscrowed disagrees with the bounty list");
    }

    /// @notice Money in equals money still held plus money paid out.
    function invariant_NothingAppearsOrDisappears() public view {
        assertEq(
            handler.ghostDeposited(),
            address(registry).balance + handler.ghostPaidOut(),
            "value was created or destroyed"
        );
    }

    /// @notice A paid bounty must never reappear as claimable.
    function invariant_PaidBountiesStayOffTheBoard() public view {
        uint256[] memory open = registry.openBountyIds();
        for (uint256 i = 0; i < open.length; ++i) {
            assertFalse(registry.getBounty(open[i]).paid, "a paid bounty is still listed as open");
        }
    }

    /**
     * @notice Guards against the invariants passing vacuously.
     * @dev Runs once at the end of each invariant run, unlike `invariant_`
     *      functions which Foundry also evaluates immediately after setUp —
     *      when nothing has happened yet and any "something happened" assertion
     *      is guaranteed to fail.
     *
     *      Only `opens` is asserted here. Claims per run depend on the fuzzer
     *      reaching the boundary value, which is likely but not certain, and a
     *      flaky guard is worse than none. The claim count is asserted
     *      deterministically in `test_HandlerCanReachThePayoutPath` below and
     *      printed by `invariant_CallSummary`.
     */
    function afterInvariant() public view {
        assertGt(handler.opens(), 0, "this run opened no bounties at all");
    }

    /**
     * @notice Proves the handler is capable of producing a payout.
     * @dev Without this, the invariant suite could be sterilised by a future
     *      change and still report all green — which is exactly what an earlier
     *      version of the handler did: 12,800 calls, 0 claims, 6 passing
     *      invariants, nothing proven.
     */
    function test_HandlerCanReachThePayoutPath() public {
        for (uint256 i = 0; i < 5; ++i) {
            handler.openBounty(1 ether + i, 0, i);
        }
        assertGt(handler.opens(), 0, "handler should be able to open bounties");

        for (uint256 i = 0; i < 5; ++i) {
            handler.attempt(i, 0, i); // amountSeed 0 selects exactly 1e18
        }

        assertGt(handler.successfulClaims(), 0, "handler must be able to produce a claim");
        assertGt(handler.ghostPaidOut(), 0, "and money must actually have moved");
    }

    function invariant_CallSummary() public view {
        console.log("opens               :", handler.opens());
        console.log("successful claims   :", handler.successfulClaims());
        console.log("griefs              :", handler.griefs());
        console.log("deposited (wei)     :", handler.ghostDeposited());
        console.log("paid out  (wei)     :", handler.ghostPaidOut());
        console.log("still escrowed (wei):", registry.totalEscrowed());
    }
}
