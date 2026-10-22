// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {MockERC20} from "../src/MockERC20.sol";
import {TripFundBase} from "../src/TripFundBase.sol";
import {TripFundV1} from "../src/TripFundV1.sol";
import {TripFundV2} from "../src/TripFundV2.sol";

contract TripFundUpgradeTest is Test {
    event Contributed(address indexed contributor, uint256 amount);
    event ContributedFor(address indexed payer, address indexed beneficiary, uint256 amount);
    event Refunded(address indexed contributor, uint256 amount);

    MockERC20 internal token;
    TripFundV1 internal fund;

    address internal admin;
    address internal organizer;
    address internal alice;
    address internal bob;
    address internal friend;

    uint256 internal constant GOAL = 1_000 ether;
    uint256 internal deadline;
    address internal proxy;

    function setUp() public {
        admin = makeAddr("proxyAdminOwner");
        organizer = makeAddr("organizer");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        friend = makeAddr("friend");

        token = new MockERC20();
        deadline = block.timestamp + 7 days;

        proxy = Upgrades.deployTransparentProxy(
            "TripFundV1.sol:TripFundV1",
            admin,
            abi.encodeCall(TripFundV1.initialize, (address(token), organizer, GOAL, deadline))
        );
        fund = TripFundV1(proxy);

        token.mint(alice, 10_000 ether);
        token.mint(bob, 10_000 ether);
        token.mint(friend, 10_000 ether);
    }

    function _approveAndContribute(address user, uint256 amount) internal {
        vm.startPrank(user);
        token.approve(proxy, amount);
        fund.contribute(amount);
        vm.stopPrank();
    }

    function test_storageLayoutCompatibleWithOpenZeppelinUpgrades() public {
        Options memory opts;
        opts.referenceContract = "TripFundV1.sol:TripFundV1";
        Upgrades.validateUpgrade("TripFundV2.sol:TripFundV2", opts);
    }

    function test_cannotInitializeImplementationDirectly() public {
        TripFundV1 implementation = new TripFundV1();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(address(token), organizer, GOAL, deadline);
    }

    function test_cannotReinitializeProxy() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        fund.initialize(address(token), organizer, GOAL, deadline);
    }

    function test_upgradePreservesStateThenContributeForAndRefundFriend() public {
        _approveAndContribute(alice, 200 ether);

        uint256 raisedBefore = fund.totalRaised();
        uint256 aliceBefore = fund.contributions(alice);
        uint256 tokenBalBefore = token.balanceOf(proxy);
        address implV1 = Upgrades.getImplementationAddress(proxy);

        Options memory opts;
        opts.referenceContract = "TripFundV1.sol:TripFundV1";
        Upgrades.upgradeProxy(proxy, "TripFundV2.sol:TripFundV2", "", opts, admin);

        TripFundV2 v2 = TripFundV2(proxy);
        assertEq(address(v2), proxy);
        assertTrue(Upgrades.getImplementationAddress(proxy) != implV1);

        assertEq(address(v2.token()), address(token));
        assertEq(v2.organizer(), organizer);
        assertEq(v2.goal(), GOAL);
        assertEq(v2.deadline(), deadline);
        assertEq(v2.contributions(alice), aliceBefore);
        assertEq(v2.totalRaised(), raisedBefore);
        assertEq(token.balanceOf(proxy), tokenBalBefore);

        vm.startPrank(bob);
        token.approve(proxy, 80 ether);
        vm.expectEmit(true, true, false, true, proxy);
        emit ContributedFor(bob, friend, 80 ether);
        v2.contributeFor(friend, 80 ether);
        vm.stopPrank();

        assertEq(v2.contributions(friend), 80 ether);
        assertEq(v2.contributions(bob), 0);
        assertEq(v2.totalRaised(), 280 ether);

        vm.startPrank(bob);
        token.approve(proxy, 50 ether);
        vm.expectEmit(true, false, false, true, proxy);
        emit Contributed(bob, 50 ether);
        v2.contribute(50 ether);
        vm.stopPrank();

        assertEq(v2.contributions(bob), 50 ether);
        assertEq(v2.totalRaised(), 330 ether);

        vm.warp(deadline);

        uint256 friendBefore = token.balanceOf(friend);
        vm.expectEmit(true, false, false, true, proxy);
        emit Refunded(friend, 80 ether);
        vm.prank(friend);
        v2.refund();
        assertEq(token.balanceOf(friend), friendBefore + 80 ether);
        assertEq(v2.contributions(friend), 0);

        vm.prank(alice);
        v2.refund();
        vm.prank(bob);
        v2.refund();

        assertEq(v2.totalRaised(), 330 ether);
        assertEq(token.balanceOf(proxy), 0);
    }

    function test_strangerCannotUpgrade() public {
        Options memory opts;
        opts.referenceContract = "TripFundV1.sol:TripFundV1";
        address newImpl = Upgrades.deployImplementation("TripFundV2.sol:TripFundV2", opts);
        address proxyAdmin = Upgrades.getAdminAddress(proxy);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        ProxyAdmin(proxyAdmin).upgradeAndCall(ITransparentUpgradeableProxy(proxy), newImpl, "");
    }

    function test_cannotReinitializeAfterUpgrade() public {
        Upgrades.upgradeProxy(proxy, "TripFundV2.sol:TripFundV2", "", admin);
        TripFundV2 v2 = TripFundV2(proxy);

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        v2.initialize(address(token), organizer, GOAL, deadline);
    }

    function test_contributeForZeroBeneficiaryReverts() public {
        Upgrades.upgradeProxy(proxy, "TripFundV2.sol:TripFundV2", "", admin);
        TripFundV2 v2 = TripFundV2(proxy);

        vm.startPrank(alice);
        token.approve(proxy, 10 ether);
        vm.expectRevert(TripFundBase.ZeroAddress.selector);
        v2.contributeFor(address(0), 10 ether);
        vm.stopPrank();
    }

    function test_contributeForSumsWithExistingCredit() public {
        _approveAndContribute(friend, 40 ether);
        Upgrades.upgradeProxy(proxy, "TripFundV2.sol:TripFundV2", "", admin);
        TripFundV2 v2 = TripFundV2(proxy);

        vm.startPrank(alice);
        token.approve(proxy, 15 ether);
        v2.contributeFor(friend, 15 ether);
        vm.stopPrank();

        assertEq(v2.contributions(friend), 55 ether);
        assertEq(v2.contributions(alice), 0);
        assertEq(v2.totalRaised(), 55 ether);
    }
}
