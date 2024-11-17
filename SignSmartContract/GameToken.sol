// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title GameToken
 * @dev Implementation of the Signs game token with role-based minting and burning
 */
contract GameToken is ERC20, Pausable, AccessControl, ReentrancyGuard {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant GAME_MANAGER_ROLE = keccak256("GAME_MANAGER_ROLE");
    
    // Events
    event RewardPaid(address indexed to, uint256 amount, string reason);
    event TokensBurned(address indexed from, uint256 amount, string reason);
    event TokensLocked(address indexed owner, uint256 amount);
    event TokensUnlocked(address indexed owner, uint256 amount);
    
    // Staking and locking mechanism
    mapping(address => uint256) private _lockedTokens;
    mapping(address => uint256) private _lockTimestamp;
    
    // Constants
    uint256 public constant LOCK_DURATION = 24 hours;
    uint256 public constant MAX_SUPPLY = 1000000000 * 10**18; // 1 billion tokens
    
    constructor() ERC20("Signs Game Token", "SIGN") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
    
    // Modifiers
    modifier onlyGameManager() {
        require(hasRole(GAME_MANAGER_ROLE, msg.sender), "Caller is not a game manager");
        _;
    }
    
    modifier onlyMinter() {
        require(hasRole(MINTER_ROLE, msg.sender), "Caller is not a minter");
        _;
    }
    
    // Core token functions
    
    /**
     * @dev Mint new tokens to an address
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) 
        external 
        onlyMinter 
        whenNotPaused 
    {
        require(to != address(0), "Cannot mint to zero address");
        require(totalSupply() + amount <= MAX_SUPPLY, "Would exceed max supply");
        _mint(to, amount);
    }
    
    /**
     * @dev Burn tokens from an address
     * @param from Address to burn tokens from
     * @param amount Amount of tokens to burn
     */
    function burn(address from, uint256 amount) 
        external 
        onlyGameManager 
        whenNotPaused 
    {
        require(from != address(0), "Cannot burn from zero address");
        require(balanceOf(from) >= amount, "Insufficient balance to burn");
        _burn(from, amount);
        emit TokensBurned(from, amount, "Game mechanics burn");
    }
    
    /**
     * @dev Pay rewards to players
     * @param to Address to receive rewards
     * @param amount Amount of tokens to reward
     * @param reason Reason for the reward
     */
    function payReward(
        address to, 
        uint256 amount, 
        string memory reason
    ) 
        external 
        onlyGameManager 
        whenNotPaused 
        nonReentrant 
    {
        require(to != address(0), "Cannot reward zero address");
        require(totalSupply() + amount <= MAX_SUPPLY, "Would exceed max supply");
        
        _mint(to, amount);
        emit RewardPaid(to, amount, reason);
    }
    
    /**
     * @dev Lock tokens for staking or other game mechanics
     * @param amount Amount of tokens to lock
     */
    function lockTokens(uint256 amount) 
        external 
        whenNotPaused 
        nonReentrant 
    {
        require(amount > 0, "Cannot lock zero tokens");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance to lock");
        
        _lockedTokens[msg.sender] += amount;
        _lockTimestamp[msg.sender] = block.timestamp;
        
        emit TokensLocked(msg.sender, amount);
    }
    
    /**
     * @dev Unlock previously locked tokens after lock duration
     */
    function unlockTokens() 
        external 
        whenNotPaused 
        nonReentrant 
    {
        uint256 lockedAmount = _lockedTokens[msg.sender];
        require(lockedAmount > 0, "No tokens locked");
        require(
            block.timestamp >= _lockTimestamp[msg.sender] + LOCK_DURATION,
            "Tokens still locked"
        );
        
        _lockedTokens[msg.sender] = 0;
        emit TokensUnlocked(msg.sender, lockedAmount);
    }
    
    // View functions
    
    /**
     * @dev Get the amount of locked tokens for an address
     * @param account Address to check
     * @return Amount of locked tokens
     */
    function getLockedTokens(address account) 
        external 
        view 
        returns (uint256) 
    {
        return _lockedTokens[account];
    }
    
    /**
     * @dev Get the timestamp when tokens were locked
     * @param account Address to check
     * @return Timestamp of lock
     */
    function getLockTimestamp(address account) 
        external 
        view 
        returns (uint256) 
    {
        return _lockTimestamp[account];
    }
    
    /**
     * @dev Get available (unlocked) balance
     * @param account Address to check
     * @return Available balance
     */
    function getAvailableBalance(address account) 
        external 
        view 
        returns (uint256) 
    {
        return balanceOf(account) - _lockedTokens[account];
    }
    
    // Override transfer functions to check for locked tokens
    function transfer(address to, uint256 amount) 
        public 
        virtual 
        override 
        whenNotPaused 
        returns (bool) 
    {
        require(
            balanceOf(msg.sender) - _lockedTokens[msg.sender] >= amount,
            "Transfer amount exceeds available balance"
        );
        return super.transfer(to, amount);
    }
    
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) 
        public 
        virtual 
        override 
        whenNotPaused 
        returns (bool) 
    {
        require(
            balanceOf(from) - _lockedTokens[from] >= amount,
            "Transfer amount exceeds available balance"
        );
        return super.transferFrom(from, to, amount);
    }
    
    // Admin functions
    
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }
    
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}