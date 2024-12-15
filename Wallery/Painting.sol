// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

interface IRoleManager {
    function hasRole(bytes32 role, address account) external view returns (bool);
    function ADMIN_ROLE() external view returns (bytes32);
    function PAINTER_ROLE() external view returns (bytes32);
    function GALLERY_OWNER_ROLE() external view returns (bytes32);
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
}

interface IGallery {
    struct GalleryData {
        uint256 id;
        string name;
        string description;
        address owner;
        uint256 ownershipPercentage;
        bool isActive;
        uint256 createdAt;
        uint256 lastUpdated;
    }

    function getGallery(uint256 galleryId) external view returns (GalleryData memory);
    function platformPercentage() external view returns (uint256);
}

interface IPaintingShares {
    function createSharesForPainting(
        uint256 paintingId,
        address platformAdmin,
        address wallOwner,
        address galleryOwner,
        address painter,
        uint256 platformPercentage,
        uint256 wallOwnerPercentage,
        uint256 galleryOwnerPercentage
    ) external;
}

contract PaintingNFT is ERC721, Pausable {
    using Counters for Counters.Counter;

    IRoleManager public immutable roleManager;
    IWall public immutable wallContract;
    IGallery public immutable galleryContract;
    IPaintingShares public immutable paintingShares;

    Counters.Counter private _paintingIds;

    enum PaintingStatus { None, Requested, InProcess, Completed }

    struct PaintingRequest {
        uint256 wallId;
        address painter;
        string description;
        PaintingStatus status;
        uint256 timestamp;
    }

    struct PaintingData {
        uint256 id;
        uint256 wallId;
        address painter;
        string description;
        bool sharesMinted;
        uint256 createdAt;
    }

    // New mappings for better request tracking
    mapping(address => uint256[]) private painterPendingRequestIds;
    mapping(uint256 => uint256[]) private wallPendingRequestIds;
    mapping(address => uint256[]) private painterAcceptedRequestIds;
    mapping(uint256 => uint256[]) private wallCompletedRequestIds;


    mapping(uint256 => PaintingData) public paintings;
    mapping(uint256 => PaintingRequest) public paintingRequests;
    mapping(uint256 => bool) public wallPainted;
    mapping(address => uint256[]) private painterToRequests;
    mapping(uint256 => uint256[]) private wallToRequests;

    event PaintingRequested(uint256 indexed wallId, address indexed painter);
    event PaintingRequestApproved(uint256 indexed wallId, address indexed painter);
    event PaintingRequestRejected(uint256 indexed wallId, address indexed painter);
    event PaintingCompleted(uint256 indexed paintingId, uint256 indexed wallId);
    event SharesCreated(uint256 indexed paintingId);

    constructor(
        address _roleManager,
        address _wallContract,
        address _galleryContract,
        address _paintingShares
    ) ERC721("Wall Painting", "WPAINT") {
        require(_roleManager != address(0), "Invalid RoleManager address");
        require(_wallContract != address(0), "Invalid Wall contract address");
        require(_galleryContract != address(0), "Invalid Gallery contract address");
        require(_paintingShares != address(0), "Invalid Shares contract address");

        roleManager = IRoleManager(_roleManager);
        wallContract = IWall(_wallContract);
        galleryContract = IGallery(_galleryContract);
        paintingShares = IPaintingShares(_paintingShares);
    }

    modifier onlyPainter() {
        require(roleManager.hasRole(roleManager.PAINTER_ROLE(), msg.sender), "Must have PAINTER_ROLE");
        _;
    }

    modifier onlyGalleryOwner(uint256 wallId) {
        IWall.WallData memory wallData = wallContract.getWall(wallId);
        require(wallData.isInGallery, "Wall not in gallery");
        IGallery.GalleryData memory gallery = galleryContract.getGallery(wallData.galleryId);
        require(gallery.isActive, "Gallery not active");
        require(msg.sender == gallery.owner, "Not gallery owner");
        _;
    }

     function requestPainting(uint256 wallId, string calldata description) 
        external 
        onlyPainter 
        whenNotPaused 
    {
        require(bytes(description).length > 0, "Description cannot be empty");
        require(!wallPainted[wallId], "Wall already painted");
        require(paintingRequests[wallId].status == PaintingStatus.None, "Request exists");
        
        IWall.WallData memory wallData = wallContract.getWall(wallId);
        require(wallData.isInGallery, "Wall not in gallery");
        
        paintingRequests[wallId] = PaintingRequest({
            wallId: wallId,
            painter: msg.sender,
            description: description,
            status: PaintingStatus.Requested,
            timestamp: block.timestamp
        });

        // Update tracking arrays
        painterPendingRequestIds[msg.sender].push(wallId);
        wallPendingRequestIds[wallId].push(wallId);

        emit PaintingRequested(wallId, msg.sender);
    }

    function approvePaintingRequest(uint256 wallId) 
        external 
        onlyGalleryOwner(wallId) 
        whenNotPaused 
    {
        PaintingRequest storage request = paintingRequests[wallId];
        require(request.status == PaintingStatus.Requested, "Invalid status");
        
        request.status = PaintingStatus.InProcess;
        
        // Update tracking arrays
        _removeFromArray(painterPendingRequestIds[request.painter], wallId);
        _removeFromArray(wallPendingRequestIds[wallId], wallId);
        painterAcceptedRequestIds[request.painter].push(wallId);
        
        emit PaintingRequestApproved(wallId, request.painter);
    }

    function rejectPaintingRequest(uint256 wallId)
        external
        onlyGalleryOwner(wallId)
        whenNotPaused
    {
        PaintingRequest storage request = paintingRequests[wallId];
        require(request.status == PaintingStatus.Requested, "Invalid status");

        request.status = PaintingStatus.None;
        
        // Update tracking arrays
        _removeFromArray(painterPendingRequestIds[request.painter], wallId);
        _removeFromArray(wallPendingRequestIds[wallId], wallId);
        
        emit PaintingRequestRejected(wallId, request.painter);
    }

    function submitPaintingCompletion(uint256 wallId)
        external
        onlyPainter
        whenNotPaused
    {
        PaintingRequest storage request = paintingRequests[wallId];
        require(request.painter == msg.sender, "Not assigned painter");
        require(request.status == PaintingStatus.InProcess, "Not in process");

        request.status = PaintingStatus.Completed;
        
        // Update tracking arrays
        _removeFromArray(painterAcceptedRequestIds[msg.sender], wallId);
        wallCompletedRequestIds[wallId].push(wallId);
    }

    function finalizePainting(uint256 wallId)
        external
        onlyGalleryOwner(wallId)
        whenNotPaused
    {
        PaintingRequest storage request = paintingRequests[wallId];
        require(request.status == PaintingStatus.Completed, "Not completed");

        _paintingIds.increment();
        uint256 newPaintingId = _paintingIds.current();

        _safeMint(request.painter, newPaintingId);

        paintings[newPaintingId] = PaintingData({
            id: newPaintingId,
            wallId: wallId,
            painter: request.painter,
            description: request.description,
            sharesMinted: false,
            createdAt: block.timestamp
        });

        // Update tracking arrays
        _removeFromArray(wallCompletedRequestIds[wallId], wallId);
        
        wallPainted[wallId] = true;
        _createShares(newPaintingId, wallId, request.painter);

        emit PaintingCompleted(newPaintingId, wallId);
    }

    // Updated query functions
    function painterPendingRequests(address painter) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return painterPendingRequestIds[painter];
    }

    function wallPaintingPendingRequests(uint256 wallId) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return wallPendingRequestIds[wallId];
    }

    function painterAcceptedRequests(address painter) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return painterAcceptedRequestIds[painter];
    }

    function wallPaintingPendingSubmits(uint256 wallId) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return wallCompletedRequestIds[wallId];
    }

    // Helper Functions
    function _removeFromArray(uint256[] storage arr, uint256 value) private {
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i] == value) {
                arr[i] = arr[arr.length - 1];
                arr.pop();
                break;
            }
        }
    }

    function _createShares(uint256 paintingId, uint256 wallId, address painter) private {
        require(!paintings[paintingId].sharesMinted, "Shares minted");

        IWall.WallData memory wallData = wallContract.getWall(wallId);
        IGallery.GalleryData memory gallery = galleryContract.getGallery(wallData.galleryId);
        uint256 platformPercentage = galleryContract.platformPercentage();

        require(platformPercentage + wallData.ownershipPercentage + gallery.ownershipPercentage <= 100, 
                "Exceeds 100%");

        paintingShares.createSharesForPainting(
            paintingId,
            address(0),
            wallData.owner,
            gallery.owner,
            painter,
            platformPercentage,
            wallData.ownershipPercentage,
            gallery.ownershipPercentage
        );

        paintings[paintingId].sharesMinted = true;
        emit SharesCreated(paintingId);
    }

    function pause() external {
        require(roleManager.hasRole(roleManager.ADMIN_ROLE(), msg.sender), "Must have ADMIN_ROLE");
        _pause();
    }

    function unpause() external {
        require(roleManager.hasRole(roleManager.ADMIN_ROLE(), msg.sender), "Must have ADMIN_ROLE");
        _unpause();
    }
}