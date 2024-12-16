// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

interface IRoleManager {
    function hasRole(bytes32 role, address account) external view returns (bool);
    function ADMIN_ROLE() external view returns (bytes32);
    function GALLERY_OWNER_ROLE() external view returns (bytes32);
    function WALL_OWNER_ROLE() external view returns (bytes32);
}

interface IWall {
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

    function getWall(uint256 wallId) external view returns (WallData memory);
    function setGalleryStatus(uint256 wallId, uint256 galleryId, bool inGallery) external;
}

contract Gallery is Pausable {
    using Counters for Counters.Counter;
    
    IRoleManager public roleManager;
    IWall public wallContract;
    Counters.Counter private _galleryIds;

    uint256 public platformPercentage;

    struct Location {
        string city;
        string country;
        int256 longitude;
        int256 latitude;
    }

    struct GalleryData {
        uint256 id;
        string name;
        string description;
        Location location;
        address owner;
        uint256 ownershipPercentage;
        bool isActive;
        uint256 createdAt;
        uint256 lastUpdated;
    }

    struct GalleryRequest {
        address requester;
        string name;
        string description;
        Location location;
        uint256 ownershipPercentage;
        bool pending;
        bool approved;
    }

    struct WallToGalleryRequest {
        uint256 wallId;
        address wallOwner;
        uint256 wallOwnerPercentage;
        bool pending;
        bool approved;
    }

    struct GalleryCreationParams {
        string name;
        string description;
        string city;
        string country;
        int256 longitude;
        int256 latitude;
        uint256 ownershipPercentage;
    }

    // Storage
    mapping(uint256 => GalleryData) public galleries;
    mapping(uint256 => GalleryRequest) public galleryRequests;
    mapping(uint256 => mapping(uint256 => WallToGalleryRequest)) public wallToGalleryRequests;
    mapping(uint256 => uint256[]) public galleryWalls;
    // New mappings for pending walls
    mapping(uint256 => uint256[]) public pendingWallsPerGallery;
    mapping(uint256 => mapping(uint256 => uint256)) private pendingWallIndex;

    // Events
    event PlatformPercentageUpdated(uint256 newPercentage);
    event GalleryRequested(uint256 indexed requestId, address indexed requester);
    event GalleryRequestApproved(uint256 indexed galleryId);
    event GalleryRequestRejected(uint256 indexed requestId);
    event WallToGalleryRequested(uint256 indexed galleryId, uint256 indexed wallId, address indexed wallOwner);
    event WallToGalleryRequestApproved(uint256 indexed galleryId, uint256 indexed wallId);
    event WallToGalleryRequestRejected(uint256 indexed galleryId, uint256 indexed wallId);
    event WallRemovedFromGallery(uint256 indexed galleryId, uint256 indexed wallId);

    constructor(address _roleManagerAddress, address _wallContractAddress) {
        require(_roleManagerAddress != address(0), "Invalid RoleManager address");
        require(_wallContractAddress != address(0), "Invalid Wall contract address");
        roleManager = IRoleManager(_roleManagerAddress);
        wallContract = IWall(_wallContractAddress);
        platformPercentage = 0;
    }

    modifier onlyAdmin() {
        require(roleManager.hasRole(roleManager.ADMIN_ROLE(), msg.sender), "Caller is not an admin");
        _;
    }

    modifier onlyGalleryOwner(uint256 galleryId) {
        require(galleries[galleryId].owner == msg.sender, "Caller is not the gallery owner");
        _;
    }

    function setPlatformPercentage(uint256 _percentage) external onlyAdmin {
        require(_percentage <= 100, "Invalid percentage");
        platformPercentage = _percentage;
        emit PlatformPercentageUpdated(_percentage);
    }

    function requestGallery(GalleryCreationParams calldata params) external whenNotPaused {
        require(roleManager.hasRole(roleManager.GALLERY_OWNER_ROLE(), msg.sender), 
                "Must have GALLERY_OWNER_ROLE");
        require(bytes(params.name).length > 0, "Name required");
        require(params.ownershipPercentage <= 50, "Max ownership percentage is 50%");
        
        uint256 requestId = _galleryIds.current();
        _galleryIds.increment();

        Location memory location = Location({
            city: params.city,
            country: params.country,
            longitude: params.longitude,
            latitude: params.latitude
        });

        galleryRequests[requestId] = GalleryRequest({
            requester: msg.sender,
            name: params.name,
            description: params.description,
            location: location,
            ownershipPercentage: params.ownershipPercentage,
            pending: true,
            approved: false
        });

        emit GalleryRequested(requestId, msg.sender);
    }

    function approveGalleryRequest(uint256 requestId) external onlyAdmin whenNotPaused {
        GalleryRequest storage request = galleryRequests[requestId];
        require(request.pending, "Request not pending");
        require(roleManager.hasRole(roleManager.GALLERY_OWNER_ROLE(), request.requester), 
                "Requester must maintain GALLERY_OWNER_ROLE");

        request.pending = false;
        request.approved = true;

        galleries[requestId] = GalleryData({
            id: requestId,
            name: request.name,
            description: request.description,
            location: request.location,
            owner: request.requester,
            ownershipPercentage: request.ownershipPercentage,
            isActive: true,
            createdAt: block.timestamp,
            lastUpdated: block.timestamp
        });

        emit GalleryRequestApproved(requestId);
    }

    function rejectGalleryRequest(uint256 requestId) external onlyAdmin whenNotPaused {
        GalleryRequest storage request = galleryRequests[requestId];
        require(request.pending, "Request not pending");

        request.pending = false;
        request.approved = false;

        emit GalleryRequestRejected(requestId);
    }

    function requestWallToGallery(uint256 galleryId, uint256 wallId) external whenNotPaused {
        require(roleManager.hasRole(roleManager.WALL_OWNER_ROLE(), msg.sender), 
                "Must have WALL_OWNER_ROLE");
        require(galleries[galleryId].isActive, "Gallery not active");

        IWall.WallData memory wall = wallContract.getWall(wallId);
        
        require(wall.owner == msg.sender, "Not wall owner");
        require(!wall.isInGallery, "Wall already in a gallery");
        
        uint256 totalPercentage = wall.ownershipPercentage + 
                                 galleries[galleryId].ownershipPercentage + 
                                 platformPercentage;
        require(totalPercentage <= 100, "Total percentage exceeds 100%");

        wallToGalleryRequests[galleryId][wallId] = WallToGalleryRequest({
            wallId: wallId,
            wallOwner: msg.sender,
            wallOwnerPercentage: wall.ownershipPercentage,
            pending: true,
            approved: false
        });

        // Add to pending walls tracking
        pendingWallsPerGallery[galleryId].push(wallId);
        pendingWallIndex[galleryId][wallId] = pendingWallsPerGallery[galleryId].length - 1;

        emit WallToGalleryRequested(galleryId, wallId, msg.sender);
    }

    function approveWallToGallery(uint256 galleryId, uint256 wallId) 
        external 
        onlyGalleryOwner(galleryId) 
        whenNotPaused 
    {
        WallToGalleryRequest storage request = wallToGalleryRequests[galleryId][wallId];
        require(request.pending, "Request not pending");
        require(roleManager.hasRole(roleManager.WALL_OWNER_ROLE(), request.wallOwner), 
                "Wall owner must maintain WALL_OWNER_ROLE");

        request.pending = false;
        request.approved = true;
        
        // Remove from pending walls
        _removePendingWall(galleryId, wallId);
        
        wallContract.setGalleryStatus(wallId, galleryId, true);
        galleryWalls[galleryId].push(wallId);

        emit WallToGalleryRequestApproved(galleryId, wallId);
    }

    function rejectWallToGallery(uint256 galleryId, uint256 wallId) 
        external 
        onlyGalleryOwner(galleryId) 
        whenNotPaused 
    {
        WallToGalleryRequest storage request = wallToGalleryRequests[galleryId][wallId];
        require(request.pending, "Request not pending");

        request.pending = false;
        request.approved = false;

        // Remove from pending walls
        _removePendingWall(galleryId, wallId);

        emit WallToGalleryRequestRejected(galleryId, wallId);
    }

    function removeWallFromGallery(uint256 galleryId, uint256 wallId) 
        external 
        onlyAdmin 
        whenNotPaused 
    {
        require(galleries[galleryId].isActive, "Gallery not active");
        
        _removeWallFromGallery(galleryId, wallId);
        wallContract.setGalleryStatus(wallId, 0, false);
        delete wallToGalleryRequests[galleryId][wallId];
        
        emit WallRemovedFromGallery(galleryId, wallId);
    }

    function _removeWallFromGallery(uint256 galleryId, uint256 wallId) private {
        uint256[] storage walls = galleryWalls[galleryId];
        for (uint i = 0; i < walls.length; i++) {
            if (walls[i] == wallId) {
                walls[i] = walls[walls.length - 1];
                walls.pop();
                break;
            }
        }
    }

    function _removePendingWall(uint256 galleryId, uint256 wallId) private {
        uint256 index = pendingWallIndex[galleryId][wallId];
        uint256 lastIndex = pendingWallsPerGallery[galleryId].length - 1;
        
        if (index != lastIndex) {
            uint256 lastWallId = pendingWallsPerGallery[galleryId][lastIndex];
            pendingWallsPerGallery[galleryId][index] = lastWallId;
            pendingWallIndex[galleryId][lastWallId] = index;
        }
        
        pendingWallsPerGallery[galleryId].pop();
        delete pendingWallIndex[galleryId][wallId];
    }

    // View functions
    function getGalleriesByOwner(address _owner) external view returns (GalleryData[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < _galleryIds.current(); i++) {
            if (galleries[i].owner == _owner) {
                count++;
            }
        }

        GalleryData[] memory result = new GalleryData[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < _galleryIds.current(); i++) {
            if (galleries[i].owner == _owner) {
                result[index] = galleries[i];
                index++;
            }
        }

        return result;
    }

    function getGallery(uint256 galleryId) external view returns (GalleryData memory) {
        GalleryData memory gallery = galleries[galleryId];
        require(gallery.owner != address(0), "Gallery does not exist");
        return gallery;
    }

    function galleryExists(uint256 galleryId) public view returns (bool) {
        return galleries[galleryId].owner != address(0);
    }

    function getGalleryWalls(uint256 galleryId) external view returns (uint256[] memory) {
        require(galleries[galleryId].isActive, "Gallery not active");
        return galleryWalls[galleryId];
    }

    function getPendingWallRequests(uint256 galleryId) external view returns (WallToGalleryRequest[] memory) {
        require(galleryExists(galleryId), "Gallery does not exist");
        
        uint256[] storage pendingWallIds = pendingWallsPerGallery[galleryId];
        WallToGalleryRequest[] memory requests = new WallToGalleryRequest[](pendingWallIds.length);
        
        for (uint256 i = 0; i < pendingWallIds.length; i++) {
            requests[i] = wallToGalleryRequests[galleryId][pendingWallIds[i]];
        }
        
        return requests;
    }

    function pause() external onlyAdmin {
        _pause();
    }

    function unpause() external onlyAdmin {
        _unpause();
    }


// Add these functions to the Gallery contract
function getPlatformPercentage() external view returns (uint256) {
    return platformPercentage;
}

function isGalleryActive(uint256 galleryId) external view returns (bool) {
    return galleries[galleryId].isActive;
}

function getGalleryOwner(uint256 galleryId) external view returns (address) {
    return galleries[galleryId].owner;
}

}