// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {TripFundBase} from "./TripFundBase.sol";

/// @notice Upgradeable V1. Deploy behind a Transparent Proxy and call initialize.
contract TripFundV1 is Initializable, TripFundBase {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address token_, address organizer_, uint256 goal_, uint256 deadline_) public initializer {
        _init(token_, organizer_, goal_, deadline_);
    }
}
