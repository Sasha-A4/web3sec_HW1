// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Shared TripFund logic: contributions, organizer withdraw, refunds.
abstract contract TripFundBase {
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error ZeroGoal();
    error DeadlineNotInFuture();
    error ZeroAmount();
    error DeadlineReached();
    error DeadlineNotReached();
    error GoalNotReached();
    error GoalReached();
    error NotOrganizer();
    error AlreadyWithdrawn();
    error NothingToRefund();

    event Contributed(address indexed contributor, uint256 amount);
    event Refunded(address indexed contributor, uint256 amount);
    event Withdrawn(address indexed organizer, uint256 amount);

    IERC20 public token;
    address public organizer;
    uint256 public goal;
    uint256 public deadline;
    uint256 public totalRaised;
    mapping(address => uint256) public contributions;
    bool public withdrawn;

    function contribute(uint256 amount) public {
        _credit(msg.sender, amount);
        _pull(msg.sender, amount);
        emit Contributed(msg.sender, amount);
    }

    function withdraw() public {
        if (block.timestamp < deadline) revert DeadlineNotReached();
        if (totalRaised < goal) revert GoalNotReached();
        if (msg.sender != organizer) revert NotOrganizer();
        if (withdrawn) revert AlreadyWithdrawn();

        withdrawn = true;
        uint256 amount = totalRaised;
        token.safeTransfer(organizer, amount);
        emit Withdrawn(organizer, amount);
    }

    function refund() public {
        if (block.timestamp < deadline) revert DeadlineNotReached();
        if (totalRaised >= goal) revert GoalReached();

        uint256 amount = contributions[msg.sender];
        if (amount == 0) revert NothingToRefund();

        contributions[msg.sender] = 0;
        token.safeTransfer(msg.sender, amount);
        emit Refunded(msg.sender, amount);
    }

    function _init(address token_, address organizer_, uint256 goal_, uint256 deadline_) internal {
        if (token_ == address(0) || organizer_ == address(0)) revert ZeroAddress();
        if (goal_ == 0) revert ZeroGoal();
        if (deadline_ <= block.timestamp) revert DeadlineNotInFuture();

        token = IERC20(token_);
        organizer = organizer_;
        goal = goal_;
        deadline = deadline_;
    }

    function _credit(address beneficiary, uint256 amount) internal {
        if (amount == 0) revert ZeroAmount();
        if (block.timestamp >= deadline) revert DeadlineReached();
        if (beneficiary == address(0)) revert ZeroAddress();

        contributions[beneficiary] += amount;
        totalRaised += amount;
    }

    function _pull(address from, uint256 amount) internal {
        token.safeTransferFrom(from, address(this), amount);
    }
}
