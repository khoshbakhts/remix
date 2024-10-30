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
    function getWall(uint256 wallId) external view returns (
        uint256 id,
        address owner,
        uint256 size,
        uint256 ownershipPercentage,
        bool isInGallery,
        uint256 galleryId
    );
}

interface IGallery {
    function galleries(uint256 galleryId) external view returns (
        uint256 id,
        string memory name,
        string memory description,
        address owner,
        uint256 ownershipPercentage,
        bool isActive
    );
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

    // Storage
    mapping(uint256 => PaintingData) public paintings;
    mapping(uint256 => PaintingRequest) public paintingRequests;
    mapping(uint256 => bool) public wallPainted;

    // Events
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
        require(roleManager.hasRole(roleManager.PAINTER_ROLE(), msg.sender), 
                "Must have PAINTER_ROLE");
        _;
    }

    modifier onlyGalleryOwner(uint256 wallId) {
        (,,,, bool isInGallery, uint256 galleryId) = wallContract.getWall(wallId);
        require(isInGallery, "Wall not in gallery");
        
        (,,,address galleryOwner,,) = galleryContract.galleries(galleryId);
        require(msg.sender == galleryOwner, "Not gallery owner");
        _;
    }

    function requestPainting(
        uint256 wallId, 
        string calldata description
    ) external onlyPainter whenNotPaused {
        require(!wallPainted[wallId], "Wall already painted");
        require(paintingRequests[wallId].status == PaintingStatus.None, 
                "Request already exists");

        (,,,, bool isInGallery,) = wallContract.getWall(wallId);
        require(isInGallery, "Wall not in gallery");

        paintingRequests[wallId] = PaintingRequest({
            wallId: wallId,
            painter: msg.sender,
            description: description,
            status: PaintingStatus.Requested,
            timestamp: block.timestamp
        });

        emit PaintingRequested(wallId, msg.sender);
    }

    function approvePaintingRequest(uint256 wallId) 
        external 
        onlyGalleryOwner(wallId) 
        whenNotPaused 
    {
        PaintingRequest storage request = paintingRequests[wallId];
        require(request.status == PaintingStatus.Requested, "Invalid request status");
        
        request.status = PaintingStatus.InProcess;
        emit PaintingRequestApproved(wallId, request.painter);
    }

    function rejectPaintingRequest(uint256 wallId) 
        external 
        onlyGalleryOwner(wallId) 
        whenNotPaused 
    {
        PaintingRequest storage request = paintingRequests[wallId];
        require(request.status == PaintingStatus.Requested, "Invalid request status");

        request.status = PaintingStatus.None;
        emit PaintingRequestRejected(wallId, request.painter);
    }

    function submitPaintingCompletion(uint256 wallId) 
        external 
        onlyPainter 
        whenNotPaused 
    {
        PaintingRequest storage request = paintingRequests[wallId];
        require(request.painter == msg.sender, "Not the assigned painter");
        require(request.status == PaintingStatus.InProcess, "Not in process");

        request.status = PaintingStatus.Completed;
    }

    function finalizePainting(uint256 wallId) 
        external 
        onlyGalleryOwner(wallId) 
        whenNotPaused 
    {
        PaintingRequest storage request = paintingRequests[wallId];
        require(request.status == PaintingStatus.Completed, "Painting not completed");

        _paintingIds.increment();
        uint256 newPaintingId = _paintingIds.current();

        // Create painting NFT
        _safeMint(request.painter, newPaintingId);

        // Store painting data
        paintings[newPaintingId] = PaintingData({
            id: newPaintingId,
            wallId: wallId,
            painter: request.painter,
            description: request.description,
            sharesMinted: false,
            createdAt: block.timestamp
        });

        wallPainted[wallId] = true;
        
        // Get ownership percentages and create shares
        _createShares(newPaintingId, wallId, request.painter);

        emit PaintingCompleted(newPaintingId, wallId);
    }

    function _createShares(uint256 paintingId, uint256 wallId, address painter) private {
        require(!paintings[paintingId].sharesMinted, "Shares already minted");

        // Get wall and gallery data
        (,address wallOwner,,uint256 wallOwnerPercentage,, uint256 galleryId) = 
            wallContract.getWall(wallId);
        
        (,,,address galleryOwner, uint256 galleryOwnerPercentage,) = 
            galleryContract.galleries(galleryId);
        
        uint256 platformPercentage = galleryContract.platformPercentage();

        // Create and distribute shares
        paintingShares.createSharesForPainting(
            paintingId,
            _getPlatformAdmin(),
            wallOwner,
            galleryOwner,
            painter,
            platformPercentage,
            wallOwnerPercentage,
            galleryOwnerPercentage
        );

        paintings[paintingId].sharesMinted = true;
        emit SharesCreated(paintingId);
    }

    function _getPlatformAdmin() private view returns (address) {
        // Get the first admin address from RoleManager
        return msg.sender; // This should be updated based on your admin management system
    }

    // Admin functions
    function pause() external {
        require(roleManager.hasRole(roleManager.ADMIN_ROLE(), msg.sender), 
                "Must have ADMIN_ROLE");
        _pause();
    }

    function unpause() external {
        require(roleManager.hasRole(roleManager.ADMIN_ROLE(), msg.sender), 
                "Must have ADMIN_ROLE");
        _unpause();
    }
}