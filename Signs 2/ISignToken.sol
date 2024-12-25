// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ISignToken {
    struct WagePaymentResult {
        uint256 paidAmount;
        uint256 remainingWage;
        bool isPartialPayment;
    }

    function payWage(
        uint256 tokenId,
        address carrier,
        uint256 amount
    ) external returns (WagePaymentResult memory);
    
}