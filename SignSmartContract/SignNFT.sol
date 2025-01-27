// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract SignNFT is ERC721, ERC721Enumerable, Pausable, AccessControl {
    using Counters for Counters.Counter;

    bytes32 public constant GAME_MANAGER_ROLE = keccak256("GAME_MANAGER_ROLE");
    Counters.Counter private _tokenIdCounter;

    struct SignData {
        uint256 homeLocationLat;
        uint256 homeLocationLong;
        uint256 currentLocationLat;
        uint256 currentLocationLong;
        uint256 weight;
        uint256 lastMoveTimestamp;
        address[] carriers;
        bool exists;
    }

    mapping(uint256 => SignData) private _signData;
    mapping(address => bool) private _hasSign;

    event SignMinted(address indexed to, uint256 indexed tokenId, uint256 homeLocationLat, uint256 homeLocationLong);
    event SignMoved(uint256 indexed tokenId, uint256 newLat, uint256 newLong, address indexed carrier);
    event HomeLocationUpdated(uint256 indexed tokenId, uint256 newLat, uint256 newLong);
    event CarrierAdded(uint256 indexed tokenId, address indexed carrier);

    constructor() ERC721("Signs Game NFT", "SIGN") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    modifier onlyGameManager() {
        require(hasRole(GAME_MANAGER_ROLE, msg.sender), "Caller is not a game manager");
        _;
    }

    modifier signExists(uint256 tokenId) {
        require(_signData[tokenId].exists, "Sign does not exist");
        _;
    }

    function mint(address to, uint256 homeLocationLat, uint256 homeLocationLong) 
        external 
        onlyGameManager 
        returns (uint256) 
    {
        require(!_hasSign[to], "Address already has a SIGN");
        require(to != address(0), "Cannot mint to zero address");

        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        
        _safeMint(to, tokenId);
        _hasSign[to] = true;

        SignData storage newSign = _signData[tokenId];
        newSign.homeLocationLat = homeLocationLat;
        newSign.homeLocationLong = homeLocationLong;
        newSign.currentLocationLat = homeLocationLat;
        newSign.currentLocationLong = homeLocationLong;
        newSign.weight = 100; // Initial weight
        newSign.lastMoveTimestamp = block.timestamp;
        newSign.exists = true;
        
        emit SignMinted(to, tokenId, homeLocationLat, homeLocationLong);
        return tokenId;
    }

    function updateLocation(
        uint256 tokenId, 
        uint256 newLat, 
        uint256 newLong
    ) 
        external 
        onlyGameManager 
        signExists(tokenId) 
    {
        SignData storage sign = _signData[tokenId];
        sign.currentLocationLat = newLat;
        sign.currentLocationLong = newLong;
        sign.lastMoveTimestamp = block.timestamp;

        emit SignMoved(tokenId, newLat, newLong, msg.sender);
    }

    function setHomeLocation(
        uint256 tokenId, 
        uint256 newLat, 
        uint256 newLong
    ) 
        external 
        signExists(tokenId) 
    {
        require(ownerOf(tokenId) == msg.sender, "Not sign owner");
        
        SignData storage sign = _signData[tokenId];
        sign.homeLocationLat = newLat;
        sign.homeLocationLong = newLong;

        emit HomeLocationUpdated(tokenId, newLat, newLong);
    }

    function addCarrier(uint256 tokenId, address carrier) 
        external 
        onlyGameManager 
        signExists(tokenId) 
    {
        require(carrier != address(0), "Invalid carrier address");
        
        SignData storage sign = _signData[tokenId];
        sign.carriers.push(carrier);
        sign.weight += 10;

        emit CarrierAdded(tokenId, carrier);
    }

    function getSignLocation(uint256 tokenId) 
        external 
        view 
        signExists(tokenId) 
        returns (uint256 lat, uint256 long) 
    {
        SignData storage sign = _signData[tokenId];
        return (sign.currentLocationLat, sign.currentLocationLong);
    }

    function getHomeLocation(uint256 tokenId) 
        external 
        view 
        signExists(tokenId) 
        returns (uint256 lat, uint256 long) 
    {
        SignData storage sign = _signData[tokenId];
        return (sign.homeLocationLat, sign.homeLocationLong);
    }

    function getSignWeight(uint256 tokenId) 
        external 
        view 
        signExists(tokenId) 
        returns (uint256) 
    {
        return _signData[tokenId].weight;
    }

    function getSignCarriers(uint256 tokenId) 
        external 
        view 
        signExists(tokenId) 
        returns (address[] memory) 
    {
        return _signData[tokenId].carriers;
    }

    function getLastMoveTime(uint256 tokenId) 
        external 
        view 
        signExists(tokenId) 
        returns (uint256) 
    {
        return _signData[tokenId].lastMoveTimestamp;
    }

    function hasSign(address owner) external view returns (bool) {
        return _hasSign[owner];
    }

    // Required overrides for OpenZeppelin V5
    function _update(address to, uint256 tokenId, address auth)
        internal
        virtual
        override(ERC721, ERC721Enumerable)
        returns (address)
    {
        require(auth == address(0) || to == address(0), "SIGN tokens cannot be transferred");
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 amount)
        internal
        virtual
        override(ERC721, ERC721Enumerable)
    {
        super._increaseBalance(account, amount);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // Admin functions
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}