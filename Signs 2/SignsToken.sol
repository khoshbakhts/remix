// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title SignToken
 * @dev ERC20 token for the Signs game economy, managing sign balances and wage payments
 */
contract SignToken is ERC20, Pausable, Ownable, ReentrancyGuard {
    // Contract references
    address public signsNFTContract;
    
    // Commission settings
    uint256 public commissionPercent; // Commission in basis points (1% = 100)
    address public commissionTreasury;
    
    // Constants
    uint256 private constant BASIS_POINTS = 10000; // 100% = 10000
    
    // Sign balances
    mapping(uint256 => uint256) public signBalances;  // tokenId => balance
    
    // Events
    event SignBalanceCharged(uint256 indexed tokenId, uint256 amount);
    event SignBalanceWithdrawn(uint256 indexed tokenId, address indexed owner, uint256 amount);
    event WagePaid(uint256 indexed tokenId, address indexed carrier, uint256 amount);
    event NFTContractUpdated(address newAddress);
    event CommissionUpdated(uint256 newCommissionPercent);
    event CommissionTreasuryUpdated(address newTreasury);
    event CommissionPaid(uint256 indexed tokenId, uint256 amount);
    
    // Errors
    error UnauthorizedCaller();
    error InvalidCommission();
    error InvalidTreasuryAddress();
    error InsufficientSignBalance();
    error InsufficientBalance();
    error InvalidAmount();
    error InvalidNFTContract();
    error UnauthorizedOwner();

    constructor(
        string memory name,
        string memory symbol,
        address _signsNFTContract,
        address _commissionTreasury
    ) ERC20(name, symbol) Ownable(msg.sender) {
        if (_signsNFTContract == address(0)) revert InvalidNFTContract();
        if (_commissionTreasury == address(0)) revert InvalidTreasuryAddress();
        
        signsNFTContract = _signsNFTContract;
        commissionTreasury = _commissionTreasury;
        commissionPercent = 500; // Default 5% commission

        _mint(msg.sender, 1_000_000 * 10**decimals());
    }

    // Modifiers
    modifier onlySignsNFT() {
        if (msg.sender != signsNFTContract) revert UnauthorizedCaller();
        _;
    }

    /**
     * @dev Charges a sign's balance with tokens
     * @param tokenId The ID of the sign to charge
     * @param amount Amount of tokens to charge
     */
    function chargeSignBalance(uint256 tokenId, uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert InvalidAmount();
        
        address sender = msg.sender;
        address token = address(this);
        
        // First transfer tokens from user to contract
        _spendAllowance(sender, token, amount);  // Handle allowance first
        _transfer(sender, token, amount);         // Then do the transfer
        
        // Update sign balance
        signBalances[tokenId] += amount;
        
        emit SignBalanceCharged(tokenId, amount);
    }
    /**
     * @dev Withdraws tokens from a sign's balance back to the owner
     * @param tokenId The ID of the sign
     * @param amount Amount to withdraw
     */
    function withdrawSignBalance(uint256 tokenId, uint256 amount) external nonReentrant whenNotPaused {
        // Check if caller owns the sign
        // This requires interface integration with SignsNFT contract
        if (!_isSignOwner(msg.sender, tokenId)) revert UnauthorizedOwner();
        
        if (amount == 0) revert InvalidAmount();
        if (signBalances[tokenId] < amount) revert InsufficientSignBalance();
        
        // Update balance before transfer
        signBalances[tokenId] -= amount;
        
        // Transfer tokens to owner
        bool success = transfer(msg.sender, amount);
        require(success, "Transfer failed");
        
        emit SignBalanceWithdrawn(tokenId, msg.sender, amount);
    }

    /**
     * @dev Pays wage to carrier from sign's balance
     * @param tokenId The ID of the sign
     * @param carrier Address of the carrier to pay
     * @param amount Amount of wage to pay
     */
    struct WagePaymentResult {
        uint256 paidAmount;      // Actual amount paid
        uint256 remainingWage;   // Unpaid amount
        bool isPartialPayment;   // Whether this was a partial payment
    }

    event LowSignBalance(uint256 indexed tokenId, uint256 currentBalance, uint256 requiredAmount);
    event PartialWagePaid(
        uint256 indexed tokenId, 
        address indexed carrier, 
        uint256 paidAmount, 
        uint256 remainingUnpaid
    );

    /**
     * @dev Pays wage to carrier from sign's balance, handles partial payments
     * @param tokenId The ID of the sign
     * @param carrier Address of the carrier to pay
     * @param amount Amount of wage to pay
     * @return result WagePaymentResult struct with payment details
     */
    function payWage(
        uint256 tokenId,
        address carrier,
        uint256 amount
    ) external onlySignsNFT nonReentrant whenNotPaused returns (WagePaymentResult memory) {
        if (amount == 0) revert InvalidAmount();
        
        uint256 currentBalance = signBalances[tokenId];
        bool isFullPayment = currentBalance >= amount;
        uint256 paymentAmount;
        uint256 commissionAmount;
        
        if (isFullPayment) {
            // Calculate commission only for full payments
            commissionAmount = (amount * commissionPercent) / BASIS_POINTS;
            paymentAmount = amount - commissionAmount;
            
            // Update balance before transfers
            signBalances[tokenId] = currentBalance - amount;
            
            // Transfer commission
            if (commissionAmount > 0) {
                bool commissionSuccess = transfer(commissionTreasury, commissionAmount);
                require(commissionSuccess, "Commission transfer failed");
                emit CommissionPaid(tokenId, commissionAmount);
            }
            
            // Transfer wage to carrier
            bool success = transfer(carrier, paymentAmount);
            require(success, "Wage transfer failed");
            
            emit WagePaid(tokenId, carrier, paymentAmount);
        } else {
            // For partial payments, no commission is taken
            paymentAmount = currentBalance;
            commissionAmount = 0;
            
            // Update balance before transfer
            signBalances[tokenId] = 0;
            
            if (paymentAmount > 0) {
                // Transfer all available balance to carrier
                bool success = transfer(carrier, paymentAmount);
                require(success, "Partial wage transfer failed");
                
                emit PartialWagePaid(tokenId, carrier, paymentAmount, amount - paymentAmount);
            }
            
            emit LowSignBalance(tokenId, currentBalance, amount);
        }
        
        return WagePaymentResult({
            paidAmount: paymentAmount,
            remainingWage: amount - paymentAmount,
            isPartialPayment: !isFullPayment
        });
    }

    /**
     * @dev Updates the SignsNFT contract address
     * @param _newAddress New contract address
     */
    function updateSignsNFTContract(address _newAddress) external onlyOwner {
        if (_newAddress == address(0)) revert InvalidNFTContract();
        signsNFTContract = _newAddress;
        emit NFTContractUpdated(_newAddress);
    }

    /**
     * @dev Checks if an address owns a specific sign
     * @param owner Address to check
     * @param tokenId Sign ID to check
     */
    function _isSignOwner(address owner, uint256 tokenId) internal view returns (bool) {
        // This should integrate with your SignsNFT contract
        // Implementation depends on your NFT contract interface
        return true; // Placeholder - implement actual check
    }

    // Pause/unpause functionality
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Updates the commission percentage
     * @param newCommissionPercent New commission in basis points (1% = 100)
     */
    function updateCommission(uint256 newCommissionPercent) external onlyOwner {
        if (newCommissionPercent > BASIS_POINTS) revert InvalidCommission();
        commissionPercent = newCommissionPercent;
        emit CommissionUpdated(newCommissionPercent);
    }

    /**
     * @dev Updates the commission treasury address
     * @param newTreasury New treasury address
     */
    function updateCommissionTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0)) revert InvalidTreasuryAddress();
        commissionTreasury = newTreasury;
        emit CommissionTreasuryUpdated(newTreasury);
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

        function getApprovalInfo(address owner) external view returns (
        uint256 balance,
        uint256 contractAllowance
    ) {
        return (
            balanceOf(owner),
            allowance(owner, address(this))
        );
    }
}