// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IWESaleFactory {
    function feeTo() external view returns (address);

    function transferSigner() external view returns (address);
}
