// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {FundMe} from "../../src/FundMe.sol";
import {DeployFundMe} from "../../script/DeployFundMe.s.sol";

contract FundMeTest is Test {
    FundMe fundMe;
    uint256 expectedVersion;
    uint256 constant MAINNET_AGGREGATOR_VERSION = 6;
    uint256 constant SEPOLIA_AND_MOCK_AGGREGATOR_VERSION = 4;
    uint256 constant MINIMUM_DOLLAR_AMOUNT = 5e18;
    uint256 constant INVALID_FUND_VALUE = 0.0001 ether;
    uint256 constant FUND_VALUE = 0.1 ether;
    uint256 constant STARTING_USER_BALANCE = 10 ether;
    uint256 constant GAS_PRICE = 1;

    address USER = makeAddr("user");

    modifier funded() {
        vm.prank(USER);
        fundMe.fund{value: FUND_VALUE}();
        _;
    }

    function setUp() external {
        DeployFundMe deployFundMe = new DeployFundMe();
        fundMe = deployFundMe.run();
        // chainlink price feed contracts have different versions depending on chain ID
        if (block.chainid == 1) {
            expectedVersion = MAINNET_AGGREGATOR_VERSION;
        } else {
            expectedVersion = SEPOLIA_AND_MOCK_AGGREGATOR_VERSION;
        }
        vm.deal(USER, STARTING_USER_BALANCE);
    }

    function testMinimumDollarAmountIsFive() public view {
        assertEq(fundMe.MINIMUM_USD(), MINIMUM_DOLLAR_AMOUNT);
    }

    function testOwnerIsDeployer() public view {
        console.log(fundMe.getOwner());
        console.log(address(this));
        console.log(msg.sender);
        assertEq(fundMe.getOwner(), msg.sender);
    }

    function testPriceFeedVersionIsAccurate() public view {
        uint256 version = fundMe.getVersion();
        console.log(expectedVersion);
        console.log(version);
        assertEq(version, expectedVersion);
    }

    function testFundFailsWithoutEnoughEth() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                FundMe.FundMe__EthSentIsLessThanMinimumDonation.selector,
                0,
                MINIMUM_DOLLAR_AMOUNT
            )
        );
        fundMe.fund();

        vm.expectRevert(
            abi.encodeWithSelector(
                FundMe.FundMe__EthSentIsLessThanMinimumDonation.selector,
                INVALID_FUND_VALUE,
                MINIMUM_DOLLAR_AMOUNT
            )
        );
        fundMe.fund{value: INVALID_FUND_VALUE}();
    }

    function testFundUpdatesFundedDataStructure() public {
        vm.prank(USER);
        fundMe.fund{value: FUND_VALUE}();
        uint256 amountFunded = fundMe.getAmountFundedByAddress(USER);
        assertEq(amountFunded, FUND_VALUE);
        assertEq(USER.balance, STARTING_USER_BALANCE - FUND_VALUE);
    }

    function testFunderIsAddedToArrayOfFunders() public {
        testFundUpdatesFundedDataStructure();
        assertEq(fundMe.getFunderAtIndex(0), USER);
    }

    function testOnlyOwnerCanWithdraw() public funded {
        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(FundMe.FundMe__NotOwner.selector)
        );
        fundMe.withdraw();
    }

    function testOwnerCanWithdrawFundsFromSingleFunder() public funded {
        // Arrange
        uint256 startingOwnerBalance = fundMe.getOwner().balance;
        uint256 startingFundMeBalance = address(fundMe).balance;
        uint256 expectedBalanceAfterWithdraw = startingOwnerBalance +
            FUND_VALUE;
        assertEq(startingFundMeBalance, FUND_VALUE);
        assertEq(
            startingOwnerBalance + startingFundMeBalance,
            expectedBalanceAfterWithdraw
        );
        // Act
        // uint256 gasStart = gasleft();
        // vm.txGasPrice(GAS_PRICE);
        vm.prank(fundMe.getOwner());
        fundMe.withdraw();
        // uint256 gasEnd = gasleft();
        // uint256 gasUsed = (gasStart - gasEnd) * tx.gasprice;
        // console.log(gasUsed);
        // Note: If you want to get exact balance, need to account for gas cost but test environment sets gas price to 0 unless you change it like above
        // Assert
        assertEq(address(fundMe).balance, 0);
        assertEq(fundMe.getOwner().balance, expectedBalanceAfterWithdraw);
    }

    function testOwnerCanWithdrawFundsFromMultipleFunders() public funded {
        // Arrange
        uint160 numberOfFunders = 10;
        uint160 startingFunderIndex = 1;
        for (uint160 i = startingFunderIndex; i < numberOfFunders; i++) {
            // vm.prank and vm.deal at the same time with hoax
            hoax(address(i), FUND_VALUE);
            fundMe.fund{value: FUND_VALUE}();
        }
        uint256 startingOwnerBalance = fundMe.getOwner().balance;
        uint256 startingFundMeBalance = address(fundMe).balance;
        assertEq(startingFundMeBalance, FUND_VALUE * numberOfFunders);
        uint256 expectedBalanceAfterWithdraw = startingOwnerBalance +
            startingFundMeBalance;

        // ACT
        // vm.txGasPrice(GAS_PRICE);
        vm.prank(fundMe.getOwner());
        fundMe.withdraw();

        // Assert
        assertEq(address(fundMe).balance, 0);
        assertEq(fundMe.getOwner().balance, expectedBalanceAfterWithdraw);
    }

    function testFallbackFunction() public {
        vm.prank(USER);
        (bool success, ) = address(fundMe).call{value: FUND_VALUE}("donate()");
        assert(success);

        uint256 amountFunded = fundMe.getAmountFundedByAddress(USER);
        assertEq(amountFunded, FUND_VALUE);
        assertEq(USER.balance, STARTING_USER_BALANCE - FUND_VALUE);
        assertEq(fundMe.getFunderAtIndex(0), USER);
    }

    function testReceiveFunction() public {
        vm.prank(USER);
        (bool success, ) = address(fundMe).call{value: FUND_VALUE}("");
        assert(success);

        uint256 amountFunded = fundMe.getAmountFundedByAddress(USER);
        assertEq(amountFunded, FUND_VALUE);
        assertEq(USER.balance, STARTING_USER_BALANCE - FUND_VALUE);
        assertEq(fundMe.getFunderAtIndex(0), USER);
    }

    function testReceiveFunctionFailsWithoutEnoughEth() public {
        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(
                FundMe.FundMe__EthSentIsLessThanMinimumDonation.selector,
                0,
                MINIMUM_DOLLAR_AMOUNT
            )
        );
        (bool success, ) = address(fundMe).call{value: INVALID_FUND_VALUE}("");
        assert(!success);
        assertEq(fundMe.getAmountFundedByAddress(USER), 0);
    }
}
