// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

interface IRoleManager {
    function hasRole(bytes32 role, address account) external view returns (bool);
    function ADMIN_ROLE() external view returns (bytes32);
    function WALL_OWNER_ROLE() external view returns (bytes32);
    function PAINTER_ROLE() external view returns (bytes32);
    function GALLERY_OWNER_ROLE() external view returns (bytes32);
    function SPONSOR_ROLE() external view returns (bytes32);
}

// Base contract with shared functionality
abstract contract WallBase is Pausable {
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
        bool isInGallery;
        bool isPainted;
        address galleryOwner;
        uint256 createdAt;
        uint256 lastUpdated;
    }

    // Shared storage
    mapping(uint256 => WallData) public walls;
    mapping(address => uint256[]) public ownerWalls;

    // Events
    event WallTransferred(uint256 indexed wallId, address indexed from, address indexed to);
    event WallUpdated(uint256 indexed wallId);
    event WallPainted(uint256 indexed wallId);

    constructor(address _roleManagerAddress) {
        require(_roleManagerAddress != address(0), "Invalid RoleManager address");
        roleManager = IRoleManager(_roleManagerAddress);
    }

    // Shared modifiers
    modifier onlyAdmin() {
        require(roleManager.hasRole(roleManager.ADMIN_ROLE(), msg.sender), "Caller is not an admin");
        _;
    }

    modifier onlyWallOwner(uint256 wallId) {
        require(walls[wallId].owner == msg.sender || 
                roleManager.hasRole(roleManager.WALL_OWNER_ROLE(), msg.sender), 
                "Caller is not the wall owner");
        _;
    }

    modifier wallExists(uint256 wallId) {
        require(walls[wallId].owner != address(0), "Wall does not exist");
        _;
    }

    // Internal helper functions
    function _getNextWallId() internal returns (uint256) {
        _wallIds.increment();
        return _wallIds.current();
    }

    function _removeWallFromOwner(uint256 wallId, address owner) internal {
        uint256[] storage ownerWallsList = ownerWalls[owner];
        for (uint i = 0; i < ownerWallsList.length; i++) {
            if (ownerWallsList[i] == wallId) {
                ownerWallsList[i] = ownerWallsList[ownerWallsList.length - 1];
                ownerWallsList.pop();
                break;
            }
        }
    }
}

// Registry contract for wall registration and approval
contract WallRegistry is WallBase {
    struct WallRequest {
        address requester;
        Location location;
        uint256 size;
        bool pending;
        bool approved;
    }

    mapping(uint256 => WallRequest) public wallRequests;
    uint256[] public pendingWallRequests;

    event WallRequested(uint256 indexed requestId, address indexed requester);
    event WallRequestApproved(uint256 indexed requestId, uint256 indexed wallId);
    event WallRequestRejected(uint256 indexed requestId);

    constructor(address _roleManager) WallBase(_roleManager) {}

    function requestWall(
        string calldata country,
        string calldata city,
        string calldata physicalAddress,
        int256 longitude,
        int256 latitude,
        uint256 size
    ) external whenNotPaused {
        // Check if requester has WALL_OWNER_ROLE
        require(roleManager.hasRole(roleManager.WALL_OWNER_ROLE(), msg.sender), 
                "Must have WALL_OWNER_ROLE to request wall registration");
        
        require(bytes(country).length > 0 && bytes(city).length > 0, "Invalid location data");
        require(size > 0, "Invalid size");

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
            pending: true,
            approved: false
        });

        pendingWallRequests.push(requestId);
        emit WallRequested(requestId, msg.sender);
    }

    function approveWallRequest(uint256 requestId) external onlyAdmin whenNotPaused {
        WallRequest storage request = wallRequests[requestId];
        require(request.pending, "Request not pending");
        
        // Double check requester still has WALL_OWNER_ROLE
        require(roleManager.hasRole(roleManager.WALL_OWNER_ROLE(), request.requester), 
                "Requester must maintain WALL_OWNER_ROLE");

        request.pending = false;
        request.approved = true;

        WallData memory newWall = WallData({
            id: requestId,
            owner: request.requester,
            location: request.location,
            size: request.size,
            isInGallery: false,
            isPainted: false,
            galleryOwner: address(0),
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

    function getPendingRequests() external view returns (uint256[] memory) {
        // Only admin and wall owners can view pending requests
        require(roleManager.hasRole(roleManager.ADMIN_ROLE(), msg.sender) || 
                roleManager.hasRole(roleManager.WALL_OWNER_ROLE(), msg.sender),
                "Not authorized to view requests");
        return pendingWallRequests;
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
}

// Management contract for wall updates and transfers
contract WallManagement is WallBase {
    constructor(address _roleManager) WallBase(_roleManager) {}

    function updateWall(
        uint256 wallId,
        string calldata country,
        string calldata city,
        string calldata physicalAddress,
        int256 longitude,
        int256 latitude,
        uint256 size
    ) external wallExists(wallId) whenNotPaused {
        // Check if caller is wall owner or admin
        require(walls[wallId].owner == msg.sender || 
                roleManager.hasRole(roleManager.ADMIN_ROLE(), msg.sender),
                "Not authorized to update wall");
        
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
        whenNotPaused 
    {
        // Check if caller is wall owner or admin
        require(walls[wallId].owner == msg.sender || 
                roleManager.hasRole(roleManager.ADMIN_ROLE(), msg.sender),
                "Not authorized to transfer wall");
                
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

    function markWallAsPainted(uint256 wallId) external 
        wallExists(wallId) 
        whenNotPaused 
    {
        require(roleManager.hasRole(roleManager.PAINTER_ROLE(), msg.sender) ||
                roleManager.hasRole(roleManager.ADMIN_ROLE(), msg.sender),
                "Not authorized to mark wall as painted");
                
        require(!walls[wallId].isPainted, "Wall already painted");

        walls[wallId].isPainted = true;
        walls[wallId].lastUpdated = block.timestamp;

        emit WallPainted(wallId);
    }
}

// Gallery integration contract
contract GalleryIntegration is WallBase {
    event WallAddedToGallery(uint256 indexed wallId, address indexed galleryOwner);
    event WallRemovedFromGallery(uint256 indexed wallId);

    constructor(address _roleManager) WallBase(_roleManager) {}

    function addWallToGallery(uint256 wallId) external 
        wallExists(wallId) 
        whenNotPaused 
    {
        require(roleManager.hasRole(roleManager.GALLERY_OWNER_ROLE(), msg.sender), 
                "Must have GALLERY_OWNER_ROLE to add wall to gallery");
                
        require(!walls[wallId].isInGallery, "Wall already in a gallery");
        
        walls[wallId].isInGallery = true;
        walls[wallId].galleryOwner = msg.sender;
        walls[wallId].lastUpdated = block.timestamp;

        emit WallAddedToGallery(wallId, msg.sender);
    }

    function removeWallFromGallery(uint256 wallId) external 
        wallExists(wallId) 
        whenNotPaused 
    {
        require(walls[wallId].isInGallery, "Wall not in a gallery");
        require(msg.sender == walls[wallId].galleryOwner || 
                roleManager.hasRole(roleManager.ADMIN_ROLE(), msg.sender), 
                "Not authorized to remove wall from gallery");

        walls[wallId].isInGallery = false;
        walls[wallId].galleryOwner = address(0);
        walls[wallId].lastUpdated = block.timestamp;

        emit WallRemovedFromGallery(wallId);
    }
}