// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ISignToken {
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
    function transfer(address to, uint256 amount) external returns (bool);
}

contract SignityNFT {
    // Structs
    struct Sign {
        uint256 id;
        address owner;
        string homeLocation; // GPS coordinates as string
        uint256 wage;       // Payment in SIGN tokens for moving
        address currentHolder;
        bool isPickedUp;    // Track if sign is currently picked up
        uint256 lastDropTime; // To implement minimum time between pickups
        string currentLocation; // Current GPS location
        uint256 totalMoves;    // Total number of times sign has been moved
        uint256 totalDistance; // Total distance traveled (in meters)
    }

    struct Carrier {
        uint256 totalMoves;      // Total number of signs moved
        uint256 totalDistance;   // Total distance covered
        uint256 totalEarned;     // Total tokens earned
    }

    // Events
    event SignCreated(uint256 indexed tokenId, address indexed owner);
    event SignMoved(uint256 indexed tokenId, address indexed mover, string newLocation, uint256 paidAmount);
    event SignPickedUp(uint256 indexed tokenId, address indexed picker);
    event SignDropped(uint256 indexed tokenId, address indexed dropper, string location);
    event WageUpdated(uint256 indexed tokenId, uint256 newWage);

    // State variables
    address public immutable owner;
    ISignToken public signToken;
    uint256 private _nextTokenId;
    uint256 public constant MINIMUM_DROP_TIME = 1 hours;
    uint256 public constant MAXIMUM_HOLD_TIME = 24 hours;
    uint256 public constant MINIMUM_PICKUP_INTERVAL = 6 hours;
    
    // Mappings
    mapping(uint256 => Sign) private _signs;
    mapping(address => Carrier) private _carriers;
    mapping(uint256 => mapping(address => uint256)) private _carrierHistory; // tokenId => carrier => lastPickupTime
    mapping(address => uint256[]) private _ownedTokens;

    constructor(address _signToken) {
        owner = msg.sender;
        signToken = ISignToken(_signToken);
        _nextTokenId = 1;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "SignityNFT: caller is not the owner");
        _;
    }

    modifier onlySignOwner(uint256 tokenId) {
        require(_signs[tokenId].owner == msg.sender, "SignityNFT: caller is not sign owner");
        _;
    }

    // Core sign operations
    function createSign(string memory homeLocation) external returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        
        _signs[tokenId] = Sign({
            id: tokenId,
            owner: msg.sender,
            homeLocation: homeLocation,
            wage: 0,
            currentHolder: address(0),
            isPickedUp: false,
            lastDropTime: block.timestamp,
            currentLocation: homeLocation,
            totalMoves: 0,
            totalDistance: 0
        });

        _ownedTokens[msg.sender].push(tokenId);
        
        emit SignCreated(tokenId, msg.sender);
        return tokenId;
    }

    function pickupSign(uint256 tokenId) external {
        Sign storage sign = _signs[tokenId];
        require(!sign.isPickedUp, "SignityNFT: sign is already picked up");
        require(block.timestamp >= sign.lastDropTime + MINIMUM_PICKUP_INTERVAL, "SignityNFT: too soon to pickup");
        require(_carrierHistory[tokenId][msg.sender] + MINIMUM_PICKUP_INTERVAL <= block.timestamp, "SignityNFT: carrier must wait");

        sign.isPickedUp = true;
        sign.currentHolder = msg.sender;
        _carrierHistory[tokenId][msg.sender] = block.timestamp;

        emit SignPickedUp(tokenId, msg.sender);
    }

    function dropSign(uint256 tokenId, string memory newLocation) external {
        Sign storage sign = _signs[tokenId];
        require(sign.isPickedUp, "SignityNFT: sign is not picked up");
        require(sign.currentHolder == msg.sender, "SignityNFT: not the current holder");
        require(block.timestamp <= _carrierHistory[tokenId][msg.sender] + MAXIMUM_HOLD_TIME, "SignityNFT: held too long");
        
        uint256 distance = _calculateDistance(sign.currentLocation, newLocation);
        uint256 reward = _calculateReward(sign.wage, distance);
        
        // Update sign state
        sign.isPickedUp = false;
        sign.currentHolder = address(0);
        sign.lastDropTime = block.timestamp;
        sign.currentLocation = newLocation;
        sign.totalMoves++;
        sign.totalDistance += distance;

        // Update carrier stats
        _carriers[msg.sender].totalMoves++;
        _carriers[msg.sender].totalDistance += distance;
        _carriers[msg.sender].totalEarned += reward;

        // Transfer reward
        if (reward > 0) {
            signToken.transfer(msg.sender, reward);
        }

        emit SignDropped(tokenId, msg.sender, newLocation);
        emit SignMoved(tokenId, msg.sender, newLocation, reward);
    }

    // Wage management
    function setWage(uint256 tokenId, uint256 newWage) external onlySignOwner(tokenId) {
        _signs[tokenId].wage = newWage;
        emit WageUpdated(tokenId, newWage);
    }

    // View functions
    function getSignDetails(uint256 tokenId) external view returns (Sign memory) {
        require(_signs[tokenId].owner != address(0), "SignityNFT: sign does not exist");
        return _signs[tokenId];
    }

    function getCarrierStats(address carrier) external view returns (Carrier memory) {
        return _carriers[carrier];
    }

    function getOwnedSigns(address owner_) external view returns (uint256[] memory) {
        return _ownedTokens[owner_];
    }

    function getSignsNearby(string memory location, uint256 radius) external view returns (uint256[] memory) {
        // Note: This is a simplified implementation
        // In a real implementation, you would need an oracle or off-chain indexer
        // to properly implement location-based queries
        uint256[] memory nearbySigns = new uint256[](_nextTokenId - 1);
        uint256 count = 0;

        for (uint256 i = 1; i < _nextTokenId; i++) {
            if (!_signs[i].isPickedUp && 
                _isWithinRadius(_signs[i].currentLocation, location, radius)) {
                nearbySigns[count] = i;
                count++;
            }
        }

        // Resize array to actual count
        uint256[] memory result = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = nearbySigns[i];
        }

        return result;
    }

    // Internal functions
    function _calculateDistance(string memory location1, string memory location2) internal pure returns (uint256) {
        // Note: This would need to be implemented with proper GPS calculation
        // For now, return a dummy value
        return 100; // 100 meters
    }

    function _calculateReward(uint256 wage, uint256 distance) internal pure returns (uint256) {
        // Simple reward calculation: wage * distance / 1000 (to convert to kilometers)
        return (wage * distance) / 1000;
    }

    function _isWithinRadius(string memory location1, string memory location2, uint256 radius) internal pure returns (bool) {
        // Note: This would need to be implemented with proper GPS calculation
        // For now, return true for testing
        return true;
    }
}