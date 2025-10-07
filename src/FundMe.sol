// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// Note: The AggregatorV3Interface might be at a different location than what was in the video!
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {PriceConverter} from "./PriceConverter.sol";

contract FundMe {
    using PriceConverter for uint256;

    error FundMe__NotOwner();
    error FundMe__EthSentIsLessThanMinimumDonation(
        uint256 ethSent,
        uint256 minimumUsdValue
    );

    mapping(address => uint256) private s_addressToAmountFunded;
    address[] private s_funders;

    // Cant be constant because owner is set in constructor. Constants are for variables set at compile time
    address private immutable i_owner;
    AggregatorV3Interface private s_priceFeed;
    uint256 public constant MINIMUM_USD = 5 * 10 ** 18;

    constructor(address priceFeed) {
        i_owner = msg.sender;
        s_priceFeed = AggregatorV3Interface(priceFeed);
    }

    function fund() public payable {
        uint256 donationUsdValue = msg.value.getConversionRate(s_priceFeed);
        if (donationUsdValue < MINIMUM_USD) {
            revert FundMe__EthSentIsLessThanMinimumDonation(
                msg.value,
                MINIMUM_USD
            );
        }
        // require(PriceConverter.getConversionRate(msg.value) >= MINIMUM_USD, "You need to spend more ETH!");
        s_addressToAmountFunded[msg.sender] += msg.value;
        s_funders.push(msg.sender);
    }

    function getVersion() public view returns (uint256) {
        return s_priceFeed.version();
    }

    modifier onlyOwner() {
        // require(msg.sender == owner);
        if (msg.sender != i_owner) revert FundMe__NotOwner();
        _;
    }

    function withdraw() public onlyOwner {
        // save to memory instead of reading from storage multiple times
        uint256 fundersLength = s_funders.length;
        // set amounts funded for all funders back to 0
        for (
            uint256 funderIndex = 0;
            funderIndex < fundersLength;
            funderIndex++
        ) {
            address funder = s_funders[funderIndex];
            s_addressToAmountFunded[funder] = 0;
        }
        // reset the array
        s_funders = new address[](0);
        // call method to withdraw the funds to owner
        (bool callSuccess, ) = payable(msg.sender).call{
            value: address(this).balance
        }("");
        require(callSuccess, "Call failed");
    }

    // function withdraw() public onlyOwner {
    //     for (
    //         uint256 funderIndex = 0;
    //         funderIndex < s_funders.length;
    //         funderIndex++
    //     ) {
    //         address funder = s_funders[funderIndex];
    //         s_addressToAmountFunded[funder] = 0;
    //     }
    //     s_funders = new address[](0);
    //     // // transfer
    //     // payable(msg.sender).transfer(address(this).balance);

    //     // // send
    //     // bool sendSuccess = payable(msg.sender).send(address(this).balance);
    //     // require(sendSuccess, "Send failed");

    //     // call
    //     (bool callSuccess, ) = payable(msg.sender).call{
    //         value: address(this).balance
    //     }("");
    //     require(callSuccess, "Call failed");
    // }

    // Explainer from: https://solidity-by-example.org/fallback/
    // Ether is sent to contract
    //      is msg.data empty?
    //          /   \
    //         yes  no
    //         /     \
    //    receive()?  fallback()
    //     /   \
    //   yes   no
    //  /        \
    //receive()  fallback()

    fallback() external payable {
        fund();
    }

    receive() external payable {
        fund();
    }

    /**
     * View / Pure functions (Getters)
     */

    function getAmountFundedByAddress(
        address fundingAddress
    ) external view returns (uint256) {
        return s_addressToAmountFunded[fundingAddress];
    }

    function getFunderAtIndex(uint256 index) external view returns (address) {
        return s_funders[index];
    }

    function getOwner() external view returns (address) {
        return i_owner;
    }

    // function getPriceFeed() external view returns (AggregatorV3Interface) {
    //     return s_priceFeed;
    // }
}
