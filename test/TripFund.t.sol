// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import {MockERC20} from "../src/MockERC20.sol";
import {TripFund} from "../src/TripFund.sol";
import {TripFundBase} from "../src/TripFundBase.sol";

contract TripFundTest is Test {
    event Contributed(address indexed contributor, uint256 amount);
    event Refunded(address indexed contributor, uint256 amount);
    event Withdrawn(address indexed organizer, uint256 amount);

    MockERC20 internal token;
    TripFund internal fund;

    address internal organizer;
    address internal alice;
    address internal bob;

    uint256 internal constant GOAL = 1_000 ether;
    uint256 internal deadline;

    function setUp() public {
        organizer = makeAddr("organizer");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        token = new MockERC20();
        deadline = block.timestamp + 7 days;
        fund = new TripFund(address(token), organizer, GOAL, deadline);

        token.mint(alice, 10_000 ether);
        token.mint(bob, 10_000 ether);
    }

    function _contribute(address user, uint256 amount) internal {
        vm.startPrank(user);
        token.approve(address(fund), amount);
        fund.contribute(amount);
        vm.stopPrank();
    }

    function _snapshot(address user)
        internal
        view
        returns (uint256 raised, uint256 contrib, uint256 userBal, uint256 fundBal)
    {
        raised = fund.totalRaised();
        contrib = fund.contributions(user);
        userBal = token.balanceOf(user);
        fundBal = token.balanceOf(address(fund));
    }

    function _assertUnchanged(address user, uint256 raised, uint256 contrib, uint256 userBal, uint256 fundBal)
        internal
        view
    {
        assertEq(fund.totalRaised(), raised);
        assertEq(fund.contributions(user), contrib);
        assertEq(token.balanceOf(user), userBal);
        assertEq(token.balanceOf(address(fund)), fundBal);
    }

    // --- constructor ---

    function test_constructorSetsParams() public view {
        assertEq(address(fund.token()), address(token));
        assertEq(fund.organizer(), organizer);
        assertEq(fund.goal(), GOAL);
        assertEq(fund.deadline(), deadline);
        assertEq(fund.totalRaised(), 0);
    }

    function test_constructorRevertsZeroToken() public {
        vm.expectRevert(TripFundBase.ZeroAddress.selector);
        new TripFund(address(0), organizer, GOAL, deadline);
    }

    function test_constructorRevertsZeroOrganizer() public {
        vm.expectRevert(TripFundBase.ZeroAddress.selector);
        new TripFund(address(token), address(0), GOAL, deadline);
    }

    function test_constructorRevertsZeroGoal() public {
        vm.expectRevert(TripFundBase.ZeroGoal.selector);
        new TripFund(address(token), organizer, 0, deadline);
    }

    function test_constructorRevertsDeadlineNow() public {
        vm.expectRevert(TripFundBase.DeadlineNotInFuture.selector);
        new TripFund(address(token), organizer, GOAL, block.timestamp);
    }

    function test_constructorRevertsDeadlineInPast() public {
        vm.expectRevert(TripFundBase.DeadlineNotInFuture.selector);
        new TripFund(address(token), organizer, GOAL, block.timestamp - 1);
    }

    // --- 6. two contributors, repeats, bad inputs ---

    function test_twoContributorsAndRepeatedContributions() public {
        vm.startPrank(alice);
        token.approve(address(fund), 100 ether);
        vm.expectEmit(true, false, false, true, address(fund));
        emit Contributed(alice, 100 ether);
        fund.contribute(100 ether);
        vm.stopPrank();

        _contribute(alice, 250 ether);
        _contribute(bob, 400 ether);

        assertEq(fund.contributions(alice), 350 ether);
        assertEq(fund.contributions(bob), 400 ether);
        assertEq(fund.totalRaised(), 750 ether);
        assertEq(token.balanceOf(address(fund)), 750 ether);
        assertEq(token.balanceOf(alice), 10_000 ether - 350 ether);
        assertEq(token.balanceOf(bob), 10_000 ether - 400 ether);
    }

    function test_zeroAmountRevertsWithoutStateChange() public {
        _contribute(alice, 50 ether);
        (uint256 raised, uint256 contrib, uint256 userBal, uint256 fundBal) = _snapshot(alice);

        vm.startPrank(alice);
        token.approve(address(fund), 1 ether);
        vm.expectRevert(TripFundBase.ZeroAmount.selector);
        fund.contribute(0);
        vm.stopPrank();

        _assertUnchanged(alice, raised, contrib, userBal, fundBal);
    }

    function test_insufficientAllowanceRevertsWithoutStateChange() public {
        (uint256 raised, uint256 contrib, uint256 userBal, uint256 fundBal) = _snapshot(alice);

        vm.startPrank(alice);
        token.approve(address(fund), 10 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(fund), 10 ether, 100 ether)
        );
        fund.contribute(100 ether);
        vm.stopPrank();

        _assertUnchanged(alice, raised, contrib, userBal, fundBal);
    }

    function test_insufficientBalanceRevertsWithoutStateChange() public {
        address poor = makeAddr("poor");
        token.mint(poor, 5 ether);

        (uint256 raised, uint256 contrib, uint256 userBal, uint256 fundBal) = _snapshot(poor);

        vm.startPrank(poor);
        token.approve(address(fund), 100 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, poor, 5 ether, 100 ether)
        );
        fund.contribute(100 ether);
        vm.stopPrank();

        _assertUnchanged(poor, raised, contrib, userBal, fundBal);
    }

    // --- 7. deadline boundary, no payouts before deadline ---

    function test_contributeOneSecondBeforeDeadlineSucceeds() public {
        vm.warp(deadline - 1);
        _contribute(alice, 100 ether);
        assertEq(fund.contributions(alice), 100 ether);
        assertEq(fund.totalRaised(), 100 ether);
    }

    function test_contributeAtDeadlineReverts() public {
        vm.warp(deadline);
        (uint256 raised, uint256 contrib, uint256 userBal, uint256 fundBal) = _snapshot(alice);

        vm.startPrank(alice);
        token.approve(address(fund), 100 ether);
        vm.expectRevert(TripFundBase.DeadlineReached.selector);
        fund.contribute(100 ether);
        vm.stopPrank();

        _assertUnchanged(alice, raised, contrib, userBal, fundBal);
    }

    function test_payoutsForbiddenBeforeDeadlineEvenIfGoalReached() public {
        _contribute(alice, GOAL);

        vm.prank(organizer);
        vm.expectRevert(TripFundBase.DeadlineNotReached.selector);
        fund.withdraw();

        vm.prank(alice);
        vm.expectRevert(TripFundBase.DeadlineNotReached.selector);
        fund.refund();

        assertEq(token.balanceOf(address(fund)), GOAL);
        assertEq(fund.totalRaised(), GOAL);
        assertFalse(fund.withdrawn());
    }

    // --- 8. success / failure outcomes ---

    function test_withdrawWhenRaisedEqualsGoal() public {
        _contribute(alice, GOAL);
        vm.warp(deadline);

        vm.expectEmit(true, false, false, true, address(fund));
        emit Withdrawn(organizer, GOAL);
        vm.prank(organizer);
        fund.withdraw();

        assertEq(token.balanceOf(organizer), GOAL);
        assertEq(token.balanceOf(address(fund)), 0);
        assertEq(fund.totalRaised(), GOAL);
        assertTrue(fund.withdrawn());
    }

    function test_withdrawWhenRaisedAboveGoal() public {
        _contribute(alice, 700 ether);
        _contribute(bob, 400 ether);
        vm.warp(deadline);

        vm.prank(organizer);
        fund.withdraw();

        assertEq(token.balanceOf(organizer), 1_100 ether);
        assertEq(fund.totalRaised(), 1_100 ether);
        assertEq(token.balanceOf(address(fund)), 0);
    }

    function test_strangerCannotWithdraw() public {
        _contribute(alice, GOAL);
        vm.warp(deadline);

        vm.prank(alice);
        vm.expectRevert(TripFundBase.NotOrganizer.selector);
        fund.withdraw();

        assertEq(token.balanceOf(organizer), 0);
        assertFalse(fund.withdrawn());
    }

    function test_repeatWithdrawReverts() public {
        _contribute(alice, GOAL);
        vm.warp(deadline);

        vm.prank(organizer);
        fund.withdraw();

        vm.prank(organizer);
        vm.expectRevert(TripFundBase.AlreadyWithdrawn.selector);
        fund.withdraw();
    }

    function test_refundOnSuccessReverts() public {
        _contribute(alice, GOAL);
        vm.warp(deadline);

        vm.prank(alice);
        vm.expectRevert(TripFundBase.GoalReached.selector);
        fund.refund();
    }

    function test_independentRefundsOnFailure() public {
        _contribute(alice, 200 ether);
        _contribute(bob, 300 ether);
        vm.warp(deadline);

        uint256 aliceBefore = token.balanceOf(alice);
        vm.expectEmit(true, false, false, true, address(fund));
        emit Refunded(alice, 200 ether);
        vm.prank(alice);
        fund.refund();

        assertEq(token.balanceOf(alice), aliceBefore + 200 ether);
        assertEq(fund.contributions(alice), 0);
        assertEq(fund.contributions(bob), 300 ether);
        assertEq(fund.totalRaised(), 500 ether);

        uint256 bobBefore = token.balanceOf(bob);
        vm.prank(bob);
        fund.refund();

        assertEq(token.balanceOf(bob), bobBefore + 300 ether);
        assertEq(fund.contributions(bob), 0);
        assertEq(token.balanceOf(address(fund)), 0);
        assertEq(fund.totalRaised(), 500 ether);
    }

    function test_withdrawOnFailureReverts() public {
        _contribute(alice, 100 ether);
        vm.warp(deadline);

        vm.prank(organizer);
        vm.expectRevert(TripFundBase.GoalNotReached.selector);
        fund.withdraw();
    }

    function test_refundWithoutContributionReverts() public {
        _contribute(alice, 100 ether);
        vm.warp(deadline);

        vm.prank(bob);
        vm.expectRevert(TripFundBase.NothingToRefund.selector);
        fund.refund();
    }

    function test_repeatRefundReverts() public {
        _contribute(alice, 100 ether);
        vm.warp(deadline);

        vm.prank(alice);
        fund.refund();

        vm.prank(alice);
        vm.expectRevert(TripFundBase.NothingToRefund.selector);
        fund.refund();
    }

    // --- 9. direct token transfer is ignored ---

    function test_directTransferDoesNotChangeTotalRaisedAndStaysAfterPayout() public {
        token.mint(address(this), 500 ether);
        token.transfer(address(fund), 500 ether);

        assertEq(fund.totalRaised(), 0);
        assertEq(token.balanceOf(address(fund)), 500 ether);

        _contribute(alice, GOAL);
        assertEq(fund.totalRaised(), GOAL);
        assertEq(token.balanceOf(address(fund)), GOAL + 500 ether);

        vm.warp(deadline);
        vm.prank(organizer);
        fund.withdraw();

        assertEq(token.balanceOf(organizer), GOAL);
        assertEq(fund.totalRaised(), GOAL);
        assertEq(token.balanceOf(address(fund)), 500 ether);
    }

    function test_directTransferStaysAfterRefunds() public {
        token.mint(address(this), 80 ether);
        token.transfer(address(fund), 80 ether);

        _contribute(alice, 100 ether);
        _contribute(bob, 50 ether);
        vm.warp(deadline);

        vm.prank(alice);
        fund.refund();
        vm.prank(bob);
        fund.refund();

        assertEq(fund.totalRaised(), 150 ether);
        assertEq(token.balanceOf(address(fund)), 80 ether);
    }
}
