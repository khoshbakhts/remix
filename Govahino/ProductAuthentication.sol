// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./ProductTypes.sol";

contract ProductAuthentication is ERC721, Ownable {
    using Strings for uint256;
    using ProductTypes for ProductTypes.Product;

    mapping(uint256 => ProductTypes.Product) private _products;
    mapping(string => uint256) private _productIdToTokenId;
    // نگاشت جدید برای تاریخچه مالکیت
    mapping(uint256 => mapping(uint256 => ProductTypes.OwnerInfo)) private _ownerHistory;
    uint256 private _tokenIdCounter;

    constructor() ERC721("Luxury Product Authentication", "LPA") Ownable(msg.sender) {}

    // ثبت محصول جدید با اطلاعات مالک اولیه
    function registerProduct(
        ProductTypes.RegistrationParams memory params,
        address owner,
        bytes32 ownerInfoHash
    ) public onlyOwner {
        require(_productIdToTokenId[params.productId] == 0, "Product already registered");
        
        _tokenIdCounter++;
        uint256 tokenId = _tokenIdCounter;

        _products[tokenId] = ProductTypes.Product({
            productId: params.productId,
            details: params.details,
            limitation: params.limitation,
            certificates: params.certificates,
            features: params.features,
            images: params.images,
            ownerHistoryCount: 1
        });

        // ثبت اولین مالک در تاریخچه
        _ownerHistory[tokenId][0] = ProductTypes.OwnerInfo({
            infoHash: ownerInfoHash,
            timestamp: block.timestamp
        });
        
        _productIdToTokenId[params.productId] = tokenId;
        _safeMint(owner, tokenId);
    }

    // انتقال مالکیت با ثبت اطلاعات مالک جدید
    function transferProductWithInfo(
        string memory productId, 
        address to,
        bytes32 newOwnerInfoHash
    ) public {
        uint256 tokenId = _productIdToTokenId[productId];
        require(tokenId != 0, "Product not found");
        require(ownerOf(tokenId) == msg.sender, "Not the owner");

        // ثبت اطلاعات مالک جدید
        uint256 currentCount = _products[tokenId].ownerHistoryCount;
        _ownerHistory[tokenId][currentCount] = ProductTypes.OwnerInfo({
            infoHash: newOwnerInfoHash,
            timestamp: block.timestamp
        });
        _products[tokenId].ownerHistoryCount++;

        // انتقال توکن
        safeTransferFrom(msg.sender, to, tokenId);
    }

    // تأیید مالکیت با مقایسه هش اطلاعات
    function verifyOwnershipWithInfo(
        string memory productId,
        address owner,
        bytes32 infoHash
    ) public view returns (bool) {
        uint256 tokenId = _productIdToTokenId[productId];
        if (tokenId == 0) return false;
        if (ownerOf(tokenId) != owner) return false;

        // بررسی هش اطلاعات با آخرین مالک
        uint256 lastIndex = _products[tokenId].ownerHistoryCount - 1;
        return _ownerHistory[tokenId][lastIndex].infoHash == infoHash;
    }

    // دریافت تاریخچه مالکیت
    function getOwnershipHistory(string memory productId) 
        public 
        view 
        returns (ProductTypes.OwnerInfo[] memory) 
    {
        uint256 tokenId = _productIdToTokenId[productId];
        require(tokenId != 0, "Product not found");
        
        uint256 count = _products[tokenId].ownerHistoryCount;
        ProductTypes.OwnerInfo[] memory history = new ProductTypes.OwnerInfo[](count);
        
        for (uint256 i = 0; i < count; i++) {
            history[i] = _ownerHistory[tokenId][i];
        }
        
        return history;
    }

    // دریافت اطلاعات محصول با شناسه محصول
    function getProductByProductId(string memory productId) 
        public 
        view 
        returns (ProductTypes.Product memory) 
    {
        uint256 tokenId = _productIdToTokenId[productId];
        require(tokenId != 0, "Product not found");
        return _products[tokenId];
    }
}