// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

interface IRoleManager {
    function hasRole(bytes32 role, address account) external view returns (bool);
    function ADMIN_ROLE() external view returns (bytes32);
    function WALL_OWNER_ROLE() external view returns (bytes32);
}

contract Wall is Pausable {
    address public galleryContract;
    using Counters for Counters.Counter;
    
    IRoleManager public roleManager;
    Counters.Counter private _wallIds;

    struct Location {
        string country;
        string city;
        string physicalAddress;
        int256 longitude;
        int256 latitude;
    }

    struct WallData {
        uint256 id;
        address owner;
        Location location;
        uint256 size;
        uint256 ownershipPercentage;
        bool isInGallery;
        uint256 galleryId;
        uint256 createdAt;
        uint256 lastUpdated;
    }

    struct WallRequest {
        address requester;
        Location location;
        uint256 size;
        uint256 ownershipPercentage;
        bool pending;
        bool approved;
    }

    // Storage
    mapping(uint256 => WallData) public walls;
    mapping(uint256 => WallRequest) public wallRequests;
    mapping(address => uint256[]) public ownerWalls;
    uint256[] public pendingWallRequests;

    // Events for wall registration
    event WallRequested(uint256 indexed requestId, address indexed requester);
    event WallRequestApproved(uint256 indexed requestId, uint256 indexed wallId);
    event WallRequestRejected(uint256 indexed requestId);

    // Events for wall management
    event WallTransferred(uint256 indexed wallId, address indexed from, address indexed to);
    event WallUpdated(uint256 indexed wallId);
    event WallOwnershipPercentageUpdated(uint256 indexed wallId, uint256 percentage);
    event WallGalleryStatusUpdated(uint256 indexed wallId, uint256 indexed galleryId, bool isInGallery);

    constructor(address _roleManagerAddress) {
        require(_roleManagerAddress != address(0), "Invalid RoleManager address");
        roleManager = IRoleManager(_roleManagerAddress);
    }

    // Modifiers
    modifier onlyAdmin() {
        require(roleManager.hasRole(roleManager.ADMIN_ROLE(), msg.sender), "Caller is not an admin");
        _;
    }

    modifier wallExists(uint256 wallId) {
        require(walls[wallId].owner != address(0), "Wall does not exist");
        _;
    }

    modifier onlyWallOwner(uint256 wallId) {
        require(walls[wallId].owner == msg.sender || 
                roleManager.hasRole(roleManager.ADMIN_ROLE(), msg.sender), 
                "Not authorized");
        _;
    }

    // Add setter for gallery contract address (can only be set by admin)
    function setGalleryContract(address _galleryContract) external onlyAdmin {
        require(_galleryContract != address(0), "Invalid gallery contract");
        galleryContract = _galleryContract;
    }

    // Registration functions
    function requestWall(
        string calldata country,
        string calldata city,
        string calldata physicalAddress,
        int256 longitude,
        int256 latitude,
        uint256 size,
        uint256 ownershipPercentage
    ) external whenNotPaused {
        require(roleManager.hasRole(roleManager.WALL_OWNER_ROLE(), msg.sender), 
                "Must have WALL_OWNER_ROLE to request wall registration");
        
        require(bytes(country).length > 0 && bytes(city).length > 0, "Invalid location data");
        require(size > 0, "Invalid size");
        require(ownershipPercentage <= 90, "Max ownership percentage is 90%");

        uint256 requestId = _getNextWallId();
        
        Location memory location = Location({
            country: country,
            city: city,
            physicalAddress: physicalAddress,
            longitude: longitude,
            latitude: latitude
        });

        wallRequests[requestId] = WallRequest({
            requester: msg.sender,
            location: location,
            size: size,
            ownershipPercentage: ownershipPercentage,
            pending: true,
            approved: false
        });

        pendingWallRequests.push(requestId);
        emit WallRequested(requestId, msg.sender);
    }

    function approveWallRequest(uint256 requestId) external onlyAdmin whenNotPaused {
        WallRequest storage request = wallRequests[requestId];
        require(request.pending, "Request not pending");
        
        require(roleManager.hasRole(roleManager.WALL_OWNER_ROLE(), request.requester), 
                "Requester must maintain WALL_OWNER_ROLE");

        request.pending = false;
        request.approved = true;

        WallData memory newWall = WallData({
            id: requestId,
            owner: request.requester,
            location: request.location,
            size: request.size,
            ownershipPercentage: request.ownershipPercentage,
            isInGallery: false,
            galleryId: 0,
            createdAt: block.timestamp,
            lastUpdated: block.timestamp
        });

        walls[requestId] = newWall;
        ownerWalls[request.requester].push(requestId);
        _removeFromPendingRequests(requestId);

        emit WallRequestApproved(requestId, requestId);
    }

    function rejectWallRequest(uint256 requestId) external onlyAdmin whenNotPaused {
        WallRequest storage request = wallRequests[requestId];
        require(request.pending, "Request not pending");

        request.pending = false;
        request.approved = false;
        _removeFromPendingRequests(requestId);

        emit WallRequestRejected(requestId);
    }

    // Management functions
    function updateWall(
        uint256 wallId,
        string calldata country,
        string calldata city,
        string calldata physicalAddress,
        int256 longitude,
        int256 latitude,
        uint256 size
    ) external wallExists(wallId) onlyWallOwner(wallId) whenNotPaused {
        require(bytes(country).length > 0 && bytes(city).length > 0, "Invalid location data");
        require(size > 0, "Invalid size");

        WallData storage wall = walls[wallId];
        wall.location.country = country;
        wall.location.city = city;
        wall.location.physicalAddress = physicalAddress;
        wall.location.longitude = longitude;
        wall.location.latitude = latitude;
        wall.size = size;
        wall.lastUpdated = block.timestamp;

        emit WallUpdated(wallId);
    }

    function transferWall(uint256 wallId, address newOwner) external 
        wallExists(wallId) 
        onlyWallOwner(wallId)
        whenNotPaused 
    {
        require(newOwner != address(0), "Invalid new owner");
        require(roleManager.hasRole(roleManager.WALL_OWNER_ROLE(), newOwner), 
                "New owner must have WALL_OWNER_ROLE");

        address oldOwner = walls[wallId].owner;
        walls[wallId].owner = newOwner;
        walls[wallId].lastUpdated = block.timestamp;

        _removeWallFromOwner(wallId, oldOwner);
        ownerWalls[newOwner].push(wallId);

        emit WallTransferred(wallId, oldOwner, newOwner);
    }

    function setOwnershipPercentage(uint256 wallId, uint256 percentage) 
        external 
        wallExists(wallId) 
        onlyWallOwner(wallId)
        whenNotPaused 
    {
        require(percentage <= 90, "Max ownership percentage is 90%");
        
        walls[wallId].ownershipPercentage = percentage;
        walls[wallId].lastUpdated = block.timestamp;

        emit WallOwnershipPercentageUpdated(wallId, percentage);
    }

    // Gallery integration function
    function setGalleryStatus(uint256 wallId, uint256 galleryId, bool inGallery) 
        external 
        wallExists(wallId)
    {
        require(msg.sender == galleryContract, "Only gallery contract can call");
        walls[wallId].isInGallery = inGallery;
        walls[wallId].galleryId = galleryId;
        walls[wallId].lastUpdated = block.timestamp;

        emit WallGalleryStatusUpdated(wallId, galleryId, inGallery);
    }

    // View functions
    function getWall(uint256 wallId) external view wallExists(wallId) returns (WallData memory) {
        return walls[wallId];
    }

    function getWallsByOwner(address owner) external view returns (uint256[] memory) {
        return ownerWalls[owner];
    }

    function getPendingRequests() external view returns (uint256[] memory) {
        require(roleManager.hasRole(roleManager.ADMIN_ROLE(), msg.sender) || 
                roleManager.hasRole(roleManager.WALL_OWNER_ROLE(), msg.sender),
                "Not authorized to view requests");
        return pendingWallRequests;
    }

    // Internal helper functions
    function _getNextWallId() private returns (uint256) {
        _wallIds.increment();
        return _wallIds.current();
    }

    function _removeFromPendingRequests(uint256 requestId) private {
        for (uint i = 0; i < pendingWallRequests.length; i++) {
            if (pendingWallRequests[i] == requestId) {
                pendingWallRequests[i] = pendingWallRequests[pendingWallRequests.length - 1];
                pendingWallRequests.pop();
                break;
            }
        }
    }

    function _removeWallFromOwner(uint256 wallId, address owner) private {
        uint256[] storage ownerWallsList = ownerWalls[owner];
        for (uint i = 0; i < ownerWallsList.length; i++) {
            if (ownerWallsList[i] == wallId) {
                ownerWallsList[i] = ownerWallsList[ownerWallsList.length - 1];
                ownerWallsList.pop();
                break;
            }
        }
    }

    // Admin functions
    function pause() external onlyAdmin {
        _pause();
    }

    function unpause() external onlyAdmin {
        _unpause();
    }
}