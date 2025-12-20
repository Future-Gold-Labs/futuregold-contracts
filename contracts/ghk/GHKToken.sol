// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20BurnableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {ERC20PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract GHKToken is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    ERC20PausableUpgradeable,
    OwnableUpgradeable,
    ERC20PermitUpgradeable
{
    mapping(address => bool) private _blacklist;
    mapping(address => bool) private minters;

    event AddedToBlacklist(address indexed account);
    event RemovedFromBlacklist(address indexed account);

    event AddedToMinters(address indexed account);
    event RemovedFromMinters(address indexed account);

    function initialize(uint256 initialSupply) public initializer {
        __ERC20_init("GoldHK", "GHK");
        __ERC20Burnable_init();
        __ERC20Pausable_init();
        __Ownable_init(msg.sender);
        __ERC20Permit_init("GoldHK");

        _mint(msg.sender, initialSupply * (10 ** decimals()));
    }

    function mint(address to, uint256 amount) external onlyOwner {
        require(!_blacklist[to], "BlacklistToken: to is blacklisted");
        _mint(to, amount);
    }

    function mintBy(address to, uint256 amount) external {
        require(!minters[msg.sender], "Minters: permission denied");
        _mint(to, amount);
    }

    function addedToMinters(address account) external onlyOwner {
        require(account != address(0), "Minters: Zero address");
        require(!minters[account], "Minters: Joined already");
        minters[account] = true;
        emit AddedToMinters(account);
    }

    function removedFromMinters(address account) external onlyOwner {
        require(account != address(0), "Minters: Zero address");
        require(minters[account], "Minters: invalid");
        minters[account] = false;
        emit RemovedFromMinters(account);
    }

    function isMinter(address account) public view returns (bool) {
        return minters[account];
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

    function _update(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20Upgradeable, ERC20PausableUpgradeable) {
        require(!_blacklist[from], "BlacklistToken: Sender is blacklisted");
        require(!_blacklist[to], "BlacklistToken: Recipient is blacklisted");
        super._update(from, to, amount);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }
}
