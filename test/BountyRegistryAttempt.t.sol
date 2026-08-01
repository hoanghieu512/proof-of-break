// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {BountyRegistry} from "../src/BountyRegistry.sol";
import {DemoVault} from "../src/DemoVault.sol";
import {IChecker} from "../src/IChecker.sol";
import {VaultChecker, IVaultLedger} from "../src/VaultChecker.sol";
import {
    FlagTarget,
    FlagChecker,
    ReentrantTarget,
    SabotageChecker,
    CheckerSabotagingTarget,
    ReturndataBombTarget,
    RejectingClaimant
} from "./mocks/HostileMocks.sol";

/**
 * @notice The attack surface of `attempt`.
 * @dev Registry hands control to an arbitrary contract while holding every
 *      bounty's money. These tests are the reason to believe that is survivable.
 */
contract BountyRegistryAttemptTest is Test {
    BountyRegistry internal registry;
    DemoVault internal vault;
    VaultChecker internal checker;

    address internal sponsor = makeAddr("sponsor");
    address internal agent = makeAddr("agent");
    address internal bystander = makeAddr("bystander");

    uint256 internal oneUsdc;
    uint256 internal threshold;
    uint256 internal reward;

    string internal constant SIG = "deposit(uint256)";

    event AttemptMade(uint256 indexed bountyId, address indexed attacker, bool brokeInvariant);
    event BountyClaimed(uint256 indexed bountyId, address indexed claimant, uint256 reward);

    function setUp() public {
        registry = new BountyRegistry();
        vault = new DemoVault();
        checker = new VaultChecker(IVaultLedger(address(vault)));

        oneUsdc = registry.ONE_USDC();
        threshold = vault.LARGE_DEPOSIT_THRESHOLD();
        reward = 10 * oneUsdc;

        vm.deal(sponsor, 1_000 * oneUsdc);
        vm.deal(agent, 1_000 * oneUsdc);
        vm.deal(bystander, 1_000 * oneUsdc);
    }

    function _openVaultBounty() internal returns (uint256 id) {
        vm.prank(sponsor);
        id = registry.openBounty{value: reward}(address(vault), checker, SIG);
    }

    function _breakingCall() internal view returns (bytes memory) {
        return abi.encodeCall(DemoVault.deposit, (threshold));
    }

    // ---------------------------------------------------------------------
    // 1. The happy path — and it must be exactly this happy, no more
    // ---------------------------------------------------------------------

    function test_BreakingTheInvariantPaysTheCallerAndClosesTheBounty() public {
        uint256 id = _openVaultBounty();
        uint256 agentBefore = agent.balance;

        vm.prank(agent);
        bool broke = registry.attempt(id, _breakingCall());

        assertTrue(broke, "the boundary value should break it");
        assertEq(agent.balance, agentBefore + reward, "agent must receive exactly the reward");
        assertEq(address(registry).balance, 0, "escrow must be emptied of this bounty");
        assertEq(registry.totalEscrowed(), 0, "books must follow the money");

        BountyRegistry.Bounty memory b = registry.getBounty(id);
        assertTrue(b.paid, "bounty must be closed");

        assertEq(registry.openBountyIds().length, 0, "and must leave the open board");
        assertFalse(checker.checkInvariant(), "the break is real and still visible");
    }

    function test_PayoutEmitsTheClaimEvent() public {
        uint256 id = _openVaultBounty();

        vm.expectEmit(true, true, false, true, address(registry));
        emit AttemptMade(id, agent, true);
        vm.expectEmit(true, true, false, true, address(registry));
        emit BountyClaimed(id, agent, reward);

        vm.prank(agent);
        registry.attempt(id, _breakingCall());
    }

    function test_OnlyTheAttackedBountyIsAffected() public {
        uint256 idA = _openVaultBounty();

        DemoVault vaultB = new DemoVault();
        VaultChecker checkerB = new VaultChecker(IVaultLedger(address(vaultB)));
        uint256 rewardB = 4 * oneUsdc;
        vm.prank(sponsor);
        uint256 idB = registry.openBounty{value: rewardB}(address(vaultB), checkerB, SIG);

        vm.prank(agent);
        registry.attempt(idA, _breakingCall());

        assertEq(registry.getBounty(idB).reward, rewardB, "bounty B must be untouched");
        assertFalse(registry.getBounty(idB).paid);
        assertEq(registry.totalEscrowed(), rewardB, "only A left the books");
        assertEq(address(registry).balance, rewardB, "only A's money moved");
    }

    // ---------------------------------------------------------------------
    // 2. Everything that must NOT pay
    // ---------------------------------------------------------------------

    function test_HarmlessActionPaysNobody() public {
        uint256 id = _openVaultBounty();
        uint256 agentBefore = agent.balance;

        vm.prank(agent);
        bool broke = registry.attempt(id, abi.encodeCall(DemoVault.deposit, (threshold - 1)));

        assertFalse(broke, "a near-miss is not a break");
        assertEq(agent.balance, agentBefore, "nothing paid out");
        assertEq(address(registry).balance, reward, "escrow untouched");
        assertFalse(registry.getBounty(id).paid, "bounty stays open");
    }

    function test_AnInvariantBrokenBeforehandPaysNobody() public {
        uint256 id = _openVaultBounty();

        // Anyone can call the target directly — it is a public contract. This
        // is the accepted griefing vector documented in the README.
        vm.prank(bystander);
        vault.deposit(threshold);
        assertFalse(checker.checkInvariant(), "vault is already broken");

        vm.prank(agent);
        vm.expectRevert(BountyRegistry.InvariantAlreadyBroken.selector);
        registry.attempt(id, _breakingCall());

        assertEq(address(registry).balance, reward, "money stays put");
        assertFalse(registry.getBounty(id).paid);
    }

    function test_APaidBountyCannotBePaidAgain() public {
        uint256 id = _openVaultBounty();

        vm.prank(agent);
        registry.attempt(id, _breakingCall());
        assertEq(address(registry).balance, 0);

        vm.prank(bystander);
        vm.expectRevert(abi.encodeWithSelector(BountyRegistry.BountyAlreadyPaid.selector, id));
        registry.attempt(id, _breakingCall());
    }

    function test_CallingAFunctionTheBountyDidNotDeclareIsRefused() public {
        uint256 id = _openVaultBounty();

        bytes memory forbidden = abi.encodeCall(DemoVault.withdraw, (1));
        bytes4 attempted = bytes4(keccak256("withdraw(uint256)"));
        bytes4 allowed = bytes4(keccak256(bytes(SIG)));

        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(BountyRegistry.DisallowedFunction.selector, attempted, allowed)
        );
        registry.attempt(id, forbidden);

        assertEq(address(registry).balance, reward);
    }

    function test_CallDataShorterThanASelectorIsRefused() public {
        uint256 id = _openVaultBounty();

        vm.prank(agent);
        vm.expectRevert(BountyRegistry.CallDataTooShort.selector);
        registry.attempt(id, hex"abcd");
    }

    function test_AttemptOnAMissingBountyReverts() public {
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(BountyRegistry.NoSuchBounty.selector, uint256(7)));
        registry.attempt(7, _breakingCall());
    }

    function test_ATargetCallThatRevertsPaysNobody() public {
        uint256 id = _openVaultBounty();

        // deposit(0) reverts inside DemoVault.
        vm.prank(agent);
        vm.expectRevert(BountyRegistry.TargetCallFailed.selector);
        registry.attempt(id, abi.encodeCall(DemoVault.deposit, (0)));

        assertEq(address(registry).balance, reward);
    }

    // ---------------------------------------------------------------------
    // 3. Reentrancy — the failure mode that empties contracts
    // ---------------------------------------------------------------------

    function test_TargetReenteringAttemptIsBlockedAndStealsNothing() public {
        uint256 victimId = _openVaultBounty();

        ReentrantTarget hostile = new ReentrantTarget(registry);
        FlagChecker hostileChecker = new FlagChecker(address(hostile));
        uint256 hostileReward = 3 * oneUsdc;

        vm.prank(sponsor);
        uint256 hostileId =
            registry.openBounty{value: hostileReward}(address(hostile), hostileChecker, "poke(uint256)");

        hostile.configure(ReentrantTarget.Mode.ReenterAttempt, victimId);

        uint256 escrowBefore = address(registry).balance;
        assertEq(escrowBefore, reward + hostileReward);

        vm.prank(agent);
        bool broke = registry.attempt(hostileId, abi.encodeWithSignature("poke(uint256)", 1));

        // The hostile target does genuinely break its own invariant, so its own
        // bounty pays — that part is legitimate and expected.
        assertTrue(broke, "the hostile target really does trip its own checker");
        assertTrue(hostile.reentryWasBlocked(), "the re-entry must have been refused");
        assertEq(
            bytes4(hostile.reentryRevertData()),
            BountyRegistry.ReentrantCall.selector,
            "and refused specifically by the reentrancy lock"
        );

        // The crucial assertions: the victim bounty is untouched and exactly
        // one reward left the contract.
        assertFalse(registry.getBounty(victimId).paid, "victim bounty must be untouched");
        assertEq(registry.getBounty(victimId).reward, reward);
        assertEq(address(registry).balance, reward, "only the hostile bounty's own reward left");
        assertEq(registry.totalEscrowed(), reward, "books agree");
    }

    function test_TargetReenteringOpenBountyIsBlocked() public {
        ReentrantTarget hostile = new ReentrantTarget(registry);
        FlagChecker hostileChecker = new FlagChecker(address(hostile));

        vm.prank(sponsor);
        uint256 hostileId =
            registry.openBounty{value: 5 * oneUsdc}(address(hostile), hostileChecker, "poke(uint256)");

        hostile.configure(ReentrantTarget.Mode.ReenterOpenBounty, 0);
        vm.deal(address(hostile), 1 ether);

        uint256 countBefore = registry.bountyCount();

        vm.prank(agent);
        registry.attempt(hostileId, abi.encodeWithSignature("poke(uint256)", 1));

        assertTrue(hostile.reentryWasBlocked(), "opening a bounty mid-attempt must be refused");
        assertEq(
            bytes4(hostile.reentryRevertData()),
            BountyRegistry.ReentrantCall.selector,
            "refused by the lock, not by argument validation"
        );
        assertEq(registry.bountyCount(), countBefore, "no bounty was created");
    }

    function test_RegistryCannotBeNamedAsTargetOrChecker() public {
        vm.prank(sponsor);
        vm.expectRevert(BountyRegistry.SelfReference.selector);
        registry.openBounty{value: oneUsdc}(address(registry), checker, SIG);

        vm.prank(sponsor);
        vm.expectRevert(BountyRegistry.SelfReference.selector);
        registry.openBounty{value: oneUsdc}(address(vault), IChecker(address(registry)), SIG);
    }

    // ---------------------------------------------------------------------
    // 4. A checker that cannot answer must never look like proof
    // ---------------------------------------------------------------------

    function test_ACheckerSabotagedMidAttemptDoesNotProduceAPayout() public {
        CheckerSabotagingTarget hostile = new CheckerSabotagingTarget();
        SabotageChecker sabotaged = new SabotageChecker(address(hostile));
        hostile.configure(sabotaged, SabotageChecker.Sabotage.Revert);

        vm.prank(sponsor);
        uint256 id =
            registry.openBounty{value: reward}(address(hostile), sabotaged, "poke(uint256)");

        uint256 agentBefore = agent.balance;

        // The action makes the checker unable to answer. If "cannot answer"
        // were read as "invariant broken", this would mint a payout.
        vm.prank(agent);
        vm.expectRevert(BountyRegistry.CheckerUnusable.selector);
        registry.attempt(id, abi.encodeWithSignature("poke(uint256)", 1));

        assertEq(agent.balance, agentBefore, "no payout for a silent checker");
        assertEq(address(registry).balance, reward, "escrow intact");
        assertFalse(registry.getBounty(id).paid);
    }

    function test_ACheckerThatBurnsAllGasDoesNotProduceAPayout() public {
        CheckerSabotagingTarget hostile = new CheckerSabotagingTarget();
        SabotageChecker sabotaged = new SabotageChecker(address(hostile));
        hostile.configure(sabotaged, SabotageChecker.Sabotage.BurnGas);

        vm.prank(sponsor);
        uint256 id =
            registry.openBounty{value: reward}(address(hostile), sabotaged, "poke(uint256)");

        uint256 agentBefore = agent.balance;

        vm.prank(agent);
        (bool ok,) = address(registry).call{gas: 3_000_000}(
            abi.encodeCall(
                BountyRegistry.attempt, (id, abi.encodeWithSignature("poke(uint256)", 1))
            )
        );

        assertFalse(ok, "a checker that cannot answer must not yield a successful claim");
        assertEq(agent.balance, agentBefore, "no payout");
        assertEq(address(registry).balance, reward, "escrow intact");
        assertFalse(registry.getBounty(id).paid);
    }

    function test_OtherBountiesStillWorkAfterAPoisonedOneFails() public {
        // "Not stuck": one bad bounty must not brick the Registry.
        CheckerSabotagingTarget hostile = new CheckerSabotagingTarget();
        SabotageChecker sabotaged = new SabotageChecker(address(hostile));
        hostile.configure(sabotaged, SabotageChecker.Sabotage.Revert);

        vm.prank(sponsor);
        uint256 poisonedId =
            registry.openBounty{value: 2 * oneUsdc}(address(hostile), sabotaged, "poke(uint256)");

        uint256 goodId = _openVaultBounty();

        vm.prank(agent);
        vm.expectRevert(BountyRegistry.CheckerUnusable.selector);
        registry.attempt(poisonedId, abi.encodeWithSignature("poke(uint256)", 1));

        // The healthy bounty is entirely unaffected.
        uint256 agentBefore = agent.balance;
        vm.prank(agent);
        assertTrue(registry.attempt(goodId, _breakingCall()));
        assertEq(agent.balance, agentBefore + reward);
        assertEq(registry.totalEscrowed(), 2 * oneUsdc, "the poisoned bounty's money is still held");
    }

    // ---------------------------------------------------------------------
    // 5. Odds and ends that could still cost money
    // ---------------------------------------------------------------------

    function test_AReturndataBombDoesNotBreakTheAttempt() public {
        ReturndataBombTarget bomb = new ReturndataBombTarget();
        FlagChecker bombChecker = new FlagChecker(address(bomb));

        vm.prank(sponsor);
        uint256 id = registry.openBounty{value: reward}(address(bomb), bombChecker, "poke(uint256)");

        uint256 agentBefore = agent.balance;
        vm.prank(agent);
        bool broke = registry.attempt(id, abi.encodeWithSignature("poke(uint256)", 1));

        assertTrue(broke, "the bomb still breaks its invariant honestly");
        assertEq(agent.balance, agentBefore + reward, "and is paid normally");
    }

    function test_AClaimantThatRefusesPaymentRevertsTheWholeAttempt() public {
        uint256 id = _openVaultBounty();
        RejectingClaimant claimant = new RejectingClaimant(registry);

        vm.expectRevert(BountyRegistry.PayoutFailed.selector);
        claimant.attempt(id, _breakingCall());

        // The revert undoes everything: the bounty is still open and funded.
        assertFalse(registry.getBounty(id).paid, "nothing was settled");
        assertEq(address(registry).balance, reward, "money is still escrowed");
        assertEq(registry.totalEscrowed(), reward);
        assertTrue(checker.checkInvariant(), "even the target's state was rolled back");
    }

    function test_TheLockIsReleasedAfterAFailedAttempt() public {
        uint256 id = _openVaultBounty();

        vm.prank(agent);
        vm.expectRevert(BountyRegistry.TargetCallFailed.selector);
        registry.attempt(id, abi.encodeCall(DemoVault.deposit, (0)));

        // A stuck lock would brick the contract permanently.
        vm.prank(agent);
        assertFalse(registry.attempt(id, abi.encodeCall(DemoVault.deposit, (1 wei))));

        DemoVault freshVault = new DemoVault();
        VaultChecker freshChecker = new VaultChecker(IVaultLedger(address(freshVault)));
        vm.prank(sponsor);
        registry.openBounty{value: oneUsdc}(address(freshVault), freshChecker, SIG);
    }

    function test_AnyoneCanClaim_ThereIsNoAllowlist() public {
        uint256 id = _openVaultBounty();
        address nobody = makeAddr("a complete stranger");
        uint256 before = nobody.balance;

        vm.prank(nobody);
        assertTrue(registry.attempt(id, _breakingCall()));
        assertEq(nobody.balance, before + reward);
    }
}
