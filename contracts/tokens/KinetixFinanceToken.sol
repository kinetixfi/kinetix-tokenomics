// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.22;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract KinetixFinanceToken is ERC20, AccessControl, ERC20Permit {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice The timestamp after which minting may occur
    uint256 public mintingAllowedAfter;

    /// @notice Minimum time between mints
    uint256 public constant minimumTimeBetweenMints = 1 days * 365;

    /// @notice Cap on the percentage of totalSupply that can be minted at each mint
    uint256 public constant mintCap = 2;

    constructor(address defaultAdmin, address minter, uint256 _mintingAllowedAfter)
        ERC20("Kinetix Finance", "KAI")
        ERC20Permit("Kinetix Finance")
    {
        require(defaultAdmin != address(0), "KAI::constructor:invalid defaultAdmin");
        require(minter != address(0), "KAI::constructor:invalid minter");
        require(_mintingAllowedAfter >= block.timestamp + 1 days * 365 * 5, "KAI::constructor: minting can only begin after 5 years");
        _mint(msg.sender, 1000000000 * 10 ** decimals());
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(MINTER_ROLE, minter);
        mintingAllowedAfter = _mintingAllowedAfter;
    }

    /**
     * @notice Mint new tokens
     * @param to The address of the destination account
     * @param amount The number of tokens to be minted
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        require(block.timestamp >= mintingAllowedAfter, "KAI::mint: minting not allowed yet");
        require(amount <= (totalSupply() * mintCap)/ 100, "KAI::mint: exceeded mint cap");

        // record the mint
        mintingAllowedAfter = block.timestamp + minimumTimeBetweenMints;
        _mint(to, amount);

    }

}