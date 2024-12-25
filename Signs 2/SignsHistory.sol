// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./ISigns.sol";

/**
 * @title SignsHistory
 * @dev Manages and verifies the history of sign movements with off-chain content integration
 */
contract SignsHistory is ISigns, Ownable, Pausable {
    // Number of recent movements to keep on-chain for quick access
    uint256 public constant RECENT_MOVEMENTS_LIMIT = 10;
    
    // Core storage structures
    mapping(uint256 => MovementRecord[]) public recentMovements;
    mapping(uint256 => bytes32[]) public movementHashes;  // Complete history of movement hashes
    mapping(uint256 => uint256) public totalMovements;
    
    // Contract references
    address public signsNFTContract;
    
    // Events
    event SignMovement(
        uint256 indexed tokenId,
        address indexed carrier,
        Location fromLocation,
        Location toLocation,
        uint256 timestamp,
        uint256 wage,
        bytes32 contentHash,  // Hash of off-chain content (photos, notes)
        bytes32 movementHash  // Hash of entire movement record
    );
    
    event MovementVerified(
        uint256 indexed tokenId,
        bytes32 movementHash,
        bool isValid
    );
    
    // Errors
    error UnauthorizedCaller();
    error InvalidMovement();
    error InvalidMerkleProof();
    error InvalidSignId();
    error MovementNotFound();
    
    constructor(address _signsNFTContract) Ownable(msg.sender) {
        signsNFTContract = _signsNFTContract;
    }
    
    /**
     * @dev Records a new movement with its associated content hash
     * @param tokenId The ID of the sign
     * @param carrier Address of the carrier
     * @param fromLoc Starting location
     * @param toLoc Ending location
     * @param wage Amount paid for the movement
     * @param contentHash Hash of off-chain content (photos, notes)
     */
    function recordMovement(
        uint256 tokenId,
        address carrier,
        Location calldata fromLoc,
        Location calldata toLoc,
        uint256 wage,
        bytes32 contentHash
    ) external override whenNotPaused {
        if (msg.sender != signsNFTContract) revert UnauthorizedCaller();
        if (!_validateMovement(fromLoc, toLoc)) revert InvalidMovement();
        
        // Create and store movement record
        MovementRecord memory movement = MovementRecord({
            fromLocation: fromLoc,
            toLocation: toLoc,
            carrier: carrier,
            wage: uint96(wage)
        });
        
        // Generate and store movement hash
        bytes32 movementHash = _generateMovementHash(movement, contentHash);
        movementHashes[tokenId].push(movementHash);
        
        // Update recent movements for quick access
        _updateRecentMovements(tokenId, movement);
        totalMovements[tokenId]++;
        
        emit SignMovement(
            tokenId,
            carrier,
            fromLoc,
            toLoc,
            toLoc.timestamp,
            wage,
            contentHash,
            movementHash
        );
    }
    
    /**
     * @dev Retrieves complete movement history for a sign
     * @param tokenId The ID of the sign
     * @return hashes Array of movement hashes in chronological order
     */
    function getMovementHistory(uint256 tokenId) 
        external 
        view 
        returns (bytes32[] memory) 
    {
        return movementHashes[tokenId];
    }
    
    /**
     * @dev Verifies the integrity of a specific movement record
     * @param tokenId The ID of the sign
     * @param movementData The movement data to verify
     * @param contentHash The content hash associated with the movement
     * @return bool True if the movement record is valid
     */
    function verifyMovementRecord(
        uint256 tokenId,
        MovementRecord calldata movementData,
        bytes32 contentHash
    ) external view returns (bool) {
        bytes32 computedHash = _generateMovementHash(movementData, contentHash);
        
        // Search for the computed hash in the movement history
        bytes32[] storage history = movementHashes[tokenId];
        for (uint256 i = 0; i < history.length; i++) {
            if (history[i] == computedHash) {
                return true;
            }
        }
        
        return false;
    }
    
    /**
     * @dev Returns recent movements for quick access
     * @param tokenId The ID of the sign
     */
    function getRecentMovements(uint256 tokenId) 
        external 
        view 
        returns (MovementRecord[] memory) 
    {
        return recentMovements[tokenId];
    }
    
    /**
     * @dev Updates the recent movements list
     * @param tokenId The ID of the sign
     * @param movement New movement record to add
     */
    function _updateRecentMovements(
        uint256 tokenId,
        MovementRecord memory movement
    ) private {
        MovementRecord[] storage movements = recentMovements[tokenId];
        
        if (movements.length >= RECENT_MOVEMENTS_LIMIT) {
            // Shift elements left and add new movement at the end
            for (uint256 i = 1; i < movements.length; i++) {
                movements[i-1] = movements[i];
            }
            movements[movements.length - 1] = movement;
        } else {
            movements.push(movement);
        }
    }
    
    /**
     * @dev Validates movement coordinates and timestamp
     */
    function _validateMovement(
        Location memory fromLoc,
        Location memory toLoc
    ) private pure returns (bool) {
        if (toLoc.timestamp <= fromLoc.timestamp) {
            return false;
        }
        
        if (fromLoc.latitude < -90e4 || fromLoc.latitude > 90e4 ||
            fromLoc.longitude < -180e4 || fromLoc.longitude > 180e4 ||
            toLoc.latitude < -90e4 || toLoc.latitude > 90e4 ||
            toLoc.longitude < -180e4 || toLoc.longitude > 180e4) {
            return false;
        }
        
        return true;
    }
    
    /**
     * @dev Generates a unique hash for a movement record
     */
    function _generateMovementHash(
        MovementRecord memory movement,
        bytes32 contentHash
    ) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(
            movement.fromLocation.latitude,
            movement.fromLocation.longitude,
            movement.fromLocation.timestamp,
            movement.toLocation.latitude,
            movement.toLocation.longitude,
            movement.toLocation.timestamp,
            movement.carrier,
            movement.wage,
            contentHash
        ));
    }
    
    // Admin functions
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
    
    function updateSignsNFTContract(address _newAddress) external onlyOwner {
        signsNFTContract = _newAddress;
    }
}