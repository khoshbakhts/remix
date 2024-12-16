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
    function getPlatformPercentage() external view returns (uint256);
    function isGalleryActive(uint256 galleryId) external view returns (bool);
    function getGalleryOwner(uint256 galleryId) external view returns (address);
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
    Counters.Counter private _requestIds;

    enum PaintingStatus { None, Requested, InProcess, Completed }

    struct PaintingRequest {
        uint256 requestId;
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

    mapping(uint256 => PaintingRequest) public paintingRequests;
    mapping(uint256 => uint256[]) public wallToRequestIds;
    mapping(address => uint256[]) private painterPendingRequestIds;
    mapping(address => uint256[]) private painterAcceptedRequestIds;
    mapping(uint256 => uint256[]) private wallCompletedRequestIds;
    mapping(uint256 => PaintingData) public paintings;
    mapping(uint256 => bool) public wallPainted;

    event PaintingRequested(uint256 indexed requestId, uint256 indexed wallId, address indexed painter);
    event PaintingRequestApproved(uint256 indexed requestId, uint256 indexed wallId, address indexed painter);
    event PaintingRequestRejected(uint256 indexed requestId, uint256 indexed wallId, address indexed painter);
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

    function validateGalleryOwner(uint256 wallId, address owner) public view returns (bool) {
        IWall.WallData memory wallData = wallContract.getWall(wallId);
        if (!wallData.isInGallery) {
            return false;
        }
        return galleryContract.isGalleryActive(wallData.galleryId) && 
               galleryContract.getGalleryOwner(wallData.galleryId) == owner;
    }

    function requestPainting(uint256 wallId, string calldata description) 
        external 
        onlyPainter 
        whenNotPaused 
    {
        require(bytes(description).length > 0, "Description cannot be empty");
        require(!wallPainted[wallId], "Wall already painted");
        
        IWall.WallData memory wallData = wallContract.getWall(wallId);
        require(wallData.isInGallery, "Wall not in gallery");
        
        _requestIds.increment();
        uint256 newRequestId = _requestIds.current();
        
        paintingRequests[newRequestId] = PaintingRequest({
            requestId: newRequestId,
            wallId: wallId,
            painter: msg.sender,
            description: description,
            status: PaintingStatus.Requested,
            timestamp: block.timestamp
        });

        wallToRequestIds[wallId].push(newRequestId);
        painterPendingRequestIds[msg.sender].push(newRequestId);

        emit PaintingRequested(newRequestId, wallId, msg.sender);
    }

    function approvePaintingRequest(uint256 requestId) 
        external 
        whenNotPaused 
    {
        PaintingRequest storage request = paintingRequests[requestId];
        require(request.requestId == requestId, "Request does not exist");
        require(request.status == PaintingStatus.Requested, "Invalid status");
        require(validateGalleryOwner(request.wallId, msg.sender), "Not authorized gallery owner");
        require(!wallPainted[request.wallId], "Wall already painted");
        require(request.painter != address(0), "Invalid painter address");
        
        IWall.WallData memory wallData = wallContract.getWall(request.wallId);
        require(wallData.isInGallery, "Wall not in gallery");
        
        request.status = PaintingStatus.InProcess;
        
        _removeFromArray(painterPendingRequestIds[request.painter], requestId);
        painterAcceptedRequestIds[request.painter].push(requestId);
        
        emit PaintingRequestApproved(requestId, request.wallId, request.painter);
    }

    function submitPaintingCompletion(uint256 requestId)
        external
        onlyPainter
        whenNotPaused
    {
        PaintingRequest storage request = paintingRequests[requestId];
        require(request.requestId == requestId, "Request does not exist");
        require(request.painter == msg.sender, "Not assigned painter");
        require(request.status == PaintingStatus.InProcess, "Not in process");

        request.status = PaintingStatus.Completed;
        
        _removeFromArray(painterAcceptedRequestIds[msg.sender], requestId);
        wallCompletedRequestIds[request.wallId].push(requestId);
    }

    function finalizePainting(uint256 requestId)
        external
        whenNotPaused
    {
        PaintingRequest storage request = paintingRequests[requestId];
        require(request.requestId == requestId, "Request does not exist");
        require(request.status == PaintingStatus.Completed, "Not completed");
        require(validateGalleryOwner(request.wallId, msg.sender), "Not authorized gallery owner");

        _paintingIds.increment();
        uint256 newPaintingId = _paintingIds.current();

        _safeMint(request.painter, newPaintingId);

        paintings[newPaintingId] = PaintingData({
            id: newPaintingId,
            wallId: request.wallId,
            painter: request.painter,
            description: request.description,
            sharesMinted: false,
            createdAt: block.timestamp
        });

        _removeFromArray(wallCompletedRequestIds[request.wallId], requestId);
        
        wallPainted[request.wallId] = true;
        _createShares(newPaintingId, request.wallId, request.painter);

        emit PaintingCompleted(newPaintingId, request.wallId);
    }

    function _createShares(uint256 paintingId, uint256 wallId, address painter) private {
        require(!paintings[paintingId].sharesMinted, "Shares minted");

        IWall.WallData memory wallData = wallContract.getWall(wallId);
        address galleryOwner = galleryContract.getGalleryOwner(wallData.galleryId);
        uint256 platformPercentage = galleryContract.getPlatformPercentage();

        paintingShares.createSharesForPainting(
            paintingId,
            address(0),
            wallData.owner,
            galleryOwner,
            painter,
            platformPercentage,
            wallData.ownershipPercentage,
            100 - platformPercentage - wallData.ownershipPercentage // Gallery owner gets remaining percentage
        );

        paintings[paintingId].sharesMinted = true;
        emit SharesCreated(paintingId);
    }

    function _removeFromArray(uint256[] storage arr, uint256 value) private {
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i] == value) {
                arr[i] = arr[arr.length - 1];
                arr.pop();
                break;
            }
        }
    }

    // Query functions
    function getWallRequests(uint256 wallId) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return wallToRequestIds[wallId];
    }

    function getPainterPendingRequests(address painter) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return painterPendingRequestIds[painter];
    }

    function getPainterAcceptedRequests(address painter) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return painterAcceptedRequestIds[painter];
    }

    function getWallCompletedRequests(uint256 wallId) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return wallCompletedRequestIds[wallId];
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