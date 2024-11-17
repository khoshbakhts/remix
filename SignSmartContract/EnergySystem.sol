// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title EnergySystem
 * @dev Manages the energy system for the Signs game
 */
contract EnergySystem is Pausable, AccessControl, ReentrancyGuard {
    bytes32 public constant GAME_MANAGER_ROLE = keccak256("GAME_MANAGER_ROLE");
    
    // Events
    event EnergyConsumed(address indexed user, uint256 amount, string reason);
    event EnergyRecharged(address indexed user, uint256 amount, string reason);
    event EnergyPurchased(address indexed user, uint256 amount, uint256 tokensCost);
    event EnergyPriceUpdated(uint256 newPrice);
    event RechargeRateUpdated(uint256 newRate, uint256 newInterval);
    
    // State variables
    IERC20 public gameToken;
    
    struct UserEnergy {
        uint256 energy;
        uint256 lastRechargeTime;
        uint256 totalEnergyConsumed;
        uint256 totalEnergyRecharged;
    }
    
    mapping(address => UserEnergy) private _userEnergy;
    
    // Constants and configurable values
    uint256 public constant INITIAL_ENERGY = 100;
    uint256 public constant MAX_ENERGY = 1000;
    uint256 public energyPrice = 1e16; // 0.01 tokens per energy unit
    uint256 public rechargeRate = 25; // Energy units per recharge
    uint256 public rechargeInterval = 6 hours;
    
    constructor(address gameTokenAddress) {
        require(gameTokenAddress != address(0), "Invalid token address");
        gameToken = IERC20(gameTokenAddress);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
    
    // Modifiers
    modifier onlyGameManager() {
        require(hasRole(GAME_MANAGER_ROLE, msg.sender), "Caller is not a game manager");
        _;
    }
    
    /**
     * @dev Initialize energy for a new user
     * @param user Address of the new user
     */
    function initializeUser(address user) 
        external 
        onlyGameManager 
        whenNotPaused 
    {
        require(user != address(0), "Invalid user address");
        require(_userEnergy[user].lastRechargeTime == 0, "User already initialized");
        
        _userEnergy[user] = UserEnergy({
            energy: INITIAL_ENERGY,
            lastRechargeTime: block.timestamp,
            totalEnergyConsumed: 0,
            totalEnergyRecharged: INITIAL_ENERGY
        });
        
        emit EnergyRecharged(user, INITIAL_ENERGY, "Initial energy");
    }
    
    /**
     * @dev Consume energy for game actions
     * @param user Address of the user
     * @param amount Amount of energy to consume
     * @param reason Reason for consumption
     */
    function consumeEnergy(
        address user, 
        uint256 amount, 
        string memory reason
    ) 
        external 
        onlyGameManager 
        whenNotPaused 
    {
        require(amount > 0, "Amount must be positive");
        
        // Process automatic recharge first
        _processAutomaticRecharge(user);
        
        UserEnergy storage userEnergy = _userEnergy[user];
        require(userEnergy.energy >= amount, "Insufficient energy");
        
        userEnergy.energy -= amount;
        userEnergy.totalEnergyConsumed += amount;
        
        emit EnergyConsumed(user, amount, reason);
    }
    
    /**
     * @dev Calculate energy consumption for movement
     * @param distance Distance in meters
     * @param weight Weight of the sign
     * @return required energy units
     */
    function calculateEnergyConsumption(
        uint256 distance, 
        uint256 weight
    ) 
        public 
        pure 
        returns (uint256) 
    {
        // E = div(D/100) * W
        return (distance / 100) * weight;
    }
    
    /**
     * @dev Purchase energy using game tokens
     * @param amount Amount of energy to purchase
     */
    function purchaseEnergy(uint256 amount) 
        external 
        whenNotPaused 
        nonReentrant 
    {
        require(amount > 0, "Amount must be positive");
        
        UserEnergy storage userEnergy = _userEnergy[msg.sender];
        require(userEnergy.energy + amount <= MAX_ENERGY, "Would exceed max energy");
        
        uint256 cost = amount * energyPrice;
        require(
            gameToken.transferFrom(msg.sender, address(this), cost),
            "Token transfer failed"
        );
        
        userEnergy.energy += amount;
        userEnergy.totalEnergyRecharged += amount;
        
        emit EnergyPurchased(msg.sender, amount, cost);
    }
    
    /**
     * @dev Process automatic energy recharge
     * @param user Address of the user
     */
    function _processAutomaticRecharge(address user) internal {
        UserEnergy storage userEnergy = _userEnergy[user];
        uint256 timePassed = block.timestamp - userEnergy.lastRechargeTime;
        uint256 rechargesPending = timePassed / rechargeInterval;
        
        if (rechargesPending > 0) {
            uint256 energyToAdd = rechargesPending * rechargeRate;
            uint256 newEnergy = userEnergy.energy + energyToAdd;
            
            // Cap at MAX_ENERGY
            if (newEnergy > MAX_ENERGY) {
                energyToAdd = MAX_ENERGY - userEnergy.energy;
                newEnergy = MAX_ENERGY;
            }
            
            userEnergy.energy = newEnergy;
            userEnergy.lastRechargeTime += rechargesPending * rechargeInterval;
            userEnergy.totalEnergyRecharged += energyToAdd;
            
            emit EnergyRecharged(user, energyToAdd, "Automatic recharge");
        }
    }
    
    // View functions
    
    /**
     * @dev Get current energy balance for user
     * @param user Address of the user
     * @return Current energy balance
     */
    function getEnergy(address user) 
        external 
        view 
        returns (uint256) 
    {
        UserEnergy storage userEnergy = _userEnergy[user];
        uint256 timePassed = block.timestamp - userEnergy.lastRechargeTime;
        uint256 rechargesPending = timePassed / rechargeInterval;
        
        uint256 pendingEnergy = rechargesPending * rechargeRate;
        uint256 totalEnergy = userEnergy.energy + pendingEnergy;
        
        return totalEnergy > MAX_ENERGY ? MAX_ENERGY : totalEnergy;
    }
    
    /**
     * @dev Get last recharge time for user
     * @param user Address of the user
     * @return Timestamp of last recharge
     */
    function lastRechargeTime(address user) 
        external 
        view 
        returns (uint256) 
    {
        return _userEnergy[user].lastRechargeTime;
    }
    
    /**
     * @dev Get user energy statistics
     * @param user Address of the user
     * @return current energy, total consumed, total recharged
     */
    function getUserStats(address user) 
        external 
        view 
        returns (
            uint256 currentEnergy,
            uint256 totalConsumed,
            uint256 totalRecharged
        ) 
    {
        UserEnergy storage userEnergy = _userEnergy[user];
        return (
            userEnergy.energy,
            userEnergy.totalEnergyConsumed,
            userEnergy.totalEnergyRecharged
        );
    }
    
    // Admin functions
    
    /**
     * @dev Update energy price
     * @param newPrice New price per energy unit
     */
    function updateEnergyPrice(uint256 newPrice) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(newPrice > 0, "Invalid price");
        energyPrice = newPrice;
        emit EnergyPriceUpdated(newPrice);
    }
    
    /**
     * @dev Update recharge rate and interval
     * @param newRate New energy units per recharge
     * @param newInterval New recharge interval
     */
    function updateRechargeRate(
        uint256 newRate, 
        uint256 newInterval
    ) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(newRate > 0 && newInterval > 0, "Invalid parameters");
        rechargeRate = newRate;
        rechargeInterval = newInterval;
        emit RechargeRateUpdated(newRate, newInterval);
    }
    
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }
    
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}