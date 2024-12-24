// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./ISigns.sol";
import "./ISignToken.sol";

contract SignsNFT is ISigns, ERC721, Ownable, Pausable {
    using Counters for Counters.Counter;

    struct Sign {
        Location home;
        Location current;
        uint256 totalMoves;
        uint256 totalDistanceMeters;
        uint256 weight;
        address owner;
        bool isPickedUp;
        bytes32 contentHash;
        uint256 signWage;    // Custom wage per meter for this sign
    }

    Counters.Counter private _tokenIds;
    mapping(uint256 => Sign) public signs;
    mapping(address => uint256) public userSignCount;
    mapping(uint256 => address) public signCarriers;
    
    uint256 public constant MAX_SIGNS_PER_USER = 1;
    uint256 public constant MAX_PICKUP_RADIUS = 100; // meters
    uint256 public baseWageRate = 1; // 1 token per 100 meters, can be updated by owner
    
    ISigns public signsHistory;
    ISignToken public signToken;    

    event SignCreated(uint256 indexed tokenId, address indexed owner, Location home);
    event SignMoved(uint256 indexed tokenId, address indexed carrier, Location from, Location to);
    event HomeUpdated(uint256 indexed tokenId, Location newHome);
    event SignPickedUp(uint256 indexed tokenId, address indexed carrier, Location location);
    event SignDropped(uint256 indexed tokenId, address indexed carrier, Location location);
    event ContentHashUpdated(uint256 indexed tokenId, bytes32 newContentHash);
    event SignWageUpdated(uint256 indexed tokenId, uint256 newWage);
    event BaseWageRateUpdated(uint256 newRate);
    event WagePaymentProcessed(
        uint256 indexed tokenId,
        address indexed carrier,
        uint256 requestedAmount,
        uint256 paidAmount,
        bool isPartialPayment
    );    

    error ExceedsMaxSignsPerUser();
    error SignNotFound();
    error SignAlreadyPickedUp();
    error SignNotPickedUp();
    error UnauthorizedCarrier();
    error OutsidePickupRadius();
    error InvalidLocation();
    error SignsHistoryNotSet();
    error InvalidWage();
    error UnauthorizedOwner();
    error SignTokenNotSet();
    error InvalidAddress();
    error InvalidSignsHistoryAddress();

    constructor() ERC721("Signs Game NFT", "SIGN") Ownable(msg.sender) {}

    function setSignsHistory(address _signsHistory) external onlyOwner {
        signsHistory = ISigns(_signsHistory);
    }

    function setSignToken(address _signToken) external onlyOwner {
        if (_signToken == address(0)) revert InvalidAddress();
        signToken = ISignToken(_signToken);
    }

    function recordMovement(
        uint256 tokenId,
        address carrier,
        Location calldata fromLoc,
        Location calldata toLoc,
        uint256 wage,
        bytes32 contentHash
    ) external pure override {
        revert("SignsNFT: not implemented");
    }

    function updateBaseWageRate(uint256 newRate) external onlyOwner {
        baseWageRate = newRate;
        emit BaseWageRateUpdated(newRate);
    }

    function updateSignWage(uint256 tokenId, uint256 newWage) external {
        Sign storage sign = signs[tokenId];
        if (sign.owner != msg.sender) revert UnauthorizedOwner();
        
        sign.signWage = newWage;
        emit SignWageUpdated(tokenId, newWage);
    }

    function createSign(Location calldata homeLocation) 
        external 
        whenNotPaused 
        returns (uint256) 
    {
        if (userSignCount[msg.sender] >= MAX_SIGNS_PER_USER) {
            revert ExceedsMaxSignsPerUser();
        }

        if (!_isValidLocation(homeLocation)) {
            revert InvalidLocation();
        }

        _tokenIds.increment();
        uint256 newTokenId = _tokenIds.current();

        Sign storage newSign = signs[newTokenId];
        newSign.home = homeLocation;
        newSign.current = homeLocation;
        newSign.owner = msg.sender;
        newSign.weight = 0;
        newSign.totalDistanceMeters = 0;
        newSign.isPickedUp = false;
        newSign.signWage = baseWageRate; // Initialize with default base rate

        userSignCount[msg.sender]++;
        _safeMint(msg.sender, newTokenId);

        emit SignCreated(newTokenId, msg.sender, homeLocation);
        return newTokenId;
    }

    function pickupSign(uint256 tokenId, Location calldata location) 
        external 
        whenNotPaused 
    {
        Sign storage sign = signs[tokenId];
        
        if (sign.owner == address(0)) revert SignNotFound();
        if (sign.isPickedUp) revert SignAlreadyPickedUp();
        if (msg.sender == sign.owner) revert UnauthorizedCarrier();
        if (!_isWithinRadius(location, sign.current)) revert OutsidePickupRadius();
        if (!_isValidLocation(location)) revert InvalidLocation();

        sign.isPickedUp = true;
        signCarriers[tokenId] = msg.sender;

        emit SignPickedUp(tokenId, msg.sender, location);
    }

    function dropSign(
        uint256 tokenId, 
        Location calldata location,
        bytes32 contentHash
    ) external whenNotPaused {
        if (address(signsHistory) == address(0)) revert SignsHistoryNotSet();
        if (address(signToken) == address(0)) revert SignTokenNotSet();
        
        Sign storage sign = signs[tokenId];
        
        if (sign.owner == address(0)) revert SignNotFound();
        if (!sign.isPickedUp) revert SignNotPickedUp();
        if (signCarriers[tokenId] != msg.sender) revert UnauthorizedCarrier();
        if (!_isValidLocation(location)) revert InvalidLocation();

        Location memory oldLocation = sign.current;
        
        // Update sign state
        sign.current = location;
        sign.isPickedUp = false;
        sign.totalMoves++;

        // Calculate and update total distance
        uint256 movedDistance = _calculateDistance(oldLocation, location);
        sign.totalDistanceMeters += movedDistance;

        // Calculate and update new weight based on total moves and distance
        sign.weight = _calculateNewWeight(sign.totalMoves, sign.totalDistanceMeters);
        
        sign.contentHash = contentHash;

        // Calculate wage using updated weight
        uint256 calculatedWage = _calculateWage(tokenId, oldLocation, location, sign.weight);

        // Process wage payment through SignToken contract
        ISignToken.WagePaymentResult memory paymentResult = 
            signToken.payWage(tokenId, msg.sender, calculatedWage);

        // Record movement in history
        signsHistory.recordMovement(
            tokenId,
            msg.sender,
            oldLocation,
            location,
            paymentResult.paidAmount, // Use actual paid amount
            contentHash
        );

        delete signCarriers[tokenId];

        // Emit all relevant events
        emit SignDropped(tokenId, msg.sender, location);
        emit SignMoved(tokenId, msg.sender, oldLocation, location);
        emit ContentHashUpdated(tokenId, contentHash);
        emit WagePaymentProcessed(
            tokenId,
            msg.sender,
            calculatedWage,
            paymentResult.paidAmount,
            paymentResult.isPartialPayment
        );
    }

    function _calculateDistance(
        Location memory from,
        Location memory to
    ) internal pure returns (uint256) {
        int64 latDiff = to.latitude - from.latitude;
        int64 lonDiff = to.longitude - from.longitude;
        
        uint64 absLatDiff = latDiff < 0 ? uint64(-latDiff) : uint64(latDiff);
        uint64 absLonDiff = lonDiff < 0 ? uint64(-lonDiff) : uint64(lonDiff);
        
        uint256 distance = uint256(absLatDiff) * uint256(absLatDiff) + 
                          uint256(absLonDiff) * uint256(absLonDiff);
        
        return distance * 111000; // Convert to meters
    }    

    function _calculateNewWeight(
        uint256 totalMoves,
        uint256 totalDistanceMeters
    ) internal view returns (uint256) {
        // Base weight from number of moves (increases with more moves)
        // Earlier moves have less impact, later moves have more impact
        uint256 moveWeight = (totalMoves * totalMoves * moveWeightMultiplier) / 
                           ((totalMoves + moveWeightDivisor) * moveWeightDivisor);
        
        // Weight from distance (1 point per kilometer, divided by distanceWeightDivisor)
        uint256 distanceWeight = totalDistanceMeters / distanceWeightDivisor;
        
        return moveWeight + distanceWeight;
    }

    // Weight calculation parameters
    uint256 public moveWeightMultiplier = 10;     // Base multiplier for move weight
    uint256 public moveWeightDivisor = 10;        // Divisor for move count in weight calculation
    uint256 public distanceWeightDivisor = 10000; // Converts to km and divides by 10 (1km = 0.1 weight)
    
    event WeightParametersUpdated(
        uint256 newMoveWeightMultiplier,
        uint256 newMoveWeightDivisor,
        uint256 newDistanceWeightDivisor
    );

    // Admin functions to update weight parameters
    function updateWeightParameters(
        uint256 newMoveWeightMultiplier,
        uint256 newMoveWeightDivisor,
        uint256 newDistanceWeightDivisor
    ) external onlyOwner {
        require(newMoveWeightDivisor > 0 && newDistanceWeightDivisor > 0, "Invalid divisors");
        
        moveWeightMultiplier = newMoveWeightMultiplier;
        moveWeightDivisor = newMoveWeightDivisor;
        distanceWeightDivisor = newDistanceWeightDivisor;
        
        emit WeightParametersUpdated(
            newMoveWeightMultiplier,
            newMoveWeightDivisor,
            newDistanceWeightDivisor
        );
    }    

    function updateHome(uint256 tokenId, Location calldata newHome) 
        external 
        whenNotPaused 
    {
        Sign storage sign = signs[tokenId];
        if (sign.owner == address(0)) revert SignNotFound();
        if (sign.owner != msg.sender) revert UnauthorizedCarrier();
        if (!_isValidLocation(newHome)) revert InvalidLocation();

        sign.home = newHome;
        emit HomeUpdated(tokenId, newHome);
    }

    function _isWithinRadius(Location memory loc1, Location memory loc2) 
        internal 
        pure 
        returns (bool) 
    {
        int64 latDiff = loc1.latitude - loc2.latitude;
        int64 lonDiff = loc1.longitude - loc2.longitude;
        
        uint64 absLatDiff = latDiff < 0 ? uint64(-latDiff) : uint64(latDiff);
        uint64 absLonDiff = lonDiff < 0 ? uint64(-lonDiff) : uint64(lonDiff);
        
        uint256 distanceM = uint256(absLatDiff) * uint256(absLatDiff) + 
                           uint256(absLonDiff) * uint256(absLonDiff);
        distanceM = distanceM * 111000 * 111000;
        
        return distanceM <= MAX_PICKUP_RADIUS;
    }

    function _calculateWage(
        uint256 tokenId,
        Location memory from,
        Location memory to,
        uint256 weight
    ) internal view returns (uint256) {
        int64 latDiff = to.latitude - from.latitude;
        int64 lonDiff = to.longitude - from.longitude;
        
        uint64 absLatDiff = latDiff < 0 ? uint64(-latDiff) : uint64(latDiff);
        uint64 absLonDiff = lonDiff < 0 ? uint64(-lonDiff) : uint64(lonDiff);
        
        uint256 distance = uint256(absLatDiff) * uint256(absLatDiff) + 
                          uint256(absLonDiff) * uint256(absLonDiff);
        
        // Convert to meters and apply sign-specific wage rate
        uint256 distanceMeters = (distance * 111000);
        uint256 baseWage = (distanceMeters * signs[tokenId].signWage) / 100; // Wage per 100 meters
        
        // Apply weight multiplier (heavier signs cost more to move)
        // Weight increases price by 1% for each point of weight
        uint256 weightMultiplier = 10000 + weight;  // Base 10000 (100%) + weight percentage
        uint256 finalWage = (baseWage * weightMultiplier) / 10000;
        
        return finalWage;
    }

    function _isValidLocation(Location memory location) 
        internal 
        pure 
        returns (bool) 
    {
        return location.latitude >= -90 * 10000 && 
               location.latitude <= 90 * 10000 &&
               location.longitude >= -180 * 10000 && 
               location.longitude <= 180 * 10000 &&
               location.timestamp > 0;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function approve(address to, uint256 tokenId) public virtual override {
        revert("Signs: direct approval not allowed");
    }

    function setApprovalForAll(address operator, bool approved) public virtual override {
        revert("Signs: approval for all not allowed");
    }

    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal virtual override whenNotPaused returns (address) {
        require(!signs[tokenId].isPickedUp, "Sign is currently picked up");
        return super._update(to, tokenId, auth);
    }
}