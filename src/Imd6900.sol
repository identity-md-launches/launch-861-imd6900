// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Imd6900
/// @notice Fixed-supply ERC-20 with 18 decimals and no administrative privileges.
contract Imd6900 is ERC20 {
    /// @notice Mints one billion tokens to the immediate deployer, including a deploying factory.
    constructor() ERC20("Imd6900", "IMD6900") {
        _mint(msg.sender, 1_000_000_000 * 10 ** 18);
    }
}
