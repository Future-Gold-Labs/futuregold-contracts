// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract GHKEToken is Initializable, ERC20Upgradeable, OwnableUpgradeable {

    mapping(address => bool) private _blacklist;

    event AddedToBlacklist(address indexed account);
    event RemovedFromBlacklist(address indexed account);
    
    function initialize() public initializer {
        __ERC20_init("GoldHKE", "GHKE");
        __Ownable_init(msg.sender);

        _mint(msg.sender, 10 * 100000000 * (10 ** decimals()));
    }

    function addToBlacklist(address account) external onlyOwner {
        require(account != address(0), "BlacklistToken: Zero address");
        require(!_blacklist[account], "BlacklistToken: Already blacklisted");
        _blacklist[account] = true;
        emit AddedToBlacklist(account);
    }

    function removeFromBlacklist(address account) external onlyOwner {
        require(account != address(0), "BlacklistToken: Zero address");
        require(_blacklist[account], "BlacklistToken: Not blacklisted");
        _blacklist[account] = false;
        emit RemovedFromBlacklist(account);
    }

    function isBlacklisted(address account) public view returns (bool) {
        return _blacklist[account];
    }

    function _update(address from, address to, uint256 amount) internal override {
        require(!_blacklist[from], "BlacklistToken: Sender is blacklisted");
        require(!_blacklist[to], "BlacklistToken: Recipient is blacklisted");
        super._update(from, to, amount);
    }


}