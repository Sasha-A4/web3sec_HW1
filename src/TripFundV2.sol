// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TripFundV1} from "./TripFundV1.sol";

/// @custom:oz-upgrades-from TripFundV1
/// @notice V2 adds contributeFor: payer is msg.sender, credit goes to beneficiary.
contract TripFundV2 is TripFundV1 {
    event ContributedFor(address indexed payer, address indexed beneficiary, uint256 amount);

    function contributeFor(address beneficiary, uint256 amount) public {
        _credit(beneficiary, amount);
        _pull(msg.sender, amount);
        emit ContributedFor(msg.sender, beneficiary, amount);
    }
}
