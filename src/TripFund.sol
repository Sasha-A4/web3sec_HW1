// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TripFundBase} from "./TripFundBase.sol";

/// @notice Non-upgradeable TripFund. Parameters are fixed in the constructor.
contract TripFund is TripFundBase {
    constructor(address token_, address organizer_, uint256 goal_, uint256 deadline_) {
        _init(token_, organizer_, goal_, deadline_);
    }
}
