// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
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

// Library for constants
library SharesConstants {
    uint256 public constant TOTAL_SHARES = 100000;
}

// Contract for fractional tokens of each painting
contract PaintingShares is ERC20 {
    address public paintingNFT;
    uint256 public paintingId;

    constructor(
        string memory name,
        string memory symbol,
        uint256 _paintingId,
        address _paintingNFT
    ) ERC20(name, symbol) {
        paintingId = _paintingId;
        paintingNFT = _paintingNFT;
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == paintingNFT, "Only PaintingNFT can mint");
        _mint(to, amount);
    }
}

// Main Painting NFT contract
contract PaintingNFT is ERC721, Pausable {
    using Counters for Counters.Counter;

    IRoleManager public immutable roleManager;
    IWall public immutable wallContract;
    IGallery public immutable galleryContract;

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
        address sharesContract;
        bool sharesMinted;
        uint256 createdAt;
    }

    // Storage
    mapping(uint256 => PaintingData) public paintings;
    mapping(uint256 => PaintingRequest) public paintingRequests; // wallId => request
    mapping(uint256 => bool) public wallPainted; // wallId => isPainted

    // Events
    event PaintingRequested(uint256 indexed wallId, address indexed painter);
    event PaintingRequestApproved(uint256 indexed wallId, address indexed painter);
    event PaintingRequestRejected(uint256 indexed wallId, address indexed painter);
    event PaintingCompleted(uint256 indexed paintingId, uint256 indexed wallId);
    event SharesDistributed(
        uint256 indexed paintingId, 
        address sharesContract, 
        uint256 platformShares,
        uint256 wallOwnerShares,
        uint256 galleryOwnerShares,
        uint256 painterShares
    );

    constructor(
        address _roleManager,
        address _wallContract,
        address _galleryContract
    ) ERC721("Wall Painting", "WPAINT") {
        require(_roleManager != address(0), "Invalid RoleManager address");
        require(_wallContract != address(0), "Invalid Wall contract address");
        require(_galleryContract != address(0), "Invalid Gallery contract address");
        
        roleManager = IRoleManager(_roleManager);
        wallContract = IWall(_wallContract);
        galleryContract = IGallery(_galleryContract);
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

    // Request to paint a wall
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

    // Gallery owner approves painting request
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

    // Gallery owner rejects painting request
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

    // Painter submits completed painting
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

    // Gallery owner finalizes painting and mints NFT + shares
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

        // Create and store painting data
        paintings[newPaintingId] = PaintingData({
            id: newPaintingId,
            wallId: wallId,
            painter: request.painter,
            description: request.description,
            sharesContract: address(0), // Will be set after shares creation
            sharesMinted: false,
            createdAt: block.timestamp
        });

        wallPainted[wallId] = true;
        emit PaintingCompleted(newPaintingId, wallId);

        // Create and distribute shares
        _createAndDistributeShares(newPaintingId);
    }

    function _createAndDistributeShares(uint256 paintingId) private {
        require(!paintings[paintingId].sharesMinted, "Shares already minted");
        PaintingData storage painting = paintings[paintingId];

        // Get wall and gallery data
        (,address wallOwner,,uint256 wallOwnerPercentage,, uint256 galleryId) = 
            wallContract.getWall(painting.wallId);
        
        (,,,address galleryOwner, uint256 galleryOwnerPercentage,) = 
            galleryContract.galleries(galleryId);
        
        uint256 platformPercentage = galleryContract.platformPercentage();

        // Create shares token
        string memory shareName = string(abi.encodePacked("Painting ", 
            toString(paintingId), " Shares"));
        string memory shareSymbol = string(abi.encodePacked("PAINT", 
            toString(paintingId)));
        
        PaintingShares sharesContract = new PaintingShares(
            shareName,
            shareSymbol,
            paintingId,
            address(this)
        );

        painting.sharesContract = address(sharesContract);
        painting.sharesMinted = true;

        // Calculate and distribute shares
        uint256 platformShares = (SharesConstants.TOTAL_SHARES * platformPercentage) / 100;
        uint256 wallOwnerShares = (SharesConstants.TOTAL_SHARES * wallOwnerPercentage) / 100;
        uint256 galleryOwnerShares = (SharesConstants.TOTAL_SHARES * galleryOwnerPercentage) / 100;
        uint256 painterShares = SharesConstants.TOTAL_SHARES - platformShares - 
            wallOwnerShares - galleryOwnerShares;

        // Mint shares
        address platformAdmin = _getPlatformAdmin();
        sharesContract.mint(platformAdmin, platformShares);
        sharesContract.mint(wallOwner, wallOwnerShares);
        sharesContract.mint(galleryOwner, galleryOwnerShares);
        sharesContract.mint(painting.painter, painterShares);

        emit SharesDistributed(
            paintingId, 
            address(sharesContract),
            platformShares,
            wallOwnerShares,
            galleryOwnerShares,
            painterShares
        );
    }

    function _getPlatformAdmin() private view returns (address) {
        // For now, we'll consider msg.sender as admin
        // This should be updated based on your admin management system
        return msg.sender;
    }

    // Utility function to convert uint to string
    function toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
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