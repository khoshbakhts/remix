// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./ISigns.sol";

contract SignsNFT is ISigns, ERC721, Ownable, Pausable {
    using Counters for Counters.Counter;

    struct Sign {
        Location home;
        Location current;
        uint256 totalMoves;
        uint256 totalCarriers;
        uint256 weight;
        address owner;
        bool isPickedUp;
        bytes32 contentHash;
    }

    Counters.Counter private _tokenIds;
    mapping(uint256 => Sign) public signs;
    mapping(address => uint256) public userSignCount;
    mapping(uint256 => address) public signCarriers;
    
    uint256 public constant MAX_SIGNS_PER_USER = 1;
    uint256 public constant MAX_PICKUP_RADIUS = 100; // meters
    
    ISigns public signsHistory;

    event SignCreated(uint256 indexed tokenId, address indexed owner, Location home);
    event SignMoved(uint256 indexed tokenId, address indexed carrier, Location from, Location to);
    event HomeUpdated(uint256 indexed tokenId, Location newHome);
    event SignPickedUp(uint256 indexed tokenId, address indexed carrier, Location location);
    event SignDropped(uint256 indexed tokenId, address indexed carrier, Location location);
    event ContentHashUpdated(uint256 indexed tokenId, bytes32 newContentHash);

    error ExceedsMaxSignsPerUser();
    error SignNotFound();
    error SignAlreadyPickedUp();
    error SignNotPickedUp();
    error UnauthorizedCarrier();
    error OutsidePickupRadius();
    error InvalidLocation();
    error SignsHistoryNotSet();

    constructor() ERC721("Signs Game NFT", "SIGN") Ownable(msg.sender) {}

    function setSignsHistory(address _signsHistory) external onlyOwner {
        signsHistory = ISigns(_signsHistory);
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
        newSign.isPickedUp = false;

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
    ) 
        external 
        whenNotPaused 
    {
        if (address(signsHistory) == address(0)) revert SignsHistoryNotSet();
        
        Sign storage sign = signs[tokenId];
        
        if (sign.owner == address(0)) revert SignNotFound();
        if (!sign.isPickedUp) revert SignNotPickedUp();
        if (signCarriers[tokenId] != msg.sender) revert UnauthorizedCarrier();
        if (!_isValidLocation(location)) revert InvalidLocation();

        Location memory oldLocation = sign.current;
        sign.current = location;
        sign.isPickedUp = false;
        sign.totalMoves++;
        sign.totalCarriers++;
        sign.contentHash = contentHash;

        uint256 wage = _calculateWage(oldLocation, location, sign.weight);

        signsHistory.recordMovement(
            tokenId,
            msg.sender,
            oldLocation,
            location,
            wage,
            contentHash
        );

        delete signCarriers[tokenId];

        emit SignDropped(tokenId, msg.sender, location);
        emit SignMoved(tokenId, msg.sender, oldLocation, location);
        emit ContentHashUpdated(tokenId, contentHash);
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
        Location memory from,
        Location memory to,
        uint256 weight
    ) internal pure returns (uint256) {
        int64 latDiff = to.latitude - from.latitude;
        int64 lonDiff = to.longitude - from.longitude;
        
        uint64 absLatDiff = latDiff < 0 ? uint64(-latDiff) : uint64(latDiff);
        uint64 absLonDiff = lonDiff < 0 ? uint64(-lonDiff) : uint64(lonDiff);
        
        uint256 distance = uint256(absLatDiff) * uint256(absLatDiff) + 
                          uint256(absLonDiff) * uint256(absLonDiff);
        
        uint256 baseWage = (distance * 111000) / 100;
        uint256 weightPenalty = (baseWage * weight) / 10000;
        return baseWage > weightPenalty ? baseWage - weightPenalty : 0;
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