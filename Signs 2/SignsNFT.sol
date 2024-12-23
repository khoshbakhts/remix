// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";

contract SignsNFT is Initializable, ERC721Upgradeable, OwnableUpgradeable, PausableUpgradeable {
    using CountersUpgradeable for CountersUpgradeable.Counter;

    struct Location {
        int64 latitude;    // ~4 decimal places precision (-90 to +90)
        int64 longitude;   // ~4 decimal places precision (-180 to +180)
        uint64 timestamp;  // Good until year 2554
    }

    struct Sign {
        Location home;
        Location current;
        uint256 totalMoves;
        uint256 totalCarriers;
        uint256 weight;
        address owner;
        bool isPickedUp;
        bytes32 contentHash;  // Hash of off-chain content (diary entries, photos)
    }

    CountersUpgradeable.Counter private _tokenIds;
    mapping(uint256 => Sign) public signs;
    mapping(address => uint256) public userSignCount;
    mapping(uint256 => address) public signCarriers;
    
    uint256 public constant MAX_SIGNS_PER_USER = 1;
    uint256 public constant MAX_PICKUP_RADIUS = 100; // meters

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

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __ERC721_init("Signs Game NFT", "SIGN");
        __Ownable_init(msg.sender);
        __Pausable_init();
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
        
        // Convert to positive values for calculation
        uint64 absLatDiff = latDiff < 0 ? uint64(-latDiff) : uint64(latDiff);
        uint64 absLonDiff = lonDiff < 0 ? uint64(-lonDiff) : uint64(lonDiff);
        
        // Rough approximation: 1 degree ≈ 111km
        uint256 distanceM = uint256(absLatDiff) * uint256(absLatDiff) + 
                           uint256(absLonDiff) * uint256(absLonDiff);
        distanceM = distanceM * 111000 * 111000;
        
        return distanceM <= MAX_PICKUP_RADIUS;
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

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal virtual whenNotPaused {
        require(!signs[tokenId].isPickedUp, "Sign is currently picked up");
    }
}