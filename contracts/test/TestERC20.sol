// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestERC20 is ERC20 {
    uint8 public _decimals = 18;

    constructor(
        string memory name,
        string memory symbol,
        uint8 __decimals,
        uint256 initSupply
    ) ERC20(name, symbol) {
        _decimals = __decimals;
        _mint(msg.sender, initSupply);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}
