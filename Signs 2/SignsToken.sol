// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title SignsToken
 * @dev ERC20 token for the Signs game economy, managing rewards and wages
 */
contract SignsToken is ERC20, Pausable, Ownable, ReentrancyGuard {
    struct RewardRates {
        uint256 movementBaseRate;    // Base rate for movement rewards (per meter)
        uint256 diaryEntryRate;      // Rate for diary entries
        uint256 photoUploadRate;     // Rate for photo uploads
    }

    // Game economy parameters
    RewardRates public rates;
    uint256 public dailyEarningsCap;             // Maximum earnings per day per user
    uint256 public constant DAILY_RESET = 1 days; // Reset period for daily earnings
    
    // Contract references
    address public signsNFTContract;
    address public signsHistoryContract;
    
    // User balances and limits
    mapping(address => uint256) public wageBalance;         // Pending wages to be claimed
    mapping(address => uint256) public lastEarningsReset;   // Last time user's daily earnings were reset
    mapping(address => uint256) public earningsToday;       // Track daily earnings
    
    // Events
    event WagePaid(address indexed from, address indexed to, uint256 amount);
    event RewardPaid(address indexed user, uint256 amount, string rewardType);
    event RatesUpdated(uint256 movementBaseRate, uint256 diaryEntryRate, uint256 photoUploadRate);
    event DailyEarningsCapUpdated(uint256 newCap);
    event ContractUpdated(string contractType, address newAddress);
    
    // Errors
    error UnauthorizedCaller();
    error InsufficientBalance();
    error DailyEarningsLimitExceeded();
    error InvalidRate();
    error InvalidAddress();
    error InvalidAmount();

    constructor(
        string memory name,
        string memory symbol,
        uint256 initialSupply,
        address _signsNFTContract,
        address _signsHistoryContract
    ) ERC20(name, symbol) Ownable(msg.sender) {
        if (_signsNFTContract == address(0) || _signsHistoryContract == address(0)) 
            revert InvalidAddress();
            
        signsNFTContract = _signsNFTContract;
        signsHistoryContract = _signsHistoryContract;
        
        // Initial rates (can be updated by owner)
        rates = RewardRates({
            movementBaseRate: 1e15,    // 0.001 tokens per meter
            diaryEntryRate: 1e18,      // 1 token per diary entry
            photoUploadRate: 2e18      // 2 tokens per photo
        });
        
        dailyEarningsCap = 100e18;     // 100 tokens per day
        
        // Mint initial supply to contract owner
        _mint(msg.sender, initialSupply);
    }

    // Modifiers
    modifier onlyGameContracts() {
        if (msg.sender != signsNFTContract && msg.sender != signsHistoryContract)
            revert UnauthorizedCaller();
        _;
    }

    /**
     * @dev Records wage owed to a carrier for moving a sign
     * @param carrier Address of the sign carrier
     * @param amount Amount of tokens to be paid
     */
    function recordWage(address carrier, uint256 amount) 
        external 
        onlyGameContracts 
        whenNotPaused 
    {
        if (amount == 0) revert InvalidAmount();
        
        // Reset daily earnings if necessary
        _checkAndResetDailyEarnings(carrier);
        
        // Check daily earnings cap
        if (earningsToday[carrier] + amount > dailyEarningsCap)
            revert DailyEarningsLimitExceeded();
            
        wageBalance[carrier] += amount;
        earningsToday[carrier] += amount;
        
        emit WagePaid(msg.sender, carrier, amount);
    }

    /**
     * @dev Pays reward for social activities (diary entries, photos)
     * @param user Address of the user to reward
     * @param rewardType Type of reward ("diary" or "photo")
     */
    function payReward(address user, string calldata rewardType) 
        external 
        onlyGameContracts 
        whenNotPaused 
    {
        uint256 amount;
        if (keccak256(bytes(rewardType)) == keccak256(bytes("diary"))) {
            amount = rates.diaryEntryRate;
        } else if (keccak256(bytes(rewardType)) == keccak256(bytes("photo"))) {
            amount = rates.photoUploadRate;
        } else {
            revert InvalidRate();
        }
        
        // Reset daily earnings if necessary
        _checkAndResetDailyEarnings(user);
        
        // Check daily earnings cap
        if (earningsToday[user] + amount > dailyEarningsCap)
            revert DailyEarningsLimitExceeded();
            
        earningsToday[user] += amount;
        
        // Transfer reward directly
        _mint(user, amount);
        
        emit RewardPaid(user, amount, rewardType);
    }

    /**
     * @dev Allows users to claim their accumulated wages
     */
    function claimWages() 
        external 
        nonReentrant 
        whenNotPaused 
    {
        uint256 amount = wageBalance[msg.sender];
        if (amount == 0) revert InsufficientBalance();
        
        // Reset wage balance before transfer
        wageBalance[msg.sender] = 0;
        
        // Mint tokens to user
        _mint(msg.sender, amount);
    }

    /**
     * @dev Updates reward rates
     * @param newRates New reward rates structure
     */
    function updateRates(RewardRates calldata newRates) 
        external 
        onlyOwner 
    {
        rates = newRates;
        emit RatesUpdated(
            newRates.movementBaseRate,
            newRates.diaryEntryRate,
            newRates.photoUploadRate
        );
    }

    /**
     * @dev Updates daily earnings cap
     * @param newCap New daily earnings cap
     */
    function updateDailyEarningsCap(uint256 newCap) 
        external 
        onlyOwner 
    {
        dailyEarningsCap = newCap;
        emit DailyEarningsCapUpdated(newCap);
    }

    /**
     * @dev Updates game contract addresses
     * @param contractType Type of contract to update ("nft" or "history")
     * @param newAddress New contract address
     */
    function updateGameContract(string calldata contractType, address newAddress) 
        external 
        onlyOwner 
    {
        if (newAddress == address(0)) revert InvalidAddress();
        
        if (keccak256(bytes(contractType)) == keccak256(bytes("nft"))) {
            signsNFTContract = newAddress;
        } else if (keccak256(bytes(contractType)) == keccak256(bytes("history"))) {
            signsHistoryContract = newAddress;
        } else {
            revert InvalidRate();
        }
        
        emit ContractUpdated(contractType, newAddress);
    }

    /**
     * @dev Internal function to check and reset daily earnings if necessary
     * @param user Address of the user to check
     */
    function _checkAndResetDailyEarnings(address user) internal {
        if (block.timestamp >= lastEarningsReset[user] + DAILY_RESET) {
            earningsToday[user] = 0;
            lastEarningsReset[user] = block.timestamp;
        }
    }

    // Pause/unpause functionality
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // Override transfer functions to check for pause state
    function transfer(address to, uint256 amount) 
        public 
        virtual 
        override 
        whenNotPaused 
        returns (bool) 
    {
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount)
        public
        virtual
        override
        whenNotPaused
        returns (bool)
    {
        return super.transferFrom(from, to, amount);
    }
}