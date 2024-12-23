// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./ISigns.sol";

contract SignsHistory is ISigns, Ownable, Pausable {
    uint256 public constant RECENT_MOVEMENTS_LIMIT = 10;
    mapping(uint256 => MovementRecord[]) public recentMovements;
    mapping(uint256 => bytes32) public signMovementRoots;
    mapping(uint256 => uint256) public totalMovements;
    address public signsNFTContract;

    event SignMovement(
        uint256 indexed tokenId,
        address indexed carrier,
        Location fromLocation,
        Location toLocation,
        uint256 timestamp,
        uint256 wage,
        bytes32 contentHash,
        bytes32 movementHash
    );

    event MovementRootUpdated(uint256 indexed tokenId, bytes32 newRoot);

    error UnauthorizedCaller();
    error InvalidMovement();
    error InvalidMerkleProof();
    error InvalidSignId();

    constructor(address _signsNFTContract) Ownable(msg.sender) {
        signsNFTContract = _signsNFTContract;
    }

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

        MovementRecord memory movement = MovementRecord({
            fromLocation: fromLoc,
            toLocation: toLoc,
            carrier: carrier,
            wage: uint96(wage)
        });

        _updateRecentMovements(tokenId, movement);
        bytes32 movementHash = _generateMovementHash(movement, contentHash);
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

    function updateMovementRoot(uint256 tokenId, bytes32 newRoot) external onlyOwner {
        signMovementRoots[tokenId] = newRoot;
        emit MovementRootUpdated(tokenId, newRoot);
    }

    function verifyMovement(
        uint256 tokenId,
        bytes32 movementHash,
        bytes32[] calldata proof
    ) external view returns (bool) {
        bytes32 computedRoot = movementHash;
        
        for (uint256 i = 0; i < proof.length; i++) {
            computedRoot = _hashPair(computedRoot, proof[i]);
        }
        
        return computedRoot == signMovementRoots[tokenId];
    }

    function getRecentMovements(uint256 tokenId) 
        external 
        view 
        returns (MovementRecord[] memory) 
    {
        return recentMovements[tokenId];
    }

    function _updateRecentMovements(
        uint256 tokenId,
        MovementRecord memory movement
    ) private {
        MovementRecord[] storage movements = recentMovements[tokenId];
        
        if (movements.length >= RECENT_MOVEMENTS_LIMIT) {
            for (uint256 i = 1; i < movements.length; i++) {
                movements[i-1] = movements[i];
            }
            movements[movements.length - 1] = movement;
        } else {
            movements.push(movement);
        }
    }

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

    function _hashPair(bytes32 a, bytes32 b) private pure returns (bytes32) {
        return a < b 
            ? keccak256(abi.encodePacked(a, b))
            : keccak256(abi.encodePacked(b, a));
    }

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