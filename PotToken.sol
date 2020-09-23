// SPDX-License-Identifier: MIT

pragma solidity 0.5.8;

import "./ERC20.sol";
import "./Ownable.sol";

contract PotToken is ERC20("POTATO", "POT"), Ownable {
    /// @notice Creates `_amount` token to `_to`. Must only be called by the owner(PotPool)
    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }
}