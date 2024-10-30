// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract PaintingShares is Ownable, Pausable, ReentrancyGuard {
    uint256 public constant TOTAL_SHARES = 100000;

    struct ShareInfo {
        string name;
        string symbol;
        uint256 totalSupply;
        bool exists;
        mapping(address => uint256) balances;
    }

    // paintingId => ShareInfo
    mapping(uint256 => ShareInfo) public shares;
    
    // owner => paintingId => balance
    mapping(address => mapping(uint256 => uint256)) public balanceOf;
    
    // Approval mapping: owner => spender => paintingId => amount
    mapping(address => mapping(address => mapping(uint256 => uint256))) public allowance;

    address public paintingNFTContract;

    event SharesCreated(
        uint256 indexed paintingId,
        string name,
        string symbol,
        uint256 platformShares,
        uint256 wallOwnerShares,
        uint256 galleryOwnerShares,
        uint256 painterShares
    );

    event Transfer(
        uint256 indexed paintingId,
        address indexed from,
        address indexed to,
        uint256 value
    );

    event Approval(
        uint256 indexed paintingId,
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    constructor(address initialOwner) Ownable(initialOwner) {
        _pause(); // Start paused until PaintingNFT contract is set
    }

    modifier onlyPaintingNFT() {
        require(msg.sender == paintingNFTContract, "Only PaintingNFT contract");
        _;
    }

    modifier validPaintingId(uint256 paintingId) {
        require(shares[paintingId].exists, "Shares don't exist for this painting");
        _;
    }

    function setPaintingNFTContract(address _paintingNFTContract) external onlyOwner {
        require(_paintingNFTContract != address(0), "Invalid address");
        paintingNFTContract = _paintingNFTContract;
        _unpause();
    }

    function createSharesForPainting(
        uint256 paintingId,
        address platformAdmin,
        address wallOwner,
        address galleryOwner,
        address painter,
        uint256 platformPercentage,
        uint256 wallOwnerPercentage,
        uint256 galleryOwnerPercentage
    ) external onlyPaintingNFT whenNotPaused {
        require(!shares[paintingId].exists, "Shares already exist");
        require(platformPercentage + wallOwnerPercentage + galleryOwnerPercentage <= 100, 
                "Invalid percentages");

        string memory name = string(abi.encodePacked("Painting ", _toString(paintingId), " Shares"));
        string memory symbol = string(abi.encodePacked("PAINT", _toString(paintingId)));

        // Initialize share info
        ShareInfo storage newShares = shares[paintingId];
        newShares.name = name;
        newShares.symbol = symbol;
        newShares.exists = true;
        newShares.totalSupply = TOTAL_SHARES;

        // Calculate shares
        uint256 platformShares = (TOTAL_SHARES * platformPercentage) / 100;
        uint256 wallOwnerShares = (TOTAL_SHARES * wallOwnerPercentage) / 100;
        uint256 galleryOwnerShares = (TOTAL_SHARES * galleryOwnerPercentage) / 100;
        uint256 painterShares = TOTAL_SHARES - platformShares - wallOwnerShares - galleryOwnerShares;

        // Distribute shares
        _mintShares(paintingId, platformAdmin, platformShares);
        _mintShares(paintingId, wallOwner, wallOwnerShares);
        _mintShares(paintingId, galleryOwner, galleryOwnerShares);
        _mintShares(paintingId, painter, painterShares);

        emit SharesCreated(
            paintingId,
            name,
            symbol,
            platformShares,
            wallOwnerShares,
            galleryOwnerShares,
            painterShares
        );
    }

    function transfer(
        uint256 paintingId,
        address to,
        uint256 amount
    ) external validPaintingId(paintingId) whenNotPaused nonReentrant returns (bool) {
        require(to != address(0), "Transfer to zero address");
        require(balanceOf[msg.sender][paintingId] >= amount, "Insufficient balance");

        _transfer(paintingId, msg.sender, to, amount);
        return true;
    }

    function approve(
        uint256 paintingId,
        address spender,
        uint256 amount
    ) external validPaintingId(paintingId) whenNotPaused returns (bool) {
        require(spender != address(0), "Approve to zero address");

        allowance[msg.sender][spender][paintingId] = amount;
        emit Approval(paintingId, msg.sender, spender, amount);
        return true;
    }

    function transferFrom(
        uint256 paintingId,
        address from,
        address to,
        uint256 amount
    ) external validPaintingId(paintingId) whenNotPaused nonReentrant returns (bool) {
        require(to != address(0), "Transfer to zero address");
        require(balanceOf[from][paintingId] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender][paintingId] >= amount, "Insufficient allowance");

        allowance[from][msg.sender][paintingId] -= amount;
        _transfer(paintingId, from, to, amount);
        return true;
    }

    function getShareInfo(uint256 paintingId) external view returns (
        string memory name,
        string memory symbol,
        uint256 totalSupply,
        bool exists
    ) {
        ShareInfo storage info = shares[paintingId];
        return (info.name, info.symbol, info.totalSupply, info.exists);
    }

    function _transfer(
        uint256 paintingId,
        address from,
        address to,
        uint256 amount
    ) internal {
        balanceOf[from][paintingId] -= amount;
        balanceOf[to][paintingId] += amount;
        shares[paintingId].balances[from] -= amount;
        shares[paintingId].balances[to] += amount;

        emit Transfer(paintingId, from, to, amount);
    }

    function _mintShares(
        uint256 paintingId,
        address to,
        uint256 amount
    ) internal {
        require(to != address(0), "Mint to zero address");
        
        balanceOf[to][paintingId] += amount;
        shares[paintingId].balances[to] += amount;

        emit Transfer(paintingId, address(0), to, amount);
    }

    function _toString(uint256 value) internal pure returns (string memory) {
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

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}