// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

error InvalidToken(string _origin);
error InvalidNumber(string _origin, uint256 _num);

error InsufficientAllowedPresaleAmount();
error InsufficientPresaleBalance();
error InsufficientAllowedInvestAmount();
error InsufficientInvestBalance();
error UnsupportedDexRouter();

error InvestmentClosed();
error InvestmentIsNotClosed();
error DidNotMeetDivestmentRequirements();

error IllegalOperation();
error Locked();

error ClaimInvestError();
error ClaimPresaleError();

error NotAnAutoListingLaunchPad();
error IsAnAutoListingLaunchPad();
error PresaleNotCompleted();
error TransferAllowedPresaleAmount();
error TransferPresaleBalanc();
error TransferAllowedInvestAmount();
error TransferInvestBalance();
error TransferLiquidityFailed();
error TransferLiquiditySignatureVerificationFailed();
